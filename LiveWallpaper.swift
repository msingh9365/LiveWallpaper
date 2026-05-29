// ─────────────────────────────────────────────────────────────────────────────
//  LiveWallpaper.swift
//  DIY macOS Live Wallpaper — No third-party apps needed
//
//  COMPILE (Apple Silicon):
//    swiftc LiveWallpaper.swift -o LiveWallpaper -framework AVFoundation \
//      -framework IOKit -framework AppKit -O
//
//  RUN:
//    ./LiveWallpaper /path/to/your/video.mp4
// ─────────────────────────────────────────────────────────────────────────────

import AppKit
import AVFoundation
import IOKit.ps

// ─── Per-Screen State ─────────────────────────────────────────────────────────

private struct ScreenState {
    let window: NSWindow
    let player: AVQueuePlayer
    let looper: AVPlayerLooper          // gapless loop — no black-frame stutter
    let playerLayer: AVPlayerLayer
}

// ─── Startup Error ────────────────────────────────────────────────────────────

private enum StartupError: Error, CustomStringConvertible {
    case noArgument
    case fileNotFound(String)
    case unsupportedFormat(String)
    case notPlayable(String)

    var description: String {
        switch self {
        case .noArgument:
            return "No video file specified.\n\n"
                 + "Usage:  LiveWallpaper /path/to/video.mp4\n\n"
                 + "Supported formats: .mp4, .m4v, .mov"
        case .fileNotFound(let path):
            return "File not found:\n\(path)"
        case .unsupportedFormat(let ext):
            return "Unsupported format: .\(ext)\n\n"
                 + "Supported formats: .mp4, .m4v, .mov\n\n"
                 + "Tip: Convert with ffmpeg:\n"
                 + "  ffmpeg -i input.\\(ext) -c:v hevc_videotoolbox -b:v 8M -r 30 -an wallpaper.mp4"
        case .notPlayable(let name):
            return "Cannot play \"\(name)\".\n\n"
                 + "The file may be corrupt or encoded with an unsupported codec.\n\n"
                 + "Tip: Re-encode with hardware acceleration:\n"
                 + "  ffmpeg -i \"\(name)\" -c:v hevc_videotoolbox -b:v 8M -r 30 -an wallpaper.mp4"
        }
    }
}

