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
    var description: String
    var created_by: String
    var created_date: Date
    var invite_code: String
    var member_count: Int
    var bet_count: Int
    var total_bets: Int
    var members: [String]? // Array of user emails who are members (optional)
    var admin_email: String?
    var created_by_id: String?
    var is_active: Bool // Firestore stores this as true/false
    
    // Computed property for backward compatibility
    var isActive: Bool {
        return is_active
    }
    var is_private: Bool
    var updated_date: Date?
    var chat_history: [String: FirestoreCommunityMessage]? // Messages stored as a map with message ID as key
}

struct FirestoreBet: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var bet_type: String
    var community_id: String
    var community_name: String
    var created_by: String
    var creator_email: String
    var deadline: Date
    var odds: [String: String]
    var outcomes: [String]
    var options: [String]
    var status: String
    var title: String
    var description: String
    var winner_option: String?
    var winner: String?
    var image_url: String? // Unsplash image URL stored in Firestore
    var created_date: Date
    var updated_date: Date?
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
    var is_admin: Int // Firestore stores this as 1/0
    var joined_date: Date
    var is_active: Int // Firestore stores this as 1/0
    var created_by: String?
    var created_by_id: String?
    var created_date: Date?
    var updated_date: Date?
    
    // Computed properties to convert Int to Bool
    var isAdmin: Bool {
        return is_admin == 1
    }
    
    var isActive: Bool {
        return is_active == 1
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
