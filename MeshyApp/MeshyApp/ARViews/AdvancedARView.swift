//
//  AdvancedARView.swift
//  MeshyApp
//
//  Advanced AR view with animations and interactions
//

import SwiftUI
import RealityKit
import ARKit
import Combine

struct AdvancedARView: View {
    let model: Model3D
    @Environment(\.dismiss) var dismiss
    @StateObject private var arViewModel = ARViewModel()

    @State private var showControls = true
    @State private var showSettings = false
    @State private var selectedAnimation: String?

    var body: some View {
        ZStack {
            // AR View
            AdvancedARViewContainer(
                model: model,
                viewModel: arViewModel
            )
            .ignoresSafeArea()

            // Top controls
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                            .background(NeonTheme.cardBackground.opacity(0.8))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                            .background(NeonTheme.cardBackground.opacity(0.8))
                            .clipShape(Circle())
                    }
                }
                .padding()
                .opacity(showControls ? 1 : 0)

                Spacer()

                // Bottom controls
                if showControls {
                    VStack(spacing: 15) {
                        // Object info
                        if let placedObject = arViewModel.placedObjects.first {
                            HStack {
                                Text("Tap to animate • Pinch to scale • Drag to move")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(NeonTheme.cardBackground.opacity(0.8))
                            .cornerRadius(20)
                        }

                        // Action buttons
                        HStack(spacing: 15) {
                            ARActionButton(
                                icon: "cube.fill",
                                title: "Place",
                                color: NeonTheme.neonPurple
                            ) {
                                arViewModel.placementMode = .single
                            }

                            ARActionButton(
                                icon: "play.fill",
                                title: "Animate",
                                color: NeonTheme.neonBlue
                            ) {
                                arViewModel.playAnimation()
                            }

                            ARActionButton(
                                icon: "camera.fill",
                                title: "Photo",
                                color: NeonTheme.neonCyan
                            ) {
                                arViewModel.takeScreenshot()
                            }

                            ARActionButton(
                                icon: "trash.fill",
                                title: "Clear",
                                color: NeonTheme.neonPink
                            ) {
                                arViewModel.clearAll()
                            }
                        }
                        .padding()
                        .background(NeonTheme.cardBackground.opacity(0.8))
                        .cornerRadius(25)
                    }
                    .padding()
                }
            }

            // Settings panel
            if showSettings {
                ARSettingsPanel(viewModel: arViewModel)
                    .transition(.move(edge: .trailing))
            }
        }
        .statusBar(hidden: true)
        .onTapGesture {
            withAnimation {
                showControls.toggle()
            }
        }
    }
}

// MARK: - Advanced AR View Container
struct AdvancedARViewContainer: UIViewRepresentable {
    let model: Model3D
    @ObservedObject var viewModel: ARViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure AR session
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        arView.session.run(config)

        // Add coaching overlay
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .horizontalPlane
        arView.addSubview(coachingOverlay)

