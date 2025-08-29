import Foundation
import FirebaseFirestoreSwift

// MARK: - Message Types

enum MessageType: String, Codable {
    case regular
    case betAnnouncement
    case betResult
    case system
}

struct CommunityMessage: Identifiable, Codable, Equatable {
    let id: String
    let communityId: String
    let senderEmail: String
    let senderName: String
    let text: String
    let timestamp: Date
    let messageType: MessageType
    let betId: String?
    let reactions: [String: Int]
    let readBy: [String] // Add read_by field to track which users have read the message
    
    init(id: String, communityId: String, senderEmail: String, senderName: String, text: String, timestamp: Date, messageType: MessageType = .regular, betId: String? = nil, reactions: [String: Int] = [:], readBy: [String] = []) {
        self.id = id
        self.communityId = communityId
        self.senderEmail = senderEmail
        self.senderName = senderName
        self.text = text
        self.timestamp = timestamp
        self.messageType = messageType
        self.betId = betId
        self.reactions = reactions
        self.readBy = readBy
    }
}

struct FirestoreCommunity: Identifiable, Codable, Equatable {
    @DocumentID var documentId: String?
    var id: String? // Community ID field (like "687f665c9fd93c3795664442")
    var name: String
    var description: String?
    var created_by: String
    var created_date: Date
    var invite_code: String
    var member_count: Int
    var bet_count: Int?
    var total_bets: Int
    var members: [String]? // Array of user emails who are members (optional)
    var admin_email: String?
    var created_by_id: String?
    var is_active: Bool? // Firestore stores this as true/false, but some old docs might have Int
    
    // Computed property for backward compatibility
    var isActive: Bool {
        return is_active ?? true // Default to true if not specified
    }
    var is_private: Bool?
    var updated_date: Date?
    var chat_history: [String: FirestoreCommunityMessage]? // Messages stored as a map with message ID as key
    
    // Custom initializer to handle both Int and Bool for is_active field, and Int/Double for member_count
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        documentId = try container.decodeIfPresent(String.self, forKey: .documentId)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        created_by = try container.decode(String.self, forKey: .created_by)
        created_date = try container.decode(Date.self, forKey: .created_date)
        invite_code = try container.decode(String.self, forKey: .invite_code)
        
        // Handle member_count that might be Int or Double
        if let memberCountInt = try? container.decode(Int.self, forKey: .member_count) {
            member_count = memberCountInt
        } else if let memberCountDouble = try? container.decode(Double.self, forKey: .member_count) {
            member_count = Int(memberCountDouble)
        } else {
            member_count = 0 // Default to 0 if not specified
        }
        
        bet_count = try container.decodeIfPresent(Int.self, forKey: .bet_count)
        total_bets = try container.decode(Int.self, forKey: .total_bets)
        members = try container.decodeIfPresent([String].self, forKey: .members)
        admin_email = try container.decodeIfPresent(String.self, forKey: .admin_email)
        created_by_id = try container.decodeIfPresent(String.self, forKey: .created_by_id)
        is_private = try container.decodeIfPresent(Bool.self, forKey: .is_private)
        updated_date = try container.decodeIfPresent(Date.self, forKey: .updated_date)
        chat_history = try container.decodeIfPresent([String: FirestoreCommunityMessage].self, forKey: .chat_history)
        
        // Handle is_active field that might be Int or Bool
        if let isActiveBool = try? container.decode(Bool.self, forKey: .is_active) {
            is_active = isActiveBool
        } else if let isActiveInt = try? container.decode(Int.self, forKey: .is_active) {
            is_active = isActiveInt == 1
        } else {
            is_active = true // Default to true if not specified
        }
    }
    
    // Custom initializer for fallback community creation
    init(documentId: String?, id: String?, name: String, description: String?, created_by: String, created_date: Date, invite_code: String, member_count: Int, bet_count: Int?, total_bets: Int, members: [String]?, admin_email: String?, created_by_id: String?, is_active: Bool?, is_private: Bool?, updated_date: Date?, chat_history: [String: FirestoreCommunityMessage]?) {
        self.documentId = documentId
        self.id = id
        self.name = name
        self.description = description
        self.created_by = created_by
        self.created_date = created_date
        self.invite_code = invite_code
        self.member_count = member_count
        self.bet_count = bet_count
        self.total_bets = total_bets
        self.members = members
        self.admin_email = admin_email
        self.created_by_id = created_by_id
        self.is_active = is_active
        self.is_private = is_private
        self.updated_date = updated_date
        self.chat_history = chat_history
    }
    
    // Coding keys for custom initializer
    private enum CodingKeys: String, CodingKey {
        case documentId, id, name, description, created_by, created_date, invite_code
        case member_count, bet_count, total_bets, members, admin_email, created_by_id
        case is_active, is_private, updated_date, chat_history
    }
}

