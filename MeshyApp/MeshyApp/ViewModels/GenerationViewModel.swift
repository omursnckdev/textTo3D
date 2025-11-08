//
//  GenerationViewModel.swift
//  MeshyApp
//
//  ViewModel for handling 3D generation
//

import Foundation
import SwiftUI
import Combine

class GenerationViewModel: ObservableObject {
    @Published var generations: [Generation] = []
    @Published var currentGeneration: Generation?
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var showError = false

    private let meshyAPI = MeshyAPIService.shared
    private let firestoreService = FirestoreService.shared
    private let authService = AuthenticationService.shared

    private var generationListeners: [String: ListenerRegistration] = [:]
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Text to 3D

    func generateTextTo3D(
        prompt: String,
        artStyle: ArtStyle,
        aiModel: AIModel,
        targetPolycount: Int,
        enablePBR: Bool,
        texturePrompt: String? = nil
    ) async {
        guard let userId = authService.user?.id else {
            await showErrorMessage("You must be logged in to generate models")
            return
        }

        // Check if user has enough credits
        let estimatedCost = aiModel.creditCost + (enablePBR ? 10 : 0)
        guard let userCredits = authService.user?.credits, userCredits >= estimatedCost else {
            await showErrorMessage("Insufficient credits. You need \(estimatedCost) credits.")
            return
        }

        await setGenerating(true)

        do {
            // Create generation record
            let generation = Generation(
                userId: userId,
                type: .textTo3D,
                status: .pending,
                progress: 0,
                prompt: prompt,
                artStyle: artStyle,
                aiModel: aiModel,
                enablePBR: enablePBR,
                targetPolycount: targetPolycount,
                createdAt: Date(),
                updatedAt: Date()
            )

            let generationId = try await firestoreService.createGeneration(generation)

            // Start listening to generation updates
            startListeningToGeneration(generationId: generationId)

            // Step 1: Create preview
            let previewTaskId = try await meshyAPI.createTextTo3DPreview(
                prompt: prompt,
                artStyle: artStyle,
                aiModel: aiModel,
                targetPolycount: targetPolycount
            )

            // Update generation with preview task ID
            try await firestoreService.updateGeneration(Generation(
                id: generationId,
                userId: userId,
                type: .textTo3D,
                status: .inProgress,
                progress: 10,
                previewTaskId: previewTaskId,
                prompt: prompt,
                artStyle: artStyle,
                aiModel: aiModel,
                enablePBR: enablePBR,
                targetPolycount: targetPolycount,
                createdAt: Date(),
                updatedAt: Date()
            ))

            // Poll preview task
            let previewTask = try await meshyAPI.pollTaskStatus(
                taskId: previewTaskId,
                type: .textTo3D
            )

            // Update progress
            try await firestoreService.updateGenerationStatus(
                generationId: generationId,
                status: .inProgress,
                progress: 50
            )

            // Step 2: Create refine task (add textures)
            let refineTaskId = try await meshyAPI.createTextTo3DRefine(
                previewTaskId: previewTaskId,
                enablePBR: enablePBR,
                texturePrompt: texturePrompt,
                aiModel: aiModel
            )

            // Update generation with refine task ID
            try await firestoreService.updateGenerationStatus(
                generationId: generationId,
                status: .inProgress,
                progress: 60
            )

            // Poll refine task
            let refineTask = try await meshyAPI.pollTaskStatus(
                taskId: refineTaskId,
                type: .textTo3D
            )

            // Create 3D model from result
            let model = createModel3D(
                from: refineTask,
                generationId: generationId,
                userId: userId
            )

            // Save model to Firestore
            let modelId = try await firestoreService.createModel(model)

            // Update generation with completed status
            try await firestoreService.updateGeneration(Generation(
                id: generationId,
                userId: userId,
                type: .textTo3D,
                status: .succeeded,
                progress: 100,
                previewTaskId: previewTaskId,
                refineTaskId: refineTaskId,
                prompt: prompt,
                artStyle: artStyle,
                aiModel: aiModel,
                enablePBR: enablePBR,
                targetPolycount: targetPolycount,
                model3D: model,
                thumbnailURL: refineTask.thumbnail_url,
                videoURL: refineTask.video_url,
                createdAt: Date(),
                updatedAt: Date(),
                completedAt: Date()
            ))

            // Deduct credits
            try await authService.updateCredits(amount: -estimatedCost)

            await setGenerating(false)

        } catch {
            await showErrorMessage("Generation failed: \(error.localizedDescription)")
            await setGenerating(false)
        }
    }

    // MARK: - Image to 3D

