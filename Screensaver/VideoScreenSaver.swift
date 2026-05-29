// ─────────────────────────────────────────────────────────────────────────────
//  VideoScreenSaver.swift
//  A macOS screensaver that plays a looping video — battery efficient
//
//  SET YOUR VIDEO:
//    defaults write com.manish.videoscreensaver VideoPath "/full/path/to/video.mp4"
//
//  Or just place a file at ~/Movies/screensaver.mp4
//
//  Build:   ./build_screensaver.sh
//  Install: open VideoScreenSaver.saver
// ─────────────────────────────────────────────────────────────────────────────

import ScreenSaver
import AVFoundation

// ─── Constants ────────────────────────────────────────────────────────────────

private let kBundleID      = "com.manish.videoscreensaver"
private let kVideoPathKey  = "VideoPath"
private let kValidExts     = Set(["mp4", "m4v", "mov"])

// ─── Screensaver View ─────────────────────────────────────────────────────────

@objc(VideoScreenSaverView)
class VideoScreenSaverView: ScreenSaverView {

    // ── State ──
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var statusObserver: NSKeyValueObservation?
    private var messageLabel: NSTextField?
    private var videoReady = false                // true only after isPlayable confirmed
    private var animationStarted = false          // tracks startAnimation calls

    // ── Init ───────────────────────────────────────────────────────────────────

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // AVPlayerLayer handles rendering; this timer is just a heartbeat.
        // 1 fps avoids wasting CPU on a no-op animateOneFrame().
        animationTimeInterval = 1.0

