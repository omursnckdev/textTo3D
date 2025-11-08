//
//  ARViewContainer.swift
//  MeshyApp
//
//  ARKit integration for viewing 3D models in augmented reality
//

import SwiftUI
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {
    let modelURL: URL
    @Binding var isPlaced: Bool

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure AR session
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        arView.session.run(config)

        // Add coaching overlay
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .horizontalPlane
        arView.addSubview(coachingOverlay)

        // Add tap gesture to place model
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        context.coordinator.arView = arView
        context.coordinator.loadModel()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Update if needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(modelURL: modelURL, isPlaced: $isPlaced)
    }

    class Coordinator: NSObject {
        let modelURL: URL
        @Binding var isPlaced: Bool
        var arView: ARView?
        var modelEntity: ModelEntity?

        init(modelURL: URL, isPlaced: Binding<Bool>) {
            self.modelURL = modelURL
            self._isPlaced = isPlaced
        }

        func loadModel() {
            Task {
                do {
                    // Load model asynchronously
                    let entity = try await ModelEntity.loadModel(contentsOf: modelURL)

                    // Scale model to appropriate size
                    entity.scale = SIMD3<Float>(0.01, 0.01, 0.01)

                    // Add model to scene (initially hidden)
                    entity.isEnabled = false

                    await MainActor.run {
                        self.modelEntity = entity
                    }
                } catch {
                    print("Failed to load model: \(error)")
                }
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView = arView,
                  let modelEntity = modelEntity else { return }

            let location = recognizer.location(in: arView)

            // Perform raycast to find surface
            let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)

            if let firstResult = results.first {
                // Create anchor at the raycast result
                let anchor = AnchorEntity(world: firstResult.worldTransform)

                // Clone the model entity
                let clonedModel = modelEntity.clone(recursive: true)
                clonedModel.isEnabled = true

                // Add interaction components
                clonedModel.generateCollisionShapes(recursive: true)

                // Enable gestures
                arView.installGestures([.translation, .rotation, .scale], for: clonedModel)

                // Add model to anchor
                anchor.addChild(clonedModel)

                // Add anchor to scene
                arView.scene.addAnchor(anchor)

                isPlaced = true
            }
        }
    }
}

// MARK: - AR Quick Look
struct ARQuickLookView: UIViewControllerRepresentable {
    let modelURL: URL

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()

        // Present AR Quick Look
        DispatchQueue.main.async {
            let previewController = QLPreviewController()
            previewController.dataSource = context.coordinator
            viewController.present(previewController, animated: true)
        }

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(modelURL: modelURL)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let modelURL: URL

        init(modelURL: URL) {
            self.modelURL = modelURL
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return modelURL as QLPreviewItem
        }
    }
}

import QuickLook
