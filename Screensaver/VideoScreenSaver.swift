// ─────────────────────────────────────────────────────────────────────────────
//  VideoScreenSaver.swift
//  A macOS screensaver that plays a looping video — battery efficient
//
//  IMPORTANT: Use H.264 (not HEVC) — HEVC renders black via AVPlayerLayer
//  on macOS 26. M-series has hardware H.264 decoder, so battery is identical.
//
//  SET YOUR VIDEO:
//    ./set-video.sh ~/Movies/wallpaper.mp4
//    (embeds the video inside the .saver bundle)
//
//  Build:   ./build_screensaver.sh
//  Install: System Settings > Screen Saver > Video Screen Saver
// ─────────────────────────────────────────────────────────────────────────────

import ScreenSaver
import AVFoundation

@objc(VideoScreenSaverView)
class VideoScreenSaverView: ScreenSaverView {

    // ── State ──
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var statusObserver: NSKeyValueObservation?
    private var messageLabel: NSTextField?

    // ── Init ───────────────────────────────────────────────────────────────────

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        // AVPlayerLayer handles rendering; this timer is just a heartbeat (1 fps)
        animationTimeInterval = 1.0

        if let url = findVideoURL() {
            configurePlayer(url: url, isPreview: isPreview)
        } else {
            showMessage(
                "No video embedded.\n\n"
              + "Run from the Screensaver folder:\n"
              + "  ./set-video.sh /path/to/video.mp4\n\n"
              + "Important: Use H.264 codec, not HEVC.\n"
              + "Supported: .mp4  .m4v  .mov")
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        tearDown()
    }

    // ─── Video Lookup ─────────────────────────────────────────────────────────

    private func findVideoURL() -> URL? {
        // Video is embedded in the bundle's Resources by set-video.sh
        let bundle = Bundle(for: type(of: self))
        for ext in ["mp4", "m4v", "mov"] {
            if let url = bundle.url(forResource: "video", withExtension: ext) {
                return url
            }
        }
        return nil
    }

    // ─── Player Setup ─────────────────────────────────────────────────────────

    private func configurePlayer(url: URL, isPreview: Bool) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        // Battery optimizations
        item.preferredForwardBufferDuration = 2
        if isPreview {
            item.preferredMaximumResolution = CGSize(width: 640, height: 480)
        } else {
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

        // Surface errors instead of silent black screen
        statusObserver = qp.observe(\.status, options: [.new]) { [weak self] p, _ in
            if p.status == .failed {
                DispatchQueue.main.async {
                    self?.tearDown()
                    self?.showMessage(
                        "Playback failed:\n\(p.error?.localizedDescription ?? "unknown")\n\n"
                      + "Re-encode with H.264:\n"
                      + "  ffmpeg -i input -c:v h264_videotoolbox -b:v 6M -r 24 -an output.mp4")
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
    }

    // ─── Message Display ──────────────────────────────────────────────────────

    private func showMessage(_ text: String) {
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
        looper?.disableLooping()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerLayer?.removeFromSuperlayer()
        statusObserver?.invalidate()
        looper = nil; player = nil; playerLayer = nil; statusObserver = nil
    }

    // ─── ScreenSaverView Lifecycle ────────────────────────────────────────────

    override func startAnimation() {
        super.startAnimation()
        playerLayer?.frame = bounds
        player?.seek(to: .zero)
        player?.play()
    }

    override func stopAnimation() {
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
        // AVPlayerLayer handles all rendering — intentionally empty
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
