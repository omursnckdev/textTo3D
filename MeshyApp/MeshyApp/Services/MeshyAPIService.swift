//
//  MeshyAPIService.swift
//  MeshyApp
//
//  Service for interacting with Meshy API
//

import Foundation
import Combine

class MeshyAPIService {
    static let shared = MeshyAPIService()

    private let apiKey = "msy_RXfyMYJnX171yRZo0Byx6NQQbD16cJJqyIrJ"
    private let baseURL = "https://api.meshy.ai"

    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Text to 3D

    /// Create a preview task for text-to-3D
    func createTextTo3DPreview(
        prompt: String,
        artStyle: ArtStyle = .realistic,
        aiModel: AIModel = .latest,
        targetPolycount: Int = 30000,
        negativPrompt: String? = nil
    ) async throws -> String {
        let endpoint = "/openapi/v2/text-to-3d"
        let url = URL(string: baseURL + endpoint)!

        var body: [String: Any] = [
            "mode": "preview",
            "prompt": prompt,
            "art_style": artStyle.rawValue,
            "ai_model": aiModel.rawValue,
            "target_polycount": targetPolycount,
            "should_remesh": true
        ]

        if let negativPrompt = negativPrompt {
            body["negative_prompt"] = negativPrompt
        }

        let (data, response) = try await performRequest(url: url, method: "POST", body: body)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MeshyAPIError.invalidResponse
        }

        let result = try JSONDecoder().decode(TaskResponse.self, from: data)
        return result.result
    }

    /// Create a refine task for text-to-3D (adds textures)
    func createTextTo3DRefine(
        previewTaskId: String,
        enablePBR: Bool = true,
        texturePrompt: String? = nil,
        aiModel: AIModel = .latest
    ) async throws -> String {
        let endpoint = "/openapi/v2/text-to-3d"
        let url = URL(string: baseURL + endpoint)!

        var body: [String: Any] = [
            "mode": "refine",
            "preview_task_id": previewTaskId,
            "enable_pbr": enablePBR,
            "ai_model": aiModel.rawValue
        ]

        if let texturePrompt = texturePrompt {
            body["texture_prompt"] = texturePrompt
        }

        let (data, response) = try await performRequest(url: url, method: "POST", body: body)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MeshyAPIError.invalidResponse
        }

        let result = try JSONDecoder().decode(TaskResponse.self, from: data)
        return result.result
    }

    /// Get task status for text-to-3D
    func getTextTo3DTask(taskId: String) async throws -> TaskDetails {
        let endpoint = "/openapi/v2/text-to-3d/\(taskId)"
        let url = URL(string: baseURL + endpoint)!

        let (data, response) = try await performRequest(url: url, method: "GET")

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MeshyAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(TaskDetails.self, from: data)
    }

    // MARK: - Image to 3D

    /// Create image-to-3D task
    func createImageTo3D(
        imageURL: String,
        aiModel: AIModel = .latest,
        enablePBR: Bool = true,
        shouldTexture: Bool = true,
        targetPolycount: Int = 30000,
        texturePrompt: String? = nil
    ) async throws -> String {
        let endpoint = "/openapi/v1/image-to-3d"
        let url = URL(string: baseURL + endpoint)!

        var body: [String: Any] = [
            "image_url": imageURL,
            "ai_model": aiModel.rawValue,
            "enable_pbr": enablePBR,
            "should_texture": shouldTexture,
            "target_polycount": targetPolycount,
            "should_remesh": true
        ]

        if let texturePrompt = texturePrompt {
            body["texture_prompt"] = texturePrompt
        }

        let (data, response) = try await performRequest(url: url, method: "POST", body: body)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MeshyAPIError.invalidResponse
        }

        let result = try JSONDecoder().decode(TaskResponse.self, from: data)
        return result.result
    }

    /// Get task status for image-to-3D
    func getImageTo3DTask(taskId: String) async throws -> TaskDetails {
        let endpoint = "/openapi/v1/image-to-3d/\(taskId)"
        let url = URL(string: baseURL + endpoint)!

        let (data, response) = try await performRequest(url: url, method: "GET")

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MeshyAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(TaskDetails.self, from: data)
    }

    // MARK: - Helper Methods

    private func performRequest(
        url: URL,
        method: String,
        body: [String: Any]? = nil
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return try await URLSession.shared.data(for: request)
    }

    /// Poll task status until completion or failure
    func pollTaskStatus(
        taskId: String,
        type: GenerationType,
        maxAttempts: Int = 120,
        intervalSeconds: TimeInterval = 5
    ) async throws -> TaskDetails {
        var attempts = 0

        while attempts < maxAttempts {
            let task = try await (type == .textTo3D
                ? getTextTo3DTask(taskId: taskId)
                : getImageTo3DTask(taskId: taskId))

            switch task.status {
            case "SUCCEEDED":
                return task
            case "FAILED", "CANCELED":
                throw MeshyAPIError.taskFailed(task.task_error?.message ?? "Unknown error")
            default:
                // Still in progress, wait and try again
                try await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                attempts += 1
            }
        }

        throw MeshyAPIError.timeout
    }
}

// MARK: - Response Models

struct TaskResponse: Codable {
    let result: String
}

struct TaskDetails: Codable {
    let id: String
    let status: String
    let progress: Int?
    let model_urls: ModelURLs?
    let texture_urls: [TextureURL]?
    let thumbnail_url: String?
    let video_url: String?
    let task_error: TaskError?
    let created_at: Int?
    let started_at: Int?
    let finished_at: Int?
    let expires_at: Int?
}

struct ModelURLs: Codable {
    let glb: String?
    let fbx: String?
    let obj: String?
    let mtl: String?
    let usdz: String?
}

struct TextureURL: Codable {
    let base_color: String?
    let metallic: String?
    let normal: String?
    let roughness: String?
}

struct TaskError: Codable {
    let message: String?
}

// MARK: - Errors

enum MeshyAPIError: LocalizedError {
    case invalidResponse
    case taskFailed(String)
    case timeout
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .taskFailed(let message):
            return "Task failed: \(message)"
        case .timeout:
            return "Request timed out"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
