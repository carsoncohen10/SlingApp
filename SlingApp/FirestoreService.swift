import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift
import FirebaseAuth
import FirebaseStorage
import UIKit

// MARK: - Balance Data Structures

struct BalanceTransaction: Identifiable {
    let id: String
    let betId: String
    let betTitle: String
    let amount: Double
    let isOwed: Bool // true = you owe them, false = they owe you
    let date: Date
    let communityName: String
}

struct ResolvedBalance: Identifiable {
    let id: String
    let profilePicture: String?
    let username: String
    let name: String
    let netAmount: Double // Net amount that was resolved
    let transactions: [BalanceTransaction] // Individual transactions that made up this balance
    let counterpartyId: String
    let resolvedDate: Date // When it was marked as resolved
    let resolvedBy: String // "paid" or "received"
    
    // Computed properties
    var wasOwed: Bool { netAmount < 0 } // true = you owed them, false = they owed you
    var displayAmount: Double { abs(netAmount) }
    var isPositive: Bool { netAmount > 0 }
}

struct CommunityMemberInfo: Identifiable, Hashable {
    let id: String
    let email: String
    let name: String
    let isActive: Bool
    let joinDate: Date
    let isAdmin: Bool
    
    init(id: String, email: String, name: String, isActive: Bool, joinDate: Date, isAdmin: Bool = false) {
        self.id = id
        self.email = email
        self.name = name
        self.isActive = isActive
        self.joinDate = joinDate
        self.isAdmin = isAdmin
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CommunityMemberInfo, rhs: CommunityMemberInfo) -> Bool {
        return lhs.id == rhs.id
    }
}

struct CommunityMemberWithPoints: Identifiable {
    let member: CommunityMemberInfo
    let netPoints: Double
    
    var id: String { member.id }
    var email: String { member.email }
    var name: String { member.name }
    var isActive: Bool { member.isActive }
    var joinDate: Date { member.joinDate }
    var isAdmin: Bool { member.isAdmin }
}

class FirestoreService: ObservableObject {
    @Published var communities: [FirestoreCommunity] = []
    @Published var userCommunities: [FirestoreCommunity] = []
    @Published var bets: [FirestoreBet] = []
    @Published var userBetParticipations: [BetParticipant] = []
    @Published var currentUser: FirestoreUser?
    @Published var isAuthenticated: Bool = false
    @Published var notifications: [FirestoreNotification] = []
    @Published var messages: [CommunityMessage] = []
    @Published var communityLastMessages: [String: CommunityMessage] = [:] // Community ID -> Last Message
    @Published var mutedCommunities: Set<String> = [] // Community IDs that are muted
    @Published var totalUnreadCount: Int = 0 // Total unread messages across all communities
    private var messageListener: ListenerRegistration?
    
    var db = Firestore.firestore()
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    init() {
        setupAuthStateListener()
    }
    
