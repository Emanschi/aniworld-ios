import AVFoundation
import AVKit
import Foundation
import Observation

/// Wraps `AVPictureInPictureController` for the custom player surface.
@MainActor
@Observable
final class PictureInPictureController: NSObject, AVPictureInPictureControllerDelegate {
    var isPossible = false
    var isActive = false

    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    /// Called on the main actor whenever `isActive` changes.
    @ObservationIgnored var onActiveChange: ((Bool) -> Void)?

    func attach(to layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if let controller, controller.playerLayer === layer { return }
        possibleObservation = nil
        guard let pip = AVPictureInPictureController(playerLayer: layer) else { return }
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        controller = pip
        possibleObservation = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
            [weak self] pip, _ in
            let possible = pip.isPictureInPicturePossible
            Task { @MainActor in self?.isPossible = possible }
        }
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        }
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    private func setActive(_ active: Bool) {
        isActive = active
        onActiveChange?(active)
    }

    // MARK: AVPictureInPictureControllerDelegate

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.setActive(true) }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.setActive(false) }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
            @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}
