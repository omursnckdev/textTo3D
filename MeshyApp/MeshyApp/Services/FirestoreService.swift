//
//  FirestoreService.swift
//  MeshyApp
//
//  Firestore database service
//

import Foundation
import FirebaseFirestore
import Combine

class FirestoreService {
    static let shared = FirestoreService()

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Collections

    private var usersCollection: CollectionReference {
        db.collection("users")
    }

    private var generationsCollection: CollectionReference {
        db.collection("generations")
    }

    private var modelsCollection: CollectionReference {
        db.collection("models")
    }

    // MARK: - User Methods

    func createUser(_ user: AppUser) async throws {
        guard let userId = user.id else {
            throw FirestoreError.invalidUserId
        }

        try usersCollection.document(userId).setData(from: user)
    }

    func getUser(userId: String) async throws -> AppUser? {
        let snapshot = try await usersCollection.document(userId).getDocument()
        return try snapshot.data(as: AppUser.self)
    }

    func updateLastLogin(userId: String) async throws {
        try await usersCollection.document(userId).updateData([
            "lastLoginAt": FieldValue.serverTimestamp()
        ])
    }

    func updateUserCredits(userId: String, amount: Int) async throws {
        try await usersCollection.document(userId).updateData([
            "credits": FieldValue.increment(Int64(amount))
        ])
    }

    func updateSubscription(userId: String, type: SubscriptionType, endDate: Date?) async throws {
        var data: [String: Any] = [
            "subscriptionType": type.rawValue
        ]

        if let endDate = endDate {
            data["subscriptionEndDate"] = Timestamp(date: endDate)
        }

        try await usersCollection.document(userId).updateData(data)
    }

    func deleteUser(userId: String) async throws {
        // Delete all user's generations
        let generations = try await getUserGenerations(userId: userId)
        for generation in generations {
            if let genId = generation.id {
                try await deleteGeneration(generationId: genId)
            }
        }

        // Delete user document
        try await usersCollection.document(userId).delete()
    }

    // MARK: - Generation Methods

    func createGeneration(_ generation: Generation) async throws -> String {
        let ref = try generationsCollection.addDocument(from: generation)
        return ref.documentID
    }

    func getGeneration(generationId: String) async throws -> Generation? {
        let snapshot = try await generationsCollection.document(generationId).getDocument()
        return try snapshot.data(as: Generation.self)
    }

    func updateGeneration(_ generation: Generation) async throws {
        guard let generationId = generation.id else {
            throw FirestoreError.invalidGenerationId
        }

        try generationsCollection.document(generationId).setData(from: generation, merge: true)
    }

    func updateGenerationStatus(
        generationId: String,
        status: GenerationStatus,
        progress: Int? = nil,
        errorMessage: String? = nil
    ) async throws {
        var data: [String: Any] = [
            "status": status.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let progress = progress {
            data["progress"] = progress
        }

        if let errorMessage = errorMessage {
            data["errorMessage"] = errorMessage
        }

        if status == .succeeded {
            data["completedAt"] = FieldValue.serverTimestamp()
        }

        try await generationsCollection.document(generationId).updateData(data)
    }

    func getUserGenerations(userId: String, limit: Int = 50) async throws -> [Generation] {
        let snapshot = try await generationsCollection
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: Generation.self)
        }
    }

    func deleteGeneration(generationId: String) async throws {
        try await generationsCollection.document(generationId).delete()
    }

    // MARK: - Model Methods

    func createModel(_ model: Model3D) async throws -> String {
        let ref = try modelsCollection.addDocument(from: model)
        return ref.documentID
    }

    func getModel(modelId: String) async throws -> Model3D? {
        let snapshot = try await modelsCollection.document(modelId).getDocument()
        return try snapshot.data(as: Model3D.self)
    }

    func updateModel(_ model: Model3D) async throws {
        guard let modelId = model.id else {
            throw FirestoreError.invalidModelId
        }

        try modelsCollection.document(modelId).setData(from: model, merge: true)
    }

    func getUserModels(userId: String, limit: Int = 50) async throws -> [Model3D] {
        let snapshot = try await modelsCollection
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: Model3D.self)
        }
    }

    func getFavoriteModels(userId: String) async throws -> [Model3D] {
        let snapshot = try await modelsCollection
            .whereField("userId", isEqualTo: userId)
            .whereField("isFavorite", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: Model3D.self)
        }
    }

    func toggleFavorite(modelId: String, isFavorite: Bool) async throws {
        try await modelsCollection.document(modelId).updateData([
            "isFavorite": isFavorite
        ])
    }

    func deleteModel(modelId: String) async throws {
        try await modelsCollection.document(modelId).delete()
    }

    // MARK: - Real-time Listeners

    func listenToGeneration(
        generationId: String,
        completion: @escaping (Result<Generation, Error>) -> Void
    ) -> ListenerRegistration {
        return generationsCollection.document(generationId).addSnapshotListener { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let snapshot = snapshot else {
                completion(.failure(FirestoreError.documentNotFound))
                return
            }

            do {
                let generation = try snapshot.data(as: Generation.self)
                completion(.success(generation))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Firestore Errors

enum FirestoreError: LocalizedError {
    case invalidUserId
    case invalidGenerationId
    case invalidModelId
    case documentNotFound

    var errorDescription: String? {
        switch self {
        case .invalidUserId:
            return "Invalid user ID"
        case .invalidGenerationId:
            return "Invalid generation ID"
        case .invalidModelId:
            return "Invalid model ID"
        case .documentNotFound:
            return "Document not found"
        }
    }
}