        // Add gestures
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tapGesture)

        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        arView.addGestureRecognizer(longPressGesture)

        context.coordinator.arView = arView
        context.coordinator.loadModel()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.viewModel = viewModel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, viewModel: viewModel)
    }

    class Coordinator: NSObject {
        let model: Model3D
        var viewModel: ARViewModel
        var arView: ARView?
        var modelEntity: ModelEntity?
        var placedEntities: [AnchorEntity] = []

        init(model: Model3D, viewModel: ARViewModel) {
            self.model = model
            self.viewModel = viewModel
        }

        func loadModel() {
            guard let urlString = model.usdzURL ?? model.glbURL,
                  let url = URL(string: urlString) else { return }

            Task {
                do {
                    let entity = try await ModelEntity.loadModel(contentsOf: url)

                    // Scale model
                    entity.scale = SIMD3<Float>(
                        viewModel.modelScale,
                        viewModel.modelScale,
                        viewModel.modelScale
                    )

                    // Add collision shapes for interaction
                    entity.generateCollisionShapes(recursive: true)

                    // Enable physics if enabled
                    if viewModel.physicsEnabled {
                        entity.physicsBody = PhysicsBodyComponent(
                            massProperties: .default,
                            mode: .dynamic
                        )
                    }

                    await MainActor.run {
                        self.modelEntity = entity

                        // Load animations if available
                        if entity.availableAnimations.count > 0 {
                            viewModel.availableAnimations = entity.availableAnimations.map { $0.name ?? "Animation" }
                        }
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

            // Check if tapping on an existing object
            if let entity = arView.entity(at: location) as? ModelEntity {
                // Play animation on tap
                if !entity.availableAnimations.isEmpty {
                    let animation = entity.availableAnimations[0]
                    entity.playAnimation(animation.repeat())

                    // Add tap animation effect
                    var transform = entity.transform
                    transform.scale *= 1.1
                    entity.move(to: transform, relativeTo: entity.parent, duration: 0.1)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        transform.scale /= 1.1
                        entity.move(to: transform, relativeTo: entity.parent, duration: 0.1)
                    }
                }
                return
            }

            // Place new object
            if viewModel.placementMode != .none {
                let results = arView.raycast(
                    from: location,
                    allowing: .estimatedPlane,
                    alignment: .any
                )

                if let firstResult = results.first {
                    let anchor = AnchorEntity(world: firstResult.worldTransform)
                    let clonedModel = modelEntity.clone(recursive: true)

                    // Apply settings
                    clonedModel.scale = SIMD3<Float>(
                        repeating: viewModel.modelScale
                    )

                    // Enable gestures
                    arView.installGestures(
                        [.translation, .rotation, .scale],
                        for: clonedModel
                    )

                    // Add lighting
                    if viewModel.dynamicLightingEnabled {
                        let light = DirectionalLight()
                        light.light.intensity = 1000
                        light.light.color = .white
                        light.shadow = DirectionalLightComponent.Shadow()
                        anchor.addChild(light)
                    }

                    anchor.addChild(clonedModel)
                    arView.scene.addAnchor(anchor)

                    placedEntities.append(anchor)
                    viewModel.placedObjects.append(clonedModel)

                    // Placement animation
                    clonedModel.scale = SIMD3<Float>(0.01, 0.01, 0.01)
                    clonedModel.move(
                        to: Transform(
                            scale: SIMD3<Float>(
                                repeating: viewModel.modelScale
                            ),
                            rotation: clonedModel.transform.rotation,
                            translation: clonedModel.transform.translation
                        ),
                        relativeTo: clonedModel.parent,
                        duration: 0.3,
                        timingFunction: .easeOut
                    )
                }
            }
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let arView = arView else { return }

            if recognizer.state == .began {
                let location = recognizer.location(in: arView)

                if let entity = arView.entity(at: location) as? ModelEntity,
                   let anchorEntity = entity.anchor {
                    // Remove entity with animation
                    entity.scale *= 0.01

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        arView.scene.removeAnchor(anchorEntity)
                        self.placedEntities.removeAll { $0 == anchorEntity }
                        self.viewModel.placedObjects.removeAll { $0 == entity }
                    }
                }
            }
        }
    }
}

// MARK: - AR View Model
class ARViewModel: ObservableObject {
    @Published var placementMode: PlacementMode = .single
    @Published var placedObjects: [ModelEntity] = []
    @Published var availableAnimations: [String] = []
    @Published var currentAnimation: String?
    @Published var modelScale: Float = 0.01
    @Published var physicsEnabled = false
    @Published var occlusionEnabled = true
    @Published var dynamicLightingEnabled = true
    @Published var shadowsEnabled = true

    enum PlacementMode {
        case none
        case single
        case multiple
    }

    func playAnimation() {
        guard !availableAnimations.isEmpty else { return }

        for entity in placedObjects {
            if !entity.availableAnimations.isEmpty {
                let animation = entity.availableAnimations[0]
                entity.playAnimation(animation.repeat())
            }
        }
    }

    func stopAnimation() {
        for entity in placedObjects {
            entity.stopAllAnimations()
        }
    }

    func clearAll() {
        placedObjects.removeAll()
    }

    func takeScreenshot() {
        // Screenshot functionality
        if let window = UIApplication.shared.windows.first {
            UIGraphicsBeginImageContextWithOptions(window.bounds.size, false, 0)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            if let image = image {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        }
    }
}

// MARK: - AR Action Button
struct ARActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(.white)
            .frame(width: 70, height: 70)
            .background(color.opacity(0.3))
            .cornerRadius(15)
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(color, lineWidth: 1)
            )
        }
    }
}

// MARK: - AR Settings Panel
struct ARSettingsPanel: View {
    @ObservedObject var viewModel: ARViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("AR Settings")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            // Scale slider
            VStack(alignment: .leading, spacing: 10) {
                Text("Model Scale: \(String(format: "%.2f", viewModel.modelScale))")
                    .foregroundColor(.white)

                Slider(value: $viewModel.modelScale, in: 0.001...0.1)
                    .tint(NeonTheme.neonPurple)
            }

            Divider().background(NeonTheme.neonPurple.opacity(0.3))

            // Toggle settings
            Toggle("Physics", isOn: $viewModel.physicsEnabled)
                .tint(NeonTheme.neonPurple)

            Toggle("Occlusion", isOn: $viewModel.occlusionEnabled)
                .tint(NeonTheme.neonPurple)

            Toggle("Dynamic Lighting", isOn: $viewModel.dynamicLightingEnabled)
                .tint(NeonTheme.neonPurple)

            Toggle("Shadows", isOn: $viewModel.shadowsEnabled)
                .tint(NeonTheme.neonPurple)

            Spacer()
        }
        .foregroundColor(.white)
        .padding()
        .frame(width: 300)
        .background(NeonTheme.cardBackground.opacity(0.95))
        .cornerRadius(20)
    }
}
