import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit

/// A gaplessly-looping video filling its container — the AVFoundation building blocks SwiftUI's
/// `VideoPlayer` doesn't expose (no playback controls, frame-accurate looping via
/// `AVPlayerLooper`), used for the intro screen's background video.
struct LoopingVideoBackground: UIViewRepresentable {
    let resource: String
    let fileExtension: String
    var isMuted: Bool

    func makeUIView(context: Context) -> PlayerContainerView {
        // `.playback` so the video's sound plays even with the silent switch on, like any other
        // app that plays intentional foreground media (e.g. a movie trailer).
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let view = PlayerContainerView()
        view.start(resource: resource, fileExtension: fileExtension, isMuted: isMuted)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.setMuted(isMuted)
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        /// Keeps the looper alive — it stops looping the moment it's deallocated.
        private var looper: AVPlayerLooper?

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func start(resource: String, fileExtension: String, isMuted: Bool) {
            guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension) else { return }
            let queuePlayer = AVQueuePlayer()
            queuePlayer.isMuted = isMuted
            looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: url))
            playerLayer.player = queuePlayer
            queuePlayer.play()
        }

        func setMuted(_ isMuted: Bool) {
            playerLayer.player?.isMuted = isMuted
        }
    }
}
#elseif os(macOS)
import AppKit

/// macOS counterpart of the iOS looping video background — same `AVPlayerLooper` approach, on an
/// `NSView` instead of a `UIView`.
struct LoopingVideoBackground: NSViewRepresentable {
    let resource: String
    let fileExtension: String
    var isMuted: Bool

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.start(resource: resource, fileExtension: fileExtension, isMuted: isMuted)
        return view
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        nsView.setMuted(isMuted)
    }

    final class PlayerContainerView: NSView {
        private let playerLayer = AVPlayerLayer()
        private var looper: AVPlayerLooper?

        override init(frame: CGRect) {
            super.init(frame: frame)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspectFill
            layer = playerLayer
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func start(resource: String, fileExtension: String, isMuted: Bool) {
            guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension) else { return }
            let queuePlayer = AVQueuePlayer()
            queuePlayer.isMuted = isMuted
            looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: url))
            playerLayer.player = queuePlayer
            queuePlayer.play()
        }

        func setMuted(_ isMuted: Bool) {
            playerLayer.player?.isMuted = isMuted
        }
    }
}
#endif