    func generateImageTo3D(
        imageURL: String,
        aiModel: AIModel,
        targetPolycount: Int,
        enablePBR: Bool,
        shouldTexture: Bool,
        texturePrompt: String? = nil
    ) async {
        guard let userId = authService.user?.id else {
            await showErrorMessage("You must be logged in to generate models")
            return
        }

        // Check if user has enough credits
        let estimatedCost = aiModel.creditCost + (shouldTexture ? 10 : 0)
        guard let userCredits = authService.user?.credits, userCredits >= estimatedCost else {
            await showErrorMessage("Insufficient credits. You need \(estimatedCost) credits.")
            return
        }

        await setGenerating(true)

        do {
            // Create generation record
            let generation = Generation(
                userId: userId,
                type: .imageTo3D,
                status: .pending,
                progress: 0,
                imageURL: imageURL,
                aiModel: aiModel,
                enablePBR: enablePBR,
                targetPolycount: targetPolycount,
                createdAt: Date(),
                updatedAt: Date()
            )

            let generationId = try await firestoreService.createGeneration(generation)

            // Start listening to generation updates
            startListeningToGeneration(generationId: generationId)

            // Create image-to-3D task
            let taskId = try await meshyAPI.createImageTo3D(
                imageURL: imageURL,
                aiModel: aiModel,
                enablePBR: enablePBR,
                shouldTexture: shouldTexture,
                targetPolycount: targetPolycount,
                texturePrompt: texturePrompt
            )

            // Update generation with task ID
            try await firestoreService.updateGenerationStatus(
                generationId: generationId,
                status: .inProgress,
                progress: 10
            )

            // Poll task status
            let task = try await meshyAPI.pollTaskStatus(
                taskId: taskId,
                type: .imageTo3D
            )

            // Create 3D model from result
            let model = createModel3D(
                from: task,
                generationId: generationId,
                userId: userId
            )

            // Save model to Firestore
            let modelId = try await firestoreService.createModel(model)

            // Update generation with completed status
            try await firestoreService.updateGeneration(Generation(
                id: generationId,
                userId: userId,
                type: .imageTo3D,
                status: .succeeded,
                progress: 100,
                taskId: taskId,
                imageURL: imageURL,
                aiModel: aiModel,
                enablePBR: enablePBR,
                targetPolycount: targetPolycount,
                model3D: model,
                thumbnailURL: task.thumbnail_url,
                videoURL: task.video_url,
                createdAt: Date(),
                updatedAt: Date(),
                completedAt: Date()
            ))

            // Deduct credits
            try await authService.updateCredits(amount: -estimatedCost)

            await setGenerating(false)

        } catch {
            await showErrorMessage("Generation failed: \(error.localizedDescription)")
            await setGenerating(false)
        }
    }

    // MARK: - Load Generations

    func loadUserGenerations() async {
        guard let userId = authService.user?.id else { return }

        do {
            let gens = try await firestoreService.getUserGenerations(userId: userId)
            await MainActor.run {
                self.generations = gens
            }
        } catch {
            await showErrorMessage("Failed to load generations: \(error.localizedDescription)")
        }
    }

    // MARK: - Helper Methods

    private func createModel3D(from task: TaskDetails, generationId: String, userId: String) -> Model3D {
        return Model3D(
            id: UUID().uuidString,
            generationId: generationId,
            userId: userId,
            glbURL: task.model_urls?.glb,
            fbxURL: task.model_urls?.fbx,
            objURL: task.model_urls?.obj,
            usdzURL: task.model_urls?.usdz,
            mtlURL: task.model_urls?.mtl,
            baseColorURL: task.texture_urls?.first?.base_color,
            metallicURL: task.texture_urls?.first?.metallic,
            normalURL: task.texture_urls?.first?.normal,
            roughnessURL: task.texture_urls?.first?.roughness,
            thumbnailURL: task.thumbnail_url,
            videoURL: task.video_url,
            hasPBR: task.texture_urls?.first?.metallic != nil,
            createdAt: Date(),
            expiresAt: task.expires_at != nil ? Date(timeIntervalSince1970: TimeInterval(task.expires_at! / 1000)) : nil,
            isDownloaded: false,
            isFavorite: false,
            isPublic: false,
            tags: []
        )
    }

    private func startListeningToGeneration(generationId: String) {
        let listener = firestoreService.listenToGeneration(generationId: generationId) { [weak self] result in
            switch result {
            case .success(let generation):
                Task { @MainActor in
                    self?.currentGeneration = generation
                }
            case .failure(let error):
                print("Error listening to generation: \(error)")
            }
        }

        generationListeners[generationId] = listener
    }

    @MainActor
    private func setGenerating(_ value: Bool) {
        isGenerating = value
    }

    @MainActor
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    func cancelGeneration(generationId: String) async {
        // Implement cancellation logic
        try? await firestoreService.updateGenerationStatus(
            generationId: generationId,
            status: .canceled
        )
    }

    deinit {
        generationListeners.values.forEach { $0.remove() }
    }
}
