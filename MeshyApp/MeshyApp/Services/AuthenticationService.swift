//
//  AuthenticationService.swift
//  MeshyApp
//
//  Firebase Authentication Service
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()

    @Published var user: AppUser?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let auth = Auth.auth()
    private let firestoreService = FirestoreService.shared
    private var authStateListener: AuthStateDidChangeListenerHandle?

    private init() {
        setupAuthStateListener()
    }

    deinit {
        if let listener = authStateListener {
            auth.removeStateDidChangeListener(listener)
        }
    }

    // MARK: - Auth State Listener

    private func setupAuthStateListener() {
        authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }

            if let user = user {
                Task {
                    await self.loadUserData(uid: user.uid)
                }
            } else {
                self.user = nil
                self.isAuthenticated = false
            }
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            await loadUserData(uid: result.user.uid)

            // Update last login
            try await firestoreService.updateLastLogin(userId: result.user.uid)

            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, displayName: String) async throws {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await auth.createUser(withEmail: email, password: password)

            // Create user profile in Firestore
            let newUser = AppUser(
                id: result.user.uid,
                email: email,
                displayName: displayName,
                credits: 10 // Welcome bonus
            )

            try await firestoreService.createUser(newUser)
            await loadUserData(uid: result.user.uid)

            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign Out

    func signOut() throws {
        do {
            try auth.signOut()
            user = nil
            isAuthenticated = false
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email)
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        guard let currentUser = auth.currentUser else {
            throw AuthError.notAuthenticated
        }

        // Delete Firestore data
        try await firestoreService.deleteUser(userId: currentUser.uid)

        // Delete Auth account
        try await currentUser.delete()

        user = nil
        isAuthenticated = false
    }

    // MARK: - Load User Data

    private func loadUserData(uid: String) async {
        do {
            if let userData = try await firestoreService.getUser(userId: uid) {
                await MainActor.run {
                    self.user = userData
                    self.isAuthenticated = true
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load user data: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Update User Credits

    func updateCredits(amount: Int) async throws {
        guard let userId = user?.id else {
            throw AuthError.notAuthenticated
        }

        try await firestoreService.updateUserCredits(userId: userId, amount: amount)
        await loadUserData(uid: userId)
    }

    // MARK: - Update Subscription

    func updateSubscription(type: SubscriptionType, endDate: Date?) async throws {
        guard let userId = user?.id else {
            throw AuthError.notAuthenticated
        }

        try await firestoreService.updateSubscription(
            userId: userId,
            type: type,
            endDate: endDate
        )
        await loadUserData(uid: userId)
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notAuthenticated
    case invalidCredentials
    case userNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .invalidCredentials:
            return "Invalid email or password"
        case .userNotFound:
            return "User not found"
        }
    }
}
