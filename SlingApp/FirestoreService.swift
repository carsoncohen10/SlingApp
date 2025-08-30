import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift
import FirebaseAuth

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
                                    print("❌ User document not found by UID either")
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
                    print("❌ User document not found for ID: \(userId)")
                    let notFoundError = NSError(domain: "FirestoreService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
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
                display_name: displayName,
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
        let payload: [String: Any] = [
            "id": msgId,
            "community_id": communityId,
            "sender_email": currentUser?.email ?? "app@slingapp.com",
            "sender_name": currentUser?.display_name ?? "Sling",
            "message": "New market: \(betTitle)",
            "time_stamp": Date(),
            "type": "announcement",
            "bet_id": betId
        ]
        db.collection("CommunityMessage").document(msgId).setData(payload) { error in
            completion(error == nil, error?.localizedDescription)
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
    
    // MARK: - Community Management
    
    func fetchCommunities() {
        db.collection("community").getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching communities: \(error.localizedDescription)")
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
                                        chat_history: nil
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
        print("🔍 fetchBets() called for user: \(currentUser?.email ?? "unknown")")
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
                            
                            // Sort bets by creation date (most recent first) to show newest bets at the top
                            let sortedBets = fetchedBets.sorted { $0.created_date > $1.created_date }
                            
                            print("🔍 fetchBets: Successfully processed \(sortedBets.count) bets")
                            if !sortedBets.isEmpty {
                                print("🔍 fetchBets: First bet title: \(sortedBets.first?.title ?? "unknown")")
                                print("🔍 fetchBets: Last bet title: \(sortedBets.last?.title ?? "unknown")")
                            }
                            
                            self?.bets = sortedBets
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
                    
                    self?.userBetParticipations = participations
                    print("✅ Fetched \(participations.count) bet participations")
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
                            let lastMessage = CommunityMessage(
                                id: lastMessageData.id,
                                communityId: communityId,
                                senderEmail: lastMessageData.sender_email,
                                senderName: lastMessageData.sender_name,
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
              let userName = currentUser?.display_name ?? currentUser?.full_name else {
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
                "sender_name": userName,
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
                        senderName: userName,
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
        guard let userEmail = currentUser?.email else { return }
        
        db.collection("Notification")
            .whereField("user_email", isEqualTo: userEmail)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Error fetching notifications: \(error.localizedDescription)")
                        return
                    }
                    
                    let notifications = snapshot?.documents.compactMap { document in
                        try? document.data(as: FirestoreNotification.self)
                    } ?? []
                    
                    // Sort by created_date in descending order (most recent first)
                    self?.notifications = notifications.sorted { $0.created_date > $1.created_date }
                }
            }
    }
    
    func fetchTransactions(communityId: String, userEmail: String, completion: @escaping ([BetParticipant]) -> Void) {
        db.collection("UserBet")
            .whereField("community_id", isEqualTo: communityId)
            .whereField("user_email", isEqualTo: userEmail)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching transactions: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                let transactions = snapshot?.documents.compactMap { document in
                    try? document.data(as: BetParticipant.self)
                } ?? []
                
                // Sort by created_date in descending order (most recent first)
                let sortedTransactions = transactions.sorted { $0.created_date > $1.created_date }
                completion(sortedTransactions)
            }
    }
    
    // MARK: - Bet Management
    
    func fetchBet(by betId: String, completion: @escaping (FirestoreBet?) -> Void) {
        db.collection("Bet").document(betId).getDocument { document, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error fetching bet: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                
                guard let document = document, document.exists else {
                    print("❌ Bet not found with ID: \(betId)")
                    completion(nil)
                    return
                }
                
                do {
                    let bet = try document.data(as: FirestoreBet.self)
                    completion(bet)
                } catch {
                    print("❌ Error parsing bet: \(error)")
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
            .getDocuments { snapshot, error in
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
            .getDocuments { snapshot, error in
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
            .getDocuments { snapshot, error in
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
    
    func fetchBetStatus(betId: String, completion: @escaping (String?) -> Void) {
        db.collection("Bet").document(betId).getDocument { document, error in
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
            final_payout: nil
        )
        
        // First get the bet to get community_id
        db.collection("Bet").document(betId).getDocument { [weak self] document, error in
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
            
            // Update participant with community_id
            var updatedParticipant = participantData
            updatedParticipant.community_id = communityId
            
            // Use a custom document ID to ensure consistency
            let documentId = "\(betId)_\(userEmail)"
            
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
                        
                        // Refresh user data and participations
                        DispatchQueue.main.async {
                            self?.refreshCurrentUser()
                            self?.fetchUserBetParticipations()
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
        db.collection("BetParticipant").whereField("bet_id", isEqualTo: betId).getDocuments { [weak self] snapshot, error in
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
            
            // Update bet status first
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
        
        // Get bet details to calculate odds
        db.collection("Bet").document(betId).getDocument { [weak self] document, error in
            if let error = error {
                print("❌ processBetPayouts: Error fetching bet details: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data(),
                  let odds = data["odds"] as? [String: String] else {
                print("❌ processBetPayouts: Bet not found or missing odds")
                completion(false)
                return
            }
            
            print("✅ processBetPayouts: Bet odds loaded: \(odds)")
            
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
                let payout = self?.calculatePayout(amount: Double(stakeAmount), odds: odds[chosenOption] ?? "-110") ?? Double(stakeAmount)
                
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
                    
                    // Process payout for user
                    if isWinner {
                        // Winner gets their stake back + winnings
                        let pointsToAdd = Int(payout)
                        self?.updateUserBlitzPoints(userId: userEmail, pointsToAdd: pointsToAdd) { success, error in
                            if success {
                                print("✅ processBetPayouts: \(userEmail) received \(pointsToAdd) points (stake + winnings)")
                            } else {
                                print("❌ processBetPayouts: Error adding points to \(userEmail): \(error ?? "Unknown error")")
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
        db.collection("Bet").document(betId).setData(updatedBetData) { error in
            if let error = error {
                print("❌ Error creating bet: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
            } else {
                print("✅ Bet created successfully with ID: \(betId)")
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
        guard let userEmail = currentUser?.email,
              let userId = currentUser?.id else {
            completion(false, "User not authenticated")
            return
        }
        
        // Validate invite code length
        guard inviteCode.count == 6 else {
            completion(false, "Invite code must be exactly 6 characters")
            return
        }
        
        // Find community by invite code
        db.collection("community")
            .whereField("invite_code", isEqualTo: inviteCode)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                
                guard let document = snapshot?.documents.first else {
                    completion(false, "Invalid invite code")
                    return
                }
                
                // Extract the actual community ID from the document data, not the document ID
                let communityData = document.data()
                guard let communityId = communityData["id"] as? String else {
                    completion(false, "Community document missing ID field")
                    return
                }
                
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
        db.collection("CommunityMember").document(memberDocumentId).setData(memberData) { error in
            if let error = error {
                print("❌ Error creating community member record: \(error.localizedDescription)")
                // Still complete with success since community was created
                completion(true, communityId)
            } else {
                print("✅ Successfully created community and added creator as member")
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
        db.collection("Notification").document(notificationId).updateData(["is_read": true]) { error in
            if let error = error {
                print("❌ Error marking notification as read: \(error.localizedDescription)")
                completion(false)
            } else {
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
        
        // First, get all communities the user is a member of
        let userCommunities = self.userCommunities
        if userCommunities.isEmpty {
            print("📋 No communities found for user")
            completion([])
            return
        }
        
        var allBalances: [OutstandingBalance] = []
        let group = DispatchGroup()
        
        for community in userCommunities {
            guard let communityId = community.id else { continue }
            
            group.enter()
            calculateOutstandingBalancesForCommunity(communityId: communityId, userEmail: currentUserEmail) { balances in
                allBalances.append(contentsOf: balances)
                group.leave()
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
    
    private func getUserDetails(email: String, completion: @escaping (String, String) -> Void) {
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
    
    private func getBetDetailsForParticipations(_ participations: [BetParticipant], completion: @escaping ([String: String]) -> Void) {
        let uniqueBetIds = Set(participations.map { $0.bet_id })
        var betDetails: [String: String] = [:]
        let group = DispatchGroup()
        
        for betId in uniqueBetIds {
            group.enter()
            db.collection("Bet").document(betId).getDocument { document, error in
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
        db.collection("community").document(communityId).getDocument { [weak self] snapshot, error in
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

}