// ─── App Delegate ─────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {

    private var screenStates: [ScreenState] = []
    private var videoURL: URL?                             // no force-unwraps
    private var videoAsset: AVURLAsset?
    private var playerStatusObservers: [NSKeyValueObservation] = []

    // Menu bar
    private var statusItem: NSStatusItem?

    // Control flags
    private var userWantsPlay  = true
    private var screenIsAwake  = true
    private var systemIsAwake  = true
    private var playOnBattery  = false   // user-togglable from menu bar

    // Power callback
    private var powerLoopSource: CFRunLoopSource?

    // Track whether we successfully started
    private var isRunning = false

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ── Step 1: Validate the video synchronously BEFORE touching the system ──
        let validationResult = validateVideoInput()

        switch validationResult {
        case .failure(let error):
            showError(error.description)
            NSApp.terminate(nil)
            return
        case .success(let (url, asset)):
            videoURL   = url
            videoAsset = asset
        }

        // ── Step 2: Async playability check — do NOT build windows until confirmed ──
        Task {
            let playable = (try? await videoAsset!.load(.isPlayable)) ?? false
            await MainActor.run {
                if !playable {
                    showError(StartupError.notPlayable(videoURL!.lastPathComponent).description)
                    NSApp.terminate(nil)
                    return
                }
                // ── Step 3: Everything validated — now set up the wallpaper ──
                startWallpaper()
            }
        }
    }

    /// Sets up all wallpaper infrastructure. Called only after video is validated.
    private func startWallpaper() {
        isRunning = true

        rebuildAllScreens()
        buildMenuBar()
        registerSystemNotifications()
        registerPowerMonitoring()

        // Rebuild windows when displays are added / removed
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        applyPlaybackState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard isRunning else { return }
        cleanup()
    }

    // ── Cleanup ────────────────────────────────────────────────────────────────

    private func cleanup() {
        tearDownScreens()

        if let src = powerLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
            powerLoopSource = nil
        }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)

        isRunning = false
    }

    // ─── Input Validation ─────────────────────────────────────────────────────

    /// Validates CLI arguments, file existence, and format BEFORE any system changes.
    /// Returns the validated URL and asset, or a descriptive error.
    private func validateVideoInput() -> Result<(URL, AVURLAsset), StartupError> {
        let args = CommandLine.arguments
        guard args.count > 1 else {
            return .failure(.noArgument)
        }

        let path = (args[1] as NSString).expandingTildeInPath
        let url  = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.fileNotFound(url.path))
        }

        // Only formats AVFoundation actually supports natively on macOS
        let ext = url.pathExtension.lowercased()
        let validExts = ["mp4", "m4v", "mov"]
        guard validExts.contains(ext) else {
            return .failure(.unsupportedFormat(ext))
        }

        let asset = AVURLAsset(url: url)
        return .success((url, asset))
    }

    // ─── Screen Management ────────────────────────────────────────────────────

    @objc private func screensChanged() {
        guard isRunning else { return }
        tearDownScreens()
        rebuildAllScreens()
        applyPlaybackState()
    }

    private func tearDownScreens() {
        // Disarm loopers FIRST — they hold strong refs and reschedule on bg threads
        for s in screenStates {
            s.looper.disableLooping()
        }
        // Now safe to tear down players and windows
        for s in screenStates {
            s.player.pause()
            s.player.replaceCurrentItem(with: nil)
            s.playerLayer.removeFromSuperlayer()
            s.window.orderOut(nil)
        }
        playerStatusObservers.removeAll()   // invalidates KVO tokens
        screenStates.removeAll()
    }

    private func rebuildAllScreens() {
        guard let asset = videoAsset else { return }

        for screen in NSScreen.screens {
            // ── Window ──
            let win = NSWindow(
                contentRect: screen.frame,
                styleMask:   .borderless,
                backing:     .buffered,
                defer:       false)

            // Place between desktop wallpaper and desktop icons
            win.level              = NSWindow.Level(rawValue:
                                        Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            win.collectionBehavior = [.stationary, .canJoinAllSpaces,
                                      .ignoresCycle]
            win.isOpaque           = true
            win.hasShadow          = false
            win.backgroundColor    = .black
            win.ignoresMouseEvents = true     // clicks pass through to Finder
            win.canHide            = false

            let cv = NSView(frame: win.contentView!.bounds)
            cv.wantsLayer       = true
            cv.autoresizingMask = [.width, .height]
            win.contentView     = cv

            // ── Player (one per screen, shared asset) ──
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 2          // 2 s buffer, not unlimited

            // Decode at screen resolution — no wasted GPU on off-screen pixels
            let scale = screen.backingScaleFactor
            item.preferredMaximumResolution = CGSize(
                width:  screen.frame.width  * scale,
                height: screen.frame.height * scale)

            let qp = AVQueuePlayer()
            qp.isMuted = true
            qp.automaticallyWaitsToMinimizeStalling = false

            // Observe player status — surface errors instead of silent black screen
            let obs = qp.observe(\.status, options: [.new]) { [weak self] player, _ in
                if player.status == .failed {
                    let msg = player.error?.localizedDescription ?? "unknown error"
                    NSLog("[LiveWallpaper] Player failed: %@", msg)
                    // Show error on main thread if player fails mid-session
                    DispatchQueue.main.async {
                        self?.handlePlayerFailure(msg)
                    }
                }
            }
            playerStatusObservers.append(obs)

            // AVPlayerLooper → gapless loop (no notification hack, no black frame)
            let looper = AVPlayerLooper(player: qp, templateItem: item)

            let layer = AVPlayerLayer(player: qp)
            layer.frame            = cv.bounds
            layer.videoGravity     = .resizeAspectFill
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            cv.layer?.addSublayer(layer)

            win.orderBack(nil)       // never steal focus — it's a wallpaper

            screenStates.append(ScreenState(
                window: win, player: qp, looper: looper, playerLayer: layer))
        }
    }

    /// Called if a player enters .failed state during playback
    private func handlePlayerFailure(_ message: String) {
        cleanup()
        showError("Playback failed:\n\(message)\n\n"
                + "The wallpaper has been stopped to prevent issues.")
        NSApp.terminate(nil)
    }

    // ─── Menu Bar ─────────────────────────────────────────────────────────────

    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        refreshMenu()
    }

    private func refreshMenu() {
        guard let statusItem = statusItem, let btn = statusItem.button else { return }

        let isPlaying = screenStates.first.map { $0.player.rate > 0 } ?? false
        btn.image = NSImage(
            systemSymbolName: isPlaying ? "play.circle.fill" : "pause.circle",
            accessibilityDescription: "Live Wallpaper")

        let m = NSMenu()

        // Video file name
        let videoName = videoURL?.lastPathComponent ?? "Unknown"
        let info = NSMenuItem(title: "🎬  \(videoName)",
                              action: nil, keyEquivalent: "")
        info.isEnabled = false
        m.addItem(info)
        m.addItem(.separator())

        // Play / Pause
        let t = NSMenuItem(
            title: userWantsPlay ? "⏸  Pause Wallpaper" : "▶  Play Wallpaper",
            action: #selector(userToggledPlayback), keyEquivalent: "p")
        t.target = self
        m.addItem(t)

        // Battery behaviour
        let b = NSMenuItem(
            title: playOnBattery
                ? "🔋  Battery: Playing (tap to pause)"
                : "🔋  Battery: Auto-Pause (tap to allow)",
            action: #selector(toggleBatteryBehavior), keyEquivalent: "b")
        b.target = self
        m.addItem(b)

        m.addItem(.separator())

        // Status
        for label in [powerStatusLabel(), screenStatusLabel(),
                      "🖥  \(NSScreen.screens.count) display(s)"] {
            let it = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            it.isEnabled = false
            m.addItem(it)
        }

        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit Live Wallpaper",
                             action: #selector(NSApplication.terminate(_:)),
                             keyEquivalent: "q"))
        statusItem.menu = m
    }

    private func powerStatusLabel() -> String {
        isOnACPower() ? "🔌  AC Power" : "🔋  Battery Power"
    }
    private func screenStatusLabel() -> String {
        screenIsAwake ? "🖥  Screen awake" : "💤  Screen sleeping"
    }

    // ─── Playback Logic ───────────────────────────────────────────────────────

    private func shouldBePlayingNow() -> Bool {
        guard isRunning, userWantsPlay, screenIsAwake, systemIsAwake else { return false }
        if !isOnACPower() && !playOnBattery { return false }
        return true
    }

    private func applyPlaybackState() {
        guard isRunning else { return }
        let shouldPlay = shouldBePlayingNow()
        for s in screenStates {
            if shouldPlay { if s.player.rate == 0 { s.player.play() } }
            else          { s.player.pause() }
        }
        refreshMenu()
    }

    @objc private func userToggledPlayback() {
        userWantsPlay.toggle()
        applyPlaybackState()
    }

    @objc private func toggleBatteryBehavior() {
        playOnBattery.toggle()
        applyPlaybackState()
    }

    // ─── Power Source ─────────────────────────────────────────────────────────

    private func isOnACPower() -> Bool {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        // IOPSGetProvidingPowerSourceType is a "Get" function (CF naming rules)
        // → must use takeUnretainedValue(), NOT takeRetainedValue()
        guard let cfType = IOPSGetProvidingPowerSourceType(snapshot) else {
            return true          // desktop Mac / can't determine → assume AC
        }
        let type = cfType.takeUnretainedValue() as String
        return type == kIOPSACPowerValue
    }

    private func registerPowerMonitoring() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        powerLoopSource = IOPSNotificationCreateRunLoopSource({ rawCtx in
            guard let ptr = rawCtx else { return }
            let me = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async { me.applyPlaybackState() }
        }, ctx).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), powerLoopSource, .defaultMode)
    }

    // ─── System Notifications ─────────────────────────────────────────────────

    private func registerSystemNotifications() {
        let ws = NSWorkspace.shared.notificationCenter

        ws.addObserver(self, selector: #selector(onScreenSleep),
                       name: NSWorkspace.screensDidSleepNotification,  object: nil)
        ws.addObserver(self, selector: #selector(onScreenWake),
                       name: NSWorkspace.screensDidWakeNotification,   object: nil)
        ws.addObserver(self, selector: #selector(onSystemSleep),
                       name: NSWorkspace.willSleepNotification,        object: nil)
        ws.addObserver(self, selector: #selector(onSystemWake),
                       name: NSWorkspace.didWakeNotification,          object: nil)

        let dc = DistributedNotificationCenter.default()
        dc.addObserver(self, selector: #selector(onScreenSaverStart),
                       name: NSNotification.Name("com.apple.screensaver.didstart"),
                       object: nil)
        dc.addObserver(self, selector: #selector(onScreenSaverStop),
                       name: NSNotification.Name("com.apple.screensaver.didstop"),
                       object: nil)
    }

    @objc private func onScreenSleep()      { screenIsAwake = false; applyPlaybackState() }
    @objc private func onScreenWake()       { screenIsAwake = true;  applyPlaybackState() }
    @objc private func onSystemSleep()      { systemIsAwake = false; applyPlaybackState() }
    @objc private func onSystemWake()       { systemIsAwake = true;  applyPlaybackState() }
    @objc private func onScreenSaverStart() { screenIsAwake = false; applyPlaybackState() }
    @objc private func onScreenSaverStop()  { screenIsAwake = true;  applyPlaybackState() }

    // ─── Helper ───────────────────────────────────────────────────────────────

    private func showError(_ msg: String) {
        let a = NSAlert()
        a.messageText     = "Live Wallpaper"
        a.informativeText = msg
        a.alertStyle      = .critical
        a.runModal()
    }
}

// ─── Main ─────────────────────────────────────────────────────────────────────

// Handle SIGINT (Ctrl+C) and SIGTERM (kill) gracefully
signal(SIGINT)  { _ in NSApp.terminate(nil) }
signal(SIGTERM) { _ in NSApp.terminate(nil) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)          // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