        // Resolve video → validate → set up player (async)
        resolveAndValidateVideo(isPreview: isPreview)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        tearDown()
    }

    // ─── Video Resolution ─────────────────────────────────────────────────────

    /// Finds the video, validates it's playable, then sets up the player.
    /// Nothing is applied to the system until validation passes.
    private func resolveAndValidateVideo(isPreview: Bool) {
        // Step 1: Find the video URL
        guard let url = findVideoURL() else {
            showMessage(
                "No video found.\n\n"
              + "Set your video with:\n"
              + "  defaults write \(kBundleID) \(kVideoPathKey) \"/path/to/video.mp4\"\n\n"
              + "Or place a file at:\n"
              + "  ~/Movies/screensaver.mp4\n\n"
              + "Supported: .mp4  .m4v  .mov")
            return
        }

        // Step 2: Validate file extension
        let ext = url.pathExtension.lowercased()
        guard kValidExts.contains(ext) else {
            showMessage(
                "Unsupported format: .\(ext)\n\n"
              + "Supported: .mp4  .m4v  .mov\n\n"
              + "Convert with:\n"
              + "  ffmpeg -i input.\(ext) -c:v hevc_videotoolbox -b:v 6M -r 24 -an ~/Movies/screensaver.mp4")
            return
        }

        let asset = AVURLAsset(url: url)

        // Step 3: Async playability check — do NOT set up player until confirmed
        Task {
            let playable = (try? await asset.load(.isPlayable)) ?? false
            await MainActor.run {
                if playable {
                    configurePlayer(asset: asset, url: url, isPreview: isPreview)
                } else {
                    showMessage(
                        "Cannot play \"\(url.lastPathComponent)\".\n\n"
                      + "The file may be corrupt or use an unsupported codec.\n\n"
                      + "Re-encode with:\n"
                      + "  ffmpeg -i \"\(url.lastPathComponent)\" -c:v hevc_videotoolbox "
                      + "-b:v 6M -r 24 -an ~/Movies/screensaver.mp4")
                }
            }
        }
    }

    /// Lookup order: defaults config → ~/Movies/screensaver.* → ~/Movies/wallpaper.*
    private func findVideoURL() -> URL? {
        // 1. User-configured path via `defaults write`
        if let prefs = UserDefaults(suiteName: kBundleID),
           let configPath = prefs.string(forKey: kVideoPathKey) {
            let expanded = (configPath as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }

        // 2. Well-known locations
        let moviesDir = (("~/Movies") as NSString).expandingTildeInPath
        let names     = ["screensaver", "wallpaper"]
        let exts      = ["mp4", "m4v", "mov"]
        for name in names {
            for ext in exts {
                let path = "\(moviesDir)/\(name).\(ext)"
                if FileManager.default.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        return nil
    }

    // ─── Player Setup (called only after validation passes) ───────────────────

    private func configurePlayer(asset: AVURLAsset, url: URL, isPreview: Bool) {
        let item = AVPlayerItem(asset: asset)

        // ⚡ Battery optimizations
        item.preferredForwardBufferDuration = 2          // 2 s buffer, not unlimited

        if isPreview {
            // Tiny thumbnail in System Settings — minimal decode work
            item.preferredMaximumResolution = CGSize(width: 640, height: 480)
        } else {
            // Full screen — use NSScreen since self.window may not be set yet during init
            let screen = NSScreen.main ?? NSScreen.screens.first
            let scale  = screen?.backingScaleFactor ?? 2.0
            let size   = screen?.frame.size ?? bounds.size
            item.preferredMaximumResolution = CGSize(
                width:  size.width  * scale,
                height: size.height * scale)
        }

        let qp = AVQueuePlayer()
        qp.isMuted = true
        qp.automaticallyWaitsToMinimizeStalling = false

        let loop = AVPlayerLooper(player: qp, templateItem: item)

        // Monitor for mid-playback failures
        statusObserver = qp.observe(\.status, options: [.new]) { [weak self] p, _ in
            if p.status == .failed {
                let msg = p.error?.localizedDescription ?? "unknown error"
                NSLog("[VideoScreenSaver] Player failed: %@", msg)
                DispatchQueue.main.async {
                    self?.tearDown()
                    self?.showMessage("Playback failed:\n\(msg)")
                }
            }
        }

        let pLayer = AVPlayerLayer(player: qp)
        pLayer.frame            = bounds
        pLayer.videoGravity     = .resizeAspectFill
        pLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(pLayer)

        player      = qp
        looper      = loop
        playerLayer = pLayer
        videoReady  = true

        // If startAnimation was already called while we were validating, play now
        if animationStarted {
            playerLayer?.frame = bounds
            player?.play()
        }
    }

    // ─── Message Display ──────────────────────────────────────────────────────

    private func showMessage(_ text: String) {
        // Remove previous message if any
        messageLabel?.removeFromSuperview()

        let label = NSTextField(labelWithString: text)
        label.alignment            = .center
        label.font                 = isPreview
            ? .monospacedSystemFont(ofSize: 5, weight: .regular)
            : .monospacedSystemFont(ofSize: 16, weight: .light)
        label.textColor            = .init(white: 0.6, alpha: 1)
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.85)
        ])
        messageLabel = label
    }

    // ─── Teardown ─────────────────────────────────────────────────────────────

    private func tearDown() {
        videoReady = false
        looper?.disableLooping()         // disarm FIRST — prevents bg rescheduling
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerLayer?.removeFromSuperlayer()
        statusObserver?.invalidate()

        looper          = nil
        player          = nil
        playerLayer     = nil
        statusObserver  = nil
    }

    // ─── ScreenSaverView Lifecycle ────────────────────────────────────────────

    override func startAnimation() {
        super.startAnimation()
        animationStarted = true
        if videoReady {
            playerLayer?.frame = bounds
            player?.seek(to: .zero)
            player?.play()
        }
    }

    override func stopAnimation() {
        animationStarted = false
        player?.pause()
        super.stopAnimation()
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        playerLayer?.frame = bounds
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }

    override func animateOneFrame() {
        // AVPlayerLayer handles all rendering — this is intentionally empty.
        // animationTimeInterval is set to 1.0s so this fires only once per second.
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
