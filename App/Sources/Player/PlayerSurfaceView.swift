import AVFoundation
import SwiftUI
import UIKit

/// UIView whose backing layer is an `AVPlayerLayer`.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var didReportLayer = false
}

/// Bare video surface (no system controls) that renders an `AVPlayer`.
struct PlayerSurfaceView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity
    var onLayerReady: (AVPlayerLayer) -> Void

    init(player: AVPlayer, videoGravity: AVLayerVideoGravity,
         onLayerReady: @escaping (AVPlayerLayer) -> Void) {
        self.player = player
        self.videoGravity = videoGravity
        self.onLayerReady = onLayerReady
    }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        if view.playerLayer.videoGravity != videoGravity {
            let gravity = videoGravity
            UIView.animate(withDuration: 0.25) {
                view.playerLayer.videoGravity = gravity
            }
        }
        if !view.didReportLayer {
            view.didReportLayer = true
            let layer = view.playerLayer
            let callback = onLayerReady
            DispatchQueue.main.async { callback(layer) }
        }
    }
}
