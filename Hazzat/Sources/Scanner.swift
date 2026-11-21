import SwiftUI
import UIKit
@preconcurrency import VisionKit

/// The iPhone document camera: scan several sheets in a row, straightened and cropped.
struct DocumentScanner: UIViewControllerRepresentable {
    let finish: @MainActor ([UIImage]) -> Void

    @MainActor static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator { Coordinator(finish: finish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let finish: @MainActor ([UIImage]) -> Void

        init(finish: @escaping @MainActor ([UIImage]) -> Void) {
            self.finish = finish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            finish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            finish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            finish([])
        }
    }
}