    deinit {
        stopListeningToMessages()
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] auth, user in
            DispatchQueue.main.async {
                if let user = user {
                    self?.isAuthenticated = true
                    self?.fetchCurrentUser(userId: user.uid)
                } else {
                    self?.isAuthenticated = false
                    self?.currentUser = nil
                }
            }
        }
    }
    
    private func fetchCurrentUser(userId: String) {

        
        // Since user documents are stored using email as document ID, try to get email first
        if let userEmail = Auth.auth().currentUser?.email {
            print("📧 Found email from Auth: \(userEmail), fetching user document")
            db.collection("Users").document(userEmail).getDocument { [weak self] document, error in
                DispatchQueue.main.async {
                    if let document = document, document.exists {
                        print("✅ User document found by email")
                        
                        // Try to decode the user
                        do {
                            let user = try document.data(as: FirestoreUser.self)
                            print("✅ User loaded: \(user.displayName) (\(user.blitz_points ?? 0) points)")
                            self?.currentUser = user
                        } catch {
                            print("❌ Error decoding user: \(error)")
                            SlingLogError("Failed to decode user from Firestore", error: error)
                        }
                        
                        // Fetch user bet participations when user is loaded
                        self?.fetchUserBetParticipations()
                        // Load muted communities
                        self?.loadMutedCommunities()
                        // Load user communities (this will also fetch last messages)
                        self?.fetchUserCommunities()
                    } else {
                        print("❌ User document not found by email, trying UID fallback")
                        // Fallback to UID if email not found (for backward compatibility)
                        self?.db.collection("Users").document(userId).getDocument { [weak self] uidDocument, uidError in
                            DispatchQueue.main.async {
                                if let uidDocument = uidDocument, uidDocument.exists {
                                    print("✅ User document found by UID fallback")
                                    
                                    do {
                                        let user = try uidDocument.data(as: FirestoreUser.self)
                                        print("✅ User loaded by UID: \(user.displayName) (\(user.blitz_points ?? 0) points)")
                                        self?.currentUser = user
                                    } catch {
                                        print("❌ Error decoding user by UID: \(error)")
                                    }
                                    
                                    // Fetch user bet participations when user is loaded
                                    self?.fetchUserBetParticipations()
                                    // Load muted communities
                                    self?.loadMutedCommunities()
                                    // Load user communities (this will also fetch last messages)
                                    self?.fetchUserCommunities()
                                } else {
                                    print("❌ User document not found by email or UID - Forcing sign out")
                                    // Force sign out when user document is not found in either location
                                    self?.signOut()
                                }
                            }
                        }
                    }
                }
            }
        } else {
            print("❌ No email available from Auth, trying UID directly")
            // If no email available, try UID directly
            db.collection("Users").document(userId).getDocument { [weak self] document, error in
                DispatchQueue.main.async {
                    if let document = document, document.exists {
                        print("✅ User document found by UID")
                        
                        do {
                            let user = try document.data(as: FirestoreUser.self)
                            print("✅ User loaded by UID: \(user.displayName) (\(user.blitz_points ?? 0) points)")
                            self?.currentUser = user
                        } catch {
                            print("❌ Error decoding user by UID: \(error)")
                        }
                        
                        // Fetch user bet participations when user is loaded
                        self?.fetchUserBetParticipations()
                        // Load muted communities
                        self?.loadMutedCommunities()
                        // Load user communities (this will also fetch last messages)
                        self?.fetchUserCommunities()
                    } else {
                        print("❌ User document not found by UID")
                    }
                }
            }
        }
    }
    
    func refreshCurrentUser() {

        
        // Try to fetch user by email first, then fallback to UID
        if let userEmail = currentUser?.email {
            print("📧 Fetching user by email: \(userEmail)")
            db.collection("Users").document(userEmail).getDocument { [weak self] document, error in
                DispatchQueue.main.async {
                    if let document = document, document.exists {
                        print("✅ User document found by email")
                        
                        do {
                            let user = try document.data(as: FirestoreUser.self)
                            print("✅ User refreshed: \(user.displayName) (\(user.blitz_points ?? 0) points)")
                            self?.currentUser = user
                        } catch {
                            print("❌ Error decoding user on refresh: \(error)")
                        }
                        
                        // Fetch user bet participations when user is refreshed
                        self?.fetchUserBetParticipations()
                        // Load muted communities
                        self?.loadMutedCommunities()
                        // Load user communities
                        self?.fetchUserCommunities()
                    } else {
                        print("❌ User document not found by email, trying UID fallback")
                        // Fallback to UID if email not found
                        if let userId = self?.currentUser?.id {
                            self?.fetchCurrentUser(userId: userId)
                        }
                    }
                }
            }
        } else if let userId = currentUser?.id {
            print("🆔 Fetching user by UID: \(userId)")
            fetchCurrentUser(userId: userId)
        } else {
            print("❌ No email or UID available for user refresh")
        }
    }
    
    // MARK: - Get User by ID
    func getUser(userId: String) async throws -> FirestoreUser {
        return try await withCheckedThrowingContinuation { continuation in
            // Try to get user by the provided ID (could be email or UID)
            db.collection("Users").document(userId).getDocument { document, error in
                if let error = error {
                    print("❌ Error fetching user by ID: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let document = document, document.exists else {
                    print("❌ User document not found for ID: \(userId) - Forcing sign out")
                    // Force sign out when user document is not found
                    DispatchQueue.main.async {
                        self.signOut()
                    }
                    let notFoundError = NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found - signed out automatically"])
                    continuation.resume(throwing: notFoundError)
                    return
                }
                
                do {
                    let user = try document.data(as: FirestoreUser.self)
                    print("✅ User loaded: \(user.displayName)")
                    continuation.resume(returning: user)
                } catch {
                    print("❌ Error decoding user: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Authentication Methods
    
    func signUp(email: String, password: String, firstName: String, lastName: String, displayName: String, completion: @escaping (Bool, String?) -> Void) {
        // Format display name to remove spaces
        let formattedDisplayName = displayName.replacingOccurrences(of: " ", with: "")
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            
            guard let user = result?.user else {
                completion(false, "Failed to create user")
                return
            }
            
            // Create user document in Firestore using email as Document ID
            let userData = FirestoreUser(
                documentId: user.uid,
                blitz_points: 10000,
                display_name: formattedDisplayName,
                email: email,
                first_name: firstName,
                full_name: "\(firstName) \(lastName)",
                last_name: lastName,
                gender: nil, // Email sign-up doesn't collect gender
                profile_picture_url: nil, // Email sign-up doesn't provide profile picture
                total_bets: 0,
                total_winnings: 0,
                id: user.uid,
                uid: user.uid,
                sling_points: nil
            )
            
            do {
                try self?.db.collection("Users").document(email).setData(from: userData)
                completion(true, nil)
            } catch {
                completion(false, "Failed to save user data: \(error.localizedDescription)")
            }
        }
    }
    
    func signIn(email: String, password: String, completion: @escaping (Bool, String?) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            
            // After successful authentication, fetch the user data
            if let user = result?.user, let email = user.email {
                print("🔐 Sign in successful for email: \(email)")
                // Fetch user document from Firestore using email as document ID
                self?.db.collection("Users").document(email).getDocument { [weak self] document, error in
                    DispatchQueue.main.async {
                        if let document = document, document.exists {
                            print("✅ User document found in Firestore")
                            self?.currentUser = try? document.data(as: FirestoreUser.self)
                            if let loadedUser = self?.currentUser {
                                print("👤 User signed in: \(loadedUser.displayName) (\(loadedUser.blitz_points ?? 0) points)")
                            }
                            // Fetch user bet participations when user is loaded
                            self?.fetchUserBetParticipations()
                            // Load muted communities
                            self?.loadMutedCommunities()
                            // Load user communities (this will also fetch last messages)
                            self?.fetchUserCommunities()
                            completion(true, nil)
                        } else {
                            print("❌ User document not found in Firestore for email: \(email)")
                            completion(false, "User data not found")
                        }
                    }
                }
            } else {
                print("❌ Failed to get user information from Auth result")
                completion(false, "Failed to get user information")
            }
        }
    }
    
    func signOut() {
        print("🔄 Starting sign out process...")
        
        do {
            // First, manually set authentication state to false to ensure immediate UI update
            DispatchQueue.main.async {
                self.isAuthenticated = false
                self.currentUser = nil
            }
            
            // Then sign out from Firebase
            try Auth.auth().signOut()
            
            // Clean up local state
            DispatchQueue.main.async {
                self.communities = []
                self.userCommunities = []
                self.bets = []
                self.userBetParticipations = []
                self.notifications = []
                self.messages = []
                self.communityLastMessages = [:]
                self.mutedCommunities = []
                self.totalUnreadCount = 0
                
                // Stop any active listeners
                self.stopListeningToMessages()
            }
            
            print("✅ User signed out successfully and local state cleaned up")
        } catch {
            print("❌ Error signing out: \(error.localizedDescription)")
            SlingLogError("Failed to sign out user", error: error)
            
            // If there was an error, restore the authentication state
            DispatchQueue.main.async {
                self.isAuthenticated = true
                // Re-fetch current user to restore state
                if let user = Auth.auth().currentUser {
                    self.fetchCurrentUser(userId: user.uid)
                }
            }
        }
    }
    
    // MARK: - Core Methods
    
    func loadMutedCommunities() {
        guard let userEmail = currentUser?.email else { return }
        
        db.collection("Users").document(userEmail).getDocument { [weak self] document, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error loading muted communities: \(error.localizedDescription)")
                    return
                }
                
                guard let document = document, document.exists,
                      let data = document.data(),
                      let mutedCommunitiesData = data["muted_communities"] as? [String: Bool] else {
                    return
                }
                
                // Extract community IDs that are muted (value is true)
                let mutedIds = Set(mutedCommunitiesData.compactMap { key, value in
                    value ? key : nil
                })
                
                self?.mutedCommunities = mutedIds
                self?.updateTotalUnreadCount()
                
                // Start monitoring for expired bets
                self?.startExpiredBetMonitoring()
            }
        }
    }
    
    func updateTotalUnreadCount() {
        guard let userId = currentUser?.id else { 
            return 
        }
        
        var totalUnread = 0
        
        for community in userCommunities {
            if let chatHistory = community.chat_history {
                
                for (_, message) in chatHistory {
                    // Check if message is not read by current user
                    if !message.read_by.contains(userId) {
                        totalUnread += 1
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            self.totalUnreadCount = totalUnread
        }
    }
    
    func sendBetAnnouncementMessage(
        to communityId: String,
        betId: String,
        betTitle: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let msgId = generateMessageId()
        let now = Date()
        
        // First, find the community document ID
        guard let community = userCommunities.first(where: { $0.id == communityId }),
              let documentId = community.documentId else {
            print("❌ Community not found for bot message: \(communityId)")
            completion(false, "Community not found")
            return
        }
        
        // Add message to chat_history field of the community document
        let chatHistoryUpdate: [String: Any] = [
            "chat_history.\(msgId)": [
                "id": msgId,
                "community_id": communityId,
                "sender_id": "sling_bot",
                "sender_name": "Sling",
                "sender_email": "app@slingapp.com",
                "message": "New market: \(betTitle)",
                "time_stamp": now,
                "type": "betAnnouncement",
                "bet_id": betId,
                "read_by": [],
                "created_by": "app@slingapp.com",
                "created_by_id": "sling_bot",
                "created_date": now,
                "updated_date": now
            ]
        ]
        
        db.collection("community").document(documentId).updateData(chatHistoryUpdate) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error sending bot announcement message: \(error.localizedDescription)")
                    completion(false, error.localizedDescription)
                } else {
                    print("✅ Bot announcement message sent for bet: \(betTitle)")
                    
                    // Refresh messages for this community
                    self?.fetchMessages(for: communityId)
                    
                    // Update unread count
                    self?.updateTotalUnreadCount()
                    
                    completion(true, nil)
                }
            }
        }
    }
    
    func sendCommunityJoinMessage(
        to communityId: String,
        userName: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let msgId = generateMessageId()
        let now = Date()
        
        // First, find the community document ID
        guard let community = userCommunities.first(where: { $0.id == communityId }),
              let documentId = community.documentId else {
            print("❌ Community not found for bot join message: \(communityId)")
            completion(false, "Community not found")
            return
        }
        
        // Add message to chat_history field of the community document
        let chatHistoryUpdate: [String: Any] = [
            "chat_history.\(msgId)": [
                "id": msgId,
                "community_id": communityId,
                "sender_id": "sling_bot",
                "sender_name": "Sling",
                "sender_email": "app@slingapp.com",
                "message": "\(userName) joined the community! 🎉",
                "time_stamp": now,
                "type": "system",
                "read_by": [],
                "created_by": "app@slingapp.com",
                "created_by_id": "sling_bot",
                "created_date": now,
                "updated_date": now
            ]
        ]
        
        db.collection("community").document(documentId).updateData(chatHistoryUpdate) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error sending bot join message: \(error.localizedDescription)")
                    completion(false, error.localizedDescription)
                } else {
                    print("✅ Bot join message sent for \(userName)")
                    
                    // Refresh messages for this community
                    self?.fetchMessages(for: communityId)
                    
                    // Update unread count
                    self?.updateTotalUnreadCount()
                    
                    completion(true, nil)
                }
            }
        }
    }
    
    func sendCommunityCreatedMessage(
        to communityId: String,
        communityName: String,
        creatorName: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let msgId = generateMessageId()
        let now = Date()
        
        // First, find the community document ID
        guard let community = userCommunities.first(where: { $0.id == communityId }),
              let documentId = community.documentId else {
            print("❌ Community not found for bot created message: \(communityId)")
            completion(false, "Community not found")
            return
        }
        
        // Add message to chat_history field of the community document
        let chatHistoryUpdate: [String: Any] = [
            "chat_history.\(msgId)": [
                "id": msgId,
                "community_id": communityId,
                "sender_id": "sling_bot",
                "sender_name": "Sling",
                "sender_email": "app@slingapp.com",
                "message": "Welcome to \(communityName)! Created by \(creatorName). Let's start betting! 🎲",
                "time_stamp": now,
                "type": "system",
                "read_by": [],
                "created_by": "app@slingapp.com",
                "created_by_id": "sling_bot",
                "created_date": now,
                "updated_date": now
            ]
        ]
        
        db.collection("community").document(documentId).updateData(chatHistoryUpdate) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error sending bot created message: \(error.localizedDescription)")
                    completion(false, error.localizedDescription)
                } else {
                    print("✅ Bot created message sent for community: \(communityName)")
                    
                    // Refresh messages for this community
                    self?.fetchMessages(for: communityId)
                    
                    // Update unread count
                    self?.updateTotalUnreadCount()
                    
                    completion(true, nil)
                }
            }
        }
    }
    
    private func generateMessageId() -> String {
        // Generate a 24-character alphanumeric ID similar to other IDs in the app
        let characters = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<24).map { _ in characters.randomElement()! })
    }
    
    private func generateBetId() -> String {
        // Generate a 24-character alphanumeric ID for bets
        let characters = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<24).map { _ in characters.randomElement()! })
    }
    
    // Helper function to convert stored name to full name for preview
    private func getFullNameFromStoredName(_ storedName: String, email: String) -> String {
        // If the stored name is the current user's display name, convert to full name
        if let currentUser = currentUser, 
           currentUser.email == email,
           storedName == currentUser.display_name {
            let fullName = "\(currentUser.first_name ?? "") \(currentUser.last_name ?? "")".trimmingCharacters(in: .whitespaces)
            return fullName.isEmpty ? storedName : fullName
        }
        
        // For other users, try to get full name from Firestore
        // For now, return the stored name as is (could be enhanced later)
        return storedName
    }
    
    // MARK: - Community Management
    
    func fetchCommunities() {
        db.collection("community").getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching communities: \(error.localizedDescription)")
                SlingLogError("Failed to fetch communities", error: error)
                return
            }

            self.communities = snapshot?.documents.compactMap { document in
                try? document.data(as: FirestoreCommunity.self)
            } ?? []
        }
    }
    
    func fetchUserCommunities() {
        guard let userEmail = currentUser?.email else { 
            print("❌ No user email available")
            return 
        }
        
        guard let userId = currentUser?.id else {
            print("❌ No user ID available")
            return
        }
        
        // First, get ALL CommunityMember documents to check created_by_id
        db.collection("CommunityMember").getDocuments { [weak self] allSnapshot, allError in
            if let allError = allError {
                print("❌ Error fetching CommunityMember documents: \(allError.localizedDescription)")
                return
            }
            
            // Now proceed with the filtered query for user's communities
            self?.performFilteredCommunityMemberQuery(userEmail: userEmail, userId: userId)
        }
    }
    
    private func performFilteredCommunityMemberQuery(userEmail: String, userId: String) {
        // Get all CommunityMember records for this user
        db.collection("CommunityMember")
            .whereField("user_email", isEqualTo: userEmail)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Error fetching CommunityMember documents: \(error.localizedDescription)")
                    return
                }
                
                let documents = snapshot?.documents ?? []
                
                // Filter for active memberships (handle both Int and Bool)
                let activeDocuments = documents.filter { document in
                    let data = document.data()
                    if let isActiveInt = data["is_active"] as? Int {
                        return isActiveInt == 1
                    } else if let isActiveBool = data["is_active"] as? Bool {
                        return isActiveBool
                    } else {
                        return false
                    }
                }
                
                if activeDocuments.isEmpty {
                    DispatchQueue.main.async {
                        self?.userCommunities = []
                    }
                    return
                }
                
                // Extract community IDs
                let communityIds = activeDocuments.compactMap { document -> String? in
                    let memberData = try? document.data(as: FirestoreCommunityMember.self)
                    return memberData?.community_id
                }
                
                // Fetch community data
                var fetchedCommunities: [FirestoreCommunity] = []
                let group = DispatchGroup()
                
                for communityId in communityIds {
                    group.enter()
                    
                    // Fetch the specific community by ID
                    self?.db.collection("community").getDocuments { allSnapshot, allError in
                        defer {
                            group.leave()
                        }
                        
                        if let allError = allError {
                            print("❌ Error fetching communities: \(allError.localizedDescription)")
                            return
                        }
                        
                        let allCommunities = allSnapshot?.documents ?? []
                        
                        // Find the specific community by matching either document ID or the 'id' field
                        let targetCommunity = allCommunities.first { doc in
                            let docId = doc.documentID
                            let data = doc.data()
                            let communityIdField = data["id"] as? String
                            
                            // Try multiple matching strategies
                            let matchesDocId = docId == communityId
                            let matchesIdField = communityIdField == communityId
                            
                            // Also check if the community ID is contained in the document ID or vice versa
                            let docIdContainsCommunityId = docId.contains(communityId)
                            let communityIdContainsDocId = communityId.contains(docId)
                            
                            return matchesDocId || matchesIdField || docIdContainsCommunityId || communityIdContainsDocId
                        }
                        
                        if let targetCommunity = targetCommunity {
                            
                            do {
                                var community = try targetCommunity.data(as: FirestoreCommunity.self)
                                community.documentId = targetCommunity.documentID
                                fetchedCommunities.append(community)
                            } catch {
                                print("❌ Failed to decode community: \(error)")
                                
                                // Fallback: try to create a basic community object
                                let data = targetCommunity.data()
                                if let name = data["name"] as? String {
                                    // Handle member_count that might be Int or Double
                                    var memberCount = 0
                                    if let memberCountInt = data["member_count"] as? Int {
                                        memberCount = memberCountInt
                                    } else if let memberCountDouble = data["member_count"] as? Double {
                                        memberCount = Int(memberCountDouble)
                                    }
                                    
                                    // Create a minimal community object
                                    let fallbackCommunity = FirestoreCommunity(
                                        documentId: targetCommunity.documentID,
                                        id: data["id"] as? String,
                                        name: name,
                                        description: nil,
                                        created_by: data["created_by"] as? String ?? "Unknown",
                                        created_date: data["created_date"] as? Date ?? Date(),
                                        invite_code: data["invite_code"] as? String ?? "",
                                        member_count: memberCount,
                                        bet_count: nil,
                                        total_bets: data["total_bets"] as? Int ?? 0,
                                        members: data["members"] as? [String],
                                        admin_email: data["admin_email"] as? String,
                                        created_by_id: data["created_by_id"] as? String,
                                        is_active: nil,
                                        is_private: nil,
                                        updated_date: data["updated_date"] as? Date,
                                        chat_history: nil,
                                        profile_image_url: data["profile_image_url"] as? String
                                    )
                                    fetchedCommunities.append(fallbackCommunity)
                                }
                            }
                        }
                    }
                }
                
                group.notify(queue: .main) { [weak self] in
                    DispatchQueue.main.async {
                        self?.userCommunities = fetchedCommunities
                        print("✅ Loaded \(fetchedCommunities.count) communities")
                        
                        // Preload community images for faster loading
                        let imageUrls = fetchedCommunities.compactMap { $0.profile_image_url }.filter { !$0.isEmpty }
                        if !imageUrls.isEmpty {
                            ImageCacheManager.shared.preloadImages(urls: imageUrls)
                        }
                        
                        // Fetch last messages for all communities immediately after loading
                        self?.fetchLastMessagesForUserCommunities()
                        
                        // Now that communities are loaded, fetch bets
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self?.fetchBets()
                        }
                    }
                }
            }
    }

    func fetchBets() {
        print("🔄 fetchBets: ===== REFRESHING BET DATA =====")
        print("🔄 fetchBets: Called for user: \(currentUser?.email ?? "unknown")")
        print("🔄 fetchBets: This will fetch updated odds after bet placement")
        guard let userEmail = currentUser?.email else { 
            print("❌ No user email available")
            return 
        }
        
        // First, get all CommunityMember records for this user to get community IDs
        db.collection("CommunityMember")
            .whereField("user_email", isEqualTo: userEmail)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Error fetching user community memberships: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    DispatchQueue.main.async {
                        self?.bets = []
                    }
                    return
                }
                
                // Filter for active memberships (handle both Int and Bool)
                let activeDocuments = documents.filter { document in
                    let data = document.data()
                    if let isActiveInt = data["is_active"] as? Int {
                        return isActiveInt == 1
                    } else if let isActiveBool = data["is_active"] as? Bool {
                        return isActiveBool
                    } else {
                        return false
                    }
                }
                
                // Extract community IDs from the member records
                let communityIds = activeDocuments.compactMap { document -> String? in
                    let memberData = try? document.data(as: FirestoreCommunityMember.self)
                    return memberData?.community_id
                }
                
                print("🔍 fetchBets: Found \(communityIds.count) community IDs: \(communityIds)")
                
                if communityIds.isEmpty {
                    DispatchQueue.main.async {
                        self?.bets = []
                    }
                    return
                }
                
                // Now fetch bets from these communities
                print("🔍 fetchBets: Querying Firestore with community IDs: \(communityIds)")
                self?.db.collection("Bet")
                    .whereField("community_id", in: communityIds)
                    .getDocuments { [weak self] betSnapshot, betError in
                        DispatchQueue.main.async {
                            if let betError = betError {
                                print("❌ fetchBets: Error fetching bets: \(betError.localizedDescription)")
                                self?.bets = []
                                return
                            }
                            
                            let betDocuments = betSnapshot?.documents ?? []
                            
                            print("🔍 fetchBets: Found \(betDocuments.count) bet documents")
                            
                            // Comprehensive logging for debugging
                            let currentTime = Date()
                            let formatter = DateFormatter()
                            formatter.dateStyle = .full
                            formatter.timeStyle = .full
                        
                            
                            // Log all bets with full metadata
                            for (_, doc) in betDocuments.enumerated() {
                                let data = doc.data()
                                let title = data["title"] as? String ?? "unknown"
                                let communityId = data["community_id"] as? String ?? "unknown"
                                let deadline = data["deadline"] as? Date ?? Date()
                                let status = data["status"] as? String ?? "unknown"
                                let createdBy = data["created_by"] as? String ?? "unknown"
                                let createdDate = data["created_date"] as? Date ?? Date()
                                
                                let timeDiff = deadline.timeIntervalSince(currentTime)
                                let hoursDiff = timeDiff / 3600
                                
                            }
                            
                            print("-" + String(repeating: "-", count: 80))
                            
                            // Log bets relevant to user's communities
                        
                            for communityId in communityIds {
                                let communityBets = betDocuments.filter { doc in
                                    let data = doc.data()
                                    return data["community_id"] as? String == communityId
                                }
                                
                                if let community = self?.userCommunities.first(where: { $0.id == communityId }) {
                                    
                                    for betDoc in communityBets {
                                        let data = betDoc.data()
                                        let title = data["title"] as? String ?? "unknown"
                                        let status = data["status"] as? String ?? "unknown"
                                        let deadline = data["deadline"] as? Date ?? Date()
                                        let timeDiff = deadline.timeIntervalSince(currentTime)
                                        let hoursDiff = timeDiff / 3600
                                        
                                    }
                                }
                            }
                            
                            
                            // Log expiration analysis
                            let openBets = betDocuments.filter { doc in
                                let data = doc.data()
                                return (data["status"] as? String ?? "").lowercased() == "open"
                            }
                            
                            let expiredBets = openBets.filter { doc in
                                let data = doc.data()
                                let deadline = data["deadline"] as? Date ?? Date()
                                return deadline < currentTime
                            }
                            
                            let futureBets = openBets.filter { doc in
                                let data = doc.data()
                                let deadline = data["deadline"] as? Date ?? Date()
                                return deadline > currentTime
                            }

                            if !expiredBets.isEmpty {
                                print("  Expired Bet Details:")
                                for betDoc in expiredBets {
                                    let data = betDoc.data()
                                    let title = data["title"] as? String ?? "unknown"
                                    let deadline = data["deadline"] as? Date ?? Date()
                                    let timeDiff = deadline.timeIntervalSince(currentTime)
                                }
                            }
                            
                            if !futureBets.isEmpty {
                                print("  Future Bet Details:")
                                for betDoc in futureBets {
                                    let data = betDoc.data()
                                    let title = data["title"] as? String ?? "unknown"
                                    let deadline = data["deadline"] as? Date ?? Date()
                                    let timeDiff = deadline.timeIntervalSince(currentTime)
                                    let hoursDiff = timeDiff / 3600
                                }
                            }
                            
                            print("=" + String(repeating: "=", count: 80))
                            
                            let fetchedBets = betDocuments.compactMap { document in
                                do {
                                    let bet = try document.data(as: FirestoreBet.self)
                                    return bet
                                } catch {
                                    print("❌ Error decoding bet document '\(document.documentID)': \(error)")
                                    return nil
                                }
                            }
                            
                            // Check for expired bets and update their status
                            self?.checkAndUpdateExpiredBets(fetchedBets)
                            
                            // Filter out expired bets for home page display
                            let now = Date()
                            let activeBets = fetchedBets.filter { bet in
                                let isExpired = bet.deadline <= now
                                if isExpired {
                                    print("🏠 fetchBets: Hiding expired bet from home page: '\(bet.title)' (deadline: \(bet.deadline))")
                                }
                                return !isExpired
                            }
                            
                            print("🏠 fetchBets: Filtered out \(fetchedBets.count - activeBets.count) expired bets, showing \(activeBets.count) active bets")
                            
                            // Sort bets by creation date (most recent first) to show newest bets at the top
                            let sortedBets = activeBets.sorted { $0.created_date > $1.created_date }
                            
                            print("🔍 fetchBets: Successfully processed \(sortedBets.count) bets")
                            if !sortedBets.isEmpty {
                                print("🔍 fetchBets: First bet title: \(sortedBets.first?.title ?? "unknown")")
                                print("🔍 fetchBets: Last bet title: \(sortedBets.last?.title ?? "unknown")")
                                
                                // Log pool data for first few bets to debug odds discrepancies
                                for (index, bet) in sortedBets.prefix(3).enumerated() {
                                    print("🔍 fetchBets: Bet \(index + 1) - ID: \(bet.id ?? "nil"), Title: \(bet.title)")
                                    print("🔍 fetchBets: Bet \(index + 1) - Pool by option: \(bet.pool_by_option ?? [:])")
                                    print("🔍 fetchBets: Bet \(index + 1) - Total pool: \(bet.total_pool ?? 0)")
                                    print("🔍 fetchBets: Bet \(index + 1) - Options: \(bet.options)")
                                    
                                    // Calculate and log the odds that will be displayed in UI
                                    let calculatedOdds = self?.calculateImpliedOdds(for: bet) ?? [:]
                                    print("🔍 fetchBets: Bet \(index + 1) - CALCULATED ODDS FOR UI: \(calculatedOdds)")
                                    
                                    // Format the odds as they would appear in the UI
                                    for option in bet.options {
                                        if let odds = calculatedOdds[option] {
                                            let formattedOdds = self?.formatImpliedOdds(odds) ?? "N/A"
                                            print("🔍 fetchBets: Bet \(index + 1) - Option '\(option)': \(odds) -> \(formattedOdds)")
                                        }
                                    }
                                }
                            }
                            
                            self?.bets = sortedBets
                            
                            // Preload bet images for faster loading
                            let betImageUrls = sortedBets.compactMap { $0.image_url }.filter { !$0.isEmpty }
                            if !betImageUrls.isEmpty {
                                ImageCacheManager.shared.preloadImages(urls: betImageUrls)
                            }
                        }
                    }
            }
    }
    
    func checkAndUpdateExpiredBets(_ bets: [FirestoreBet]) {
        let now = Date()
        print("⏰ checkAndUpdateExpiredBets: Current time: \(now)")
        
        let expiredBets = bets.filter { bet in
            let isOpen = bet.status.lowercased() == "open"
            let isExpired = bet.deadline < now
            let timeDiff = bet.deadline.timeIntervalSince(now)
            
            if isOpen && isExpired {
                print("⏰ Bet '\(bet.title)' will be closed - Status: \(bet.status), Deadline: \(bet.deadline), Time diff: \(timeDiff) seconds")
            }
            
            return isOpen && isExpired
        }
        
        if !expiredBets.isEmpty {
            print("⏰ Found \(expiredBets.count) expired bets that need status updates")
            
            for bet in expiredBets {
                updateExpiredBetStatus(betId: bet.id ?? "", newStatus: "closed")
            }
        }
    }
    
    func updateExpiredBetStatus(betId: String, newStatus: String) {
        guard !betId.isEmpty else { return }
        

        
        let updateData: [String: Any] = [
            "status": newStatus,
            "updated_date": Date()
        ]
        
        db.collection("Bet").document(betId).updateData(updateData) { [weak self] error in
            if let error = error {
                print("❌ Error updating expired bet status: \(error.localizedDescription)")
            } else {
                print("✅ Successfully updated bet \(betId) status to \(newStatus)")
                
                // Refresh bets to reflect the status change
                DispatchQueue.main.async {
                    self?.fetchBets()
                }
            }
        }
    }
    
    // MARK: - Periodic Expired Bet Checking
    
    func startExpiredBetMonitoring() {
        // Check for expired bets every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.checkAllExpiredBets()
        }
    }
    
    func checkAllExpiredBets() {
        print("⏰ Periodic check for expired bets...")
        
        let now = Date()
        let expiredBets = bets.filter { bet in
            bet.status.lowercased() == "open" && bet.deadline < now
        }
        
        if !expiredBets.isEmpty {
            print("⏰ Found \(expiredBets.count) expired bets during periodic check")
            for bet in expiredBets {
                updateExpiredBetStatus(betId: bet.id ?? "", newStatus: "closed")
            }
        } else {
            print("✅ No expired bets found during periodic check")
        }
    }
    
    func fetchUserBetParticipations() {
        guard let userEmail = currentUser?.email else { return }
        
        print("🔄 fetchUserBetParticipations: ===== FETCHING USER BET PARTICIPATIONS =====")
        print("🔄 fetchUserBetParticipations: User: \(userEmail)")
        
        db.collection("BetParticipant")
            .whereField("user_email", isEqualTo: userEmail)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Error fetching user bet participations: \(error.localizedDescription)")
                        self?.userBetParticipations = []
                        return
                    }
                    
                    let participations = snapshot?.documents.compactMap { document in
                        try? document.data(as: BetParticipant.self)
                    } ?? []
                    
                    print("🔄 fetchUserBetParticipations: Found \(participations.count) participations")
                    
                    // Log locked odds for each participation
                    for (index, participation) in participations.enumerated() {
                        print("🔄 fetchUserBetParticipations: Participation \(index + 1) - Bet ID: \(participation.bet_id)")
                        print("🔄 fetchUserBetParticipations: Participation \(index + 1) - Chosen option: \(participation.chosen_option)")
                        print("🔄 fetchUserBetParticipations: Participation \(index + 1) - Stake: \(participation.stake_amount)")
                        print("🔄 fetchUserBetParticipations: Participation \(index + 1) - LOCKED ODDS: \(participation.locked_odds ?? [:])")
                        print("🔄 fetchUserBetParticipations: Participation \(index + 1) - Created: \(participation.created_date)")
                    }
                    
                    self?.userBetParticipations = participations
                    print("✅ fetchUserBetParticipations: Successfully loaded \(participations.count) bet participations")
                    print("🔄 fetchUserBetParticipations: ================================================")
                }
            }
    }
    
    func fetchUserBetParticipations(for userEmail: String, completion: @escaping ([BetParticipant]) -> Void) {
        db.collection("BetParticipant")
            .whereField("user_email", isEqualTo: userEmail)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Error fetching bet participations for \(userEmail): \(error.localizedDescription)")
                        completion([])
                        return
                    }
                    
                    let participations = snapshot?.documents.compactMap { document in
                        try? document.data(as: BetParticipant.self)
                    } ?? []
                    
                    print("✅ Fetched \(participations.count) bet participations for \(userEmail)")
                    completion(participations)
                }
            }
    }
    
    func stopListeningToMessages() {
        messageListener?.remove()
        messageListener = nil
    }
    
    func fetchMessages(for communityId: String) {
        // Remove existing listener if any
        messageListener?.remove()
        
        // First, find the community document ID from the community ID
        guard let community = userCommunities.first(where: { $0.id == communityId }),
              let documentId = community.documentId else {
            print("❌ Community not found for ID: \(communityId)")
            self.messages = []
            return
        }
        
        // Set up real-time listener for the community document to get chat_history updates
        messageListener = db.collection("community")
            .document(documentId)
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Error fetching messages: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let document = snapshot, document.exists else {
                        self?.messages = []
                        return
                    }
                    
                    do {
                        let communityData = try document.data(as: FirestoreCommunity.self)
                        
                        // Extract messages from chat_history field
                        if let chatHistory = communityData.chat_history, !chatHistory.isEmpty {
                            var fetchedMessages: [CommunityMessage] = []
                            
                            for (_, messageData) in chatHistory {
                                let message = messageData.toCommunityMessage()
                                fetchedMessages.append(message)
                            }
                            
                            // Sort messages by timestamp (oldest first)
                            fetchedMessages.sort { $0.timestamp < $1.timestamp }
                            
                            self?.messages = fetchedMessages
                            
                            // Update unread count when new messages arrive
                            self?.updateTotalUnreadCount()
                        } else {
                            self?.messages = []
                            
                            // Update unread count even when no messages
                            self?.updateTotalUnreadCount()
                        }
                    } catch {
                        print("❌ Error parsing community data: \(error.localizedDescription)")
                        self?.messages = []
                    }
                }
            }
    }
    
    func fetchLastMessagesForUserCommunities() {
        // Use a DispatchGroup to wait for all communities to be processed
        let group = DispatchGroup()
        var tempLastMessages: [String: CommunityMessage] = [:]
        
        for community in userCommunities {
            guard let communityId = community.id,
                  let documentId = community.documentId else { 
                continue 
            }
            
            group.enter()
            
            // Fetch the community document using the actual document ID
            db.collection("community").document(documentId).getDocument { [weak self] snapshot, error in
                defer { group.leave() }
                
                if let error = error {
                    print("❌ Error fetching last message for community \(communityId): \(error.localizedDescription)")
                    return
                }
                
                guard let document = snapshot, document.exists else {
                    return
                }
                
                do {
                    let communityData = try document.data(as: FirestoreCommunity.self)
                    
                    // Extract most recent message from chat_history
                    if let chatHistory = communityData.chat_history, !chatHistory.isEmpty {
                        // Find the message with the most recent timestamp
                        let mostRecentMessage = chatHistory.values.max { $0.time_stamp < $1.time_stamp }
                        
                        if let lastMessageData = mostRecentMessage {
                            // Convert stored name to full name for preview
                            let senderFullName = self?.getFullNameFromStoredName(lastMessageData.sender_name, email: lastMessageData.sender_email) ?? lastMessageData.sender_name
                            
                            let lastMessage = CommunityMessage(
                                id: lastMessageData.id,
                                communityId: communityId,
                                senderEmail: lastMessageData.sender_email,
                                senderName: senderFullName,
                                text: lastMessageData.message,
                                timestamp: lastMessageData.time_stamp,
                                messageType: MessageType(rawValue: lastMessageData.type) ?? .regular,
                                betId: lastMessageData.bet_id,
                                reactions: [:]
                            )
                            
                            tempLastMessages[communityId] = lastMessage
                        }
                    }
                } catch {
                    print("❌ Error parsing community data for \(communityId): \(error)")
                }
            }
        }
        
        // Update all last messages at once when all communities are processed
        group.notify(queue: .main) { [weak self] in
            self?.communityLastMessages = tempLastMessages
            // Update unread count after last messages are loaded
            self?.updateTotalUnreadCount()
        }
    }
    
    func sendMessage(to communityId: String, text: String, completion: @escaping (Bool, String?) -> Void) {
        guard let userEmail = currentUser?.email,
              let userId = currentUser?.id,
              let firstName = currentUser?.first_name,
              let lastName = currentUser?.last_name else {
            completion(false, "User not authenticated")
            return
        }
        
        // First, find the community document ID from the community ID
        guard let community = userCommunities.first(where: { $0.id == communityId }),
              let documentId = community.documentId else {
            completion(false, "Community not found")
            return
        }
        
        let messageId = generateMessageId()
        let now = Date()
        
        // Store message in chat_history field of the community document
        let chatHistoryUpdate: [String: Any] = [
            "chat_history.\(messageId)": [
                "id": messageId,
                "community_id": communityId,
                "sender_id": userId,
                "sender_name": "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces), // Store full name
                "sender_email": userEmail,
                "message": text,
                "time_stamp": now,
                "type": "regular",
                "read_by": [userId], // Mark as read by sender
                "created_by": userEmail,
                "created_by_id": userId,
                "created_date": now,
                "updated_date": now,
                "bet_id": nil
            ]
        ]
        
        db.collection("community").document(documentId).updateData(chatHistoryUpdate) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error saving message to Firestore: \(error.localizedDescription)")
                    completion(false, error.localizedDescription)
                } else {
                    print("✅ Message sent successfully and saved to Firestore")
                    
                    // Update the last message for this community
                    let newMessage = CommunityMessage(
                        id: messageId,
                        communityId: communityId,
                        senderEmail: userEmail,
                        senderName: "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces), // Use full name
                        text: text,
                        timestamp: now,
                        messageType: .regular,
                        betId: nil,
                        reactions: [:]
                    )
                    self?.communityLastMessages[communityId] = newMessage
                    
                    // Refresh messages for this community
                    self?.fetchMessages(for: communityId)
                    
                    // Update unread count when new message is sent
                    self?.updateTotalUnreadCount()
                    
                    // Also refresh last messages for all communities to ensure consistency
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self?.fetchLastMessagesForUserCommunities()
                    }
                    
                    completion(true, nil)
                }
            }
        }
    }
    
    func markAllMessagesAsRead(for communityId: String, completion: @escaping (Bool) -> Void) {
        guard let userId = currentUser?.id else {
            print("❌ Cannot mark messages as read: User ID not found")
            completion(false)
            return
        }
        
        // Find the community document ID from the community ID
        guard let community = userCommunities.first(where: { $0.id == communityId }),
              let documentId = community.documentId else {
            print("❌ Cannot mark messages as read: Community not found or missing document ID")
            completion(false)
            return
        }
        
        // Get the community document to access chat_history
        db.collection("community").document(documentId).getDocument { [weak self] document, error in
            if let error = error {
                print("❌ Error fetching community document to mark messages as read: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = document, document.exists,
                  let chatHistory = document.data()?["chat_history"] as? [String: [String: Any]] else {
                print("❌ Community document or chat_history not found")
                completion(false)
                return
            }
            
            // Prepare batch update for all messages that need to be marked as read
            var updates: [String: Any] = [:]
            var messagesUpdated = 0
            
            for (messageId, messageData) in chatHistory {
                if let readBy = messageData["read_by"] as? [String] {
                    if !readBy.contains(userId) {
                        // Add current user to read_by array
                        var updatedReadBy = readBy
                        updatedReadBy.append(userId)
                        updates["chat_history.\(messageId).read_by"] = updatedReadBy
                        messagesUpdated += 1
                    }
                } else {
                    // If read_by field doesn't exist, create it with current user
                    updates["chat_history.\(messageId).read_by"] = [userId]
                    messagesUpdated += 1
                }
            }
            
            if updates.isEmpty {
                completion(true)
                return
            }
            
            // Update the community document with all the read_by changes
            self?.db.collection("community").document(documentId).updateData(updates) { error in
                if let error = error {
                    print("❌ Error marking messages as read: \(error.localizedDescription)")
                    completion(false)
                } else {
                    // Refresh messages to update local state
                    self?.fetchMessages(for: communityId)
                    
                    // Update unread count
                    self?.updateTotalUnreadCount()
                    
                    completion(true)
                }
            }
        }
    }
    
    func markMessageAsRead(messageId: String, communityId: String, completion: @escaping (Bool) -> Void) {
        guard let userId = currentUser?.id else {
            print("❌ Cannot mark message as read: User ID not found")
            completion(false)
            return
        }
        
        // Find the community document ID from the community ID
        guard let community = userCommunities.first(where: { $0.id == communityId }),
              let documentId = community.documentId else {
            print("❌ Cannot mark message as read: Community not found or missing document ID")
            completion(false)
            return
        }
        
        // Update the specific message's read_by field
        let updateData: [String: Any] = [
            "chat_history.\(messageId).read_by": FieldValue.arrayUnion([userId])
        ]
        
        db.collection("community").document(documentId).updateData(updateData) { [weak self] error in
            if let error = error {
                print("❌ Error marking message as read: \(error.localizedDescription)")
                completion(false)
            } else {
                // Update unread count
                self?.updateTotalUnreadCount()
                
                completion(true)
            }
        }
    }
    
    func toggleMuteForCommunity(_ communityId: String, completion: @escaping (Bool) -> Void) {
        guard let userEmail = currentUser?.email else {
            completion(false)
            return
        }
        
        let userRef = db.collection("Users").document(userEmail)
        
        userRef.getDocument { [weak self] document, error in
            if let error = error {
                print("❌ Error fetching user document: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = document, document.exists else {
                completion(false)
                return
            }
            
            var mutedCommunitiesData = document.data()?["muted_communities"] as? [String: Bool] ?? [:]
            let isCurrentlyMuted = mutedCommunitiesData[communityId] ?? false
            
            // Toggle the mute status
            mutedCommunitiesData[communityId] = !isCurrentlyMuted
            
            userRef.updateData(["muted_communities": mutedCommunitiesData]) { error in
                if let error = error {
                    print("❌ Error updating mute status: \(error.localizedDescription)")
                    completion(false)
                } else {
                    DispatchQueue.main.async {
                        // Update local state
                        if !isCurrentlyMuted {
                            self?.mutedCommunities.insert(communityId)
                        } else {
                            self?.mutedCommunities.remove(communityId)
                        }
                        print("✅ Mute status toggled for community \(communityId): \(!isCurrentlyMuted)")
                        completion(true)
                    }
                }
            }
        }
    }
    
    func fetchNotifications() {
        guard let userEmail = currentUser?.email else { 
            print("🔍 fetchNotifications: No current user email available")
            return 
        }
        
        print("🔍 fetchNotifications: Fetching notifications for user: \(userEmail)")
        
        db.collection("Notification")
            .whereField("user_email", isEqualTo: userEmail)
            .getDocuments(source: .default) { [weak self] snapshot, error in
                    if let error = error {
                        print("❌ Error fetching notifications: \(error.localizedDescription)")
                        return
                    }
                    
                print("🔍 fetchNotifications: Received snapshot with \(snapshot?.documents.count ?? 0) documents")
                
                let notifications: [FirestoreNotification] = snapshot?.documents.compactMap { document in
                    do {
                        let notification = try document.data(as: FirestoreNotification.self)
                        print("🔍 fetchNotifications: Successfully parsed notification: \(notification.title)")
                        print("🔍 fetchNotifications: Raw message data: '\(notification.message)'")
                        
                        // Check for garbled text patterns
                        if notification.message.contains(where: { char in
                            !char.isASCII || (char.isASCII && char.asciiValue! < 32 && char != "\n" && char != "\r" && char != "\t")
                        }) {
                            print("⚠️ fetchNotifications: Detected potentially garbled text in notification: '\(notification.message)'")
                        }
                        
                        return notification
                    } catch {
                        print("❌ fetchNotifications: Failed to parse notification document \(document.documentID): \(error)")
                        print("❌ fetchNotifications: Raw document data: \(document.data())")
                        return nil
                    }
                } ?? []
                    
                print("🔍 fetchNotifications: Successfully parsed \(notifications.count) notifications")
                
                let sortedNotifications = notifications.sorted(by: { $0.created_date > $1.created_date })
                
                DispatchQueue.main.async { [weak self] in
                    // Sort by created_date in descending order (most recent first)
                    self?.notifications = sortedNotifications
                    
                    print("🔍 fetchNotifications: Updated notifications array with \(self?.notifications.count ?? 0) items")
                    
                    // If no notifications exist, create some sample notifications for testing
                    if notifications.isEmpty {
                        self?.createSampleNotifications(for: userEmail)
                    }
                }
            }
    }
    
    // MARK: - Notification Creation
    
    private func formatNumberWithCommas(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    func createNotification(
        for userEmail: String,
        title: String,
        message: String,
        type: String,
        icon: String,
        actionUrl: String = "",
        communityId: String? = nil,
        communityName: String? = nil,
        communityIcon: String? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        var notification = [
            "title": title,
            "message": message,
            "type": type,
            "created_by": "system",
            "created_date": Date(),
            "icon": icon,
            "is_read": false,
            "user_email": userEmail,
            "timestamp": Date(),
            "action_url": actionUrl
        ] as [String: Any]
        
        // Add community information if provided
        if let communityId = communityId {
            notification["community_id"] = communityId
        }
        if let communityName = communityName {
            notification["community_name"] = communityName
        }
        if let communityIcon = communityIcon {
            notification["community_icon"] = communityIcon
        }
        
        db.collection("Notification").addDocument(data: notification) { error in
            if let error = error {
                print("❌ Error creating notification: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false)
                }
            } else {
                print("✅ Notification created successfully for \(userEmail): \(title)")
                DispatchQueue.main.async {
                    completion(true)
                }
            }
        }
    }
    
    func createBetSettledNotification(
        for userEmail: String,
        betTitle: String,
        isWinner: Bool,
        winnings: Double,
        communityId: String? = nil,
        communityName: String? = nil,
        communityIcon: String? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        let title = isWinner ? "You Won! 🎉" : "Bet Settled"
        let formattedWinnings = formatNumberWithCommas(Int(winnings))
        let message = isWinner 
            ? "Congratulations! You won \(formattedWinnings) on '\(betTitle)'"
            : "Your bet on '\(betTitle)' has been settled"
        let icon = isWinner ? "trophy.fill" : "flag.fill"
        
        createNotification(
            for: userEmail,
            title: title,
            message: message,
            type: "bet_settled",
            icon: icon,
            communityId: communityId,
            communityName: communityName,
            communityIcon: communityIcon,
            completion: completion
        )
    }
    
    func createBetJoinedNotification(
        for userEmail: String,
        betTitle: String,
        stakeAmount: Int,
        communityId: String? = nil,
        communityName: String? = nil,
        communityIcon: String? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        let title = "Bet Joined! 🎯"
        let formattedStake = formatNumberWithCommas(stakeAmount)
        let message = "You joined '\(betTitle)' with \(formattedStake)"
        let icon = "bolt.fill"
        
        createNotification(
            for: userEmail,
            title: title,
            message: message,
            type: "bet_joined",
            icon: icon,
            communityId: communityId,
            communityName: communityName,
            communityIcon: communityIcon,
            completion: completion
        )
    }
    
    func createRemindToSettleNotification(
        for creatorEmail: String,
        betTitle: String,
        communityId: String? = nil,
        communityName: String? = nil,
        communityIcon: String? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        let title = "Reminder to Settle Bet 🔔"
        let message = "Someone is reminding you to settle '\(betTitle)'"
        let icon = "exclamationmark.triangle.fill"
        
        createNotification(
            for: creatorEmail,
            title: title,
            message: message,
            type: "remind_settle",
            icon: icon,
            communityId: communityId,
            communityName: communityName,
            communityIcon: communityIcon,
            completion: completion
        )
    }
    
    func createCommunityJoinedNotification(
        for userEmail: String,
        communityName: String,
        communityId: String? = nil,
        communityIcon: String? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        let title = "Welcome! 👋"
        let message = "You've joined the '\(communityName)' community"
        let icon = communityIcon ?? "person.2"
        
        createNotification(
            for: userEmail,
            title: title,
            message: message,
            type: "community_joined",
            icon: icon,
            communityId: communityId,
            communityName: communityName,
            communityIcon: communityIcon,
            completion: completion
        )
    }
    
    func createBetCreatedNotification(
        for userEmail: String,
        betTitle: String,
        communityName: String,
        communityId: String? = nil,
        communityIcon: String? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        let title = "New Market! 🚀"
        let message = "A new market '\(betTitle)' was created in '\(communityName)'"
        let icon = "plus.circle"
        
        createNotification(
            for: userEmail,
            title: title,
            message: message,
            type: "bet_created",
            icon: icon,
            communityId: communityId,
            communityName: communityName,
            communityIcon: communityIcon,
            completion: completion
        )
    }
    
    func createUserJoinedCommunityNotification(
        for userEmail: String,
        joinedUserName: String,
        communityName: String,
        communityId: String? = nil,
        communityIcon: String? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        let title = "New Member! 👋"
        let message = "\(joinedUserName) joined '\(communityName)'"
        let icon = communityIcon ?? "person.2"
        
        createNotification(
            for: userEmail,
            title: title,
            message: message,
            type: "user_joined_community",
            icon: icon,
            communityId: communityId,
            communityName: communityName,
            communityIcon: communityIcon,
            completion: completion
        )
    }
    
    private func notifyCommunityMembersAboutNewMember(
        communityId: String,
        communityName: String,
        communityIcon: String,
        joinedUserName: String,
        joinedUserEmail: String
    ) {
        print("🔔 Notifying community members about new member: \(joinedUserName)")
        
        // Fetch all community members except the one who just joined
        db.collection("CommunityMember")
            .whereField("community_id", isEqualTo: communityId)
            .whereField("user_email", isNotEqualTo: joinedUserEmail) // Exclude the person who just joined
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Error fetching community members for notification: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("❌ No community members found to notify")
                    return
                }
                
                print("🔔 Found \(documents.count) community members to notify")
                
                // Create notifications for all existing members
                var notificationsCreated = 0
                let totalMembers = documents.count
                
                for document in documents {
                    guard let memberEmail = document.data()["user_email"] as? String else {
                        print("❌ Member document missing email field")
                        continue
                    }
                    
                    self?.createUserJoinedCommunityNotification(
                        for: memberEmail,
                        joinedUserName: joinedUserName,
                        communityName: communityName,
                        communityId: communityId,
                        communityIcon: communityIcon
                    ) { success in
                        notificationsCreated += 1
                        if success {
                            print("✅ Created new member notification for \(memberEmail)")
                        } else {
                            print("❌ Failed to create new member notification for \(memberEmail)")
                        }
                        
                        // Check if all notifications have been processed
                        if notificationsCreated == totalMembers {
                            print("✅ Completed notifying all community members about new member")
                        }
                    }
                }
            }
    }
    
    private func createBetSettledNotifications(betId: String, winnerOption: String, participants: [QueryDocumentSnapshot]) {
        // Get bet details for title and community
        db.collection("Bet").document(betId).getDocument(source: .default) { [weak self] document, error in
            guard let document = document, document.exists,
                  let data = document.data(),
                  let betTitle = data["title"] as? String else {
                print("❌ createBetSettledNotifications: Could not fetch bet title")
                return
            }
            
            // Get community information
            let communityId = data["community_id"] as? String
            let communityName = data["community_name"] as? String
            let communityIcon = data["community_icon"] as? String ?? "person.2"
            
            // Create notifications for each participant
            for participantDoc in participants {
                guard let participantData = participantDoc.data() as [String: Any]?,
                      let userEmail = participantData["user_email"] as? String,
                      let chosenOption = participantData["chosen_option"] as? String,
                      let stakeAmount = participantData["stake_amount"] as? Int else {
                    continue
                }
                
                let isWinner = chosenOption == winnerOption
                let odds = (data["odds"] as? [String: String])?[chosenOption] ?? "-110"
                let winnings = self?.calculatePayout(amount: Double(stakeAmount), odds: odds) ?? Double(stakeAmount)
                
                self?.createBetSettledNotification(
                    for: userEmail,
                    betTitle: betTitle,
                    isWinner: isWinner,
                    winnings: winnings,
                    communityId: communityId,
                    communityName: communityName,
                    communityIcon: communityIcon
                ) { success in
                    if success {
                        print("✅ Created bet settled notification for \(userEmail)")
                    } else {
                        print("❌ Failed to create bet settled notification for \(userEmail)")
                    }
                }
            }
        }
    }
    
    private func createBetCreatedNotificationsForCommunity(communityId: String, betTitle: String, excludeUser: String) {
        // Safety check to prevent empty document path
        guard !communityId.isEmpty else {
            print("❌ createBetCreatedNotificationsForCommunity: Community ID is empty")
            return
        }
        
        // Get all community members
        db.collection("CommunityMember")
            .whereField("community_id", isEqualTo: communityId)
            .getDocuments(source: .default) { [weak self] snapshot, error in
                if let error = error {
                    print("❌ createBetCreatedNotificationsForCommunity: Error fetching community members: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("❌ createBetCreatedNotificationsForCommunity: No community members found")
                    return
                }
                
                // Get community name for the notification
                guard !communityId.isEmpty else {
                    print("❌ createBetCreatedNotificationsForCommunity: Cannot fetch community with empty ID")
                    return
                }
                
                self?.db.collection("community").document(communityId).getDocument { communityDoc, communityError in
                    guard let communityDoc = communityDoc, communityDoc.exists,
                          let communityData = communityDoc.data(),
                          let communityName = communityData["name"] as? String else {
                        print("❌ createBetCreatedNotificationsForCommunity: Could not fetch community name")
                        return
                    }
                    
                    let communityIcon = communityData["icon"] as? String ?? "person.2"
                    
                    // Create notifications for all members except the creator
                    for memberDoc in documents {
                        guard let memberData = memberDoc.data() as [String: Any]?,
                              let userEmail = memberData["user_email"] as? String,
                              userEmail != excludeUser else {
                            continue
                        }
                        
                        self?.createBetCreatedNotification(
                            for: userEmail,
                            betTitle: betTitle,
                            communityName: communityName,
                            communityId: communityId,
                            communityIcon: communityIcon
                        ) { success in
                            if success {
                                print("✅ Created bet created notification for \(userEmail)")
                            } else {
                                print("❌ Failed to create bet created notification for \(userEmail)")
                            }
                        }
                    }
                }
            }
    }
    
    private func createSampleNotifications(for userEmail: String) {
        print("🔍 createSampleNotifications: Creating welcome notification for \(userEmail)")
        
        // Create a focused welcome notification for new users
        let welcomeNotification = (
            title: "Welcome to Sling! 🎉",
            message: "Join or create a community to start placing bets with friends!",
            type: "welcome",
            icon: "person.2.circle"
        )
        
        // Create the single welcome notification
        self.createNotification(
            for: userEmail,
            title: welcomeNotification.title,
            message: welcomeNotification.message,
            type: welcomeNotification.type,
            icon: welcomeNotification.icon,
            communityId: nil,
            communityName: nil,
            communityIcon: nil
        ) { success in
            if success {
                print("✅ Created welcome notification: \(welcomeNotification.title)")
            } else {
                print("❌ Failed to create welcome notification: \(welcomeNotification.title)")
            }
        }
    }
    
    func fetchTransactions(communityId: String, userEmail: String, completion: @escaping ([BetParticipant]) -> Void) {
        db.collection("UserBet")
            .whereField("community_id", isEqualTo: communityId)
            .whereField("user_email", isEqualTo: userEmail)
            .getDocuments(source: .default) { snapshot, error in
                if let error = error {
                    print("❌ Error fetching transactions: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                let transactions: [BetParticipant] = snapshot?.documents.compactMap { document in
                    try? document.data(as: BetParticipant.self)
                } ?? []
                
                // Sort by created_date in descending order (most recent first)
                let sortedTransactions = transactions.sorted(by: { $0.created_date > $1.created_date })
                completion(sortedTransactions)
            }
    }
    
    // MARK: - Bet Management
    
    func fetchBet(by betId: String, completion: @escaping (FirestoreBet?) -> Void) {
        db.collection("Bet").document(betId).getDocument(source: .default) { document, error in
                if let error = error {
                    print("❌ Error fetching bet: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
                    return
                }
                
                guard let document = document, document.exists else {
                    print("❌ Bet not found with ID: \(betId)")
                DispatchQueue.main.async {
                    completion(nil)
                }
                    return
                }
                
                do {
                    let bet = try document.data(as: FirestoreBet.self)
                DispatchQueue.main.async {
                    completion(bet)
                }
                } catch {
                    print("❌ Error parsing bet: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - Balance Calculation
    
    func calculateNetBalance(communityId: String, userEmail: String, completion: @escaping (Double) -> Void) {
        print("🔍 Calculating net balance for \(userEmail) in community \(communityId)")
        // Calculate balance based on BetParticipant data for a specific community
        db.collection("BetParticipant")
            .whereField("user_email", isEqualTo: userEmail)
            .whereField("community_id", isEqualTo: communityId)
            .getDocuments(source: .default) { snapshot, error in
                if let error = error {
                    print("❌ Error fetching bet participations for community \(communityId): \(error.localizedDescription)")
                    completion(0.0)
                    return
                }
                
                let participations = snapshot?.documents.compactMap { document in
                    try? document.data(as: BetParticipant.self)
                } ?? []
                

                
                // Calculate net balance from bet participations within this community
                let netBalance = participations.reduce(0.0) { total, participation in
                    var amount = -Double(participation.stake_amount) // Initial bet cost
                    if let payout = participation.final_payout {
                        amount += Double(payout) // Add winnings if any
                        print("  - Bet \(participation.bet_id): Stake: -\(participation.stake_amount), Payout: +\(payout), Net: \(amount)")
                    } else {
                        print("  - Bet \(participation.bet_id): Stake: -\(participation.stake_amount), Payout: 0, Net: -\(participation.stake_amount)")
                    }
                    return total + amount
                }
                

                completion(netBalance)
            }
    }
    
    // Calculate total balance across all communities for a user
    func calculateTotalBalance(userEmail: String, completion: @escaping (Double) -> Void) {
        db.collection("BetParticipant")
            .whereField("user_email", isEqualTo: userEmail)
            .getDocuments(source: .default) { snapshot, error in
                if let error = error {
                    print("❌ Error fetching all bet participations: \(error.localizedDescription)")
                    completion(0.0)
                    return
                }
                
                let participations = snapshot?.documents.compactMap { document in
                    try? document.data(as: BetParticipant.self)
                } ?? []
                
                // Calculate net balance from all bet participations
                let netBalance = participations.reduce(0.0) { total, participation in
                    var amount = -Double(participation.stake_amount) // Initial bet cost
                    if let payout = participation.final_payout {
                        amount += Double(payout) // Add winnings if any
                    }
                    return total + amount
                }
                
                completion(netBalance)
            }
    }
    
    // MARK: - Missing Methods for Views
    
    func fetchUserBets(completion: @escaping ([BetParticipant]) -> Void) {
        guard let userEmail = currentUser?.email else {
            completion([])
            return
        }
        
        db.collection("BetParticipant")
            .whereField("user_email", isEqualTo: userEmail)
            .getDocuments(source: .default) { snapshot, error in
                if let error = error {
                    print("❌ Error fetching user bets: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                let userBets = snapshot?.documents.compactMap { document in
                    try? document.data(as: BetParticipant.self)
                } ?? []
                
                completion(userBets)
            }
    }
    
    func fetchUserIndividualBets(completion: @escaping ([BetParticipant]) -> Void) {
        fetchUserBets(completion: completion)
    }
    
    func fetchAllBetParticipants(for betId: String, completion: @escaping ([BetParticipant]) -> Void) {
        db.collection("BetParticipant")
            .whereField("bet_id", isEqualTo: betId)
            .getDocuments(source: .default) { snapshot, error in
                if let error = error {
                    print("❌ Error fetching all bet participants: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                let participants = snapshot?.documents.compactMap { document in
                    try? document.data(as: BetParticipant.self)
                } ?? []
                
                // Sort by created_date in descending order (most recent first)
                let sortedParticipants = participants.sorted(by: { $0.created_date > $1.created_date })
                completion(sortedParticipants)
            }
    }
    
    func fetchBetStatus(betId: String, completion: @escaping (String?) -> Void) {
        db.collection("Bet").document(betId).getDocument(source: .default) { document, error in
            if let error = error {
                print("❌ Error fetching bet status: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data(),
                  let status = data["status"] as? String else {
                completion(nil)
                return
            }
            
            completion(status)
        }
    }
    
    func remindCreator(betId: String, completion: @escaping (Bool) -> Void) {
        // Implementation for reminding bet creator
        print("📢 Reminding creator for bet: \(betId)")
        completion(true)
    }
    
    func cancelMarket(betId: String, completion: @escaping (Bool) -> Void) {
        guard !betId.isEmpty else {
            completion(false)
            return
        }
        
        let updateData: [String: Any] = [
            "status": "cancelled",
            "updated_date": Date()
        ]
        
        db.collection("Bet").document(betId).updateData(updateData) { error in
            if let error = error {
                print("❌ Error cancelling market: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Successfully cancelled market: \(betId)")
                completion(true)
            }
        }
    }
    
    func deleteBet(betId: String, completion: @escaping (Bool) -> Void) {
        guard !betId.isEmpty else {
            completion(false)
            return
        }
        
        db.collection("Bet").document(betId).delete { error in
            if let error = error {
                print("❌ Error deleting bet: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Successfully deleted bet: \(betId)")
                completion(true)
            }
        }
    }
    
    // MARK: - Dynamic Parimutuel Odds Calculation
    
    /// Convert American odds to implied odds (decimal format)
    private func americanOddsToImplied(americanOdds: Double) -> Double {
        if americanOdds > 0 {
            // Positive odds: implied = 100 / (americanOdds + 100)
            return 100.0 / (americanOdds + 100.0)
        } else {
            // Negative odds: implied = |americanOdds| / (|americanOdds| + 100)
            let absOdds = abs(americanOdds)
            return absOdds / (absOdds + 100.0)
        }
    }
    
    /// Calculate implied odds for each option based on current pool distribution with dynamic smoothing
    func calculateImpliedOdds(for bet: FirestoreBet) -> [String: Double] {
        print("🔍 CALCULATE_IMPLIED_ODDS DEBUG - Bet ID: \(bet.id ?? "nil")")
        print("🔍 CALCULATE_IMPLIED_ODDS DEBUG - Bet title: \(bet.title)")
        print("🔍 CALCULATE_IMPLIED_ODDS DEBUG - Bet options: \(bet.options)")
        print("🔍 CALCULATE_IMPLIED_ODDS DEBUG - Pool by option: \(bet.pool_by_option ?? [:])")
        print("🔍 CALCULATE_IMPLIED_ODDS DEBUG - Total pool: \(bet.total_pool ?? 0)")
        
        guard let poolByOption = bet.pool_by_option,
              let totalPool = bet.total_pool,
              totalPool > 0 else {
            // If no pool data, try to use the stored odds from bet creation
            if !bet.odds.isEmpty {
                // Convert stored odds (American format) to implied odds (decimal format)
                var impliedOdds: [String: Double] = [:]
                for (option, americanOdds) in bet.odds {
                    if let oddsValue = Double(americanOdds) {
                        let implied = americanOddsToImplied(americanOdds: oddsValue)
                        impliedOdds[option] = implied
                    }
                }
                print("🔍 CALCULATE_IMPLIED_ODDS DEBUG - Using stored odds from bet creation: \(impliedOdds)")
                return impliedOdds
            } else {
                // Fallback to equal odds if no stored odds
                let equalOdds = 1.0 / Double(bet.options.count)
                let result = Dictionary(uniqueKeysWithValues: bet.options.map { ($0, equalOdds) })
                print("🔍 CALCULATE_IMPLIED_ODDS DEBUG - Using equal odds (no pool data or stored odds): \(result)")
                return result
            }
        }
        
        // Calculate dynamic buffer: at least 25 points, or 5% of total pool
        let minBuffer = 25.0
        let percentageBuffer = Double(totalPool) * 0.05
        let dynamicBuffer = max(minBuffer, percentageBuffer)
        
        print("🔍 CALCULATE_IMPLIED_ODDS DEBUG - Dynamic buffer: \(dynamicBuffer) (min: \(minBuffer), 5% of pool: \(percentageBuffer))")
        
        // Add buffer to total pool for smoothing calculations
        let smoothedTotalPool = Double(totalPool) + dynamicBuffer
        
        var impliedOdds: [String: Double] = [:]
        
        for option in bet.options {
            let optionPool = poolByOption[option] ?? 0
            
            if optionPool > 0 {
                // Add buffer to option pool for smoothing
                let smoothedOptionPool = Double(optionPool) + (dynamicBuffer / Double(bet.options.count))
                
                // Implied odds = smoothed option pool / smoothed total pool
                impliedOdds[option] = smoothedOptionPool / smoothedTotalPool
                print("🔍 CALCULATE_IMPLIED_ODDS DEBUG - Option '\(option)': pool=\(optionPool), smoothedPool=\(smoothedOptionPool), smoothedTotal=\(smoothedTotalPool), odds=\(smoothedOptionPool / smoothedTotalPool)")
            } else {
                // If no one has bet on this option yet, give it buffer-based odds
                let smoothedOptionPool = dynamicBuffer / Double(bet.options.count)
                impliedOdds[option] = smoothedOptionPool / smoothedTotalPool
                print("🔍 CALCULATE_IMPLIED_ODDS DEBUG - Option '\(option)': no bets, using buffer-based odds=\(smoothedOptionPool / smoothedTotalPool)")
            }
        }
        
        print("🔍 CALCULATE_IMPLIED_ODDS DEBUG - Final calculated odds: \(impliedOdds)")
        return impliedOdds
    }
    
    /// Calculate payout for a winning bet using proportional distribution
    /// Total payout to winners = total amount wagered by losers + winners get their stakes back
    func calculateParimutuelPayout(for bet: FirestoreBet, winningOption: String, userStake: Int) -> Double {
        guard let poolByOption = bet.pool_by_option,
              let totalPool = bet.total_pool,
              let winningPool = poolByOption[winningOption],
              winningPool > 0 else {
            return Double(userStake) // Return original stake if no pool data
        }
        
        // Calculate losing pool (total amount wagered by losers)
        let losingPool = totalPool - winningPool
        
        // If no losing pool, winners just get their stake back (no profit)
        guard losingPool > 0 else {
            return Double(userStake)
        }
        
        // Winners get their stake back + proportional share of losing pool
        // User's share = (userStake / totalWinningPool) * totalLosingPool
        let userShareOfWinnings = (Double(userStake) / Double(winningPool)) * Double(losingPool)
        let totalPayout = Double(userStake) + userShareOfWinnings
        
        print("💰 calculateParimutuelPayout: User stake: \(userStake), Winning pool: \(winningPool), Losing pool: \(losingPool)")
        print("💰 calculateParimutuelPayout: User share of winnings: \(userShareOfWinnings), Total payout: \(totalPayout)")
        
        return totalPayout
    }
    
    /// Get locked odds for a user's bet participation
    func getLockedOddsForUserBet(betId: String, userEmail: String) -> [String: Double]? {
        // Find the most recent participation by this user for this bet
        let userParticipations = userBetParticipations.filter { participation in
            participation.bet_id == betId && participation.user_email == userEmail
        }
        
        // Sort by creation date (most recent first) and get the latest
        let sortedParticipations = userParticipations.sorted { $0.created_date > $1.created_date }
        
        if let latestParticipation = sortedParticipations.first {
            print("🔒 getLockedOddsForUserBet: Found locked odds for user \(userEmail) on bet \(betId): \(latestParticipation.locked_odds ?? [:])")
            return latestParticipation.locked_odds
        }
        
        print("🔒 getLockedOddsForUserBet: No locked odds found for user \(userEmail) on bet \(betId)")
        return nil
    }
    
    /// Calculate countdown time for a bet deadline
    func getCountdownTime(for deadline: Date) -> (timeString: String, isUrgent: Bool, isExpired: Bool) {
        let now = Date()
        let timeInterval = deadline.timeIntervalSince(now)
        
        print("⏰ getCountdownTime: Deadline: \(deadline)")
        print("⏰ getCountdownTime: Current time: \(now)")
        print("⏰ getCountdownTime: Time interval: \(timeInterval) seconds")
        
        // Check if expired
        if timeInterval <= 0 {
            print("⏰ getCountdownTime: Bet is EXPIRED")
            return ("Expired", true, true)
        }
        
        // Check if urgent (within 24 hours)
        let isUrgent = timeInterval <= 86400 // 24 hours in seconds
        print("⏰ getCountdownTime: Is urgent (within 24h): \(isUrgent)")
        
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval.truncatingRemainder(dividingBy: 3600)) / 60
        let seconds = Int(timeInterval) % 60
        
        print("⏰ getCountdownTime: Hours: \(hours), Minutes: \(minutes), Seconds: \(seconds)")
        
            let timeString: String
            if hours >= 24 {
                let days = hours / 24
                timeString = "\(days)d \(hours % 24)h"
            } else if hours > 0 {
                if minutes > 0 {
                    timeString = "\(hours)h \(minutes)m"
                } else {
                    timeString = "\(hours)h"
                }
            } else if minutes > 0 {
                timeString = "\(minutes)m"
            } else {
                timeString = "Less than 1 minute"
            }
        
        print("⏰ getCountdownTime: Final time string: '\(timeString)'")
        return (timeString, isUrgent, false)
    }
    
    /// Format implied odds as American odds display with clamping
    func formatImpliedOdds(_ impliedOdds: Double) -> String {
        print("🔍 FORMAT_IMPLIED_ODDS DEBUG - Input implied odds: \(impliedOdds)")
        
        // Handle edge cases
        if impliedOdds <= 0 {
            print("🔍 FORMAT_IMPLIED_ODDS DEBUG - Invalid odds (<= 0), using +1000")
            return "+1000"
        }
        
        if impliedOdds >= 1.0 {
            print("🔍 FORMAT_IMPLIED_ODDS DEBUG - Invalid odds (>= 1.0), using -1000")
            return "-1000"
        }
        
        let result: String
        if impliedOdds >= 0.5 {
            // Convert to negative American odds (favorite)
            let americanOdds = -100 * impliedOdds / (1 - impliedOdds)
            // Clamp to -1000 maximum
            let clampedOdds = max(americanOdds, -1000)
            result = String(format: "%.0f", clampedOdds)
            print("🔍 FORMAT_IMPLIED_ODDS DEBUG - Favorite: americanOdds=\(americanOdds), clamped=\(clampedOdds), result=\(result)")
        } else {
            // Convert to positive American odds (underdog)
            let americanOdds = 100 * (1 - impliedOdds) / impliedOdds
            // Clamp to +1000 maximum
            let clampedOdds = min(americanOdds, 1000)
            result = "+\(String(format: "%.0f", clampedOdds))"
            print("🔍 FORMAT_IMPLIED_ODDS DEBUG - Underdog: americanOdds=\(americanOdds), clamped=\(clampedOdds), result=\(result)")
        }
        
        print("🔍 FORMAT_IMPLIED_ODDS DEBUG - Final formatted odds: \(result)")
        return result
    }
    
    // MARK: - Odds Smoothing Test Function
    
    /// Test function to demonstrate the new dynamic odds smoothing system
    func testOddsSmoothing() {
        print("🧪 TESTING DYNAMIC ODDS SMOOTHING SYSTEM")
        print(String(repeating: "=", count: 50))
        
        // Test case 1: Very small pool (first bets)
        print("\n📊 Test Case 1: Small Pool (Total: 10 points)")
        let smallPoolBet = FirestoreBet(
            id: "test1",
            bet_type: "binary",
            community_id: "test",
            community_name: "Test Community",
            created_by: "test_user",
            creator_email: "test@example.com",
            deadline: Date(),
            odds: [:],
            outcomes: nil,
            options: ["Option A", "Option B"],
            status: "active",
            title: "Small Pool Test",
            description: "Testing small pool odds",
            winner_option: nil,
            winner: nil,
            image_url: nil,
            pool_by_option: ["Option A": 8, "Option B": 2],
            total_pool: 10,
            total_participants: 2,
            created_date: Date(),
            updated_date: nil
        )
        
        let smallPoolOdds = calculateImpliedOdds(for: smallPoolBet)
        print("Small pool odds: \(smallPoolOdds)")
        for (option, odds) in smallPoolOdds {
            let formatted = formatImpliedOdds(odds)
            print("  \(option): \(formatted)")
        }
        
        // Test case 2: Medium pool
        print("\n📊 Test Case 2: Medium Pool (Total: 1000 points)")
        let mediumPoolBet = FirestoreBet(
            id: "test2",
            bet_type: "binary",
            community_id: "test",
            community_name: "Test Community",
            created_by: "test_user",
            creator_email: "test@example.com",
            deadline: Date(),
            odds: [:],
            outcomes: nil,
            options: ["Option A", "Option B"],
            status: "active",
            title: "Medium Pool Test",
            description: "Testing medium pool odds",
            winner_option: nil,
            winner: nil,
            image_url: nil,
            pool_by_option: ["Option A": 800, "Option B": 200],
            total_pool: 1000,
            total_participants: 20,
            created_date: Date(),
            updated_date: nil
        )
        
        let mediumPoolOdds = calculateImpliedOdds(for: mediumPoolBet)
        print("Medium pool odds: \(mediumPoolOdds)")
        for (option, odds) in mediumPoolOdds {
            let formatted = formatImpliedOdds(odds)
            print("  \(option): \(formatted)")
        }
        
        // Test case 3: Large pool
        print("\n📊 Test Case 3: Large Pool (Total: 10000 points)")
        let largePoolBet = FirestoreBet(
            id: "test3",
            bet_type: "binary",
            community_id: "test",
            community_name: "Test Community",
            created_by: "test_user",
            creator_email: "test@example.com",
            deadline: Date(),
            odds: [:],
            outcomes: nil,
            options: ["Option A", "Option B"],
            status: "active",
            title: "Large Pool Test",
            description: "Testing large pool odds",
            winner_option: nil,
            winner: nil,
            image_url: nil,
            pool_by_option: ["Option A": 8000, "Option B": 2000],
            total_pool: 10000,
            total_participants: 200,
            created_date: Date(),
            updated_date: nil
        )
        
        let largePoolOdds = calculateImpliedOdds(for: largePoolBet)
        print("Large pool odds: \(largePoolOdds)")
        for (option, odds) in largePoolOdds {
            let formatted = formatImpliedOdds(odds)
            print("  \(option): \(formatted)")
        }
        
        // Test case 4: Unbalanced small pool (one option has no bets)
        print("\n📊 Test Case 4: Unbalanced Small Pool (One option has no bets)")
        let unbalancedBet = FirestoreBet(
            id: "test4",
            bet_type: "binary",
            community_id: "test",
            community_name: "Test Community",
            created_by: "test_user",
            creator_email: "test@example.com",
            deadline: Date(),
            odds: [:],
            outcomes: nil,
            options: ["Option A", "Option B"],
            status: "active",
            title: "Unbalanced Pool Test",
            description: "Testing unbalanced pool odds",
            winner_option: nil,
            winner: nil,
            image_url: nil,
            pool_by_option: ["Option A": 10, "Option B": 0],
            total_pool: 10,
            total_participants: 1,
            created_date: Date(),
            updated_date: nil
        )
        
        let unbalancedOdds = calculateImpliedOdds(for: unbalancedBet)
        print("Unbalanced pool odds: \(unbalancedOdds)")
        for (option, odds) in unbalancedOdds {
            let formatted = formatImpliedOdds(odds)
            print("  \(option): \(formatted)")
        }
        
        print("\n✅ Odds smoothing test completed!")
        print(String(repeating: "=", count: 50))
    }

    // MARK: - Odds History Tracking
    
    private var oddsTrackingTimer: Timer?
    private var cleanupTimer: Timer?
    private var trackedBets: Set<String> = []
    
    /// Start automatic odds tracking for all active bets
    func startAutomaticOddsTracking() {
        // Stop any existing timer
        stopAutomaticOddsTracking()
        
        // Track odds every hour for active bets
        oddsTrackingTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.trackOddsForAllActiveBets()
        }
        
        // Clean up old odds history every week
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 7 * 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.cleanupOldOddsHistory()
        }
        
        // Also track immediately
        trackOddsForAllActiveBets()
        
        print("🕒 Started automatic odds tracking (every hour) and cleanup (weekly)")
    }
    
    /// Stop automatic odds tracking
    func stopAutomaticOddsTracking() {
        oddsTrackingTimer?.invalidate()
        oddsTrackingTimer = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        print("⏹️ Stopped automatic odds tracking")
    }
    
    /// Track odds for all active bets
    private func trackOddsForAllActiveBets() {
        guard let userEmail = currentUser?.email else { return }
        
        // Use existing bets from the service
        let activeBets = bets.filter { bet in
            bet.status.lowercased() == "open" && bet.deadline > Date()
        }
        
        print("📊 Tracking odds for \(activeBets.count) active bets")
        
        for bet in activeBets {
            if let betId = bet.id {
                trackOddsHistory(for: betId, forceUpdate: false)
            }
        }
    }
    
    /// Track odds history for a bet after pool changes
    func trackOddsHistory(for betId: String, forceUpdate: Bool = false) {
        // Fetch the current bet data
        db.collection("Bet").document(betId).getDocument { [weak self] document, error in
            if let error = error {
                print("❌ trackOddsHistory: Error fetching bet: \(error.localizedDescription)")
                return
            }
            
            guard let document = document,
                  let betData = try? document.data(as: FirestoreBet.self),
                  let poolByOption = betData.pool_by_option,
                  let totalPool = betData.total_pool else {
                print("❌ trackOddsHistory: Invalid bet data or missing pool information")
                return
            }
            
            // Calculate current odds
            let currentOdds = self?.calculateImpliedOdds(for: betData) ?? [:]
            
            print("📊 trackOddsHistory: Processing bet \(betId)")
            print("📊 Force update: \(forceUpdate)")
            print("📊 Calculated odds: \(currentOdds)")
            print("📊 Total pool: \(totalPool)")
            print("📊 Pool by option: \(poolByOption)")
            
            // Check if we should track this change (avoid duplicates)
            if !forceUpdate {
                self?.checkAndTrackOddsChange(betId: betId, currentOdds: currentOdds, totalPool: totalPool, poolByOption: poolByOption)
            } else {
                print("📊 Saving initial odds history for new bet")
                self?.saveOddsHistoryEntry(betId: betId, odds: currentOdds, totalPool: totalPool, poolByOption: poolByOption)
            }
        }
    }
    
    /// Check if odds have changed significantly and track if needed
    private func checkAndTrackOddsChange(betId: String, currentOdds: [String: Double], totalPool: Int, poolByOption: [String: Int]) {
        // Get the most recent odds history entry
        db.collection("OddsHistory")
            .whereField("bet_id", isEqualTo: betId)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("❌ checkAndTrackOddsChange: Error fetching recent odds: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents,
                      !documents.isEmpty else {
                    // No previous entry, save this one
                    self?.saveOddsHistoryEntry(betId: betId, odds: currentOdds, totalPool: totalPool, poolByOption: poolByOption)
                    return
                }
                
                // Get the most recent entry by sorting on client side
                let sortedDocuments = documents.sorted { doc1, doc2 in
                    let timestamp1 = doc1.data()["timestamp"] as? Timestamp ?? Timestamp(date: Date.distantPast)
                    let timestamp2 = doc2.data()["timestamp"] as? Timestamp ?? Timestamp(date: Date.distantPast)
                    return timestamp1.dateValue() > timestamp2.dateValue()
                }
                
                guard let lastEntry = sortedDocuments.first,
                      let lastOdds = lastEntry.data()["odds_by_option"] as? [String: Double] else {
                    // Invalid entry, save this one
                    self?.saveOddsHistoryEntry(betId: betId, odds: currentOdds, totalPool: totalPool, poolByOption: poolByOption)
                    return
                }
                
                // Check if odds have changed significantly (more than 1% or pool changed)
                let lastTotalPool = lastEntry.data()["total_pool"] as? Int ?? 0
                let hasSignificantChange = self?.hasSignificantOddsChange(currentOdds: currentOdds, lastOdds: lastOdds, currentPool: totalPool, lastPool: lastTotalPool) ?? true
                
                if hasSignificantChange {
                    self?.saveOddsHistoryEntry(betId: betId, odds: currentOdds, totalPool: totalPool, poolByOption: poolByOption)
                } else {
                    print("📊 Odds haven't changed significantly for bet \(betId), skipping tracking")
                }
            }
    }
    
    /// Check if there's a significant change in odds or pool
    private func hasSignificantOddsChange(currentOdds: [String: Double], lastOdds: [String: Double], currentPool: Int, lastPool: Int) -> Bool {
        // Check if pool changed significantly (more than 10 points)
        if abs(currentPool - lastPool) > 10 {
            return true
        }
        
        // Check if any option's odds changed by more than 1%
        for (option, currentOddsValue) in currentOdds {
            if let lastOddsValue = lastOdds[option] {
                let change = abs(currentOddsValue - lastOddsValue)
                if change > 0.01 { // 1% change
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Save odds history entry to Firestore
    private func saveOddsHistoryEntry(betId: String, odds: [String: Double], totalPool: Int, poolByOption: [String: Int]) {
        let historyEntry = OddsHistoryEntry(
            bet_id: betId,
            odds_by_option: odds,
            total_pool: totalPool,
            pool_by_option: poolByOption
        )
        
        do {
            try db.collection("OddsHistory").document().setData(from: historyEntry)
            print("✅ trackOddsHistory: Successfully saved odds history for bet \(betId)")
            print("📊 Initial odds saved: \(odds)")
            print("📊 Total pool: \(totalPool)")
            print("📊 Pool by option: \(poolByOption)")
            print("📊 Timestamp: \(historyEntry.timestamp)")
        } catch {
            print("❌ trackOddsHistory: Error saving odds history: \(error.localizedDescription)")
        }
    }
    
    /// Fetch odds history for a specific bet
    func fetchOddsHistory(for betId: String, completion: @escaping ([OddsHistoryEntry]) -> Void) {
        db.collection("OddsHistory")
            .whereField("bet_id", isEqualTo: betId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ fetchOddsHistory: Error fetching odds history: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                let historyEntries = snapshot?.documents.compactMap { document in
                    try? document.data(as: OddsHistoryEntry.self)
                } ?? []
                
                // Sort by timestamp on the client side to avoid index requirement
                let sortedEntries = historyEntries.sorted { $0.timestamp < $1.timestamp }
                
                print("✅ fetchOddsHistory: Retrieved \(sortedEntries.count) odds history entries")
                completion(sortedEntries)
            }
    }
    
    /// Clean up old odds history data (keep only last 30 days)
    func cleanupOldOddsHistory() {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days ago
        
        db.collection("OddsHistory")
            .whereField("timestamp", isLessThan: Timestamp(date: thirtyDaysAgo))
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("❌ cleanupOldOddsHistory: Error fetching old entries: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                let batch = self?.db.batch()
                var deleteCount = 0
                
                for document in documents {
                    batch?.deleteDocument(document.reference)
                    deleteCount += 1
                    
                    // Firestore batch limit is 500 operations
                    if deleteCount >= 500 {
                        break
                    }
                }
                
                batch?.commit { error in
                    if let error = error {
                        print("❌ cleanupOldOddsHistory: Error deleting old entries: \(error.localizedDescription)")
                    } else {
                        print("✅ cleanupOldOddsHistory: Deleted \(deleteCount) old odds history entries")
                    }
                }
            }
    }
    
    /// Update pool data when a bet is placed
    func updateBetPool(betId: String, chosenOption: String, stakeAmount: Int, completion: @escaping (Bool) -> Void) {
        let betRef = db.collection("Bet").document(betId)
        
        print("🔄 updateBetPool: Starting pool update for bet \(betId)")
        print("🔄 updateBetPool: Adding \(stakeAmount) points to option '\(chosenOption)'")
        
        betRef.getDocument { [weak self] document, error in
            if let error = error {
                print("❌ updateBetPool: Error fetching bet for pool update: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = document, document.exists,
                  var data = document.data() else {
                print("❌ updateBetPool: Bet document not found for pool update")
                completion(false)
                return
            }
            
            // Initialize pool data if it doesn't exist
            var poolByOption = data["pool_by_option"] as? [String: Int] ?? [:]
            var totalPool = data["total_pool"] as? Int ?? 0
            
            print("🔄 updateBetPool: BEFORE UPDATE - Pool by option: \(poolByOption)")
            print("🔄 updateBetPool: BEFORE UPDATE - Total pool: \(totalPool)")
            
            // Update pool for the chosen option
            poolByOption[chosenOption] = (poolByOption[chosenOption] ?? 0) + stakeAmount
            totalPool += stakeAmount
            
            print("🔄 updateBetPool: AFTER UPDATE - Pool by option: \(poolByOption)")
            print("🔄 updateBetPool: AFTER UPDATE - Total pool: \(totalPool)")
            
            // Update the document
            data["pool_by_option"] = poolByOption
            data["total_pool"] = totalPool
            data["updated_date"] = Timestamp(date: Date())
            
            betRef.setData(data) { error in
                if let error = error {
                    print("❌ updateBetPool: Error updating bet pool: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ updateBetPool: Successfully updated bet pool for option '\(chosenOption)' with \(stakeAmount) points")
                    print("🔄 updateBetPool: Pool update complete - odds will now be different!")
                    completion(true)
                }
            }
        }
    }

    func joinBet(betId: String, chosenOption: String, stakeAmount: Int, completion: @escaping (Bool, String?) -> Void) {
        guard let userEmail = currentUser?.email,
              let userId = currentUser?.id else {
            completion(false, "User not authenticated")
            return
        }
        
        print("🎯 joinBet: Starting bet placement for user \(userEmail) on bet \(betId)")
        print("🎯 joinBet: Chosen option: \(chosenOption), Stake amount: \(stakeAmount)")
        
        // Check if user has enough points
        guard let currentUser = currentUser,
              let currentPoints = currentUser.blitz_points,
              currentPoints >= stakeAmount else {
            completion(false, "Insufficient points. You have \(currentUser?.blitz_points ?? 0) points but need \(stakeAmount)")
            return
        }
        
        let participantData = BetParticipant(
            documentId: nil,
            id: UUID().uuidString,
            bet_id: betId,
            community_id: "", // Will be set from bet data
            user_email: userEmail,
            chosen_option: chosenOption,
            stake_amount: stakeAmount,
            created_by: userEmail,
            created_by_id: userId,
            created_date: Date(),
            updated_date: Date(),
            is_winner: nil,
            final_payout: nil,
            locked_odds: nil // Will be set after calculating odds
        )
        
        // First get the bet to get community_id and calculate odds BEFORE placing the bet
        db.collection("Bet").document(betId).getDocument(source: .default) { [weak self] document, error in
            if let error = error {
                print("❌ joinBet: Error fetching bet document: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data(),
                  let communityId = data["community_id"] as? String else {
                print("❌ joinBet: Bet not found or missing community ID")
                completion(false, "Bet not found or missing community ID")
                return
            }
            
            print("✅ joinBet: Found bet with community ID: \(communityId)")
            
            // Calculate odds BEFORE placing the bet (lock in current odds)
            let currentBet = try? document.data(as: FirestoreBet.self)
            let lockedOdds = currentBet.map { self?.calculateImpliedOdds(for: $0) } ?? [:]
            print("🔒 joinBet: ===== LOCKING IN ODDS BEFORE BET PLACEMENT =====")
            print("🔒 joinBet: Current bet pool_by_option: \(currentBet?.pool_by_option ?? [:])")
            print("🔒 joinBet: Current bet total_pool: \(currentBet?.total_pool ?? 0)")
            print("🔒 joinBet: Locked in odds: \(lockedOdds)")
            print("🔒 joinBet: ================================================")
            
            // Update participant with community_id and locked odds
            var updatedParticipant = participantData
            updatedParticipant.community_id = communityId
            updatedParticipant.locked_odds = lockedOdds
            
            // Use a unique document ID for each bet placement (allows multiple bets by same user)
            let documentId = "\(betId)_\(userEmail)_\(UUID().uuidString)"
            
            // Use a batch write to ensure both operations succeed or fail together
            let batch = self?.db.batch()
            
            do {
                // Create the participant document
                let participantRef = self?.db.collection("BetParticipant").document(documentId)
                try batch?.setData(from: updatedParticipant, forDocument: participantRef!)
                
                // Deduct points from user
                let userRef = self?.db.collection("Users").document(userEmail)
                batch?.updateData(["blitz_points": currentPoints - stakeAmount], forDocument: userRef!)
                
                // Commit the batch
                batch?.commit { error in
                    if let error = error {
                        print("❌ joinBet: Error in batch write: \(error.localizedDescription)")
                        completion(false, error.localizedDescription)
                    } else {
                        print("✅ joinBet: Successfully created BetParticipant and deducted \(stakeAmount) points")
                        
                        // Update bet pool with new stake
                        print("🔄 joinBet: About to update bet pool - this will change the odds AFTER locking in")
                        self?.updateBetPool(betId: betId, chosenOption: chosenOption, stakeAmount: stakeAmount) { poolUpdateSuccess in
                            if poolUpdateSuccess {
                                print("✅ joinBet: Successfully updated bet pool - odds have now changed")
                                print("🔄 joinBet: ===== ODDS AFTER POOL UPDATE =====")
                                // Fetch the bet again to see the new odds
                                self?.db.collection("Bet").document(betId).getDocument { updatedDoc, error in
                                    if let updatedDoc = updatedDoc, let updatedBet = try? updatedDoc.data(as: FirestoreBet.self) {
                                        let newOdds = self?.calculateImpliedOdds(for: updatedBet) ?? [:]
                                        print("🔄 joinBet: New bet pool_by_option: \(updatedBet.pool_by_option ?? [:])")
                                        print("🔄 joinBet: New bet total_pool: \(updatedBet.total_pool ?? 0)")
                                        print("🔄 joinBet: New calculated odds: \(newOdds)")
                                        print("🔄 joinBet: ======================================")
                                    }
                                }
                                // Track odds history after pool update (force update for immediate changes)
                                self?.trackOddsHistory(for: betId, forceUpdate: true)
                            } else {
                                print("❌ Failed to update bet pool, but bet was placed")
                            }
                        }
                        
                        // Refresh user data, participations, and bet data
                        DispatchQueue.main.async {
                            self?.refreshCurrentUser()
                            self?.fetchUserBetParticipations()
                            self?.fetchBets() // Refresh bet data to update odds on bet cards
                        }
                        
                        // Create notification for joining the bet
                        if let betTitle = data["title"] as? String {
                            let communityId = data["community_id"] as? String
                            let communityName = data["community_name"] as? String
                            let communityIcon = data["community_icon"] as? String ?? "person.2"
                            
                            self?.createBetJoinedNotification(
                                for: userEmail,
                                betTitle: betTitle,
                                stakeAmount: stakeAmount,
                                communityId: communityId,
                                communityName: communityName,
                                communityIcon: communityIcon
                            ) { success in
                                if success {
                                    print("✅ Created bet joined notification for \(userEmail)")
                                } else {
                                    print("❌ Failed to create bet joined notification for \(userEmail)")
                                }
                            }
                        }
                        
                        completion(true, nil)
                    }
                }
            } catch {
                print("❌ joinBet: Error preparing batch write: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
            }
        }
    }
    
    func settleBet(betId: String, winnerOption: String, completion: @escaping (Bool) -> Void) {
        guard !betId.isEmpty else {
            completion(false)
            return
        }
        
        print("🎯 settleBet: Starting settlement for bet \(betId) with winner: \(winnerOption)")
        
        // First get all participants for this bet
        db.collection("BetParticipant").whereField("bet_id", isEqualTo: betId).getDocuments(source: .default) { [weak self] snapshot, error in
            if let error = error {
                print("❌ settleBet: Error fetching participants: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("❌ settleBet: No participants found for bet")
                completion(false)
                return
            }
            
            print("✅ settleBet: Found \(documents.count) participants")
            
            // Check if bet should be voided due to single-sided betting
            if self?.checkIfBetShouldBeVoided(participants: documents) == true {
                print("⚠️ settleBet: Bet has only one-sided wagering, voiding bet instead of settling")
                self?.voidBet(betId: betId, participants: documents, completion: completion)
                return
            }
            
            // Update bet status to settled (normal settlement)
            let updateData: [String: Any] = [
                "status": "settled",
                "winner_option": winnerOption,
                "updated_date": Date()
            ]
            
            self?.db.collection("Bet").document(betId).updateData(updateData) { error in
                if let error = error {
                    print("❌ settleBet: Error updating bet status: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                print("✅ settleBet: Bet status updated to settled")
                
                // Process payouts for all participants
                self?.processBetPayouts(betId: betId, winnerOption: winnerOption, participants: documents) { success in
                    if success {
                        print("✅ settleBet: All payouts processed successfully")
                        
                        // Create notifications for all participants
                        self?.createBetSettledNotifications(betId: betId, winnerOption: winnerOption, participants: documents)
                        
                        completion(true)
                    } else {
                        print("❌ settleBet: Error processing payouts")
                        completion(false)
                    }
                }
            }
        }
    }
    
    // MARK: - Bet Payout Processing
    
    private func processBetPayouts(betId: String, winnerOption: String, participants: [QueryDocumentSnapshot], completion: @escaping (Bool) -> Void) {
        print("🎯 processBetPayouts: Processing payouts for \(participants.count) participants")
        
        // Get bet details to calculate parimutuel payouts
        db.collection("Bet").document(betId).getDocument(source: .default) { [weak self] document, error in
            if let error = error {
                print("❌ processBetPayouts: Error fetching bet details: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data() else {
                print("❌ processBetPayouts: Bet not found")
                completion(false)
                return
            }
            
            // Create a FirestoreBet object for parimutuel calculation
            do {
                let bet = try document.data(as: FirestoreBet.self)
                print("✅ processBetPayouts: Bet loaded for parimutuel calculation")
                
                // Process each participant
                var processedCount = 0
                var totalParticipants = participants.count
                
                for participantDoc in participants {
                    guard let participantData = participantDoc.data() as [String: Any]?,
                          let userEmail = participantData["user_email"] as? String,
                          let chosenOption = participantData["chosen_option"] as? String,
                          let stakeAmount = participantData["stake_amount"] as? Int else {
                        print("❌ processBetPayouts: Invalid participant data for \(participantDoc.documentID)")
                        processedCount += 1
                        if processedCount == totalParticipants {
                            completion(false)
                        }
                        continue
                    }
                    
                    let isWinner = chosenOption == winnerOption
                    let payout: Double
                    
                    if isWinner {
                        // Use parimutuel payout calculation for winners
                        payout = self?.calculateParimutuelPayout(for: bet, winningOption: winnerOption, userStake: stakeAmount) ?? Double(stakeAmount)
                    } else {
                        // Losers get nothing (points already deducted when bet was placed)
                        payout = 0
                    }
                    
                    print("🎯 processBetPayouts: \(userEmail) chose '\(chosenOption)', stake: \(stakeAmount), isWinner: \(isWinner), payout: \(payout)")
                    
                    // Update participant with result
                    let participantRef = self?.db.collection("BetParticipant").document(participantDoc.documentID)
                    let participantUpdate: [String: Any] = [
                        "is_winner": isWinner,
                        "final_payout": Int(payout),
                        "updated_date": Date()
                    ]
                    
                    participantRef?.updateData(participantUpdate) { error in
                        if let error = error {
                            print("❌ processBetPayouts: Error updating participant \(userEmail): \(error.localizedDescription)")
                        } else {
                            print("✅ processBetPayouts: Participant \(userEmail) updated successfully")
                        }
                        
                        // Process payout for user - Create outstanding balance instead of direct payment
                        if isWinner {
                            // Winner should receive payout from losers - create outstanding balance
                            let pointsToReceive = Int(payout)
                            print("🎯 processBetPayouts: \(userEmail) won \(pointsToReceive) points - will be paid by losers")
                            
                            // Create outstanding balance records for losers to pay winners
                            self?.createOutstandingBalanceForWinner(
                                winnerEmail: userEmail,
                                winnerPayout: pointsToReceive,
                                betId: betId,
                                winnerOption: winnerOption,
                                participants: participants
                            ) { success in
                                if success {
                                    print("✅ processBetPayouts: Created outstanding balances for winner \(userEmail)")
                                } else {
                                    print("❌ processBetPayouts: Failed to create outstanding balances for winner \(userEmail)")
                                }
                            }
                        } else {
                            // Loser gets nothing (points already deducted when bet was placed)
                            print("ℹ️ processBetPayouts: \(userEmail) lost, no points returned (already deducted)")
                        }
                        
                        processedCount += 1
                        if processedCount == totalParticipants {
                            print("✅ processBetPayouts: All participants processed")
                            completion(true)
                        }
                    }
                }
            } catch {
                print("❌ processBetPayouts: Error decoding bet data: \(error.localizedDescription)")
                completion(false)
            }
        }
    }
    
    private func createOutstandingBalanceForWinner(
        winnerEmail: String,
        winnerPayout: Int,
        betId: String,
        winnerOption: String,
        participants: [QueryDocumentSnapshot],
        completion: @escaping (Bool) -> Void
    ) {
        print("🎯 createOutstandingBalanceForWinner: Creating outstanding balances for winner \(winnerEmail)")
        
        // Get all losers (participants who didn't choose the winning option)
        let losers = participants.filter { participantDoc in
            guard let participantData = participantDoc.data() as [String: Any]?,
                  let chosenOption = participantData["chosen_option"] as? String,
                  let userEmail = participantData["user_email"] as? String else {
                return false
            }
            return chosenOption != winnerOption && userEmail != winnerEmail
        }
        
        guard !losers.isEmpty else {
            print("ℹ️ createOutstandingBalanceForWinner: No losers found, no outstanding balances to create")
            completion(true)
            return
        }
        
        // Get bet details for outstanding balance records
        db.collection("Bet").document(betId).getDocument { [weak self] document, error in
            if let error = error {
                print("❌ createOutstandingBalanceForWinner: Error fetching bet details: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data() else {
                print("❌ createOutstandingBalanceForWinner: Bet not found")
                completion(false)
                return
            }
            
            let betTitle = data["title"] as? String ?? "Unknown Bet"
            let communityId = data["community_id"] as? String ?? ""
            
            // Get proper community name from user communities
            let communityName = self?.userCommunities.first { $0.id == communityId }?.name ?? 
                               data["community_name"] as? String ?? "General"
            
            // Calculate how much each loser owes the winner
            // For now, distribute the winner's payout proportionally among losers
            let totalLoserStakes = losers.reduce(0) { total, loserDoc in
                guard let participantData = loserDoc.data() as [String: Any]?,
                      let stakeAmount = participantData["stake_amount"] as? Int else {
                    return total
                }
                return total + stakeAmount
            }
            
            var processedCount = 0
            let totalLosers = losers.count
            
            for loserDoc in losers {
                guard let participantData = loserDoc.data() as [String: Any]?,
                      let loserEmail = participantData["user_email"] as? String,
                      let loserStake = participantData["stake_amount"] as? Int else {
                    processedCount += 1
                    if processedCount == totalLosers {
                        completion(true)
                    }
                    continue
                }
                
                // Calculate proportional amount this loser owes
                let proportionalAmount = totalLoserStakes > 0 ? 
                    Double(winnerPayout) * (Double(loserStake) / Double(totalLoserStakes)) : 
                    Double(winnerPayout) / Double(totalLosers)
                
                // Create outstanding balance record
                let balanceData: [String: Any] = [
                    "payer_email": loserEmail,
                    "payee_email": winnerEmail,
                    "amount": proportionalAmount,
                    "bet_id": betId,
                    "bet_title": betTitle,
                    "community_id": communityId,
                    "community_name": communityName,
                    "winner_option": winnerOption,
                    "status": "pending",
                    "created_date": Timestamp(date: Date()),
                    "created_by": winnerEmail
                ]
                
                self?.db.collection("OutstandingBalances").addDocument(data: balanceData) { error in
                    if let error = error {
                        print("❌ createOutstandingBalanceForWinner: Error creating balance record: \(error.localizedDescription)")
                    } else {
                        print("✅ createOutstandingBalanceForWinner: Created balance record - \(loserEmail) owes \(winnerEmail) \(proportionalAmount) points")
                    }
                    
                    processedCount += 1
                    if processedCount == totalLosers {
                        completion(true)
                    }
                }
            }
        }
    }
    
    // MARK: - Bet Voiding Logic
    
    private func checkIfBetShouldBeVoided(participants: [QueryDocumentSnapshot]) -> Bool {
        print("🔍 checkIfBetShouldBeVoided: Checking if bet should be voided")
        
        // Get all unique options that have been wagered on
        var optionsWithWagers: Set<String> = []
        
        for participantDoc in participants {
            guard let participantData = participantDoc.data() as [String: Any]?,
                  let chosenOption = participantData["chosen_option"] as? String else {
                continue
            }
            optionsWithWagers.insert(chosenOption)
        }
        
        print("🔍 checkIfBetShouldBeVoided: Found wagers on \(optionsWithWagers.count) different options: \(optionsWithWagers)")
        
        // If there are wagers on only one side, the bet should be voided
        let shouldVoid = optionsWithWagers.count <= 1
        
        if shouldVoid {
            print("⚠️ checkIfBetShouldBeVoided: Bet should be VOIDED - only one side has wagers")
        } else {
            print("✅ checkIfBetShouldBeVoided: Bet is valid - multiple sides have wagers")
        }
        
        return shouldVoid
    }
    
    private func voidBet(betId: String, participants: [QueryDocumentSnapshot], completion: @escaping (Bool) -> Void) {
        print("🚫 voidBet: Voiding bet \(betId) and refunding all participants")
        
        // Update bet status to voided
        let updateData: [String: Any] = [
            "status": "voided",
            "winner_option": NSNull(),
            "updated_date": Date()
        ]
        
        db.collection("Bet").document(betId).updateData(updateData) { [weak self] error in
            if let error = error {
                print("❌ voidBet: Error updating bet status: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            print("✅ voidBet: Bet status updated to voided")
            
            // Refund all participants
            self?.refundAllParticipants(betId: betId, participants: participants) { success in
                if success {
                    print("✅ voidBet: All participants refunded successfully")
                    
                    // Create voided bet notifications
                    self?.createBetVoidedNotifications(betId: betId, participants: participants)
                    
                    completion(true)
                } else {
                    print("❌ voidBet: Error refunding participants")
                    completion(false)
                }
            }
        }
    }
    
    private func refundAllParticipants(betId: String, participants: [QueryDocumentSnapshot], completion: @escaping (Bool) -> Void) {
        print("💰 refundAllParticipants: Refunding \(participants.count) participants")
        
        var processedCount = 0
        let totalParticipants = participants.count
        
        guard totalParticipants > 0 else {
            completion(true)
            return
        }
        
        for participantDoc in participants {
            guard let participantData = participantDoc.data() as [String: Any]?,
                  let userEmail = participantData["user_email"] as? String,
                  let stakeAmount = participantData["stake_amount"] as? Int else {
                print("❌ refundAllParticipants: Invalid participant data for \(participantDoc.documentID)")
                processedCount += 1
                if processedCount == totalParticipants {
                    completion(false)
                }
                continue
            }
            
            print("💰 refundAllParticipants: Refunding \(stakeAmount) points to \(userEmail)")
            
            // Update participant record
            let participantRef = db.collection("BetParticipant").document(participantDoc.documentID)
            let participantUpdate: [String: Any] = [
                "is_winner": NSNull(),
                "final_payout": stakeAmount, // Refund original stake
                "updated_date": Date()
            ]
            
            participantRef.updateData(participantUpdate) { [weak self] error in
                if let error = error {
                    print("❌ refundAllParticipants: Error updating participant \(userEmail): \(error.localizedDescription)")
                } else {
                    print("✅ refundAllParticipants: Participant \(userEmail) record updated")
                }
                
                // Refund points to user
                self?.updateUserBlitzPoints(userId: userEmail, pointsToAdd: stakeAmount) { success, error in
                    if success {
                        print("✅ refundAllParticipants: \(userEmail) received \(stakeAmount) points refund")
                    } else {
                        print("❌ refundAllParticipants: Error refunding points to \(userEmail): \(error ?? "Unknown error")")
                    }
                    
                    processedCount += 1
                    if processedCount == totalParticipants {
                        print("✅ refundAllParticipants: All participants processed")
                        completion(true)
                    }
                }
            }
        }
    }
    
    private func createBetVoidedNotifications(betId: String, participants: [QueryDocumentSnapshot]) {
        print("📱 createBetVoidedNotifications: Creating voided bet notifications")
        
        // Get bet details for notification
        db.collection("Bet").document(betId).getDocument(source: .default) { [weak self] document, error in
            guard let document = document, document.exists,
                  let data = document.data(),
                  let betTitle = data["title"] as? String else {
                print("❌ createBetVoidedNotifications: Could not get bet details")
                return
            }
            
            for participantDoc in participants {
                guard let participantData = participantDoc.data() as [String: Any]?,
                      let userEmail = participantData["user_email"] as? String,
                      let stakeAmount = participantData["stake_amount"] as? Int else {
                    continue
                }
                
                self?.createNotification(
                    for: userEmail,
                    title: "Bet Voided",
                    message: "Your bet on '\(betTitle)' was voided due to lack of opposing wagers. You've been refunded \(stakeAmount) points.",
                    type: "bet_voided",
                    icon: "arrow.clockwise.circle",
                    communityId: participantData["community_id"] as? String,
                    communityName: nil,
                    communityIcon: nil
                ) { success in
                    if success {
                        print("✅ Created voided bet notification for \(userEmail)")
                    } else {
                        print("❌ Failed to create voided bet notification for \(userEmail)")
                    }
                }
            }
        }
    }
    
    // MARK: - Payout Calculation
    
    private func calculatePayout(amount: Double, odds: String) -> Double {
        // Simple payout calculation based on American odds
        if odds.hasPrefix("-") {
            // Negative odds (favorite) - e.g., -110 means bet $110 to win $100
            let oddsValue = Double(odds.dropFirst()) ?? 110
            return amount * (100 / oddsValue) + amount
        } else {
            // Positive odds (underdog) - e.g., +150 means bet $100 to win $150
            let oddsValue = Double(odds) ?? 110
            return amount * (oddsValue / 100) + amount
        }
    }
    
    func createBet(betData: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        // Generate a custom 24-character alphanumeric ID
        let betId = generateBetId()
        
        // Add the ID to the bet data
        var updatedBetData = betData
        updatedBetData["id"] = betId
        
        // Create the document with the custom ID
        db.collection("Bet").document(betId).setData(updatedBetData) { [weak self] error in
            if let error = error {
                print("❌ Error creating bet: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
            } else {
                print("✅ Bet created successfully with ID: \(betId)")
                
                // Track initial odds history for the new bet (force update for new bets)
                self?.trackOddsHistory(for: betId, forceUpdate: true)
                
                // Create notifications for all community members about the new bet
                if let communityId = betData["community_id"] as? String,
                   let betTitle = betData["title"] as? String,
                   !communityId.isEmpty {
                    self?.createBetCreatedNotificationsForCommunity(
                        communityId: communityId,
                        betTitle: betTitle,
                        excludeUser: self?.currentUser?.email ?? ""
                    )
                    
                    // Send bot announcement message to the community chat
                    self?.sendBetAnnouncementMessage(
                        to: communityId,
                        betId: betId,
                        betTitle: betTitle
                    ) { success, error in
                        if success {
                            print("✅ Bot announcement message sent for bet: \(betTitle)")
                        } else {
                            print("❌ Failed to send bot announcement message: \(error ?? "Unknown error")")
                        }
                    }
                } else {
                    print("⚠️ Warning: Cannot create bet notifications - community ID is missing or empty")
                }
                
                completion(true, betId)
            }
        }
    }
    
    func updateBetImage(betId: String, imageURL: String, completion: @escaping (Bool) -> Void) {
        let updateData: [String: Any] = [
            "image_url": imageURL,
            "updated_date": Date()
        ]
        
        db.collection("Bet").document(betId).updateData(updateData) { error in
            if let error = error {
                print("❌ Error updating bet image: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Bet image updated successfully")
                completion(true)
            }
        }
    }
    
    func joinCommunity(inviteCode: String, completion: @escaping (Bool, String?) -> Void) {
        print("🔍 FirestoreService.joinCommunity: Starting with code: '\(inviteCode)'")
        
        guard let userEmail = currentUser?.email,
              let userId = currentUser?.id else {
            print("❌ FirestoreService.joinCommunity: User not authenticated")
            completion(false, "User not authenticated")
            return
        }
        
        print("🔍 FirestoreService.joinCommunity: User authenticated - Email: \(userEmail), ID: \(userId)")
        
        // Validate invite code length
        guard inviteCode.count == 6 else {
            print("❌ FirestoreService.joinCommunity: Invalid code length - \(inviteCode.count) characters")
            completion(false, "Invite code must be exactly 6 characters")
            return
        }
        
        print("🔍 FirestoreService.joinCommunity: Searching for community with invite code: '\(inviteCode)'")
        
        // Find community by invite code
        db.collection("community")
            .whereField("invite_code", isEqualTo: inviteCode)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("❌ FirestoreService.joinCommunity: Firestore query error: \(error.localizedDescription)")
                    completion(false, error.localizedDescription)
                    return
                }
                
                print("🔍 FirestoreService.joinCommunity: Query returned \(snapshot?.documents.count ?? 0) documents")
                
                guard let document = snapshot?.documents.first else {
                    print("❌ FirestoreService.joinCommunity: No community found with invite code: '\(inviteCode)'")
                    completion(false, "Community not found")
                    return
                }
                
                print("✅ FirestoreService.joinCommunity: Found community document: \(document.documentID)")
                
                // Extract the actual community ID from the document data, not the document ID
                let communityData = document.data()
                print("🔍 FirestoreService.joinCommunity: Community data: \(communityData)")
                
                guard let communityId = communityData["id"] as? String else {
                    print("❌ FirestoreService.joinCommunity: Community document missing ID field")
                    completion(false, "Community document missing ID field")
                    return
                }
                
                print("🔍 FirestoreService.joinCommunity: Community ID: \(communityId)")
                
                // Check if user is already a member of this community
                let documentId = "\(communityId)_\(userEmail)"
                self?.db.collection("CommunityMember").document(documentId).getDocument { memberSnapshot, memberError in
                    if let memberError = memberError {
                        completion(false, memberError.localizedDescription)
                        return
                    }
                    
                    if let memberSnapshot = memberSnapshot, memberSnapshot.exists {
                        // User is already a member
                        completion(false, "You are already a member of this community")
                        return
                    }
                    
                    // User is not a member, proceed to join
                    let memberData: [String: Any] = [
                        "user_email": userEmail,
                        "community_id": communityId,
                        "is_admin": false,
                        "joined_date": Date(),
                        "is_active": true,
                        "created_by": userEmail,
                        "created_by_id": userId,
                        "created_date": Date(),
                        "updated_date": Date()
                    ]
                    
                    self?.db.collection("CommunityMember").document(documentId).setData(memberData) { error in
                        if let error = error {
                            completion(false, error.localizedDescription)
                        } else {
                            // Create notification for joining the community
                            if let communityName = communityData["name"] as? String {
                                let communityId = communityId
                                let communityIcon = communityData["icon"] as? String ?? "person.2"
                                
                                self?.createCommunityJoinedNotification(
                                    for: userEmail,
                                    communityName: communityName,
                                    communityId: communityId,
                                    communityIcon: communityIcon
                                ) { success in
                                    if success {
                                        print("✅ Created community joined notification for \(userEmail)")
                                    } else {
                                        print("❌ Failed to create community joined notification for \(userEmail)")
                                    }
                                }
                                
                                // Send bot message to community chat
                                let userName = self?.currentUser?.display_name ?? self?.currentUser?.first_name ?? "Someone"
                                self?.sendCommunityJoinMessage(
                                    to: communityId,
                                    userName: userName
                                ) { success, error in
                                    if success {
                                        print("✅ Bot join message sent for \(userName)")
                                    } else {
                                        print("❌ Failed to send bot join message: \(error ?? "Unknown error")")
                                    }
                                }
                                
                                // Notify all existing community members about the new member
                                self?.notifyCommunityMembersAboutNewMember(
                                    communityId: communityId,
                                    communityName: communityName,
                                    communityIcon: communityIcon,
                                    joinedUserName: userName,
                                    joinedUserEmail: userEmail
                                )
                            }
                            
                            completion(true, nil)
                        }
                    }
                }
            }
    }
    
    func createCommunity(communityData: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        guard let userEmail = currentUser?.email,
              let userId = currentUser?.id else {
            completion(false, "User not authenticated")
            return
        }
        
        // Create the community document
        let documentRef = db.collection("community").addDocument(data: communityData)
        let communityId = documentRef.documentID
        
        // Update the document to include the community ID
        documentRef.updateData(["id": communityId]) { updateError in
            if let updateError = updateError {
                print("⚠️ Warning: Could not update community with ID field: \(updateError.localizedDescription)")
                // Continue anyway as this is not critical
            } else {
                print("✅ Community document updated with ID: \(communityId)")
            }
        }
        
        // Automatically add the creator as a member with admin privileges
        let memberData: [String: Any] = [
            "user_email": userEmail,
            "community_id": communityId,
            "is_admin": true, // Creator is admin
            "joined_date": Date(),
            "is_active": true,
            "created_by": userEmail,
            "created_by_id": userId,
            "created_date": Date(),
            "updated_date": Date()
        ]
        
        let memberDocumentId = "\(communityId)_\(userEmail)"
        db.collection("CommunityMember").document(memberDocumentId).setData(memberData) { [weak self] error in
            if let error = error {
                print("❌ Error creating community member record: \(error.localizedDescription)")
                // Still complete with success since community was created
                completion(true, communityId)
            } else {
                print("✅ Successfully created community and added creator as member")
                
                // Send bot welcome message to the new community
                if let communityName = communityData["name"] as? String {
                    let creatorName = self?.currentUser?.display_name ?? self?.currentUser?.first_name ?? "Someone"
                    self?.sendCommunityCreatedMessage(
                        to: communityId,
                        communityName: communityName,
                        creatorName: creatorName
                    ) { success, error in
                        if success {
                            print("✅ Bot welcome message sent for community: \(communityName)")
                        } else {
                            print("❌ Failed to send bot welcome message: \(error ?? "Unknown error")")
                        }
                    }
                }
                
                completion(true, communityId)
            }
        }
    }
    
    func fetchCommunityMembers(communityId: String, completion: @escaping ([CommunityMemberInfo]) -> Void) {
        print("👥 Fetching community members for community: \(communityId)")
        
        // First try to fetch by community_id field
        db.collection("CommunityMember")
            .whereField("community_id", isEqualTo: communityId)
            .whereField("is_active", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching community members by community_id: \(error.localizedDescription)")
                    // Fallback: try to fetch by document ID pattern
                    self.fetchCommunityMembersByDocumentId(communityId: communityId, completion: completion)
                    return
                }
                
                let documents = snapshot?.documents ?? []
                print("📄 Found \(documents.count) community member documents by community_id")
                
                if documents.isEmpty {
                    print("🔄 No documents found by community_id, trying document ID pattern...")
                    self.fetchCommunityMembersByDocumentId(communityId: communityId, completion: completion)
                    return
                }
                
                let members = documents.compactMap { document -> CommunityMemberInfo? in
                    let data = document.data()
                    print("🔍 Document data: \(data)")
                    print("🔍 Available fields: \(Array(data.keys))")
                    print("🔍 Looking for full_name field: \(data["full_name"] ?? "NOT FOUND")")
                    
                    guard let userEmail = data["user_email"] as? String else {
                        print("⚠️ Skipping member document \(document.documentID) - missing user_email")
                        return nil
                    }
                    
                    // Handle different is_active formats
                    let isActive: Bool
                    if let activeBool = data["is_active"] as? Bool {
                        isActive = activeBool
                    } else if let activeInt = data["is_active"] as? Int {
                        isActive = activeInt == 1
                    } else {
                        print("⚠️ Skipping member document \(document.documentID) - is_active is neither Bool nor Int")
                        return nil
                    }
                    
                    // Handle different date formats
                    let joinDate: Date
                    if let date = data["joined_date"] as? Date {
                        joinDate = date
                    } else if let timestamp = data["joined_date"] as? Timestamp {
                        joinDate = timestamp.dateValue()
                    } else {
                        print("⚠️ Skipping member document \(document.documentID) - joined_date is neither Date nor Timestamp")
                        return nil
                    }
                    
                    let isAdmin = data["is_admin"] as? Bool ?? false
                    
                    // Use full_name if available, otherwise generate from email
                    let memberName: String
                    if let fullName = data["full_name"] as? String, !fullName.isEmpty {
                        memberName = fullName
                    } else {
                        // Fallback: generate a more user-friendly name from email
                        let userName = userEmail.components(separatedBy: "@").first ?? userEmail
                        memberName = userName.replacingOccurrences(of: ".", with: " ").capitalized
                    }
                    
                    let member = CommunityMemberInfo(
                        id: document.documentID,
                        email: userEmail,
                        name: memberName,
                        isActive: isActive,
                        joinDate: joinDate,
                        isAdmin: isAdmin
                    )
                    
                    print("✅ Loaded member: \(member.name) (\(member.email)) - Admin: \(member.isAdmin)")
                    return member
                }
                
                print("🎯 Returning \(members.count) valid community members")
                completion(members)
            }
    }
    
    private func fetchCommunityMembersByDocumentId(communityId: String, completion: @escaping ([CommunityMemberInfo]) -> Void) {
        print("🔄 Fetching community members by document ID pattern for community: \(communityId)")
        
        // Get all documents and filter by document ID pattern
        db.collection("CommunityMember").getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching all community member documents: \(error.localizedDescription)")
                completion([])
                return
            }
            
            let allDocuments = snapshot?.documents ?? []
            print("📄 Found \(allDocuments.count) total community member documents")
            
            // Filter documents by document ID pattern: communityId_userEmail
            let communityDocuments = allDocuments.filter { document in
                document.documentID.hasPrefix("\(communityId)_")
            }
            
            print("🎯 Found \(communityDocuments.count) documents matching community ID pattern")
            
            let members = communityDocuments.compactMap { document -> CommunityMemberInfo? in
                let data = document.data()
                print("🔍 Document data for \(document.documentID): \(data)")
                print("🔍 Available fields: \(Array(data.keys))")
                print("🔍 Looking for full_name field: \(data["full_name"] ?? "NOT FOUND")")
                
                guard let userEmail = data["user_email"] as? String else {
                    print("⚠️ Skipping member document \(document.documentID) - missing user_email")
                    return nil
                }
                
                // Handle different is_active formats
                let isActive: Bool
                if let activeBool = data["is_active"] as? Bool {
                    isActive = activeBool
                } else if let activeInt = data["is_active"] as? Int {
                    isActive = activeInt == 1
                } else {
                    print("⚠️ Skipping member document \(document.documentID) - is_active is neither Bool nor Int")
                    return nil
                }
                
                // Handle different date formats
                let joinDate: Date
                if let date = data["joined_date"] as? Date {
                    joinDate = date
                } else if let timestamp = data["joined_date"] as? Timestamp {
                    joinDate = timestamp.dateValue()
                } else {
                    print("⚠️ Skipping member document \(document.documentID) - joined_date is neither Date nor Timestamp")
                    return nil
                }
                
                // Use full_name if available, otherwise generate from email
                let memberName: String
                if let fullName = data["full_name"] as? String, !fullName.isEmpty {
                    memberName = fullName
                } else {
                    // Fallback: generate a more user-friendly name from email
                    let userName = userEmail.components(separatedBy: "@").first ?? userEmail
                    memberName = userName.replacingOccurrences(of: ".", with: " ").capitalized
                }
                
                let isAdmin = data["is_admin"] as? Bool ?? false
                
                let member = CommunityMemberInfo(
                    id: document.documentID,
                    email: userEmail,
                    name: memberName,
                    isActive: isActive,
                    joinDate: joinDate,
                    isAdmin: isAdmin
                )
                
                print("✅ Loaded member: \(member.name) (\(member.email)) - Admin: \(member.isAdmin)")
                return member
            }
            
            print("🎯 Returning \(members.count) valid community members from document ID pattern")
            completion(members)
        }
    }
    
    func isUserAdminInCommunity(communityId: String, userEmail: String, completion: @escaping (Bool) -> Void) {
        db.collection("CommunityMember")
            .whereField("community_id", isEqualTo: communityId)
            .whereField("user_email", isEqualTo: userEmail)
            .whereField("is_admin", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error checking admin status: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                completion(!(snapshot?.documents.isEmpty ?? true))
            }
    }
    
    // MARK: - Efficient Member Checking with New Document ID Format
    
    func isUserMemberOfCommunity(communityId: String, userEmail: String, completion: @escaping (Bool) -> Void) {
        // Use the new document ID format for efficient checking
        let documentId = "\(communityId)_\(userEmail)"
        
        db.collection("CommunityMember").document(documentId).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error checking membership: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = snapshot, document.exists else {
                completion(false)
                return
            }
            
            // Check if the member is active
            let data = document.data()
            let isActive = data?["is_active"] as? Int == 1 || data?["is_active"] as? Bool == true
            
            completion(isActive)
        }
    }
    
    func getUserMembershipStatus(communityId: String, userEmail: String, completion: @escaping (Bool, Bool) -> Void) {
        // Returns (isMember, isAdmin) using the new document ID format
        let documentId = "\(communityId)_\(userEmail)"
        
        db.collection("CommunityMember").document(documentId).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error checking membership status: \(error.localizedDescription)")
                completion(false, false)
                return
            }
            
            guard let document = snapshot, document.exists else {
                completion(false, false)
                return
            }
            
            let data = document.data()
            let isActive = data?["is_active"] as? Int == 1 || data?["is_active"] as? Bool == true
            let isAdmin = data?["is_admin"] as? Int == 1 || data?["is_admin"] as? Bool == true
            
            completion(isActive, isAdmin)
        }
    }
    
    func removeUserFromCommunity(communityId: String, userEmail: String, completion: @escaping (Bool) -> Void) {
        // Use the new document ID format for efficient removal
        let documentId = "\(communityId)_\(userEmail)"
        
        db.collection("CommunityMember").document(documentId).delete { error in
            if let error = error {
                print("❌ Error removing user from community: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Successfully removed user \(userEmail) from community \(communityId)")
                completion(true)
            }
        }
    }
    
    func deactivateUserMembership(communityId: String, userEmail: String, completion: @escaping (Bool) -> Void) {
        // Alternative to deletion - just mark as inactive
        let documentId = "\(communityId)_\(userEmail)"
        
        let updateData: [String: Any] = [
            "is_active": false,
            "updated_date": Date()
        ]
        
        db.collection("CommunityMember").document(documentId).updateData(updateData) { error in
            if let error = error {
                print("❌ Error deactivating user membership: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Successfully deactivated membership for user \(userEmail) in community \(communityId)")
                completion(true)
            }
        }
    }
    
    func updateUserMembershipStatus(communityId: String, userEmail: String, isAdmin: Bool, completion: @escaping (Bool) -> Void) {
        // Update admin status using the new document ID format
        let documentId = "\(communityId)_\(userEmail)"
        
        let updateData: [String: Any] = [
            "is_admin": isAdmin,
            "updated_date": Date()
        ]
        
        db.collection("CommunityMember").document(documentId).updateData(updateData) { error in
            if let error = error {
                print("❌ Error updating user membership status: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Successfully updated membership status for user \(userEmail) in community \(communityId) - Admin: \(isAdmin)")
                completion(true)
            }
        }
    }
    
    func updateCommunityName(communityId: String, newName: String, completion: @escaping (Bool) -> Void) {
        guard !communityId.isEmpty else {
            completion(false)
            return
        }
        
        let updateData: [String: Any] = [
            "name": newName,
            "updated_date": Date()
        ]
        
        db.collection("community").document(communityId).updateData(updateData) { error in
            if let error = error {
                print("❌ Error updating community name: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Successfully updated community name: \(communityId)")
                completion(true)
            }
        }
    }
    
    func calculateMemberBalances(communityId: String, completion: @escaping ([String: Double]) -> Void) {
        // Implementation for calculating member balances

        completion([:])
    }
    
    func markAllNotificationsAsRead(completion: @escaping (Bool) -> Void) {
        guard let userEmail = currentUser?.email else {
            completion(false)
            return
        }
        
        db.collection("Notification")
            .whereField("user_email", isEqualTo: userEmail)
            .whereField("is_read", isEqualTo: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error marking notifications as read: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                let batch = self.db.batch()
                snapshot?.documents.forEach { document in
                    batch.updateData(["is_read": true], forDocument: document.reference)
                }
                
                batch.commit { error in
                    if let error = error {
                        print("❌ Error committing batch update: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        print("✅ Successfully marked all notifications as read")
                        completion(true)
                    }
                }
            }
    }
    
    func markNotificationAsRead(notificationId: String, completion: @escaping (Bool) -> Void) {
        db.collection("Notification").document(notificationId).updateData(["is_read": true]) { [weak self] error in
            if let error = error {
                print("❌ Error marking notification as read: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Successfully marked notification as read: \(notificationId)")
                
                // Update the local notifications array to reflect the read status
                DispatchQueue.main.async {
                    if let index = self?.notifications.firstIndex(where: { $0.id == notificationId }) {
                        self?.notifications[index].is_read = true
                        print("🔍 Updated local notification array - marked notification \(notificationId) as read")
                    }
                }
                
                completion(true)
            }
        }
    }
    
    func cancelUserBet(betId: String, completion: @escaping (Bool) -> Void) {
        guard !betId.isEmpty else {
            completion(false)
            return
        }
        
        db.collection("BetParticipant")
            .whereField("bet_id", isEqualTo: betId)
            .whereField("user_email", isEqualTo: currentUser?.email ?? "")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error finding user bet: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                guard let document = snapshot?.documents.first else {
                    completion(false)
                    return
                }
                
                document.reference.delete { error in
                    if let error = error {
                        print("❌ Error cancelling user bet: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        print("✅ Successfully cancelled user bet: \(betId)")
                        completion(true)
                    }
                }
            }
    }
    
    // MARK: - Helper Methods
    
    private func getCommunityNameFromId(_ communityId: String?) -> String? {
        guard let communityId = communityId else { return nil }
        return userCommunities.first { $0.id == communityId }?.name
    }
    
    private func updateOutstandingBalanceStatus(
        currentUserEmail: String,
        counterpartyEmail: String,
        newStatus: String,
        completion: @escaping (Bool) -> Void
    ) {
        print("🔄 Updating outstanding balance status to \(newStatus) between \(currentUserEmail) and \(counterpartyEmail)")
        
        // Query for outstanding balances between these two users
        let payerQuery = db.collection("OutstandingBalances")
            .whereField("payer_email", isEqualTo: currentUserEmail)
            .whereField("payee_email", isEqualTo: counterpartyEmail)
            .whereField("status", isEqualTo: "pending")
        
        let payeeQuery = db.collection("OutstandingBalances")
            .whereField("payee_email", isEqualTo: currentUserEmail)
            .whereField("payer_email", isEqualTo: counterpartyEmail)
            .whereField("status", isEqualTo: "pending")
        
        let group = DispatchGroup()
        var hasError = false
        
        // Update records where current user is the payer
        group.enter()
        payerQuery.getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching payer balance records: \(error.localizedDescription)")
                hasError = true
                group.leave()
            } else {
                let documents = snapshot?.documents ?? []
                print("📝 Found \(documents.count) payer balance records to update")
                
                if documents.isEmpty {
                    group.leave()
                } else {
                    let updateGroup = DispatchGroup()
                    for document in documents {
                        updateGroup.enter()
                        document.reference.updateData([
                            "status": newStatus,
                            "resolved_date": Timestamp(date: Date())
                        ]) { error in
                            if let error = error {
                                print("❌ Error updating payer balance record: \(error.localizedDescription)")
                                hasError = true
                            } else {
                                print("✅ Updated payer balance record: \(document.documentID)")
                            }
                            updateGroup.leave()
                        }
                    }
                    
                    updateGroup.notify(queue: .global()) {
                        group.leave()
                    }
                }
            }
        }
        
        // Update records where current user is the payee
        group.enter()
        payeeQuery.getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching payee balance records: \(error.localizedDescription)")
                hasError = true
                group.leave()
            } else {
                let documents = snapshot?.documents ?? []
                print("📝 Found \(documents.count) payee balance records to update")
                
                if documents.isEmpty {
                    group.leave()
                } else {
                    let updateGroup = DispatchGroup()
                    for document in documents {
                        updateGroup.enter()
                        document.reference.updateData([
                            "status": newStatus,
                            "resolved_date": Timestamp(date: Date())
                        ]) { error in
                            if let error = error {
                                print("❌ Error updating payee balance record: \(error.localizedDescription)")
                                hasError = true
                            } else {
                                print("✅ Updated payee balance record: \(document.documentID)")
                            }
                            updateGroup.leave()
                        }
                    }
                    
                    updateGroup.notify(queue: .global()) {
                        group.leave()
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            completion(!hasError)
        }
    }
    
    private func updateUserBlitzPoints(userId: String, pointsToAdd: Int, completion: @escaping (Bool, String?) -> Void) {
        // Try to update using email as document ID first
        if let userEmail = currentUser?.email {
            let userRef = db.collection("Users").document(userEmail)
            
            userRef.getDocument { document, error in
                if let error = error {
                    print("❌ Error fetching user document for points update: \(error.localizedDescription)")
                    completion(false, error.localizedDescription)
                    return
                }
                
                guard let document = document, document.exists else {
                    print("❌ User document not found for points update")
                    completion(false, "User document not found")
                    return
                }
                
                let currentPoints = document.data()?["blitz_points"] as? Int ?? 0
                let newPoints = currentPoints + pointsToAdd
                
                userRef.updateData(["blitz_points": newPoints]) { error in
                    if let error = error {
                        print("❌ Error updating user points: \(error.localizedDescription)")
                        completion(false, error.localizedDescription)
                    } else {
                        print("✅ Successfully updated user points from \(currentPoints) to \(newPoints)")
                        completion(true, nil)
                    }
                }
            }
        } else {
            // Fallback to UID if email not available
            let userRef = db.collection("Users").document(userId)
            
            userRef.getDocument { document, error in
                if let error = error {
                    print("❌ Error fetching user document by UID for points update: \(error.localizedDescription)")
                    completion(false, error.localizedDescription)
                    return
                }
                
                guard let document = document, document.exists else {
                    print("❌ User document not found by UID for points update")
                    completion(false, "User document not found")
                    return
                }
                
                let currentPoints = document.data()?["blitz_points"] as? Int ?? 0
                let newPoints = currentPoints + pointsToAdd
                
                userRef.updateData(["blitz_points": newPoints]) { error in
                    if let error = error {
                        print("❌ Error updating user points by UID: \(error.localizedDescription)")
                        completion(false, error.localizedDescription)
                    } else {
                        print("✅ Successfully updated user points by UID from \(currentPoints) to \(newPoints)")
                        completion(true, nil)
                    }
                }
            }
        }
    }
    
    func updateCommunityStatistics(communityId: String, completion: @escaping (Bool, String?) -> Void) {
        // This would update community statistics like member count, bet count, etc.
        // For now, just call completion
        completion(true, nil)
    }
    
    private func notifyNewMarketCreated(betTitle: String, communityName: String, memberEmails: [String]) {
        // This would send notifications to community members about new markets
        print("📢 Would notify \(memberEmails.count) members about new market: \(betTitle)")
    }
    
    private func notifyUserJoinedBet(betTitle: String, userEmail: String) {
        // This would send notification to user that they joined a bet
        print("📢 Would notify \(userEmail) that they joined bet: \(betTitle)")
    }
    
    private func notifyBetPlacedOnYourMarket(betTitle: String, bettor: String, creatorEmail: String) {
        // This would notify bet creator that someone placed a bet on their market
        print("📢 Would notify \(creatorEmail) that \(bettor) placed a bet on their market: \(betTitle)")
    }
    
    private func notifyBetWon(betTitle: String, userEmail: String) {
        // This would notify user that they won a bet
        print("📢 Would notify \(userEmail) that they won bet: \(betTitle)")
    }
    
    private func notifyBetLost(betTitle: String, userEmail: String) {
        // This would notify user that they lost a bet
        print("📢 Would notify \(userEmail) that they lost bet: \(betTitle)")
    }
    
    private func notifyBetSettled(betTitle: String, userEmail: String) {
        // This would notify user that a bet was settled
        print("📢 Would notify \(userEmail) that bet was settled: \(betTitle)")
    }
    
    private func notifyBetVoided(betTitle: String, userEmail: String) {
        // This would notify user that a bet was voided
        print("📢 Would notify \(userEmail) that bet was voided: \(betTitle)")
    }
    
    private func notifyNewMemberJoined(communityName: String, newMember: String, memberEmails: [String]) {
        // This would notify existing members about new member
        print("📢 Would notify \(memberEmails.count) members that \(newMember) joined \(communityName)")
    }
    
    private func notifySomeoneJoinedYourCommunity(communityName: String, newMember: String, adminEmail: String) {
        // This would notify admin about new member
        print("📢 Would notify admin \(adminEmail) that \(newMember) joined \(communityName)")
    }
    
    private func notifyUserJoinedCommunity(communityName: String, userEmail: String) {
        // This would notify user that they joined a community
        print("📢 Would notify \(userEmail) that they joined \(communityName)")
    }
    
    private func notifyCommunityCreated(communityName: String, userEmail: String) {
        // This would notify user that they created a community
        print("📢 Would notify \(userEmail) that they created \(communityName)")
    }
    
    private func getUnsplashImageURL(for betTitle: String, completion: @escaping (String?) -> Void) {
        // This would fetch an image from Unsplash based on the bet title
        // For now, just return nil
        completion(nil)
    }
    
    private func calculatePayout(stakeAmount: Int, odds: [String: String], chosenOption: String) -> Double {
        // This would calculate payout based on odds and stake amount
        // For now, just return a simple calculation
        return Double(stakeAmount) * 2.0 // Simple 2:1 payout
    }
    
    // MARK: - Member Net Points
    
    func getMemberNetPoints(communityId: String, memberEmail: String, completion: @escaping (Double) -> Void) {
        // Get all bets for this community where the member participated
        print("🔍 Fetching bet participations for \(memberEmail) in community \(communityId)")
        db.collection("BetParticipants")
            .whereField("community_id", isEqualTo: communityId)
            .whereField("user_email", isEqualTo: memberEmail)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching member bet participations: \(error.localizedDescription)")
                    completion(0.0)
                    return
                }
                
                let documents = snapshot?.documents ?? []
                print("📊 Found \(documents.count) bet participations for \(memberEmail)")
                
                var netPoints: Double = 0.0
                
                for document in documents {
                    let data = document.data()
                    let amount = data["amount"] as? Double ?? 0.0
                    let isWon = data["is_won"] as? Bool ?? false
                    let isSettled = data["is_settled"] as? Bool ?? false
                    
                    if isSettled {
                        if isWon {
                            netPoints += amount * 2.0 // Won - get stake back plus winnings
                        } else {
                            netPoints -= amount // Lost - lose stake
                        }
                    }
                }
                
                print("💵 \(memberEmail) net points: \(netPoints)")
                completion(netPoints)
            }
    }
    
    func getCommunityMembersWithNetPoints(communityId: String, completion: @escaping ([CommunityMemberWithPoints]) -> Void) {
        print("🔄 Fetching community members with net points for community: \(communityId)")
        fetchCommunityMembers(communityId: communityId) { members in
            print("📋 Found \(members.count) members, now calculating net points")
            var membersWithPoints: [CommunityMemberWithPoints] = []
            let group = DispatchGroup()
            
            for member in members {
                group.enter()
                self.getMemberNetPoints(communityId: communityId, memberEmail: member.email) { netPoints in
                    let memberWithPoints = CommunityMemberWithPoints(
                        member: member,
                        netPoints: netPoints
                    )
                    membersWithPoints.append(memberWithPoints)
                    print("💰 Member \(member.name): \(netPoints) points")
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                // Sort by admin status first (admins at top), then by net points (highest first)
                let sortedMembers = membersWithPoints.sorted { first, second in
                    if first.isAdmin != second.isAdmin {
                        return first.isAdmin && !second.isAdmin
                    } else {
                        return first.netPoints > second.netPoints
                    }
                }
                print("✅ Completed loading \(sortedMembers.count) members with points")
                completion(sortedMembers)
            }
        }
    }
    
    // MARK: - Outstanding Balances
    
    func fetchOutstandingBalances(completion: @escaping ([OutstandingBalance]) -> Void) {
        guard let currentUserEmail = currentUser?.email else {
            print("❌ No current user email available")
            completion([])
            return
        }
        
        print("🔍 Fetching outstanding balances for user: \(currentUserEmail)")
        
        var allBalances: [OutstandingBalance] = []
        let group = DispatchGroup()
        
        // Fetch from OutstandingBalances collection (new system)
        group.enter()
        fetchOutstandingBalancesFromCollection(userEmail: currentUserEmail) { balances in
            allBalances.append(contentsOf: balances)
            group.leave()
        }
        
        // Also fetch from BetParticipant calculations (legacy system)
        let userCommunities = self.userCommunities
        if !userCommunities.isEmpty {
            for community in userCommunities {
                guard let communityId = community.id else { continue }
                
                group.enter()
                calculateOutstandingBalancesForCommunity(communityId: communityId, userEmail: currentUserEmail) { balances in
                    allBalances.append(contentsOf: balances)
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            // Group balances by counterparty and calculate net amounts
            let groupedBalances = self.groupBalancesByCounterparty(allBalances)
            
            // Sort by most green to least green, then least red to most red
            let sortedBalances = groupedBalances.sorted { first, second in
                if first.isOwed == second.isOwed {
                    if first.isOwed {
                        // Both are red (you owe them) - sort by least to most
                        return first.displayAmount < second.displayAmount
                    } else {
                        // Both are green (they owe you) - sort by most to least
                        return first.displayAmount > second.displayAmount
                    }
                } else {
                    // Different types - green (they owe you) comes before red (you owe them)
                    return !first.isOwed && second.isOwed
                }
            }
            
            print("✅ Fetched \(sortedBalances.count) outstanding balances")
            completion(sortedBalances)
        }
    }
    
    private func fetchOutstandingBalancesFromCollection(userEmail: String, completion: @escaping ([OutstandingBalance]) -> Void) {
        print("🔍 Fetching outstanding balances from OutstandingBalances collection")
        
        // Fetch balances where user is either payer or payee
        let payerQuery = db.collection("OutstandingBalances")
            .whereField("payer_email", isEqualTo: userEmail)
            .whereField("status", isEqualTo: "pending")
        
        let payeeQuery = db.collection("OutstandingBalances")
            .whereField("payee_email", isEqualTo: userEmail)
            .whereField("status", isEqualTo: "pending")
        
        let group = DispatchGroup()
        var allBalanceRecords: [[String: Any]] = []
        
        // Fetch records where user is the payer (owes money)
        group.enter()
        payerQuery.getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching payer balances: \(error.localizedDescription)")
            } else {
                let records: [[String: Any]] = snapshot?.documents.map { document in
                    var data = document.data()
                    data["document_id"] = document.documentID
                    data["user_role"] = "payer"
                    return data
                } ?? []
                allBalanceRecords.append(contentsOf: records)
            }
            group.leave()
        }
        
        // Fetch records where user is the payee (owed money)
        group.enter()
        payeeQuery.getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching payee balances: \(error.localizedDescription)")
            } else {
                let records: [[String: Any]] = snapshot?.documents.map { document in
                    var data = document.data()
                    data["document_id"] = document.documentID
                    data["user_role"] = "payee"
                    return data
                } ?? []
                allBalanceRecords.append(contentsOf: records)
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            // Group by counterparty and calculate net amounts
            var counterpartyBalances: [String: [String: Any]] = [:]
            
            for record in allBalanceRecords {
                guard let amount = record["amount"] as? Double,
                      let userRole = record["user_role"] as? String else { continue }
                
                let counterpartyEmail = userRole == "payer" ? 
                    (record["payee_email"] as? String ?? "") : 
                    (record["payer_email"] as? String ?? "")
                
                if counterpartyBalances[counterpartyEmail] == nil {
                    counterpartyBalances[counterpartyEmail] = [
                        "counterparty": counterpartyEmail,
                        "net_amount": 0.0,
                        "transactions": []
                    ]
                }
                
                let netAmount = counterpartyBalances[counterpartyEmail]?["net_amount"] as? Double ?? 0.0
                let adjustedAmount = userRole == "payer" ? -amount : amount
                counterpartyBalances[counterpartyEmail]?["net_amount"] = netAmount + adjustedAmount
                
                // Add transaction details
                var transactions = counterpartyBalances[counterpartyEmail]?["transactions"] as? [[String: Any]] ?? []
                transactions.append([
                    "amount": amount,
                    "user_role": userRole,
                    "bet_title": record["bet_title"] as? String ?? "",
                    "bet_id": record["bet_id"] as? String ?? "",
                    "community_name": self.getCommunityNameFromId(record["community_id"] as? String) ?? 
                                     record["community_name"] as? String ?? "General",
                    "created_date": record["created_date"] as? Timestamp ?? Timestamp()
                ])
                counterpartyBalances[counterpartyEmail]?["transactions"] = transactions
            }
            
            // Convert to OutstandingBalance objects
            var balances: [OutstandingBalance] = []
            let balanceGroup = DispatchGroup()
            
            for (counterpartyEmail, balanceData) in counterpartyBalances {
                guard let netAmount = balanceData["net_amount"] as? Double,
                      netAmount != 0 else { continue }
                
                balanceGroup.enter()
                self.getUserDetails(email: counterpartyEmail) { userName, username in
                    let transactions = balanceData["transactions"] as? [[String: Any]] ?? []
                    let balanceTransactions = transactions.map { transData in
                        BalanceTransaction(
                            id: UUID().uuidString,
                            betId: transData["bet_id"] as? String ?? "",
                            betTitle: transData["bet_title"] as? String ?? "",
                            amount: transData["amount"] as? Double ?? 0.0,
                            isOwed: transData["user_role"] as? String == "payer",
                            date: (transData["created_date"] as? Timestamp)?.dateValue() ?? Date(),
                            communityName: transData["community_name"] as? String ?? "General"
                        )
                    }
                    
                    let balance = OutstandingBalance(
                        id: "outstanding_\(counterpartyEmail)",
                        profilePicture: nil,
                        username: username,
                        name: userName,
                        netAmount: netAmount,
                        transactions: balanceTransactions,
                        counterpartyId: counterpartyEmail
                    )
                    balances.append(balance)
                    balanceGroup.leave()
                }
            }
            
            balanceGroup.notify(queue: .main) {
                print("✅ Fetched \(balances.count) outstanding balances from collection")
                completion(balances)
            }
        }
    }
    
    private func calculateOutstandingBalancesForCommunity(communityId: String, userEmail: String, completion: @escaping ([OutstandingBalance]) -> Void) {
        print("🔍 Calculating balances for community: \(communityId)")
        
        // Get all bet participations in this community
        db.collection("BetParticipant")
            .whereField("community_id", isEqualTo: communityId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching bet participations: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                let participations = snapshot?.documents.compactMap { document in
                    try? document.data(as: BetParticipant.self)
                } ?? []
                
                print("📊 Found \(participations.count) bet participations in community \(communityId)")
                
                // Get bet details for all participations
                self.getBetDetailsForParticipations(participations) { betDetails in
                    // Group participations by user to calculate balances
                    var userBalances: [String: [BetParticipant]] = [:]
                    for participation in participations {
                        if userBalances[participation.user_email] == nil {
                            userBalances[participation.user_email] = []
                        }
                        userBalances[participation.user_email]?.append(participation)
                    }
                    
                    var balances: [OutstandingBalance] = []
                    
                    // Calculate balance for each user
                    for (otherUserEmail, userParticipations) in userBalances {
                        if otherUserEmail == userEmail { continue } // Skip current user
                        
                        let netBalance = self.calculateNetBalanceBetweenUsers(
                            userParticipations: userParticipations,
                            otherUserParticipations: participations.filter { $0.user_email == userEmail }
                        )
                        
                        if netBalance != 0 {
                            // Create balance transaction objects with bet details
                            let transactions = self.createBalanceTransactions(from: userParticipations, otherUserEmail: otherUserEmail, betDetails: betDetails)
                            
                            // Get user details
                            self.getUserDetails(email: otherUserEmail) { userName, username in
                                let balance = OutstandingBalance(
                                    id: "\(communityId)_\(otherUserEmail)",
                                    profilePicture: nil,
                                    username: username,
                                    name: userName,
                                    netAmount: netBalance,
                                    transactions: transactions,
                                    counterpartyId: otherUserEmail
                                )
                                balances.append(balance)
                            }
                        }
                    }
                    
                    completion(balances)
                }
            }
    }
    
    private func calculateNetBalanceBetweenUsers(userParticipations: [BetParticipant], otherUserParticipations: [BetParticipant]) -> Double {
        var netBalance: Double = 0.0
        
        // Calculate balance from current user's perspective
        for participation in otherUserParticipations {
            var amount = -Double(participation.stake_amount) // Initial bet cost
            if let payout = participation.final_payout {
                amount += Double(payout) // Add winnings if any
            }
            netBalance += amount
        }
        
        // Subtract balance from other user's perspective (this becomes the net amount owed)
        for participation in userParticipations {
            var amount = Double(participation.stake_amount) // Other user's bet cost
            if let payout = participation.final_payout {
                amount -= Double(payout) // Subtract winnings if any
            }
            netBalance -= amount
        }
        
        return netBalance
    }
    
    private func createBalanceTransactions(from participations: [BetParticipant], otherUserEmail: String, betDetails: [String: String]) -> [BalanceTransaction] {
        return participations.compactMap { participation in
            // Get bet details to create transaction
            guard let betId = participation.documentId else { return nil }
            
            // Get community name from user communities
            let communityName = self.userCommunities.first { $0.id == participation.community_id }?.name ?? "Community"
            
            // Get actual bet title from bet details
            let betTitle = betDetails[participation.bet_id] ?? "Bet #\(participation.bet_id.prefix(8))"
            
            return BalanceTransaction(
                id: betId,
                betId: participation.bet_id,
                betTitle: betTitle,
                amount: Double(participation.stake_amount),
                isOwed: participation.final_payout == nil, // If no payout, bet is still outstanding
                date: participation.created_date,
                communityName: communityName
            )
        }
    }
    
    private func groupBalancesByCounterparty(_ balances: [OutstandingBalance]) -> [OutstandingBalance] {
        var groupedBalances: [String: OutstandingBalance] = [:]
        
        for balance in balances {
            if let existing = groupedBalances[balance.counterpartyId] {
                // Combine balances for the same counterparty
                let combinedTransactions = existing.transactions + balance.transactions
                let combinedNetAmount = existing.netAmount + balance.netAmount
                
                let combinedBalance = OutstandingBalance(
                    id: existing.id,
                    profilePicture: existing.profilePicture,
                    username: existing.username,
                    name: existing.name,
                    netAmount: combinedNetAmount,
                    transactions: combinedTransactions,
                    counterpartyId: existing.counterpartyId
                )
                
                groupedBalances[balance.counterpartyId] = combinedBalance
            } else {
                groupedBalances[balance.counterpartyId] = balance
            }
        }
        
        return Array(groupedBalances.values)
    }
    
    // MARK: - Resolved Balances Management
    
    func fetchResolvedBalances(completion: @escaping ([ResolvedBalance]) -> Void) {
        guard let currentUserEmail = currentUser?.email else {
            print("❌ No current user email available")
            completion([])
            return
        }
        
        print("🔍 Fetching resolved balances for user: \(currentUserEmail)")
        
        // Fetch from ResolvedBalances collection
        let query = db.collection("ResolvedBalances")
            .whereField("user_email", isEqualTo: currentUserEmail)
            .order(by: "resolved_date", descending: true)
            .limit(to: 50) // Limit to recent 50 resolved balances
        
        query.getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching resolved balances: \(error.localizedDescription)")
                completion([])
                return
            }
            
            var resolvedBalances: [ResolvedBalance] = []
            let group = DispatchGroup()
            
            for document in snapshot?.documents ?? [] {
                let data = document.data()
                
                guard let counterpartyEmail = data["counterparty_email"] as? String,
                      let netAmount = data["net_amount"] as? Double,
                      let resolvedBy = data["resolved_by"] as? String,
                      let resolvedDate = (data["resolved_date"] as? Timestamp)?.dateValue(),
                      let transactionsData = data["transactions"] as? [[String: Any]] else {
                    continue
                }
                
                group.enter()
                self.getUserDetails(email: counterpartyEmail) { userName, username in
                    let transactions = transactionsData.map { transData in
                        BalanceTransaction(
                            id: transData["id"] as? String ?? UUID().uuidString,
                            betId: transData["bet_id"] as? String ?? "",
                            betTitle: transData["bet_title"] as? String ?? "",
                            amount: transData["amount"] as? Double ?? 0.0,
                            isOwed: transData["is_owed"] as? Bool ?? false,
                            date: (transData["date"] as? Timestamp)?.dateValue() ?? Date(),
                            communityName: transData["community_name"] as? String ?? "General"
                        )
                    }
                    
                    let resolvedBalance = ResolvedBalance(
                        id: document.documentID,
                        profilePicture: data["profile_picture"] as? String,
                        username: username,
                        name: userName,
                        netAmount: netAmount,
                        transactions: transactions,
                        counterpartyId: counterpartyEmail,
                        resolvedDate: resolvedDate,
                        resolvedBy: resolvedBy
                    )
                    
                    resolvedBalances.append(resolvedBalance)
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                print("✅ Fetched \(resolvedBalances.count) resolved balances")
                completion(resolvedBalances)
            }
        }
    }
    
    func addResolvedBalance(_ resolvedBalance: ResolvedBalance, completion: @escaping (Bool, String?) -> Void) {
        guard let currentUserEmail = currentUser?.email else {
            print("❌ No current user email available")
            completion(false, "No current user")
            return
        }
        
        print("💾 Adding resolved balance to history: \(resolvedBalance.id)")
        
        // Convert transactions to dictionary format
        let transactionsData = resolvedBalance.transactions.map { transaction in
            [
                "id": transaction.id,
                "bet_id": transaction.betId,
                "bet_title": transaction.betTitle,
                "amount": transaction.amount,
                "is_owed": transaction.isOwed,
                "date": Timestamp(date: transaction.date),
                "community_name": transaction.communityName
            ]
        }
        
        let resolvedBalanceData: [String: Any] = [
            "user_email": currentUserEmail,
            "counterparty_email": resolvedBalance.counterpartyId,
            "counterparty_name": resolvedBalance.name,
            "counterparty_username": resolvedBalance.username,
            "profile_picture": resolvedBalance.profilePicture ?? "",
            "net_amount": resolvedBalance.netAmount,
            "transactions": transactionsData,
            "resolved_date": Timestamp(date: resolvedBalance.resolvedDate),
            "resolved_by": resolvedBalance.resolvedBy,
            "created_date": Timestamp()
        ]
        
        db.collection("ResolvedBalances").document(resolvedBalance.id).setData(resolvedBalanceData) { error in
            if let error = error {
                print("❌ Error adding resolved balance: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
            } else {
                print("✅ Successfully added resolved balance to history")
                completion(true, nil)
            }
        }
    }
    
    // MARK: - Balance Resolution
    
    func resolveOutstandingBalance(balanceId: String, completion: @escaping (Bool, String?) -> Void) {
        guard let currentUserEmail = currentUser?.email else {
            completion(false, "No current user available")
            return
        }
        
        print("🔄 Resolving outstanding balance: \(balanceId)")
        
        // For the new OutstandingBalances collection, we need to find and update the specific records
        if balanceId.hasPrefix("outstanding_") {
            let counterpartyEmail = String(balanceId.dropFirst("outstanding_".count))
            
            // Use the same method as markBalanceAsPaid but with "resolved" status
            updateOutstandingBalanceStatus(
                currentUserEmail: currentUserEmail,
                counterpartyEmail: counterpartyEmail,
                newStatus: "resolved"
            ) { success in
                if success {
                    print("✅ Successfully resolved outstanding balance")
                    
                    // Refresh outstanding balances
                    DispatchQueue.main.async {
                        self.fetchOutstandingBalances { _ in
                            // Updated balances will be reflected in UI
                        }
                    }
                    
                    completion(true, nil)
                } else {
                    print("❌ Failed to resolve outstanding balance")
                    completion(false, "Failed to resolve balance records")
                }
            }
        } else {
            // Legacy system - create a balance resolution record
            let resolutionData: [String: Any] = [
                "balance_id": balanceId,
                "resolved_by": currentUserEmail,
                "resolved_at": Timestamp(date: Date()),
                "status": "resolved"
            ]
            
            // Add to BalanceResolutions collection
            db.collection("BalanceResolutions").addDocument(data: resolutionData) { error in
                if let error = error {
                    print("❌ Error resolving balance: \(error.localizedDescription)")
                    completion(false, error.localizedDescription)
                } else {
                    print("✅ Successfully resolved balance: \(balanceId)")
                    
                    // Refresh outstanding balances
                    DispatchQueue.main.async {
                        self.fetchOutstandingBalances { _ in
                            // Updated balances will be reflected in UI
                        }
                    }
                    
                    completion(true, nil)
                }
            }
        }
    }
    
    func markBalanceAsPaid(counterpartyId: String, amount: Double, completion: @escaping (Bool, String?) -> Void) {
        guard let currentUserEmail = currentUser?.email else {
            completion(false, "No current user available")
            return
        }
        
        print("💰 Marking balance as paid: \(amount) to \(counterpartyId)")
        
        // Create a payment record
        let paymentData: [String: Any] = [
            "payer_email": currentUserEmail,
            "payee_email": counterpartyId,
            "amount": amount,
            "payment_date": Timestamp(date: Date()),
            "status": "completed",
            "created_by": currentUserEmail,
            "created_date": Timestamp(date: Date())
        ]
        
        // Add to Payments collection
        db.collection("Payments").addDocument(data: paymentData) { [weak self] error in
            if let error = error {
                print("❌ Error recording payment: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
            } else {
                print("✅ Successfully recorded payment of \(amount) to \(counterpartyId)")
                
                // Now update the status of outstanding balance records to "paid"
                self?.updateOutstandingBalanceStatus(
                    currentUserEmail: currentUserEmail,
                    counterpartyEmail: counterpartyId,
                    newStatus: "paid"
                ) { updateSuccess in
                    if updateSuccess {
                        print("✅ Successfully updated outstanding balance status to paid")
                    } else {
                        print("⚠️ Payment recorded but failed to update balance status")
                    }
                    
                    // Refresh outstanding balances regardless
                    DispatchQueue.main.async {
                        self?.fetchOutstandingBalances { _ in
                            // Updated balances will be reflected in UI
                        }
                    }
                    
                    completion(true, nil)
                }
            }
        }
    }
    
    func getUserDetails(email: String, completion: @escaping (String, String) -> Void) {
        db.collection("Users").document(email).getDocument { document, error in
            if let document = document, document.exists,
               let data = document.data() {
                let firstName = data["first_name"] as? String ?? ""
                let lastName = data["last_name"] as? String ?? ""
                let displayName = data["display_name"] as? String ?? ""
                
                let userName: String
                if !firstName.isEmpty && !lastName.isEmpty {
                    userName = "\(firstName) \(lastName)"
                } else if !displayName.isEmpty {
                    userName = displayName
                } else {
                    userName = email.components(separatedBy: "@").first ?? email
                }
                
                let username = "@\(email.components(separatedBy: "@").first ?? email)"
                completion(userName, username)
            } else {
                let username = "@\(email.components(separatedBy: "@").first ?? email)"
                completion(email, username)
            }
        }
    }
    
    func getUserProfilePicture(email: String, completion: @escaping (String?) -> Void) {
        db.collection("Users").document(email).getDocument { document, error in
            if let document = document, document.exists,
               let data = document.data() {
                let profilePictureUrl = data["profile_picture_url"] as? String
                completion(profilePictureUrl)
            } else {
                completion(nil)
            }
        }
    }
    
    private func getBetDetailsForParticipations(_ participations: [BetParticipant], completion: @escaping ([String: String]) -> Void) {
        let uniqueBetIds = Set(participations.map { $0.bet_id })
        var betDetails: [String: String] = [:]
        let group = DispatchGroup()
        
        for betId in uniqueBetIds {
            group.enter()
            db.collection("Bet").document(betId).getDocument(source: .default) { document, error in
                if let document = document, document.exists,
                   let data = document.data(),
                   let title = data["title"] as? String {
                    betDetails[betId] = title
                } else {
                    betDetails[betId] = "Bet #\(betId.prefix(8))"
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(betDetails)
        }
    }
    
    // MARK: - Community Management Methods
    
    func leaveCommunity(communityId: String, userEmail: String, completion: @escaping (Bool) -> Void) {
        // Remove user from community members array
        db.collection("community").document(communityId).getDocument(source: .default) { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Error fetching community: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = snapshot, document.exists,
                  let data = document.data(),
                  var members = data["members"] as? [String] else {
                print("❌ Community document not found or invalid")
                completion(false)
                return
            }
            
            // Remove user from members array
            members.removeAll { $0 == userEmail }
            
            // Update community document
            let updateData: [String: Any] = [
                "members": members,
                "member_count": members.count,
                "updated_date": Date()
            ]
            
            self.db.collection("community").document(communityId).updateData(updateData) { error in
                if let error = error {
                    print("❌ Error updating community members: \(error.localizedDescription)")
                    completion(false)
                } else {
                    // Also remove from CommunityMember collection
                    self.removeUserFromCommunity(communityId: communityId, userEmail: userEmail) { success in
                        if success {
                            print("✅ Successfully left community \(communityId)")
                            // Refresh user communities
                            self.fetchUserCommunities()
                        }
                        completion(success)
                    }
                }
            }
        }
    }
    
    func kickMemberFromCommunity(communityId: String, memberEmail: String, completion: @escaping (Bool) -> Void) {
        // Only admins can kick members
        guard let currentUserEmail = currentUser?.email else {
            completion(false)
            return
        }
        
        isUserAdminInCommunity(communityId: communityId, userEmail: currentUserEmail) { [weak self] isAdmin in
            guard let self = self else { return }
            
            if !isAdmin {
                print("❌ User is not admin, cannot kick members")
                completion(false)
                return
            }
            
            // Remove member from community
            self.leaveCommunity(communityId: communityId, userEmail: memberEmail) { success in
                if success {
                    print("✅ Successfully kicked member \(memberEmail) from community \(communityId)")
                }
                completion(success)
            }
        }
    }
    
    func promoteMemberToAdmin(communityId: String, memberEmail: String, completion: @escaping (Bool) -> Void) {
        // Only admins can promote members
        guard let currentUserEmail = currentUser?.email else {
            completion(false)
            return
        }
        
        isUserAdminInCommunity(communityId: communityId, userEmail: currentUserEmail) { [weak self] isAdmin in
            guard let self = self else { return }
            
            if !isAdmin {
                print("❌ User is not admin, cannot promote members")
                completion(false)
                return
            }
            
            // Update member to admin status
            self.updateUserMembershipStatus(communityId: communityId, userEmail: memberEmail, isAdmin: true) { success in
                if success {
                    print("✅ Successfully promoted \(memberEmail) to admin in community \(communityId)")
                }
                completion(success)
            }
        }
    }
    
    func demoteAdminToMember(communityId: String, memberEmail: String, completion: @escaping (Bool) -> Void) {
        // Only admins can demote other admins
        guard let currentUserEmail = currentUser?.email else {
            completion(false)
            return
        }
        
        isUserAdminInCommunity(communityId: communityId, userEmail: currentUserEmail) { [weak self] isAdmin in
            guard let self = self else { return }
            
            if !isAdmin {
                print("❌ User is not admin, cannot demote members")
                completion(false)
                return
            }
            
            // Prevent demoting yourself if you're the only admin
            if memberEmail == currentUserEmail {
                print("❌ Cannot demote yourself if you're the only admin")
                completion(false)
                return
            }
            
            // Update member to regular member status
            self.updateUserMembershipStatus(communityId: communityId, userEmail: memberEmail, isAdmin: false) { success in
                if success {
                    print("✅ Successfully demoted \(memberEmail) to member in community \(communityId)")
                }
                completion(success)
            }
        }
    }
    
    func deleteCommunity(communityId: String, completion: @escaping (Bool) -> Void) {
        // Only admins can delete communities
        guard let currentUserEmail = currentUser?.email else {
            completion(false)
            return
        }
        
        isUserAdminInCommunity(communityId: communityId, userEmail: currentUserEmail) { [weak self] isAdmin in
            guard let self = self else { return }
            
            if !isAdmin {
                print("❌ User is not admin, cannot delete community")
                completion(false)
                return
            }
            
            // Delete community document
            self.db.collection("community").document(communityId).delete { error in
                if let error = error {
                    print("❌ Error deleting community: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ Successfully deleted community \(communityId)")
                    // Refresh user communities
                    self.fetchUserCommunities()
                    completion(true)
                }
            }
        }
    }
    
    func updateCommunityDescription(communityId: String, newDescription: String, completion: @escaping (Bool) -> Void) {
        // Only admins can update community description
        guard let currentUserEmail = currentUser?.email else {
            completion(false)
            return
        }
        
        isUserAdminInCommunity(communityId: communityId, userEmail: currentUserEmail) { [weak self] isAdmin in
            guard let self = self else { return }
            
            if !isAdmin {
                print("❌ User is not admin, cannot update community description")
                completion(false)
                return
            }
            
            let updateData: [String: Any] = [
                "description": newDescription,
                "updated_date": Date()
            ]
            
            self.db.collection("community").document(communityId).updateData(updateData) { error in
                if let error = error {
                    print("❌ Error updating community description: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ Successfully updated community description")
                    completion(true)
                }
            }
        }
    }
    
    func toggleCommunityPrivacy(communityId: String, isPrivate: Bool, completion: @escaping (Bool) -> Void) {
        // Only admins can toggle community privacy
        guard let currentUserEmail = currentUser?.email else {
            completion(false)
            return
        }
        
        isUserAdminInCommunity(communityId: communityId, userEmail: currentUserEmail) { [weak self] isAdmin in
            guard let self = self else { return }
            
            if !isAdmin {
                print("❌ User is not admin, cannot toggle community privacy")
                completion(false)
                return
            }
            
            let updateData: [String: Any] = [
                "is_private": isPrivate,
                "updated_date": Date()
            ]
            
            self.db.collection("community").document(communityId).updateData(updateData) { error in
                if let error = error {
                    print("❌ Error updating community privacy: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ Successfully updated community privacy to \(isPrivate ? "private" : "public")")
                    completion(true)
                }
            }
        }
    }
    
    func updateNotificationPreferences(communityId: String, userEmail: String, isMuted: Bool, completion: @escaping (Bool) -> Void) {
        let documentId = "\(communityId)_\(userEmail)"
        
        let updateData: [String: Any] = [
            "notifications_muted": isMuted,
            "updated_date": Date()
        ]
        
        db.collection("CommunityMember").document(documentId).updateData(updateData) { error in
            if let error = error {
                print("❌ Error updating notification preferences: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Successfully updated notification preferences for \(userEmail) in community \(communityId)")
                completion(true)
            }
        }
    }
    
    func getNotificationPreferences(communityId: String, userEmail: String, completion: @escaping (Bool) -> Void) {
        let documentId = "\(communityId)_\(userEmail)"
        
        db.collection("CommunityMember").document(documentId).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error fetching notification preferences: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = snapshot, document.exists,
                  let data = document.data() else {
                completion(false)
                return
            }
            
            let isMuted = data["notifications_muted"] as? Bool ?? false
            completion(isMuted)
        }
    }
    
    // MARK: - User Settings Management
    
    func updateUserSettings(settings: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let userEmail = currentUser?.email else {
            print("❌ No current user email available")
            completion(false)
            return
        }
        
        print("🔧 Updating user settings for: \(userEmail)")
        print("🔧 Settings to update: \(settings)")
        
        // Add timestamp
        var updateData = settings
        updateData["updated_date"] = Date()
        
        db.collection("Users").document(userEmail).updateData(updateData) { error in
            if let error = error {
                print("❌ Error updating user settings: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Successfully updated user settings")
                // Refresh current user to get updated data
                self.refreshCurrentUser()
                completion(true)
            }
        }
    }
    
    func updatePushNotificationSettings(enabled: Bool, completion: @escaping (Bool) -> Void) {
        let settings: [String: Any] = [
            "push_notifications_enabled": enabled
        ]
        updateUserSettings(settings: settings, completion: completion)
    }
    
    func updateEmailNotificationSettings(weeklySummaries: Bool, betResults: Bool, communityUpdates: Bool, promotionalEmails: Bool, completion: @escaping (Bool) -> Void) {
        let settings: [String: Any] = [
            "email_notifications_enabled": true,
            "weekly_summaries_enabled": weeklySummaries,
            "bet_results_enabled": betResults,
            "community_updates_enabled": communityUpdates,
            "promotional_emails_enabled": promotionalEmails
        ]
        updateUserSettings(settings: settings, completion: completion)
    }
    
    func updateProfileVisibilitySettings(settings: ProfileVisibilitySettings, completion: @escaping (Bool) -> Void) {
        let settingsData: [String: Any] = [
            "profile_visibility_settings": [
                "showPointBalance": settings.showPointBalance,
                "showTotalWinnings": settings.showTotalWinnings,
                "showTotalBets": settings.showTotalBets,
                "showSlingPoints": settings.showSlingPoints,
                "showBlitzPoints": settings.showBlitzPoints,
                "showCommunities": settings.showCommunities
            ]
        ]
        updateUserSettings(settings: settingsData, completion: completion)
    }
    
    func updateDarkModeSetting(enabled: Bool, completion: @escaping (Bool) -> Void) {
        let settings: [String: Any] = [
            "dark_mode_enabled": enabled
        ]
        updateUserSettings(settings: settings, completion: completion)
    }
    
    func updateLanguageSetting(language: String, completion: @escaping (Bool) -> Void) {
        let settings: [String: Any] = [
            "language": language
        ]
        updateUserSettings(settings: settings, completion: completion)
    }
    
    func ensureUserSettingsExist(completion: @escaping (Bool) -> Void) {
        guard let userEmail = currentUser?.email else {
            print("❌ No current user email available")
            completion(false)
            return
        }
        
        print("🔧 Ensuring user settings exist for: \(userEmail)")
        
        // Default settings
        let defaultSettings: [String: Any] = [
            "push_notifications_enabled": true,
            "email_notifications_enabled": true,
            "weekly_summaries_enabled": true,
            "bet_results_enabled": true,
            "community_updates_enabled": true,
            "promotional_emails_enabled": false,
            "profile_visibility_settings": [
                "showPointBalance": true,
                "showTotalWinnings": true,
                "showTotalBets": true,
                "showSlingPoints": true,
                "showBlitzPoints": true,
                "showCommunities": true
            ],
            "dark_mode_enabled": false,
            "language": "English",
            "updated_date": Date()
        ]
        
        db.collection("Users").document(userEmail).setData(defaultSettings, merge: true) { error in
            if let error = error {
                print("❌ Error ensuring user settings exist: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Successfully ensured user settings exist")
                // Refresh current user to get updated data
                self.refreshCurrentUser()
                completion(true)
            }
        }
    }
    
    // MARK: - Community Image Upload
    
    func uploadCommunityImage(_ image: UIImage, communityId: String, completion: @escaping (Bool, String?) -> Void) {
        // Check if user has permission to update community image
        guard let currentUserEmail = currentUser?.email else {
            completion(false, "User not authenticated")
            return
        }
        
        // Check if user is admin or has permission to change community image
        isUserAdminInCommunity(communityId: communityId, userEmail: currentUserEmail) { isAdmin in
            // For now, allow any community member to change the profile image
            // You can modify this to restrict to admins only by changing the condition
            guard isAdmin || true else { // Allow all members for now
                completion(false, "Only admins can change community profile image")
                return
            }
            
            // Compress and upload image
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                completion(false, "Failed to process image")
                return
            }
            
            let storage = Storage.storage()
            let storageRef = storage.reference()
            
            let imageRef = storageRef.child("community_images/\(communityId)_\(UUID().uuidString).jpg")
            print("🔍 Community storage bucket: \(storageRef.bucket)")
            print("🔍 Community full path: \(imageRef.fullPath)")
            
            // Upload image
            imageRef.putData(imageData, metadata: nil) { [weak self] metadata, error in
                if let error = error {
                    print("❌ Error uploading community image: \(error)")
                    SlingLogError("Failed to upload community image to Firebase Storage", error: error)
                    completion(false, "Failed to upload image: \(error.localizedDescription)")
                    return
                }
                
                // Get download URL
                imageRef.downloadURL { [weak self] url, error in
                    if let error = error {
                        print("❌ Error getting download URL: \(error)")
                        SlingLogError("Failed to get download URL for community image", error: error)
                        completion(false, "Failed to get image URL: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let downloadURL = url?.absoluteString else {
                        completion(false, "Failed to get image URL")
                        return
                    }
                    
                    // Update community document with new image URL
                    self?.updateCommunityProfileImage(communityId: communityId, imageUrl: downloadURL, completion: completion)
                }
            }
        }
    }
    
    private func updateCommunityProfileImage(communityId: String, imageUrl: String, completion: @escaping (Bool, String?) -> Void) {
        db.collection("community").document(communityId).updateData([
            "profile_image_url": imageUrl,
            "updated_date": Date()
        ]) { [weak self] error in
            if let error = error {
                print("❌ Error updating community profile image: \(error)")
                SlingLogError("Failed to update community profile image in Firestore", error: error)
                completion(false, "Failed to update community: \(error.localizedDescription)")
                return
            }
            
            print("✅ Successfully updated community profile image")
            SlingLogInfo("User Action: Updated community profile image - Community ID: \(communityId)")
            
            // Update local community data
            DispatchQueue.main.async {
                if let index = self?.userCommunities.firstIndex(where: { $0.id == communityId }) {
                    self?.userCommunities[index].profile_image_url = imageUrl
                }
                if let index = self?.communities.firstIndex(where: { $0.id == communityId }) {
                    self?.communities[index].profile_image_url = imageUrl
                }
            }
            
            completion(true, nil)
        }
    }
    
    // MARK: - User Profile Image Upload
    
    func uploadUserProfileImage(_ image: UIImage, completion: @escaping (Bool, String?) -> Void) {
        // Check if user is authenticated
        guard let currentUserEmail = currentUser?.email,
              let userId = currentUser?.id else {
            completion(false, "User not authenticated")
            return
        }
        
        print("🔍 Starting user profile image upload for user: \(currentUserEmail)")
        
        // Debug: Check Firebase Auth state
        if let authUser = Auth.auth().currentUser {
            print("🔒 Firebase Auth - User: \(authUser.email ?? "no email"), UID: \(authUser.uid)")
            print("🔒 Firebase Auth - Is anonymous: \(authUser.isAnonymous)")
            print("🔒 Firebase Auth - Email verified: \(authUser.isEmailVerified)")
        } else {
            print("❌ No Firebase Auth user found - uploads will fail!")
        }
        
        // Compress image
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(false, "Failed to process image")
            return
        }
        
        print("📷 Image compressed successfully, size: \(imageData.count) bytes")
        
        let storage = Storage.storage()
        let storageRef = storage.reference()
        
        let fileName = "\(userId)_\(UUID().uuidString).jpg"
        let imageRef = storageRef.child("user_profile_images/\(fileName)")
        
        print("📤 Uploading to path: user_profile_images/\(fileName)")
        print("🔍 Storage bucket: \(storageRef.bucket)")
        print("🔍 Full path: \(imageRef.fullPath)")
        
        // Create metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        // Upload image with retry logic
        func attemptUpload(retryCount: Int = 0) {
            let uploadTask = imageRef.putData(imageData, metadata: metadata) { [weak self] metadata, error in
                if let error = error {
                    print("❌ Error uploading user profile image (attempt \(retryCount + 1)): \(error)")
                    print("🔍 Error domain: \(error._domain), code: \(error._code)")
                    
                    // If it's a 404 error and we haven't retried yet, try once more
                    if error._code == -13010 && retryCount < 1 {
                        print("🔄 Retrying upload due to 404 error...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            attemptUpload(retryCount: retryCount + 1)
                        }
                        return
                    }
                    
                    SlingLogError("User profile image upload failed", error: error)
                    completion(false, error.localizedDescription)
                    return
                }
            
            print("✅ Image uploaded successfully, getting download URL...")
            
            // Get download URL
            imageRef.downloadURL { [weak self] url, error in
                if let error = error {
                    print("❌ Error getting user profile image download URL: \(error)")
                    print("🔍 Download URL error domain: \(error._domain), code: \(error._code)")
                    SlingLogError("Getting user profile image URL failed", error: error)
                    completion(false, error.localizedDescription)
                    return
                }
                
                guard let downloadURL = url else {
                    completion(false, "Failed to get image URL")
                    return
                }
                
                let imageUrlString = downloadURL.absoluteString
                print("✅ User profile image uploaded successfully: \(imageUrlString)")
                
                // Update user profile with new image URL
                self?.updateUserProfileImage(imageUrl: imageUrlString, completion: completion)
            }
        }
        
        // Monitor upload progress
        uploadTask.observe(.progress) { snapshot in
            let percentComplete = 100.0 * Double(snapshot.progress!.completedUnitCount) / Double(snapshot.progress!.totalUnitCount)
            print("📊 Upload progress: \(percentComplete)%")
        }
        
        uploadTask.observe(.success) { snapshot in
            print("🎉 Upload completed successfully")
        }
        
        uploadTask.observe(.failure) { snapshot in
            if let error = snapshot.error {
                print("💥 Upload task failed: \(error)")
            }
        }
        }
        
        // Start the upload
        attemptUpload()
    }
    
    private func updateUserProfileImage(imageUrl: String, completion: @escaping (Bool, String?) -> Void) {
        guard let currentUserEmail = currentUser?.email,
              let userId = currentUser?.id else {
            completion(false, "User not authenticated")
            return
        }
        
        print("🔍 Updating user profile image - Email: \(currentUserEmail), User ID: \(userId)")
        
        // Try updating by email first (original approach)
        db.collection("Users").document(currentUserEmail).updateData([
            "profile_picture_url": imageUrl,
            "updated_date": Date()
        ]) { [weak self] error in
            if let error = error {
                print("❌ Failed to update by email, trying by user ID...")
                print("🔍 Error: \(error.localizedDescription)")
                
                // Fallback: Try updating by user ID
                self?.db.collection("Users").document(userId).updateData([
                    "profile_picture_url": imageUrl,
                    "updated_date": Date()
                ]) { [weak self] fallbackError in
                    if let fallbackError = fallbackError {
                        print("❌ Error updating user profile image in Firestore (both attempts failed): \(fallbackError)")
                        SlingLogError("User profile image update failed", error: fallbackError)
                        completion(false, fallbackError.localizedDescription)
                        return
                    }
                    
                    print("✅ User profile image updated in Firestore successfully (by user ID)")
                    SlingLogInfo("User Action: Updated user profile image - User: \(currentUserEmail)")
                    
                    // Update local user data
                    DispatchQueue.main.async {
                        self?.currentUser?.profile_picture_url = imageUrl
                    }
                    
                    completion(true, nil)
                }
                return
            }
            
            // Success with email-based update
            print("✅ User profile image updated in Firestore successfully (by email)")
            SlingLogInfo("User Action: Updated user profile image - User: \(currentUserEmail)")
            
            // Update local user data
            DispatchQueue.main.async {
                self?.currentUser?.profile_picture_url = imageUrl
            }
            
            completion(true, nil)
        }
    }
    
    // MARK: - Error Logging System
    
    // Session ID for this app session
    private var sessionId: String = UUID().uuidString
    
    // Device information cache
    private lazy var deviceInfo: (model: String, name: String, iosVersion: String, appVersion: String) = {
        let device = UIDevice.current
        let deviceModel = getDeviceModel()
        let deviceName = device.name
        let iosVersion = device.systemVersion
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        
        return (deviceModel, deviceName, iosVersion, appVersion)
    }()
    
    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            let scalar = UnicodeScalar(UInt8(value))
            return identifier + String(scalar)
        }
        return identifier
    }
    
    func logError(
        message: String,
        type: String = "runtime_error",
        level: String = "error",
        functionName: String = #function,
        fileName: String = #file,
        lineNumber: Int = #line,
        stackTrace: String? = nil,
        additionalContext: [String: String]? = nil
    ) {
        let errorLog = FirestoreErrorLog(
            error_message: message,
            error_type: type,
            log_level: level,
            timestamp: Date(),
            user_email: currentUser?.email,
            user_id: currentUser?.id,
            user_display_name: currentUser?.display_name,
            user_full_name: currentUser?.full_name,
            app_version: deviceInfo.appVersion,
            ios_version: deviceInfo.iosVersion,
            device_model: deviceInfo.model,
            device_name: deviceInfo.name,
            stack_trace: stackTrace,
            function_name: functionName,
            file_name: URL(fileURLWithPath: fileName).lastPathComponent,
            line_number: lineNumber,
            additional_context: additionalContext,
            session_id: sessionId,
            created_date: Date()
        )
        
        // Log to console for debugging
        print("🚨 ERROR LOG: [\(level.uppercased())] [\(type)] \(message)")
        if let context = additionalContext {
            print("   Context: \(context)")
        }
        
        // Store in Firestore
        do {
            _ = try db.collection("error_logs").addDocument(from: errorLog) { error in
                if let error = error {
                    print("❌ Failed to log error to Firestore: \(error)")
                } else {
                    print("✅ Error logged to Firestore successfully")
                }
            }
        } catch {
            print("❌ Failed to encode error log: \(error)")
        }
    }
    
    func logConsoleMessage(
        message: String,
        level: String = "info",
        functionName: String = #function,
        fileName: String = #file,
        lineNumber: Int = #line,
        additionalContext: [String: String]? = nil
    ) {
        // Only log warnings and errors to reduce database usage
        guard level == "warning" || level == "error" || level == "critical" else { return }
        
        logError(
            message: message,
            type: "console_log",
            level: level,
            functionName: functionName,
            fileName: fileName,
            lineNumber: lineNumber,
            additionalContext: additionalContext
        )
    }
    
    func logNetworkError(
        message: String,
        endpoint: String? = nil,
        statusCode: Int? = nil,
        functionName: String = #function,
        fileName: String = #file,
        lineNumber: Int = #line
    ) {
        var fullMessage = message
        if let endpoint = endpoint {
            fullMessage += " (Endpoint: \(endpoint))"
        }
        if let statusCode = statusCode {
            fullMessage += " (Status: \(statusCode))"
        }
        
        SlingLogError(fullMessage, file: fileName, function: functionName, line: lineNumber)
    }
    
    func logFirebaseError(
        message: String,
        firebaseError: Error? = nil,
        functionName: String = #function,
        fileName: String = #file,
        lineNumber: Int = #line
    ) {
        SlingLogError(message, error: firebaseError, file: fileName, function: functionName, line: lineNumber)
    }
    
    func logUserAction(
        action: String,
        details: String? = nil,
        functionName: String = #function,
        fileName: String = #file,
        lineNumber: Int = #line
    ) {
        var message = "User Action: \(action)"
        if let details = details {
            message += " - \(details)"
        }
        
        SlingLogInfo(message, file: fileName, function: functionName, line: lineNumber)
    }

}