struct FirestoreBet: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var bet_type: String
    var community_id: String
    var community_name: String?
    var created_by: String
    var creator_email: String
    var deadline: Date
    var odds: [String: String]
    var outcomes: [String]? // Make optional since some documents might be missing this field
    var options: [String]
    var status: String
    var title: String
    var description: String?
    var winner_option: String?
    var winner: String?
    var image_url: String? // Unsplash image URL stored in Firestore
    var pool_by_option: [String: Int]? // Map of option → pooled amount
    var total_pool: Int? // Total amount in the betting pool
    var total_participants: Int? // Total number of participants
    var created_date: Date
    var updated_date: Date?
    
    // Regular initializer for creating fallback objects
    init(id: String?, bet_type: String, community_id: String, community_name: String?, created_by: String, creator_email: String, deadline: Date, odds: [String: String], outcomes: [String]?, options: [String], status: String, title: String, description: String?, winner_option: String?, winner: String?, image_url: String?, pool_by_option: [String: Int]?, total_pool: Int?, total_participants: Int?, created_date: Date, updated_date: Date?) {
        self.id = id
        self.bet_type = bet_type
        self.community_id = community_id
        self.community_name = community_name
        self.created_by = created_by
        self.creator_email = creator_email
        self.deadline = deadline
        self.odds = odds
        self.outcomes = outcomes ?? [] // Default to empty array if nil
        self.options = options
        self.status = status
        self.title = title
        self.description = description
        self.winner_option = winner_option
        self.winner = winner
        self.image_url = image_url
        self.pool_by_option = pool_by_option
        self.total_pool = total_pool
        self.total_participants = total_participants
        self.created_date = created_date
        self.updated_date = updated_date
    }
    
    // Custom initializer to handle missing fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(String.self, forKey: .id)
        bet_type = try container.decode(String.self, forKey: .bet_type)
        community_id = try container.decode(String.self, forKey: .community_id)
        community_name = try container.decodeIfPresent(String.self, forKey: .community_name)
        created_by = try container.decode(String.self, forKey: .created_by)
        creator_email = try container.decode(String.self, forKey: .creator_email)
        deadline = try container.decode(Date.self, forKey: .deadline)
        odds = try container.decode([String: String].self, forKey: .odds)
        outcomes = try container.decodeIfPresent([String].self, forKey: .outcomes) ?? [] // Default to empty array if missing
        options = try container.decode([String].self, forKey: .options)
        status = try container.decode(String.self, forKey: .status)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        winner_option = try container.decodeIfPresent(String.self, forKey: .winner_option)
        winner = try container.decodeIfPresent(String.self, forKey: .winner)
        image_url = try container.decodeIfPresent(String.self, forKey: .image_url)
        pool_by_option = try container.decodeIfPresent([String: Int].self, forKey: .pool_by_option)
        total_pool = try container.decodeIfPresent(Int.self, forKey: .total_pool)
        total_participants = try container.decodeIfPresent(Int.self, forKey: .total_participants)
        created_date = try container.decode(Date.self, forKey: .created_date)
        updated_date = try container.decodeIfPresent(Date.self, forKey: .updated_date)
    }
    
    // Coding keys
    private enum CodingKeys: String, CodingKey {
        case id, bet_type, community_id, community_name, created_by, creator_email
        case deadline, odds, outcomes, options, status, title, description
        case winner_option, winner, image_url, pool_by_option, total_pool, total_participants, created_date, updated_date
    }
}

struct FirestoreNotification: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var message: String
    var type: String
    var created_by: String
    var created_date: Date
    var icon: String
    var is_read: Bool
    var user_email: String
    var timestamp: Date
    var action_url: String
}

struct FirestoreUser: Identifiable, Codable {
    @DocumentID var documentId: String?
    var blitz_points: Int?
    var display_name: String?
    var email: String
    var first_name: String?
    var full_name: String? // Made optional
    var last_name: String?
    var gender: String? // User's gender (optional)
    var profile_picture_url: String? // URL to user's profile picture (optional)
    var total_bets: Int?
    var total_winnings: Int?
    var id: String? // 24-character alphanumeric user ID
    var uid: String? // Firebase Auth UID
    var sling_points: Int? // Alternative points system

    // Computed property to handle missing full_name
    var displayName: String {
        if let fullName = full_name, !fullName.isEmpty {
            return fullName
        } else if let firstName = first_name, let lastName = last_name {
            return "\(firstName) \(lastName)"
        } else if let displayName = display_name, !displayName.isEmpty {
            return displayName
        } else {
            return email
        }
    }
    
    // Computed properties for compatibility with views
    var firstName: String? {
        return first_name
    }
    
    var lastName: String? {
        return last_name
    }
}

struct FirestoreCommunityMember: Identifiable, Codable {
    @DocumentID var id: String?
    var user_email: String
    var community_id: String
    var is_admin: Bool // Firestore now stores this as true/false
    var joined_date: Date
    var is_active: Bool // Firestore now stores this as true/false
    var created_by: String?
    var created_by_id: String?
    var created_date: Date?
    var updated_date: Date?
    
    // Computed properties for backward compatibility (now just return the Bool values directly)
    var isAdmin: Bool {
        return is_admin
    }
    
    var isActive: Bool {
        return is_active
    }
}

// MARK: - Point Balance Models

struct FirestorePointBalance: Identifiable, Codable {
    @DocumentID var id: String?
    var user_email: String
    var community_id: String
    var balance: Double
    var points: Int
    var description: String
    var created_date: Date
    var updated_date: Date
    var timestamp: Date
}



// MARK: - User Bet Model

struct UserBet: Identifiable, Codable {
    var id: String
    var betId: String
    var chosenOption: String
    var stakeAmount: Double
    var createdDate: Date
}

// MARK: - Bet Participant Model

struct BetParticipant: Identifiable, Codable {
    @DocumentID var documentId: String?
    var id: String
    var bet_id: String
    var community_id: String // Add community_id field for filtering
    var user_email: String
    var chosen_option: String
    var stake_amount: Int
    var created_by: String
    var created_by_id: String
    var created_date: Date
    var updated_date: Date
    var is_winner: Bool?
    var final_payout: Int?
}

// MARK: - Community Message Model

struct FirestoreCommunityMessage: Identifiable, Codable, Equatable {
    var id: String
    var community_id: String
    var sender_id: String
    var sender_name: String
    var sender_email: String
    var message: String
    var time_stamp: Date
    var type: String
    var read_by: [String]
    var created_by: String
    var created_by_id: String
    var created_date: Date
    var updated_date: Date
    var bet_id: String? // Add this for bet announcement messages
    
    // Convert to the existing CommunityMessage model used by the UI
    func toCommunityMessage() -> CommunityMessage {
        // Convert the type string to MessageType enum
        let messageType: MessageType
        switch type {
        case "betAnnouncement":
            messageType = .betAnnouncement
        case "betResult":
            messageType = .betResult
        case "system":
            messageType = .system
        default:
            messageType = .regular
        }
        
        return CommunityMessage(
            id: id,
            communityId: community_id,
            senderEmail: sender_email,
            senderName: sender_name,
            text: message,
            timestamp: time_stamp,
            messageType: messageType,
            betId: bet_id,
            reactions: [:], // Initialize with empty reactions
            readBy: read_by
        )
    }
}
