import SwiftUI
import UIKit
import FirebaseFirestore
import Network
import PhotosUI

// MARK: - Custom Colors Extension
extension Color {
    static let slingBlue = Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0))
    static let slingPurple = Color(uiColor: UIColor(red: 0x4E/255, green: 0x46/255, blue: 0xE5/255, alpha: 1.0))
    static let slingGradient: LinearGradient = LinearGradient(
        colors: [Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)), 
                 Color(uiColor: UIColor(red: 0x4E/255, green: 0x46/255, blue: 0xEB/255, alpha: 1.0))],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let slingLightBlue = Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)).opacity(0.1)
    static let slingLightPurple = Color(uiColor: UIColor(red: 0x4E/255, green: 0x46/255, blue: 0xE5/255, alpha: 1.0)).opacity(0.1)
    static let slingAccent = Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)).opacity(0.8)
}

// MARK: - View Extensions
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Unsplash Image Service
class UnsplashImageService: ObservableObject {
    private let accessKey = "9cI_wggikqQS5PKKH2wTc-xouLMPsJmL-xg0Ai4X7Zs"
    private let baseURL = "https://api.unsplash.com/search/photos"
    
    // Debug properties
    @Published var lastError: String?
    @Published var lastRequestURL: String?
    @Published var lastResponseStatus: Int?
    @Published var requestCount: Int = 0
    @Published var isNetworkAvailable: Bool = true
    
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    init() {
        startNetworkMonitoring()
    }
    
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
                if path.status != .satisfied {
                    self?.lastError = "❌ No network connection available"
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    func getImageForBet(title: String, completion: @escaping (String?) -> Void) {
        // Check network connectivity first
        guard isNetworkAvailable else {
            let errorMessage = "❌ No network connection - check your internet"
            print(errorMessage)
            DispatchQueue.main.async {
                self.lastError = errorMessage
                completion(nil)
            }
            return
        }
        
        let enrichedQuery = enrichQuery(from: title)
        let encodedQuery = enrichedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? enrichedQuery
        
        guard let url = URL(string: "\(baseURL)?query=\(encodedQuery)&per_page=30&orientation=landscape") else {
            let errorMessage = "❌ Invalid URL created for query: \(enrichedQuery)"
            print(errorMessage)
            DispatchQueue.main.async {
                self.lastError = errorMessage
            completion(nil)
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10.0 // Add timeout
        
        DispatchQueue.main.async {
            self.requestCount += 1
            self.lastRequestURL = url.absoluteString
            self.lastError = nil
        }
        


        
        URLSession.shared.dataTask(with: request) { data, response, error in
            // Log response details
            if let httpResponse = response as? HTTPURLResponse {
                print("📊 HTTP Status: \(httpResponse.statusCode)")
                DispatchQueue.main.async {
                    self.lastResponseStatus = httpResponse.statusCode
                }
                
                if httpResponse.statusCode != 200 {
                    let errorMessage = "❌ HTTP Error \(httpResponse.statusCode): \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
                    print(errorMessage)
                    
                    // Check for rate limiting
                    if httpResponse.statusCode == 403 {
                        print("🚫 Rate limit hit or invalid API key")
                    }
                    
                    DispatchQueue.main.async {
                        self.lastError = errorMessage
                    completion(nil)
                }
                return
                }
            }
            
            if let error = error {
                let errorMessage = "❌ Network Error: \(error.localizedDescription)"
                print(errorMessage)
                DispatchQueue.main.async {
                    self.lastError = errorMessage
                    completion(nil)
                }
                return
            }
            
            guard let data = data else {
                let errorMessage = "❌ No data received from Unsplash API"
                print(errorMessage)
                DispatchQueue.main.async {
                    self.lastError = errorMessage
                    completion(nil)
                }
                return
            }
            
            print("📦 Received \(data.count) bytes of data")
            
            do {
                let result = try JSONDecoder().decode(UnsplashResponse.self, from: data)
                
                print("✅ Successfully decoded Unsplash response with \(result.results.count) images")
                
                // Debug: Print first few image details
                if result.results.count > 0 {
                    let firstImage = result.results[0]
                    print("🔍 First image - ID: \(firstImage.id), Description: \(firstImage.description ?? "nil"), Alt: \(firstImage.alt_description ?? "nil")")
                }
                
                if result.results.isEmpty {
                    let errorMessage = "⚠️ No images found for query: \(enrichedQuery)"
                    print(errorMessage)
                    DispatchQueue.main.async {
                        self.lastError = errorMessage
                        completion(nil)
                    }
                    return
                }
                
                let bestImage = self.selectBestImage(from: result.results, for: title)
                if let imageURL = bestImage {
                    print("✅ Selected image URL: \(imageURL)")
                } else {
                    print("⚠️ No suitable image selected from results")
                }
                
                DispatchQueue.main.async {
                    self.lastError = bestImage == nil ? "No suitable image found" : nil
                    completion(bestImage)
                }
            } catch {
                let errorMessage = "❌ JSON Decode Error: \(error.localizedDescription)"
                print(errorMessage)
                
                // Print raw response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 Raw response: \(responseString.prefix(500))...")
                }
                
                // Print the specific decoding error details
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        print("🔑 Missing key: \(key.stringValue) at path: \(context.codingPath)")
                    case .typeMismatch(let type, let context):
                        print("🔄 Type mismatch: expected \(type) at path: \(context.codingPath)")
                    case .valueNotFound(let type, let context):
                        print("💨 Value not found: expected \(type) at path: \(context.codingPath)")
                    case .dataCorrupted(let context):
                        print("💥 Data corrupted at path: \(context.codingPath)")
                    @unknown default:
                        print("❓ Unknown decoding error")
                    }
                }
                
                DispatchQueue.main.async {
                    self.lastError = errorMessage
                    completion(nil)
                }
            }
        }.resume()
    }
    
    private func enrichQuery(from title: String) -> String {
        let lowercasedTitle = title.lowercased()
        var enrichedKeywords: [String] = []
        
        // Add original title words
        enrichedKeywords.append(contentsOf: title.components(separatedBy: " ").filter { $0.count > 2 })
        
        // Add contextual keywords based on themes
        if lowercasedTitle.contains("family") || lowercasedTitle.contains("dad") || lowercasedTitle.contains("mom") || lowercasedTitle.contains("thanksgiving") || lowercasedTitle.contains("dinner") {
            enrichedKeywords.append(contentsOf: ["family", "dinner", "holiday", "table", "celebration"])
        }
        
        if lowercasedTitle.contains("sport") || lowercasedTitle.contains("game") || lowercasedTitle.contains("team") || lowercasedTitle.contains("win") || lowercasedTitle.contains("score") {
            enrichedKeywords.append(contentsOf: ["sports", "game", "competition", "athletics"])
        }
        
        if lowercasedTitle.contains("weather") || lowercasedTitle.contains("rain") || lowercasedTitle.contains("sun") || lowercasedTitle.contains("snow") {
            enrichedKeywords.append(contentsOf: ["weather", "nature", "sky", "outdoors"])
        }
        
        if lowercasedTitle.contains("money") || lowercasedTitle.contains("price") || lowercasedTitle.contains("cost") || lowercasedTitle.contains("dollar") {
            enrichedKeywords.append(contentsOf: ["money", "finance", "business", "economics"])
        }
        
        if lowercasedTitle.contains("food") || lowercasedTitle.contains("eat") || lowercasedTitle.contains("restaurant") || lowercasedTitle.contains("cook") {
            enrichedKeywords.append(contentsOf: ["food", "cooking", "restaurant", "cuisine"])
        }
        
        if lowercasedTitle.contains("travel") || lowercasedTitle.contains("trip") || lowercasedTitle.contains("vacation") || lowercasedTitle.contains("flight") {
            enrichedKeywords.append(contentsOf: ["travel", "vacation", "adventure", "landscape"])
        }
        
        if lowercasedTitle.contains("movie") || lowercasedTitle.contains("film") || lowercasedTitle.contains("actor") || lowercasedTitle.contains("show") {
            enrichedKeywords.append(contentsOf: ["movie", "cinema", "entertainment", "film"])
        }
        
        if lowercasedTitle.contains("music") || lowercasedTitle.contains("song") || lowercasedTitle.contains("concert") || lowercasedTitle.contains("album") {
            enrichedKeywords.append(contentsOf: ["music", "concert", "performance", "art"])
        }
        
        if lowercasedTitle.contains("work") || lowercasedTitle.contains("job") || lowercasedTitle.contains("office") || lowercasedTitle.contains("meeting") {
            enrichedKeywords.append(contentsOf: ["work", "office", "business", "professional"])
        }
        
        if lowercasedTitle.contains("school") || lowercasedTitle.contains("study") || lowercasedTitle.contains("exam") || lowercasedTitle.contains("grade") {
            enrichedKeywords.append(contentsOf: ["education", "school", "study", "learning"])
        }
        
        // Remove duplicates and join
        let uniqueKeywords = Array(Set(enrichedKeywords))
        return uniqueKeywords.joined(separator: " ")
    }
    
    private func selectBestImage(from images: [UnsplashImage], for title: String) -> String? {
        guard !images.isEmpty else { return nil }
        
        let lowercasedTitle = title.lowercased()
        let titleWords = Set(lowercasedTitle.components(separatedBy: " ").filter { $0.count > 2 })
        
        var bestImage: UnsplashImage?
        var bestScore: Double = 0
        
        for image in images {
            var score: Double = 0
            
            // Description match
            let description = (image.description ?? "").lowercased()
            let altDescription = (image.alt_description ?? "").lowercased()
            
            for word in titleWords {
                if description.contains(word) { score += 2.0 }
                if altDescription.contains(word) { score += 1.5 }
            }
            
            // Tag match
            if let tags = image.tags {
                for tag in tags {
                    let tagName = tag.title.lowercased()
                    for word in titleWords {
                        if tagName.contains(word) { score += 1.0 }
                    }
                }
            }
            
            // Social bias for people-related content
            if lowercasedTitle.contains("family") || lowercasedTitle.contains("dad") || lowercasedTitle.contains("mom") || lowercasedTitle.contains("person") || lowercasedTitle.contains("people") {
                if description.contains("person") || description.contains("people") || description.contains("family") {
                    score += 0.5
                }
            }
            
            // Likes tiebreaker
            if let likes = image.likes {
                score += Double(likes) * 0.001
            }
            
            if score > bestScore {
                bestScore = score
                bestImage = image
            }
        }
        
        return bestImage?.urls.regular
    }
}

// MARK: - Unsplash Response Models
struct UnsplashResponse: Codable {
    let total: Int
    let total_pages: Int
    let results: [UnsplashImage]
}

struct UnsplashImage: Codable {
    let id: String
    let slug: String?
    let alternative_slugs: [String: String]?
    let created_at: String?
    let updated_at: String?
    let promoted_at: String?
    let width: Int?
    let height: Int?
    let color: String?
    let blur_hash: String?
    let description: String?
    let alt_description: String?
    let likes: Int?
    let urls: UnsplashURLs
    let tags: [UnsplashTag]?
    let user: UnsplashUser
}

struct UnsplashURLs: Codable {
    let regular: String
}

struct UnsplashTag: Codable {
    let title: String
}

struct UnsplashUser: Codable {
    let name: String
}

// MARK: - Bet Image View
struct BetImageView: View {
    let title: String
    let imageURL: String? // Direct image URL from Firestore
    let size: CGFloat
    @State private var hasError = false
    
    init(title: String, imageURL: String? = nil, size: CGFloat = 60) {
        self.title = title
        self.imageURL = imageURL
        self.size = size
    }
    
    var body: some View {
        Group {
            if let imageURL = imageURL, !imageURL.isEmpty {
                AsyncImage(url: URL(string: imageURL)) { phase in
                    switch phase {
                    case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipped()
                        .cornerRadius(12)
                    case .failure(_):
                        // Handle AsyncImage loading failure
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.1))
                            .frame(width: size, height: size)
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.red)
                                        .font(.system(size: size * 0.25))
                                    if size > 40 {
                                        Text("Load Failed")
                                            .font(.system(size: size * 0.12))
                                            .foregroundColor(.red)
                                    }
                                }
                            )
                    case .empty:
                        // Still loading the image
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: size, height: size)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                // No image URL provided - show placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .font(.system(size: size * 0.33))
                    )
            }
        }
        .onAppear {
            if imageURL != nil {
                // Image URL is available
            } else {
                // No image URL available
            }
        }
    }
}

// MARK: - Image Debug Console
struct ImageDebugConsole: View {
    @ObservedObject var imageService: UnsplashImageService
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                // Summary Stats
                VStack(alignment: .leading, spacing: 8) {
                    Text("Debug Summary")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Total Requests")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("\(imageService.requestCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading) {
                            Text("Network")
                                .font(.caption)
                                .foregroundColor(.gray)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(imageService.isNetworkAvailable ? .green : .red)
                                    .frame(width: 8, height: 8)
                                Text(imageService.isNetworkAvailable ? "Online" : "Offline")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(imageService.isNetworkAvailable ? .green : .red)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading) {
                            Text("Last Status")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("\(imageService.lastResponseStatus ?? 0)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(statusColor(imageService.lastResponseStatus))
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Last Request Details
                if let lastURL = imageService.lastRequestURL {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last Request")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        ScrollView {
                            Text(lastURL)
                                .font(.caption)
                                .foregroundColor(Color.slingBlue)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxHeight: 60)
                        .padding()
                        .background(Color.slingLightBlue)
                        .cornerRadius(8)
                    }
                }
                
                // Error Details
                if let lastError = imageService.lastError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last Error")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        
                        ScrollView {
                            Text(lastError)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxHeight: 80)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Status")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                        
                        Text("No errors detected")
                            .font(.subheadline)
                            .foregroundColor(.green)
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                
                // Troubleshooting Tips
                VStack(alignment: .leading, spacing: 8) {
                    Text("Troubleshooting")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Check internet connection")
                        Text("• Verify Unsplash API key is valid")
                        Text("• Look for HTTP status codes (403 = rate limit)")
                        Text("• Tap orange error icons to retry")
                    }
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding()
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Image Debug")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                isPresented = false
            })
        }
    }
    
    private func statusColor(_ status: Int?) -> Color {
        guard let status = status else { return .gray }
        
        switch status {
        case 200...299:
            return .green
        case 400...499:
            return .orange
        case 500...599:
            return .red
        default:
            return .gray
        }
    }
}



// MARK: - Welcome Card

struct WelcomeCard: View {
    @ObservedObject var firestoreService: FirestoreService
    @State private var showingJoinCommunityModal = false
    @State private var showingCreateCommunityModal = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Welcome Card with Blue Background
            VStack(spacing: 16) {
                Text("Welcome to Sling!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Get started by joining or creating your first community!")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            
            // Action Buttons
            VStack(spacing: 12) {
                Button(action: {
                        showingCreateCommunityModal = true
                }) {
                    HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.subheadline)
                            Text("Create Community")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white, lineWidth: 1)
                        )
                    }
                    
                    Button(action: {
                        showingJoinCommunityModal = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2")
                                .font(.subheadline)
                        Text("Join Community")
                                .font(.subheadline)
                                .fontWeight(.medium)
                    }
                    .foregroundColor(.blue)
                        .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                        .background(Color.white)
                    .cornerRadius(10)
                    }
                }
            }
            .padding(24)
            .background(AnyShapeStyle(Color.slingGradient))
            .cornerRadius(16)
            
            // Join Community Prompt
            VStack(spacing: 12) {
                Image(systemName: "person.2")
                    .font(.system(size: 48))
                    .foregroundColor(.gray.opacity(0.6))
                
                Text("Join a Community to Start")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                
                Text("You need to be part of a community to see or create prediction markets.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                
                Button(action: {
                    showingJoinCommunityModal = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.subheadline)
                        Text("Explore Communities")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showingJoinCommunityModal) {
            JoinCommunityPage(firestoreService: firestoreService)
        }
        .sheet(isPresented: $showingCreateCommunityModal) {
            CreateCommunityPage(firestoreService: firestoreService)
        }
    }
}

// MARK: - Empty Bets Views

struct EmptyBetsView: View {
    let firestoreService: FirestoreService
    @State private var showingCreateBetModal = false
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("No pending bets found")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
            
            Text("You don't have any pending bets right now.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Button(action: {
                showingCreateBetModal = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.subheadline)
                    Text("Browse Markets")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.slingGradient)
                .cornerRadius(10)
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showingCreateBetModal) {
            CreateBetView(firestoreService: firestoreService, preSelectedCommunity: nil)
        }
    }
}

struct EmptyActiveBetsView: View {
    let firestoreService: FirestoreService
    @State private var showingCreateBetModal = false
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("No pending bets found")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
            
            Text("You don't have any pending bets right now.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Button(action: {
                showingCreateBetModal = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.subheadline)
                    Text("Browse Markets")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.slingGradient)
                .cornerRadius(10)
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showingCreateBetModal) {
            CreateBetView(firestoreService: firestoreService, preSelectedCommunity: nil)
        }
    }
}

struct EmptyPastBetsView: View {
    let firestoreService: FirestoreService
    @State private var showingCreateBetModal = false
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("No past bets found")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
            
            Text("You haven't completed any bets yet.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Button(action: {
                showingCreateBetModal = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.subheadline)
                    Text("Browse Markets")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.slingGradient)
                .cornerRadius(10)
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showingCreateBetModal) {
            CreateBetView(firestoreService: firestoreService, preSelectedCommunity: nil)
        }
    }
}

struct EmptyCommunitiesView: View {
    let firestoreService: FirestoreService
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "person.2")
                    .font(.system(size: 48))
                    .foregroundColor(.gray.opacity(0.6))
                
                Text("No communities yet")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                
                Text("Create your first community or join an existing one to get started.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct EmptyPointsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("Join a community to track points owed")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
    }
}

// MARK: - Enhanced Bet Card View

struct EnhancedBetCardView: View {
    let bet: FirestoreBet
    let currentUserEmail: String?
    let firestoreService: FirestoreService
    let isCommunityNameClickable: Bool // Control whether community name is clickable
    @State private var showingJoinBet = false
    @State private var hasRemindedCreator = false
    @State private var showingBettingInterface = false
    @State private var selectedBettingOption = ""
    @State private var userFullNames: [String: String] = [:]
    
    private var communityName: String {
        if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
            return community.name
        }
        return "Community"
    }
    
    var body: some View {
        Button(action: {
            if bet.status.lowercased() == "open" {
                showingJoinBet = true
            }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with image and title
                HStack(alignment: .top, spacing: 12) {
                    BetImageView(title: bet.title, imageURL: bet.image_url, size: 48)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bet.title)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.caption)
                                .foregroundColor(isCommunityNameClickable ? .slingBlue : .gray)
                            
                            // Community name - conditionally clickable
                            if isCommunityNameClickable {
                                Button(action: {
                                    // Navigate to community details
                                    // This would need to be handled by the parent view
                                }) {
                                    Text(communityName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.slingBlue)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(communityName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                .foregroundColor(.gray)
                            }
                            
                            Text("• by \(currentUserEmail == bet.creator_email ? "You" : getUserFullName(from: bet.creator_email))")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    StatusBadge(status: bet.status)
                }
                
                // Options with Outcome Pills - clickable to place bets
                VStack(spacing: 8) {
                    ForEach(bet.options, id: \.self) { option in
                        Button(action: {
                            selectedBettingOption = option
                            showingBettingInterface = true
                        }) {
                            HStack {
                                Text(option)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                                
                                Spacer()
                                
                                Text(bet.odds[option] ?? "-110")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.slingLightBlue)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Footer with Deadline and Action
                HStack {
                    Text("Deadline: \(formatDate(bet.deadline))")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    // Outcome Pill
                    OutcomePill(bet: bet, currentUserEmail: currentUserEmail)
                }
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .sheet(isPresented: $showingJoinBet) {
            JoinBetView(
                bet: bet, 
                firestoreService: firestoreService,
                onCommunityTap: {
                    // Navigate to community details
                    // This will be handled by the parent view
                }
            )
        }
        .sheet(isPresented: $showingBettingInterface) {
            BettingInterfaceView(
                bet: bet,
                selectedOption: selectedBettingOption.isEmpty ? bet.options.first ?? "Yes" : selectedBettingOption,
                firestoreService: firestoreService
            )
        }
    }
    
    private func getFirstNameFromEmail(_ email: String) -> String {
        // Extract first name from email (everything before @)
        let components = email.components(separatedBy: "@")
        if let username = components.first {
            // Capitalize first letter and return
            return username.prefix(1).uppercased() + username.dropFirst()
        }
        return email
    }
    
    private func getDisplayNameFromEmail(_ email: String) -> String {
        // Extract first name from email (everything before @)
        let components = email.components(separatedBy: "@")
        if let username = components.first {
            // Capitalize first letter and return
            return username.prefix(1).uppercased() + username.dropFirst()
        }
        return email
    }
    
    // Function to get user's full name, with caching
    private func getUserFullName(from email: String) -> String {
        // Check cache first
        if let cachedName = userFullNames[email] {
            return cachedName
        }
        
        // For current user, use local data
        if let user = firestoreService.currentUser, user.email == email {
            let fullName = "\(user.first_name ?? "") \(user.last_name ?? "")".trimmingCharacters(in: .whitespaces)
            userFullNames[email] = fullName
            return fullName
        }
        
        // For other users, fetch from Firestore and cache
        firestoreService.getUserDetails(email: email) { fullName, _ in
            DispatchQueue.main.async {
                self.userFullNames[email] = fullName
            }
        }
        
        // Return first name as fallback while fetching
        return email.components(separatedBy: "@").first ?? email
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: String
    
    var statusColor: Color {
        switch status.lowercased() {
        case "open":
            return .orange
        case "matched":
            return .blue
        case "settled":
            return .green
        case "voided":
            return .red
        default:
            return .gray
        }
    }
    
    var statusText: String {
        switch status.lowercased() {
        case "open":
            return "" // Remove "Pending" text
        case "matched":
            return "Matched"
        case "settled":
            return "Settled"
        case "voided":
            return "Voided"
        default:
            return status.capitalized
        }
    }
    
    var body: some View {
        if !statusText.isEmpty {
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor)
                .cornerRadius(8)
        }
    }
}

// MARK: - Outcome Pill

struct OutcomePill: View {
    let bet: FirestoreBet
    let currentUserEmail: String?
    
    var body: some View {
        HStack(spacing: 4) {
            if bet.status.lowercased() == "matched" {
                Text("Matched")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(8)
            }
            // Removed "Unmatched" pill for open bets
        }
    }
}

// MARK: - My Bets View

struct MyBetsView: View {
    @ObservedObject var firestoreService: FirestoreService
    @Binding var selectedTab: Int
    @State private var selectedPastBetFilter = "All"
    @State private var showingCreateBetModal = false
    
    // Computed properties for statistics
    private var activeBets: [FirestoreBet] {
        let currentUserEmail = firestoreService.currentUser?.email
        return firestoreService.bets.filter { bet in
            // Show bets where user has placed a wager OR created the bet, and the bet is still active
            let hasWager = firestoreService.userBetParticipations.contains { participation in
                participation.bet_id == bet.id && participation.user_email == currentUserEmail
            }
            let isCreator = bet.creator_email == currentUserEmail
            return (hasWager || isCreator) && (bet.status == "open" || bet.status == "pending")
        }
    }
    

    
    private var pastBets: [FirestoreBet] {
        let currentUserEmail = firestoreService.currentUser?.email
        let settledBets = firestoreService.bets.filter { bet in
            bet.status == "settled" || bet.status == "cancelled"
        }
        
        return settledBets.filter { bet in
            // Show if user created it
            let isCreator = bet.creator_email == currentUserEmail
            if isCreator { return true }
            
            // Show if user has placed a wager on this bet
            let hasWager = firestoreService.userBetParticipations.contains { participation in
                participation.bet_id == bet.id && participation.user_email == currentUserEmail
            }
            
            return hasWager
        }
    }
    
    private var wonBets: [FirestoreBet] {
        let currentUserEmail = firestoreService.currentUser?.email
        guard let userEmail = currentUserEmail else { return [] }
        
        return firestoreService.bets.filter { bet in
            if bet.status == "settled", let winnerOption = bet.winner_option {
                // Check if user participated and won
                return firestoreService.userBetParticipations.contains { participation in
                    participation.bet_id == bet.id && 
                    participation.user_email == userEmail && 
                    participation.chosen_option == winnerOption
                }
            }
            return false
        }
    }
    
    private var totalBets: Int {
        activeBets.count + pastBets.count
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Markets Header
                HStack {
                    Text("Markets")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
                
                // Dynamic Header Section - Shows "Active Bets" or "Markets to Bet On"
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(activeBets.isEmpty ? "Markets to Bet On" : "Active Bets")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    
                    if activeBets.isEmpty {
                        // No active bets - show Markets to Bet On section
                        let availableBets = getAvailableBetsToBetOn()
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                // Show available bets from user's communities
                                ForEach(availableBets, id: \.id) { bet in
                                    AvailableBetCard(bet: bet, firestoreService: firestoreService)
                                }
                                
                                // Show Create Bet card if no bets exist, otherwise show View More Markets
                                if availableBets.isEmpty {
                                    // Create Bet Card - when no bets exist at all
                                    Button(action: {
                                        showingCreateBetModal = true
                                    }) {
                                        VStack(spacing: 8) {
                                            Text("Create a Bet")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.slingBlue)
                                                .multilineTextAlignment(.center)
                                            
                                            ZStack {
                                                Circle()
                                                    .fill(Color.slingBlue)
                                                    .frame(width: 32, height: 32)
                                                
                                                Image(systemName: "plus")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .frame(width: 160, height: 160)
                                        .background(Color.white)
                                        .cornerRadius(16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.slingBlue.opacity(0.3), lineWidth: 1)
                                        )
                                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                                    }
                                } else {
                                    // View More Markets Card - when some bets exist
                                Button(action: {
                                    // Navigate to home page by changing the selected tab
                                    selectedTab = 0
                                }) {
                                    VStack(spacing: 8) {
                                        Text("View More Active Markets")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.slingBlue)
                                            .multilineTextAlignment(.center)
                                        
                                        ZStack {
                                            Circle()
                                                .fill(Color.slingBlue)
                                                .frame(width: 32, height: 32)
                                            
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 16))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .frame(width: 160, height: 160)
                                    .background(Color.white)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.slingBlue.opacity(0.3), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    } else {
                        // Has active bets - show Active Bets with Create Bet card
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(activeBets) { bet in
                                    ActiveBetCard(bet: bet, firestoreService: firestoreService)
                                }
                                
                                // Create Bet Card
                                Button(action: {
                                    showingCreateBetModal = true
                                }) {
                                    VStack(spacing: 12) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.slingBlue)
                                        
                                        Text("Create Bet")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.black)
                                        
                                        Text("Start a new bet")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    .frame(width: 160, height: 140)
                                    .background(Color.white)
                                    .cornerRadius(16)
                                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                }
                
                // Past Bets Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                                Text("Past Bets")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    
                    // Filter bar for past bets
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            Button(action: { selectedPastBetFilter = "All" }) {
                                Text("All")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedPastBetFilter == "All" ? .white : .slingBlue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedPastBetFilter == "All" ? Color.slingBlue : Color.white)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(selectedPastBetFilter == "All" ? Color.clear : Color.slingBlue, lineWidth: 1)
                                    )
                            }
                            
                            Button(action: { selectedPastBetFilter = "Won" }) {
                                Text("Won")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedPastBetFilter == "Won" ? .white : .slingBlue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedPastBetFilter == "Won" ? Color.slingBlue : Color.white)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(selectedPastBetFilter == "Won" ? Color.clear : Color.slingBlue, lineWidth: 1)
                                    )
                            }
                            
                            Button(action: { selectedPastBetFilter = "Created" }) {
                                Text("Created")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedPastBetFilter == "Created" ? .white : .slingBlue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedPastBetFilter == "Created" ? Color.slingBlue : Color.white)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(selectedPastBetFilter == "Created" ? Color.clear : Color.slingBlue, lineWidth: 1)
                                    )
                            }
                            
                            Button(action: { selectedPastBetFilter = "Cancelled" }) {
                                Text("Cancelled")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedPastBetFilter == "Cancelled" ? .white : .slingBlue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedPastBetFilter == "Cancelled" ? Color.slingBlue : Color.white)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(selectedPastBetFilter == "Cancelled" ? Color.clear : Color.slingBlue, lineWidth: 1)
                                    )
                            }
                            
                            Button(action: { selectedPastBetFilter = "Lost" }) {
                                Text("Lost")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedPastBetFilter == "Lost" ? .white : .slingBlue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedPastBetFilter == "Lost" ? Color.slingBlue : Color.white)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(selectedPastBetFilter == "Lost" ? Color.clear : Color.slingBlue, lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    
                    // Horizontal line under filter row
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                    
                    // Filter the past bets based on selected filter
                    let filteredPastBets = filterPastBets(pastBets, filter: selectedPastBetFilter)
                    
                    if filteredPastBets.isEmpty {
                        // No past bets to display
                        VStack(spacing: 16) {
                            Image(systemName: "tray")
                                .font(.system(size: 48))
                                .foregroundColor(.gray.opacity(0.5))
                            
                            Text("No Past Bets")
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(.gray)
                            
                            Text("You haven't participated in any settled or cancelled bets yet.")
                                .font(.subheadline)
                                .foregroundColor(.gray.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .padding(.horizontal, 16)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredPastBets) { bet in
                                CondensedBetCard(bet: bet, currentUserEmail: firestoreService.currentUser?.email, firestoreService: firestoreService)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                
                // Past Bets section is now handled above
            }
            .padding(.bottom, 100) // Space for bottom tab bar
        }
        .refreshable {
            // Refresh data when user pulls down
            await refreshData()
        }
        .background(Color.white)
        .onAppear {
            firestoreService.fetchUserBets { _ in }
            firestoreService.fetchUserBetParticipations()
            firestoreService.fetchUserCommunities()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            firestoreService.fetchUserBets { _ in }
            firestoreService.fetchUserBetParticipations()
            firestoreService.fetchUserCommunities()
        }
        .sheet(isPresented: $showingCreateBetModal) {
            CreateBetView(firestoreService: firestoreService, preSelectedCommunity: nil)
        }

    }
    
    private func refreshData() async {
        // Update statistics for all user communities
        for community in firestoreService.userCommunities {
            if let communityId = community.id {
                firestoreService.updateCommunityStatistics(communityId: communityId) { success, error in
                    if let error = error {
                        print("❌ Error updating statistics for community \(communityId): \(error)")
                    }
                }
            }
        }
        
        // Fetch fresh data from Firestore
        firestoreService.fetchUserCommunities()
        firestoreService.fetchUserBets { _ in }
        firestoreService.fetchUserBetParticipations()
    }
    
    // MARK: - Helper Functions
    
    private func getAvailableBetsToBetOn() -> [FirestoreBet] {
        // Get available bets from user's communities that are open and not expired
        let currentDate = Date()
        return firestoreService.bets.filter { bet in
            let isOpen = bet.status.lowercased() == "open"
            let notExpired = bet.deadline > currentDate
            let isUserCommunity = firestoreService.userCommunities.contains { community in
                community.id == bet.community_id
            }
            let userNotParticipated = !firestoreService.userBetParticipations.contains { participation in
                participation.bet_id == bet.id
            }
            
            return isOpen && notExpired && isUserCommunity && userNotParticipated
        }
    }
    
    private func filterPastBets(_ bets: [FirestoreBet], filter: String) -> [FirestoreBet] {
        switch filter {
        case "Won":
            return bets.filter { bet in
                if bet.status == "settled", let winnerOption = bet.winner_option {
                    // Check if user participated and won
                    let currentUserEmail = firestoreService.currentUser?.email
                    return firestoreService.userBetParticipations.contains { participation in
                        participation.bet_id == bet.id && 
                        participation.user_email == currentUserEmail && 
                        participation.chosen_option == winnerOption
                    }
                }
                return false
            }
        case "Created":
            return bets.filter { bet in
                // Show bets created by the user
                let currentUserEmail = firestoreService.currentUser?.email
                return bet.creator_email == currentUserEmail
            }
        case "Cancelled":
            return bets.filter { bet in
                bet.status == "cancelled"
            }
        case "Lost":
            return bets.filter { bet in
                if bet.status == "settled", let winnerOption = bet.winner_option {
                    // Check if user participated and lost
                    let currentUserEmail = firestoreService.currentUser?.email
                    return firestoreService.userBetParticipations.contains { participation in
                        participation.bet_id == bet.id && 
                        participation.user_email == currentUserEmail && 
                        participation.chosen_option != winnerOption
                    }
                }
                return false
            }
        default: // "All"
            return bets
        }
    }
}

// MARK: - Active Bet Card Component
struct ActiveBetCard: View {
    let bet: FirestoreBet
    @ObservedObject var firestoreService: FirestoreService
    @State private var showingSettleBetModal = false
    @State private var showingBetDetailSheet = false
    
    // Computed property for total amount wagered on this bet
    private var totalWageredAmount: Int {
        let participations = firestoreService.userBetParticipations.filter { $0.bet_id == bet.id }
        return participations.reduce(0) { $0 + $1.stake_amount }
    }
    
    // Computed property for user's choice on this bet
    private var userChoice: String {
        guard let currentUserEmail = firestoreService.currentUser?.email else { return "Creator" }
        guard let betId = bet.id else { return "Creator" }
        
        let participation = firestoreService.userBetParticipations.first { 
            $0.bet_id == betId && $0.user_email == currentUserEmail 
        }
        return participation?.chosen_option ?? "Creator"
    }
    
    // Computed property for user's wager amount on this bet
    private var userWagerAmount: Int {
        guard let currentUserEmail = firestoreService.currentUser?.email else { return 0 }
        guard let betId = bet.id else { return 0 }
        
        let participation = firestoreService.userBetParticipations.first { 
            $0.bet_id == betId && $0.user_email == currentUserEmail 
        }
        return participation?.stake_amount ?? 0
    }
    
    // Computed property to check if user is creator but hasn't placed a wager
    private var isCreatorWithoutWager: Bool {
        guard let currentUserEmail = firestoreService.currentUser?.email else { return false }
        return bet.creator_email == currentUserEmail && userWagerAmount == 0
    }
    
    // Computed property to check if user is creator and has placed a wager
    private var isCreatorWithWager: Bool {
        guard let currentUserEmail = firestoreService.currentUser?.email else { return false }
        return bet.creator_email == currentUserEmail && userWagerAmount > 0
    }
    
    // Helper function to format deadline
    private func formatDeadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    var body: some View {
        Button(action: {
            showingBetDetailSheet = true
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Header section with choice and trophy icon
                HStack(alignment: .top) {
                    // Hero choice at the top (like the second image)
                    Text(userChoice)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Settle Bet button for creators who have wagered
                    if isCreatorWithWager {
                        Button(action: {
                            showingSettleBetModal = true
                        }) {
                            Image(systemName: "trophy.fill")
                                .font(.caption)
                                .foregroundColor(.slingBlue)
                                .padding(4)
                                .background(Color.slingBlue.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
                
                // Bet title below the choice
                Text(bet.title)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 8)
                
                // Deadline
                Text("Deadline: \(formatDeadline(bet.deadline))")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.bottom, 8)
                
                // Wager or Settle Bet line
                if isCreatorWithoutWager {
                    // Show Settle Bet for creators who haven't wagered
                    Button(action: {
                        showingSettleBetModal = true
                    }) {
                        HStack(spacing: 4) {
                            Text("Settle Bet")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.slingGradient)
                            
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.slingBlue)
                        }
                    }
                    .buttonStyle(.plain)
                } else if isCreatorWithWager {
                    // Show wager amount for creators who have wagered
                    HStack(spacing: 4) {
                        Text("Wager:")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundColor(.slingBlue)
                        
                        Text("\(userWagerAmount)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                } else {
                    // Show wager amount for participants
                    HStack(spacing: 4) {
                        Text("Wager:")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundColor(.slingBlue)
                        
                        Text("\(userWagerAmount)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(16)
            .frame(width: 160, height: 140)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSettleBetModal) {
            SettleBetModal(bet: bet, firestoreService: firestoreService)
        }
        .sheet(isPresented: $showingBetDetailSheet) {
            JoinBetView(
                bet: bet, 
                firestoreService: firestoreService,
                onCommunityTap: nil
            )
        }
        .onAppear {
            print("🔍 ActiveBetCard Debug:")
            print("  - Bet ID: \(bet.id ?? "nil")")
            print("  - Bet Title: \(bet.title)")
            print("  - User Email: \(firestoreService.currentUser?.email ?? "nil")")
            print("  - User Participations: \(firestoreService.userBetParticipations.count)")
            print("  - User Choice: \(userChoice)")
            print("  - User Wager: \(userWagerAmount)")
            print("  - Is Creator: \(bet.creator_email == firestoreService.currentUser?.email)")
            print("  - Is Creator With Wager: \(isCreatorWithWager)")
            print("  - Is Creator Without Wager: \(isCreatorWithoutWager)")
        }
    }
}

// MARK: - Active Bet Detail View
struct ActiveBetDetailView: View {
    let bet: FirestoreBet
    @ObservedObject var firestoreService: FirestoreService
    @Environment(\.dismiss) private var dismiss
    @State private var showingSettleBetModal = false
    @State private var userFullNames: [String: String] = [:]
    
    private var communityName: String {
        if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
            return community.name
        }
        return "Community"
    }
    
    private var isCreator: Bool {
        return bet.creator_email == firestoreService.currentUser?.email
    }
    
    private var participants: [BetParticipant] {
        return firestoreService.userBetParticipations.filter { $0.bet_id == bet.id }
    }
    
    private var totalWagered: Int {
        return participants.reduce(0) { $0 + $1.stake_amount }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(communityName)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(bet.status.capitalized)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.slingBlue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.slingBlue.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        Text(bet.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        
                        Text("Deadline: \(formatDeadline(bet.deadline))")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 20)
                    
                    // Betting Options
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Betting Options")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                            .padding(.horizontal, 20)
                        
                        VStack(spacing: 12) {
                            ForEach(bet.options, id: \.self) { option in
                                HStack {
                                    Text(option)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.black)
                                    
                                    Spacer()
                                    
                                    Text(bet.odds[option] ?? "-110")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    // Participants List
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Participants (\(participants.count))")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.caption)
                                    .foregroundColor(.slingBlue)
                                Text("\(totalWagered)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        if participants.isEmpty {
                            Text("No participants yet")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(participants, id: \.id) { participant in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(getUserFullName(from: participant.user_email))
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.black)
                                            
                                            HStack(spacing: 4) {
                                                Text(participant.chosen_option)
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                
                                                Text("•")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                
                                                Image(systemName: "bolt.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.yellow)
                                                
                                                Text(String(participant.stake_amount))
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: "bolt.fill")
                                                .font(.caption)
                                                .foregroundColor(.slingBlue)
                                            Text("\(participant.stake_amount)")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.black)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                    
                    // Action Buttons
                    if isCreator {
                        VStack(spacing: 12) {
                            Button(action: {
                                showingSettleBetModal = true
                            }) {
                                HStack(spacing: 8) {
                                    Text("Settle Bet")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.slingBlue)
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 20)
            }
            .navigationTitle("Bet Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showingSettleBetModal) {
            SettleBetModal(bet: bet, firestoreService: firestoreService)
        }
    }
    
    private func formatDeadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }
    
    // Function to get user's full name, with caching
    private func getUserFullName(from email: String) -> String {
        // Check cache first
        if let cachedName = userFullNames[email] {
            return cachedName
        }
        
        // For current user, use local data
        if let user = firestoreService.currentUser, user.email == email {
            let fullName = "\(user.first_name ?? "") \(user.last_name ?? "")".trimmingCharacters(in: .whitespaces)
            userFullNames[email] = fullName
            return fullName
        }
        
        // For other users, fetch from Firestore and cache
        firestoreService.getUserDetails(email: email) { fullName, _ in
            DispatchQueue.main.async {
                self.userFullNames[email] = fullName
            }
        }
        
        // Return first name as fallback while fetching
        return email.components(separatedBy: "@").first ?? email
    }
}

// MARK: - Settle Bet Modal
struct SettleBetModal: View {
    let bet: FirestoreBet
    @ObservedObject var firestoreService: FirestoreService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWinner: String = ""
    @State private var isLoading = false
    @State private var showingConfirmation = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Settle Bet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                Text("Select the winning option for:")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Text(bet.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                
                // Betting options
                VStack(spacing: 12) {
                    ForEach(bet.options, id: \.self) { option in
                        Button(action: {
                            selectedWinner = option
                        }) {
                            HStack {
                                Text(option)
                                    .font(.subheadline)
                                    .foregroundColor(selectedWinner == option ? .white : .black)
                                
                                Spacer()
                                
                                if selectedWinner == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(selectedWinner == option ? Color.slingBlue : Color.gray.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .foregroundColor(.black)
                    .cornerRadius(10)
                    
                                                    Button(action: {
                    showingConfirmation = true
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Text("Settle Bet")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selectedWinner.isEmpty ? Color.gray.opacity(0.3) : Color.slingBlue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(selectedWinner.isEmpty || isLoading)
                }
            }
            .padding(20)
            .navigationBarHidden(true)
        }
        .alert("Confirm Settlement", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Settle Bet") {
                settleBet()
            }
        } message: {
            Text("Are you sure you want to settle this bet with '\(selectedWinner)' as the winner? This action cannot be undone.")
        }
    }
    
    private func settleBet() {
        guard !selectedWinner.isEmpty else { return }
        
        isLoading = true
        
        firestoreService.settleBet(betId: bet.id ?? "", winnerOption: selectedWinner) { success in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    print("✅ Bet settled successfully!")
                    dismiss()
                } else {
                    print("❌ Error settling bet")
                    // You could add an error alert here if needed
                }
            }
        }
    }
}

// MARK: - My Bet Card Component
struct MyBetCard: View {
    let bet: FirestoreBet
    let currentUserEmail: String?
    @ObservedObject var firestoreService: FirestoreService
    
    // MARK: - State
    @State private var offset: CGFloat = 0
    @State private var showingCancelAlert = false
    @State private var showingDeleteAlert = false
    @State private var selectedBettingOption = ""
    @State private var hasRemindedCreator = false
    
    // MARK: - Cached Computed Values (Performance Optimization)
    @State private var cachedCommunityName: String = ""
    @State private var cachedUserParticipation: BetParticipant?
    @State private var cachedCreatorDisplayName: String = ""
    @State private var cachedUserChoice: String = ""
    @State private var cachedUserWager: Double = 0
    @State private var cachedIsCreator: Bool = false
    @State private var cachedHasWager: Bool = false
    
    // MARK: - Sheet Management
    private enum ActiveSheet: Identifiable {
        case chooseWinner, placeBet, share, betDetail, bettingInterface
        var id: Int { hashValue }
    }
    @State private var activeSheet: ActiveSheet?
    
    // MARK: - Constants
    private let swipeThreshold: CGFloat = 80
    private let maxSwipeDistance: CGFloat = 240
    
    private var communityName: String {
        return cachedCommunityName
    }
    
    private var creatorDisplayName: String {
        return cachedCreatorDisplayName
    }
    
    private var userParticipation: BetParticipant? {
        return cachedUserParticipation
    }
    
    private var isCreator: Bool {
        return cachedIsCreator
    }
    
    private var hasWager: Bool {
        return cachedHasWager
    }
    
    private var userChoice: String {
        return cachedUserChoice
    }
    
    private var userWager: Double {
        return cachedUserWager
    }
    
    private var formattedClosingDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d 'at' h:mm a"
        return formatter.string(from: bet.deadline)
    }
    
    private var getCreatorInitials: String {
        if bet.creator_email == currentUserEmail {
            // Use current user initials if this user is the creator
            let user = firestoreService.currentUser
            if let firstName = user?.first_name, let lastName = user?.last_name, !firstName.isEmpty, !lastName.isEmpty {
                let firstInitial = String(firstName.prefix(1)).uppercased()
                let lastInitial = String(lastName.prefix(1)).uppercased()
                return "\(firstInitial)\(lastInitial)"
            } else if let displayName = user?.display_name, !displayName.isEmpty {
                let components = displayName.components(separatedBy: " ")
                if components.count >= 2 {
                    let firstInitial = String(components[0].prefix(1)).uppercased()
                    let lastInitial = String(components[1].prefix(1)).uppercased()
                    return "\(firstInitial)\(lastInitial)"
                } else if components.count == 1 {
                    return String(components[0].prefix(1)).uppercased()
                }
            }
            // Fallback to email initial
            return String(bet.creator_email.prefix(1)).uppercased()
        } else {
            // For other users, use the first letter of their display name or email
            return String(bet.creator_email.prefix(1)).uppercased()
        }
    }
    
    // Action buttons for swipe
    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            if isCreator {
                // Cancel/Delete button for creators
                Button(action: {
                    if bet.status == "open" {
                        showingCancelAlert = true
                    } else {
                        showingDeleteAlert = true
                    }
                }) {
                    Image(systemName: bet.status == "open" ? "xmark.circle.fill" : "trash.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                
                if bet.status == "open" {
                    // Choose winner button
                    Button(action: {
                        activeSheet = .chooseWinner
                    }) {
                        Image(systemName: "trophy.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                }
            }
            
            // Share button (for everyone)
            Button(action: {
                activeSheet = .share
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(AnyShapeStyle(Color.slingGradient))
                    .clipShape(Circle())
            }
        }
        .padding(.trailing, 16)
    }
    
    var body: some View {
        ZStack {
            // Background action buttons - only show when swiped
            if offset < 0 {
                HStack {
                    Spacer()
                    actionButtonsView
                }
            }
            
            // Main card content - Exact layout from image
            VStack(alignment: .leading, spacing: 0) {
                // Top section with image, title, and status
                HStack(alignment: .top, spacing: 12) {
                    // Square image like in the reference
                    if let imageURL = bet.image_url, !imageURL.isEmpty {
                        AsyncImage(url: URL(string: imageURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 64, height: 64)
                                    .clipped()
                                    .cornerRadius(12)
                            case .failure(_), .empty:
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Text(getCreatorInitials)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.gray)
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 64, height: 64)
                            .overlay(
                                Text(getCreatorInitials)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.gray)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            // Bet title - matches main feed
                            Text(bet.title)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            // Status badge
                            Text(bet.status.uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(bet.status == "open" ? Color.green : Color.gray)
                                .cornerRadius(12)
                        }
                        
                        // Community and creator info - matches main feed
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Text("\(communityName) • by \(creatorDisplayName)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        
                        // Betting deadline - matches main feed
                        Text("Deadline: \(formattedClosingDate)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.bottom, 16)
                
                // Bottom section - Choice and Wager (always show grey box)
                HStack(alignment: .center, spacing: 0) {
                    // Left side - You Picked
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You Picked")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        
                        if hasWager {
                            Text(userChoice)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.black)
                        } else if isCreator {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.purple)
                                Text("Creator")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.purple)
                            }
                        } else {
                            Text("No bet placed")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    // Right side - Wager or Action
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Wager")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        
                        if hasWager {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(Color.slingBlue)
                                
                                Text(String(format: "%.2f", userWager))
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(Color.slingBlue)
                            }
                        } else {
                            Button(action: {
                                activeSheet = .placeBet
                            }) {
                                Text("Place Bet")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.slingBlue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.slingLightBlue)
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            .offset(x: offset)
            .onTapGesture {
                // Only handle tap if card is not swiped
                if offset != 0 {
                    // Reset swipe when tapping on the card
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        offset = 0
                    }
                } else {
                    activeSheet = .betDetail
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let translation = value.translation.width
                        if translation < 0 { // Only allow left swipe
                            offset = max(translation, -maxSwipeDistance)
                        } else if offset < 0 { // Allow right swipe only if already swiped left
                            offset = min(offset + translation, 0)
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if offset < -swipeThreshold {
                                offset = -240 // Show all actions
                            } else {
                                offset = 0 // Hide actions
                            }
                        }
                    }
            )
        }
        .clipped()
        .alert("Cancel Bet", isPresented: $showingCancelAlert) {
            Button("Cancel", role: .destructive) {
                cancelBet()
            }
            Button("Keep Bet", role: .cancel) { }
        } message: {
            Text("Are you sure you want to cancel this bet? This action cannot be undone.")
        }
        .alert("Delete Bet", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteBet()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this bet? This action cannot be undone.")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .chooseWinner:
                ChooseWinnerView(bet: bet, firestoreService: firestoreService)
            case .placeBet:
                PlaceBetView(bet: bet, presetOption: nil, firestoreService: firestoreService)
            case .share:
                ShareSheet(activityItems: [generateShareText()])
            case .betDetail:
                JoinBetView(
                    bet: bet, 
                    firestoreService: firestoreService,
                    onCommunityTap: {
                        // Navigate to community details
                        // This will be handled by the parent view
                    }
                )
            case .bettingInterface:
                BettingInterfaceView(
                    bet: bet,
                    selectedOption: selectedBettingOption.isEmpty ? (bet.options.first ?? "Yes") : selectedBettingOption,
                    firestoreService: firestoreService
                )
            }
        }
        .onAppear {
            // Cache expensive computed values to prevent recalculation on every render
            if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
                cachedCommunityName = community.name
            } else {
                cachedCommunityName = "ZBT Basketball 2025"
            }
            
            if bet.creator_email == currentUserEmail {
                cachedCreatorDisplayName = "You"
            } else {
                let emailComponents = bet.creator_email.components(separatedBy: "@")
                cachedCreatorDisplayName = emailComponents.first ?? "elonmusk"
            }
            
            cachedUserParticipation = firestoreService.userBetParticipations.first { participation in
                participation.bet_id == bet.id && participation.user_email == currentUserEmail
            }
            
            cachedIsCreator = currentUserEmail == bet.creator_email
            cachedHasWager = cachedUserParticipation != nil
            
            if let participation = cachedUserParticipation {
                let optionWithOdds = bet.odds[participation.chosen_option] ?? ""
                cachedUserChoice = "\(participation.chosen_option) \(optionWithOdds)".trimmingCharacters(in: .whitespaces)
            } else {
                cachedUserChoice = "Over -110"
            }
            
            cachedUserWager = Double(cachedUserParticipation?.stake_amount ?? 0)
        }
    }
    
    private func cancelBet() {
        firestoreService.cancelMarket(betId: bet.id ?? "") { success in
            if success {
                print("✅ Bet cancelled successfully")
            } else {
                print("❌ Error cancelling bet")
            }
        }
    }
    
    private func deleteBet() {
        firestoreService.deleteBet(betId: bet.id ?? "") { success in
            if success {
                print("✅ Bet deleted successfully")
            } else {
                print("❌ Error deleting bet")
            }
        }
    }
    
    private func generateShareText() -> String {
        return "Check out this prediction on Sling: \(bet.title)"
    }
}

// MARK: - Condensed Bet Card Component (matches image format)
struct CondensedBetCard: View {
    let bet: FirestoreBet
    let currentUserEmail: String?
    @ObservedObject var firestoreService: FirestoreService
    
    // MARK: - State
    @State private var showingCancelAlert = false
    @State private var showingDeleteAlert = false
    @State private var selectedBettingOption = ""
    @State private var offset: CGFloat = 0
    @State private var userFullNames: [String: String] = [:]
    
    // MARK: - Constants
    private let swipeThreshold: CGFloat = 80
    private let maxSwipeDistance: CGFloat = 240
    
    // MARK: - Sheet Management
    private enum ActiveSheet: Identifiable {
        case chooseWinner, placeBet, share, betDetail, bettingInterface
        var id: Int { hashValue }
    }
    @State private var activeSheet: ActiveSheet?
    
    // MARK: - Computed Properties
    private var communityName: String {
        let communityId = bet.community_id
        if let community = firestoreService.userCommunities.first(where: { $0.id == communityId }) {
            return community.name
        }
        return "Unknown Community"
    }
    
    private var creatorDisplayName: String {
        if bet.creator_email == currentUserEmail {
            return "You"
        }
        return getUserFullName(from: bet.creator_email)
    }
    
    // Function to get user's full name, with caching
    private func getUserFullName(from email: String) -> String {
        // Check cache first
        if let cachedName = userFullNames[email] {
            return cachedName
        }
        
        // For current user, use local data
        if let user = firestoreService.currentUser, user.email == email {
            let fullName = "\(user.first_name ?? "") \(user.last_name ?? "")".trimmingCharacters(in: .whitespaces)
            userFullNames[email] = fullName
            return fullName
        }
        
        // For other users, fetch from Firestore and cache
        firestoreService.getUserDetails(email: email) { fullName, _ in
            DispatchQueue.main.async {
                self.userFullNames[email] = fullName
            }
        }
        
        // Return first name as fallback while fetching
        return email.components(separatedBy: "@").first ?? email
    }
    
    private var userParticipation: BetParticipant? {
        guard let currentUserEmail = currentUserEmail else { return nil }
        let participation = firestoreService.userBetParticipations.first { participation in
            participation.bet_id == bet.id && participation.user_email == currentUserEmail
        }
        return participation
    }
    
    private var isCreator: Bool {
        return bet.creator_email == currentUserEmail
    }
    
    private var hasWager: Bool {
        return userParticipation != nil
    }
    
    private var userChoice: String {
        return userParticipation?.chosen_option ?? ""
    }
    
    private var userWager: Int {
        return userParticipation?.stake_amount ?? 0
    }
    
    private var statusColor: Color {
        switch bet.status.lowercased() {
        case "open":
            return .green
        case "pending":
            return .orange
        case "settled":
            return .blue
        case "cancelled":
            return .red
        default:
            return .gray
        }
    }
    
    // Action buttons for swipe
    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            if isCreator {
                // Cancel/Delete button for creators
                Button(action: {
                    if bet.status == "open" {
                        showingCancelAlert = true
                    } else {
                        showingDeleteAlert = true
                    }
                }) {
                    Image(systemName: bet.status == "open" ? "xmark.circle.fill" : "trash.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                
                if bet.status == "open" {
                    // Choose winner button
                    Button(action: {
                        activeSheet = .chooseWinner
                    }) {
                        Image(systemName: "trophy.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                }
            }
            
            // Share button (for everyone)
            Button(action: {
                activeSheet = .share
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(AnyShapeStyle(Color.slingGradient))
                    .clipShape(Circle())
            }
        }
        .padding(.trailing, 16)
    }
    
    private var getCreatorInitials: String {
        if bet.creator_email == currentUserEmail {
            // Use current user initials if this user is the creator
            let user = firestoreService.currentUser
            if let firstName = user?.first_name, let lastName = user?.last_name, !firstName.isEmpty, !lastName.isEmpty {
                let firstInitial = String(firstName.prefix(1)).uppercased()
                let lastInitial = String(lastName.prefix(1)).uppercased()
                return "\(firstInitial)\(lastInitial)"
            } else if let displayName = user?.display_name, !displayName.isEmpty {
                let components = displayName.components(separatedBy: " ")
                if components.count >= 2 {
                    let firstInitial = String(components[0].prefix(1)).uppercased()
                    let lastInitial = String(components[1].prefix(1)).uppercased()
                    return "\(firstInitial)\(lastInitial)"
                } else if components.count == 1 {
                    return String(components[0].prefix(1)).uppercased()
                }
            }
            // Fallback to email initial
            return String(bet.creator_email.prefix(1)).uppercased()
        } else {
            // For other users, use the first letter of their display name or email
            return String(bet.creator_email.prefix(1)).uppercased()
        }
    }
    
    var body: some View {
        ZStack {
            // Background action buttons - only show when swiped
            if offset < 0 {
                HStack {
                    Spacer()
                    actionButtonsView
                }
            }
            
            // Main card content
            HStack(alignment: .top, spacing: 12) {
                // Bet image (40x40 like Community Details)
                if let imageURL = bet.image_url, !imageURL.isEmpty {
                    AsyncImage(url: URL(string: imageURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipped()
                                .cornerRadius(8)
                        case .failure(_), .empty:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(getCreatorInitials)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.gray)
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(getCreatorInitials)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.gray)
                        )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    // Bet title and status badge in same row
                    HStack(alignment: .top) {
                    Text(bet.title)
                            .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    
                        // Status badge
                        Text(getStatusText())
                        .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(getStatusBadgeBackgroundColor())
                            .cornerRadius(8)
                    }
                    
                    // User's choice
                    HStack {
                        Text("Your Choice:")
                            .font(.caption2)
                        .foregroundColor(.gray)
                        Text(userChoice.isEmpty ? "No choice made" : userChoice)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.slingBlue)
                        Spacer()
                    }
                    
                    // Wager and payout information
                    HStack {
                        HStack(spacing: 4) {
                            Text("Wager:")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                                .foregroundColor(.slingBlue)
                            Text("\(userWager)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        
                        if bet.status == "settled" && hasWager {
                            HStack(spacing: 4) {
                                Text("Paid:")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Image(systemName: "bolt.fill")
                                    .font(.caption2)
                                    .foregroundColor(.slingBlue)
                                Text("\(getPayoutAmount())")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        } else if bet.status == "cancelled" && hasWager {
                            HStack(spacing: 4) {
                                Text("Paid:")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Image(systemName: "bolt.fill")
                                    .font(.caption2)
                                    .foregroundColor(.slingBlue)
                                Text("\(userWager)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                }
                
                Spacer()
                
                        // Community name and icon
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Text(communityName)
                                .font(.caption2)
                    .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer()
                
                // Removed navigation chevron - no more right arrow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: offset)
        .onTapGesture {
            // Only handle tap if card is not swiped
            if offset != 0 {
                // Reset swipe when tapping on the card
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    offset = 0
                }
            } else {
                activeSheet = .betDetail
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    let translation = value.translation.width
                    if translation < 0 { // Only allow left swipe
                        offset = max(translation, -maxSwipeDistance)
                    } else if offset < 0 { // Allow right swipe only if already swiped left
                        offset = min(offset + translation, 0)
                    }
                }
                .onEnded { value in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if offset < -swipeThreshold {
                            offset = -240 // Show all actions
                        } else {
                            offset = 0 // Hide actions
                        }
                    }
                }
        )
        .clipped()
        .alert("Cancel Bet", isPresented: $showingCancelAlert) {
            Button("Cancel Bet", role: .destructive) {
                cancelBet()
            }
            Button("Keep Bet", role: .cancel) { }
        } message: {
            Text("Are you sure you want to cancel this bet? This action cannot be undone.")
        }
        .alert("Delete Bet", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteBet()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this bet? This action cannot be undone.")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .chooseWinner:
                ChooseWinnerView(bet: bet, firestoreService: firestoreService)
            case .placeBet:
                PlaceBetView(bet: bet, presetOption: nil, firestoreService: firestoreService)
            case .share:
                ShareSheet(activityItems: [generateShareText()])
            case .betDetail:
                JoinBetView(
                    bet: bet, 
                    firestoreService: firestoreService,
                    onCommunityTap: {
                        // Navigate to community details
                        // This will be handled by the parent view
                    }
                )
            case .bettingInterface:
                BettingInterfaceView(
                    bet: bet,
                    selectedOption: selectedBettingOption.isEmpty ? (bet.options.first ?? "Yes") : selectedBettingOption,
                    firestoreService: firestoreService)
            }
        }
        .onAppear {
            // Ensure user bet participations are loaded
            firestoreService.fetchUserBetParticipations()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Refresh when app comes to foreground
            firestoreService.fetchUserBetParticipations()
        }
    }
    
    private func generateShareText() -> String {
        return "Check out this bet: \(bet.title) - \(communityName)"
    }
    
    private func cancelBet() {
        firestoreService.cancelMarket(betId: bet.id ?? "") { success in
            if success {
                print("✅ Bet cancelled successfully")
            } else {
                print("❌ Error cancelling bet")
            }
        }
    }
    
    private func formatDeadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func getStatusText() -> String {
        switch bet.status.lowercased() {
        case "settled":
            if let winnerOption = bet.winner_option, hasWager {
                let currentUserEmail = firestoreService.currentUser?.email
                let participation = firestoreService.userBetParticipations.first { participation in
                    participation.bet_id == bet.id && participation.user_email == currentUserEmail
                }
                if let participation = participation {
                    return participation.chosen_option == winnerOption ? "Won" : "Lost"
                }
            }
            return "Settled"
        case "cancelled":
            return "Cancelled"
        case "open", "pending":
            return "Active"
        default:
            return bet.status.capitalized
        }
    }
    
    private func getStatusColor() -> Color {
        switch getStatusText() {
        case "Won":
            return Color.green.opacity(0.8)
        case "Lost":
            return Color.red.opacity(0.8)
        case "Cancelled":
            return Color.orange.opacity(0.8)
        case "Active":
            return .blue
        default:
            return .gray
        }
    }
    
    private func getStatusBadgeBackgroundColor() -> Color {
        switch getStatusText() {
        case "Won":
            return Color.green.opacity(0.8)
        case "Lost":
            return Color.red.opacity(0.8)
        case "Cancelled":
            return Color.orange.opacity(0.8)
        case "Active":
            return .blue
        default:
            return .gray
        }
    }
    
    private func getPayoutAmount() -> Int {
        if bet.status == "settled", let winnerOption = bet.winner_option, hasWager {
            let currentUserEmail = firestoreService.currentUser?.email
            let participation = firestoreService.userBetParticipations.first { participation in
                participation.bet_id == bet.id && participation.user_email == currentUserEmail
            }
            if let participation = participation {
                if participation.chosen_option == winnerOption {
                    // Won - calculate winnings (this is simplified, you might want to add actual odds calculation)
                    return userWager * 2
                } else {
                    // Lost - no payout
                    return 0
                }
            }
        }
        return userWager
    }
    
    private func deleteBet() {
        firestoreService.deleteBet(betId: bet.id ?? "") { success in
            if success {
                print("✅ Bet deleted successfully")
            } else {
                print("❌ Error deleting bet")
            }
        }
    }
}

// MARK: - Available Bet Card Component

struct AvailableBetCard: View {
    let bet: FirestoreBet
    @ObservedObject var firestoreService: FirestoreService
    @State private var showingBetDetail = false
    
    private var communityName: String {
        let communityId = bet.community_id
        if let community = firestoreService.userCommunities.first(where: { $0.id == communityId }) {
            return community.name
        }
        return "Unknown Community"
    }
    
    private func getOddsForOption(_ option: String) -> String {
        return bet.odds[option] ?? "-110"
    }
    
    var body: some View {
        Button(action: {
            showingBetDetail = true
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // Padding above bet title
                Spacer()
                    .frame(height: 8)
                
                // Bet title - larger font with proper wrapping
                Text(bet.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Community name with icon right under the title
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "person.2")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .frame(width: 12, height: 12)
                    
                    Text(communityName)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Bet Now Button
                HStack {
                    HStack(spacing: 8) {
                        Text("Bet")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(AnyShapeStyle(Color.slingGradient))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 160, height: 160)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingBetDetail) {
            JoinBetView(
                bet: bet,
                firestoreService: firestoreService,
                onCommunityTap: {
                    // Navigate to community details
                }
            )
        }
    }
}

// MARK: - Message Group

struct MessageGroup {
    let date: Date
    let dateHeader: String
    let messages: [CommunityMessage]
}

// MARK: - Chat List Item

struct ChatListItem: Identifiable {
    let id: String
    let communityId: String
    let communityName: String
    let lastMessage: String
    let timestamp: Date  // Changed from String to Date for proper sorting
    let timestampString: String  // Keep formatted string for display
    let unreadCount: Int
    let imageUrl: String
}

// MARK: - Chat Message Bubble

struct ChatMessageBubble: View {
    let message: CommunityMessage
    let isCurrentUser: Bool
    let firestoreService: FirestoreService
    @Binding var selectedBet: FirestoreBet?
    @Binding var showingBetDetail: Bool
    @Binding var selectedBetOption: String
    @Binding var showingPlaceBet: Bool
    
    // Global timestamp state - passed from parent view
    let isShowingTimestamps: Bool
    
    // Function to get user's full name from email
    let getUserFullName: (String) -> String
    
    // Fixed timestamp gutter for perfect vertical alignment
    private let timestampGutter: CGFloat = 68
    
    private var isBot: Bool {
        message.senderEmail == "bot@sling.app" || message.senderEmail == "app@slingapp.com"
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
    

    

    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Left side - Avatar/Logo space (consistent for all message types)
            HStack(alignment: .top, spacing: 2) {
                if isBot {
                    // Sling logo - smaller and circular like user avatars
                    Image("Logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                } else if !isCurrentUser {
                    // User avatar for other users
                    Circle()
                        .fill(Color.slingLightBlue)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Text(String(message.senderName.prefix(1)).uppercased())
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(Color.slingBlue)
                        )
                }
            }
            .frame(width: 32, alignment: .leading)
            
            // Center content area
            VStack(alignment: .leading, spacing: 3) {
                if isBot {
                    // Bot message content
                    VStack(alignment: .leading, spacing: 3) {
                        // Sling name
                        Text("Sling")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                        
                        // Bot message content (bet announcement)
                        if message.messageType == .betAnnouncement {
                            BetAnnouncementCard(
                                message: message,
                                firestoreService: firestoreService,
                                onBetTap: {
                                    // Fetch the actual bet from Firestore and show bet details
                                    if let betId = message.betId {
                                        firestoreService.fetchBet(by: betId) { fetchedBet in
                                            DispatchQueue.main.async {
                                                if let fetchedBet = fetchedBet {
                                                    selectedBet = fetchedBet
                                                    selectedBetOption = "" // Clear any selected option
                                                    showingBetDetail = true
                                                }
                                            }
                                        }
                                    }
                                },
                                onOptionTap: { option in
                                    // Fetch the actual bet from Firestore and show place bet sheet
                                    if let betId = message.betId {
                                        firestoreService.fetchBet(by: betId) { fetchedBet in
                                            DispatchQueue.main.async {
                                                if let fetchedBet = fetchedBet {
                                                    selectedBet = fetchedBet
                                                    selectedBetOption = option
                                                    showingPlaceBet = true
                                                }
                                            }
                                        }
                                    }
                                }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    // Regular user messages
                    if isCurrentUser {
                        // Current user: align to right
                        HStack(spacing: 0) {
                            // Message content with timestamp on the right when global state is active
                            Text(message.text)
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(AnyShapeStyle(Color.slingGradient))
                                .cornerRadius(16)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 0)
                    } else {
                        // Other users: align to left
                        VStack(alignment: .leading, spacing: 3) {
                            // Sender name - show full name instead of first name
                            Text(getUserFullName(message.senderEmail))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.gray)
                            
                            // Message bubble with timestamp on the right when global state is active
                            Text(message.text)
                                .font(.subheadline)
                                .foregroundColor(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            
            // Fixed timestamp gutter column - only reserve space when showing timestamps
            if isShowingTimestamps {
                Spacer(minLength: timestampGutter)
            }
        }
        .overlay(alignment: .trailing) {
            if isShowingTimestamps {
                Text(formatTime(message.timestamp))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(width: timestampGutter, alignment: .center)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }

        .sheet(isPresented: $showingBetDetail) {
            if let selectedBet = selectedBet {
                JoinBetView(
                    bet: selectedBet,
                    firestoreService: firestoreService,
                    onCommunityTap: {
                        // Navigate to community details
                        // This will be handled by the parent view
                    }
                )
            }
        }
        .sheet(isPresented: $showingPlaceBet) {
            if let selectedBet = selectedBet {
                BettingInterfaceView(
                    bet: selectedBet,
                    selectedOption: selectedBetOption.isEmpty ? (selectedBet.options.first ?? "Yes") : selectedBetOption,
                    firestoreService: firestoreService
                )
            }
        }
    }
    

}

// MARK: - Chat View

struct MessagesView: View {
    @ObservedObject var firestoreService: FirestoreService
    @State private var selectedCommunity: FirestoreCommunity?
    @State private var messageText = ""
    @State private var onlineMembers: [String] = []
    @State private var unreadCounts: [String: Int] = [:]
    @State private var showingCommunityInfo = false
    @State private var showingBetDetail = false
    @State private var showingPlaceBet = false
    @State private var selectedBet: FirestoreBet?
    @State private var selectedBetOption = ""
    @State private var isKeyboardActive = false
    @State private var isLoadingMessages = false
    @State private var userFullNames: [String: String] = [:] // Cache for user full names
    
    // Global timestamp state - activated by swiping anywhere on the page
    @State private var isShowingTimestamps = false
    
    // Helper function to generate chat list data from user's actual communities
    private func getChatList() -> [ChatListItem] {
        let chatItems = firestoreService.userCommunities.map { community in
            let unreadCount = unreadCounts[community.id ?? ""] ?? 0
            let timestampString = getLastMessageTimestamp(community)
            let actualTimestamp = getLastMessageActualDate(community)
            
            return ChatListItem(
                id: community.id ?? UUID().uuidString,
                communityId: community.id ?? "",
                communityName: community.name,
                lastMessage: getLastMessage(community),
                timestamp: actualTimestamp,
                timestampString: timestampString,
                unreadCount: unreadCount,
                imageUrl: getDefaultImageUrl(for: community.name)
            )
        }
        
        // Sort chat list: unread messages first (most recent to oldest), then read messages (most recent to oldest)
        let sortedItems = chatItems.sorted { item1, item2 in
            // First priority: communities with unread messages come first
            if item1.unreadCount > 0 && item2.unreadCount == 0 {
                return true
            } else if item1.unreadCount == 0 && item2.unreadCount > 0 {
                return false
            }
            
            // Second priority: if both have unread messages, sort by most recent activity (most recent first)
            if item1.unreadCount > 0 && item2.unreadCount > 0 {
                return item1.timestamp > item2.timestamp
            }
            
            // Third priority: if both have no unread messages, sort by most recent activity (most recent first)
            return item1.timestamp > item2.timestamp
        }
        
        // Debug: Print the sorted order
        print("📱 Chat List Sorting Debug:")
        for (index, item) in sortedItems.enumerated() {
            print("  \(index + 1). \(item.communityName) - Unread: \(item.unreadCount), Timestamp: \(item.timestampString) (Date: \(item.timestamp))")
        }
        
        return sortedItems
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let community = selectedCommunity else { return }
        
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        messageText = "" // Clear input immediately for better UX
        
        firestoreService.sendMessage(to: community.id ?? "", text: trimmedMessage) { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Failed to send message: \(error)")
                    // Optionally show an error message to user
                }
            }
        }
    }
    
    private func getOnlineMemberCount(_ community: FirestoreCommunity) -> Int {
        // Simulate online members (in real app, fetch from server)
        return Int.random(in: 1...min(community.member_count, 15))
    }
    
    private func getLastMessage(_ community: FirestoreCommunity) -> String {
        guard let communityId = community.id,
              let lastMessage = firestoreService.communityLastMessages[communityId] else {
            // Check if there are messages in the community's chat_history as a fallback
            if let chatHistory = community.chat_history, !chatHistory.isEmpty {
                // Find the most recent message from chat_history
                let mostRecentMessage = chatHistory.values.max { $0.time_stamp < $1.time_stamp }
                if let message = mostRecentMessage {
                    let formattedMessage = formatMessagePreview(message)
                    let maxLength = 50
                    if formattedMessage.count > maxLength {
                        return String(formattedMessage.prefix(maxLength)) + "..."
                    }
                    return formattedMessage
                }
            }
            return "No messages yet"
        }
        
        // Format the message as [Full Name]: [Message]
        let formattedMessage = formatMessagePreview(lastMessage)
        let maxLength = 50
        if formattedMessage.count > maxLength {
            return String(formattedMessage.prefix(maxLength)) + "..."
        }
        return formattedMessage
    }
    
    private func formatMessagePreview(_ message: CommunityMessage) -> String {
        return "\(message.senderName): \(message.text)"
    }
    
    private func formatMessagePreview(_ message: FirestoreCommunityMessage) -> String {
        // Convert stored name to full name for preview
        let senderFullName = getFullNameFromStoredName(message.sender_name, email: message.sender_email)
        return "\(senderFullName): \(message.message)"
    }
    
    private func getLastMessageTimestamp(_ community: FirestoreCommunity) -> String {
        guard let communityId = community.id,
              let lastMessage = firestoreService.communityLastMessages[communityId] else {
            let timestamp = formatTimestamp(community.created_date)
            return timestamp
        }
        
        let timestamp = formatTimestamp(lastMessage.timestamp)
        return timestamp
    }
    
    private func getLastMessageActualDate(_ community: FirestoreCommunity) -> Date {
        guard let communityId = community.id,
              let lastMessage = firestoreService.communityLastMessages[communityId] else {
            // Use community creation date as fallback
            return community.created_date
        }
        
        // Return the actual Date object for sorting
        return lastMessage.timestamp
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func getDefaultImageUrl(for communityName: String) -> String {
        // Return empty string to use local placeholder instead of external URL
        return ""
    }
    
    // Helper function to parse relative timestamps for sorting (no longer used, kept for reference)
    private func parseRelativeTimestamp(_ timestamp: String) -> Date {
        let now = Date()
        let calendar = Calendar.current
        
        if timestamp == "Today" {
            return now
        } else if timestamp == "Yesterday" {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return yesterday
        } else if timestamp.contains("ago") {
            // Parse relative time like "6m ago", "38m ago", "1w ago", etc.
            let components = timestamp.components(separatedBy: " ")
            if components.count >= 2, let value = Int(components[0]) {
                let unit = components[1].lowercased()
                let result: Date
                
                switch unit {
                case "s", "sec", "secs", "second", "seconds":
                    result = calendar.date(byAdding: .second, value: -value, to: now) ?? now
                case "m", "min", "mins", "minute", "minutes":
                    result = calendar.date(byAdding: .minute, value: -value, to: now) ?? now
                case "h", "hr", "hrs", "hour", "hours":
                    result = calendar.date(byAdding: .hour, value: -value, to: now) ?? now
                case "d", "day", "days":
                    result = calendar.date(byAdding: .day, value: -value, to: now) ?? now
                case "w", "wk", "week", "weeks":
                    result = calendar.date(byAdding: .weekOfYear, value: -value, to: now) ?? now
                case "mo", "month", "months":
                    result = calendar.date(byAdding: .month, value: -value, to: now) ?? now
                case "y", "yr", "year", "years":
                    result = calendar.date(byAdding: .year, value: -value, to: now) ?? now
                default:
                    // If we can't parse the unit, try to extract just the number and assume minutes
                    result = calendar.date(byAdding: .minute, value: -value, to: now) ?? now
                }
                
                return result
            } else {
                // If we can't parse the components, try to extract just the number
                let numbers = timestamp.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
                if let value = numbers.first {
                    // Assume minutes if we can't determine the unit
                    let result = calendar.date(byAdding: .minute, value: -value, to: now) ?? now
                    return result
                }
            }
        } else {
            // Try to parse as a formatted date like "Monday, Aug 12"
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            if let date = formatter.date(from: timestamp) {
                // Set the year to current year for comparison
                var components = calendar.dateComponents([.year, .month, .day], from: date)
                components.year = calendar.component(.year, from: now)
                let result = calendar.date(from: components) ?? now
                return result
            }
        }
        
        // Fallback to a very old date if parsing fails
        let fallback = calendar.date(byAdding: .year, value: -100, to: now) ?? now
        return fallback
    }
    
    private func initializeUnreadCounts() {
        // Initialize unread counts for user's communities based on actual data
        for community in firestoreService.userCommunities {
            if let communityId = community.id,
               let chatHistory = community.chat_history {
                
                var unreadCount = 0
                if let userId = firestoreService.currentUser?.id {
                    for (_, message) in chatHistory {
                        // Check if message is not read by current user
                        if !message.read_by.contains(userId) {
                            unreadCount += 1
                        }
                    }
                }
                unreadCounts[communityId] = unreadCount
            } else {
                unreadCounts[community.id ?? ""] = 0
            }
        }
        
        // Update total unread count in FirestoreService
        firestoreService.updateTotalUnreadCount()
        

    }
    
    private func loadMessages(for community: FirestoreCommunity) {
        guard let communityId = community.id else { return }

        // Fetch messages without blocking the UI
        firestoreService.fetchMessages(for: communityId)
    }
    
    // Function to get user's full name, with caching
    private func getUserFullName(from email: String) -> String {
        // Check cache first
        if let cachedName = userFullNames[email] {
            return cachedName
        }
        
        // For current user, use local data
        if let user = firestoreService.currentUser, user.email == email {
            let fullName = "\(user.first_name ?? "") \(user.last_name ?? "")".trimmingCharacters(in: .whitespaces)
            userFullNames[email] = fullName
            return fullName
        }
        
        // For other users, fetch from Firestore and cache
        firestoreService.getUserDetails(email: email) { fullName, _ in
            DispatchQueue.main.async {
                self.userFullNames[email] = fullName
            }
        }
        
        // Return first name as fallback while fetching
        return email.components(separatedBy: "@").first ?? email
    }
    
    // Helper function to convert stored name to full name for preview
    private func getFullNameFromStoredName(_ storedName: String, email: String) -> String {
        // If the stored name is the current user's display name, convert to full name
        if let currentUser = firestoreService.currentUser, 
           currentUser.email == email,
           storedName == currentUser.display_name {
            let fullName = "\(currentUser.first_name ?? "") \(currentUser.last_name ?? "")".trimmingCharacters(in: .whitespaces)
            return fullName.isEmpty ? storedName : fullName
        }
        
        // For other users, try to get full name from Firestore
        // For now, return the stored name as is (could be enhanced later)
        return storedName
    }
    
    private var chatListView: some View {
        VStack(spacing: 0) {
            chatHeaderView
            searchBarView
            
            if firestoreService.userCommunities.isEmpty {
                emptyStateView
            } else {
                chatListScrollView
            }
        }
    }
    
    private var chatHeaderView: some View {
        HStack {
            Text("Messages")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.black)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }
    
    private var searchBarView: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            Text("Search chats and messages")
                .foregroundColor(.gray)
                .font(.subheadline)
            
            Spacer()
            

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "message.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("No Communities Yet")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
            
            Text("Join a community to start chatting with other members.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    private var chatListScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(getChatList(), id: \.id) { chatItem in
                    chatItemView(chatItem)
                    
                    if chatItem.id != getChatList().last?.id {
                        Divider()
                            .padding(.leading, 84)
                    }
                }
            }
        }
        .padding(.top, 20)
        .background(Color.white)
        .refreshable {
            // Refresh data when user pulls down
            isLoadingMessages = true
            firestoreService.fetchUserCommunities()
            // Refresh unread counts and last messages
            firestoreService.fetchLastMessagesForUserCommunities()
            
            // Set loading to false after refresh completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isLoadingMessages = false
            }
        }


    }
    
    private func chatItemView(_ chatItem: ChatListItem) -> some View {
        Button(action: {
            // Find the actual community from the user's communities
            if let community = firestoreService.userCommunities.first(where: { $0.id == chatItem.communityId }) {
                selectedCommunity = community
                loadMessages(for: community)
                
                // Clear unread count for this community when selected
                if let communityId = community.id {
                    unreadCounts[communityId] = 0
                    // Update total unread count
                    firestoreService.updateTotalUnreadCount()
                }
            }
        }) {
            HStack(spacing: 12) {
                chatItemAvatarView(chatItem)
                chatItemContentView(chatItem)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    private func chatItemAvatarView(_ chatItem: ChatListItem) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: URL(string: chatItem.imageUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AnyShapeStyle(Color.slingGradient))
                    .overlay(
                        Text(String(chatItem.communityName.prefix(1)).uppercased())
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            
            // Blue dot indicator for unread messages - only show if there are actually unread messages
            if let unreadCount = unreadCounts[chatItem.communityId],
               unreadCount > 0 {
                Circle()
                    .fill(Color.slingBlue)
                    .frame(width: 12, height: 12)
                    .offset(x: 4, y: -4)
            }
        }
    }
    
    private func chatItemContentView(_ chatItem: ChatListItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(chatItem.communityName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                                            Text(chatItem.timestampString)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            HStack {
                Text(chatItem.lastMessage)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                
                Spacer()
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if selectedCommunity == nil {
                chatListView
                    .transition(.move(edge: .leading))
            } else {
                chatInterfaceView
                    .transition(.move(edge: .trailing))
                    .onAppear {
                        if let community = selectedCommunity {
                            loadMessages(for: community)
                            // Mark all messages as read when entering chat
                            if let communityId = community.id {
                                firestoreService.markAllMessagesAsRead(for: communityId) { success in
                                    if success {
                                        print("✅ All messages marked as read for \(community.name)")
                                    }
                                }
                            }
                        }
                    }
                    .onDisappear {
                        firestoreService.stopListeningToMessages()
                    }
            }
        }
        .background(Color.white)
        .animation(.easeInOut(duration: 0.3), value: selectedCommunity)
        .onAppear {
            // Refresh communities when view appears
            isLoadingMessages = true
            firestoreService.fetchUserCommunities()
            // Fetch last messages for all communities to reduce lag
            firestoreService.fetchLastMessagesForUserCommunities()
            // Initialize unread counts immediately
            initializeUnreadCounts()
            
            // Set loading to false after initial load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isLoadingMessages = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Refresh data when app becomes active
            isLoadingMessages = true
            firestoreService.fetchUserCommunities()
            firestoreService.fetchLastMessagesForUserCommunities()
            
            // Set loading to false after refresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isLoadingMessages = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Refresh data when app comes to foreground
            isLoadingMessages = true
            firestoreService.fetchUserCommunities()
            firestoreService.fetchLastMessagesForUserCommunities()
            
            // Set loading to false after refresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isLoadingMessages = false
            }
        }

        .onChange(of: firestoreService.messages) { _, newMessages in
    
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardActive = false
        }
        .sheet(isPresented: $showingCommunityInfo) {
            if let community = selectedCommunity {
                EnhancedCommunityDetailView(
                    community: community, 
                    firestoreService: firestoreService,
                    onChatTap: {
                        // Already in chat, just dismiss the sheet
                        showingCommunityInfo = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingBetDetail) {
            if let bet = selectedBet {
                JoinBetView(
                    bet: bet, 
                    firestoreService: firestoreService,
                    onCommunityTap: {
                        // Navigate to community details
                        // This will be handled by the parent view
                    }
                )
            }
        }

    }
    
    private var chatInterfaceView: some View {
        VStack(spacing: 0) {
            if !isKeyboardActive {
                individualChatHeaderView
            }
            
            messagesAreaView
            
            messageInputView
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    let translation = value.translation.width
                    if translation < 0 { // Left swipe - show timestamps
                        // Activate timestamps when swiping left anywhere on the page
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isShowingTimestamps = true
                        }
                    }
                }
                .onEnded { value in
                    let translation = value.translation.width
                    let velocity = value.velocity.width
                    
                    // Handle left swipe for timestamps
                    if translation < 0 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isShowingTimestamps = false
                        }
                    }
                    
                    // Handle right swipe to go back (with velocity threshold for better UX)
                    if translation > 50 || velocity > 300 { // Right swipe threshold
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedCommunity = nil
                            firestoreService.stopListeningToMessages()
                        }
                    }
                }
        )

    }
    
    private var individualChatHeaderView: some View {
        VStack(spacing: 0) {
        HStack(spacing: 12) {
            Button(action: {
                selectedCommunity = nil
                firestoreService.stopListeningToMessages()
            }) {
                Image(systemName: "arrow.left")
                    .font(.title2)
                    .foregroundColor(.slingBlue)
            }
            
            // Community avatar
            Circle()
                .fill(AnyShapeStyle(Color.slingGradient))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(String(selectedCommunity!.name.prefix(1)).uppercased())
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCommunity!.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                

            }
            
            Spacer()
            
            // Info button
            Button(action: {
                showingCommunityInfo = true
            }) {
                Image(systemName: "info.circle")
                    .font(.title2)
                    .foregroundColor(.slingBlue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .bottom
        )
        }
    }
    
    private var messagesAreaView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if firestoreService.messages.isEmpty {
                    emptyMessagesView
                } else {
                    // Group messages by date and display with headers
                    ForEach(groupedMessages, id: \.date) { group in
                        VStack(spacing: 12) {
                            // Date header (centered pill)
                            Text(group.dateHeader)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(Color.gray.opacity(0.15))
                                )
                                .frame(maxWidth: .infinity)      // centers the pill
                                .padding(.vertical, 4)
                            
                            // Messages for this date
                            ForEach(group.messages) { message in
                                ChatMessageBubble(
                                message: message,
                                isCurrentUser: message.senderEmail == firestoreService.currentUser?.email,
                                firestoreService: firestoreService,
                                selectedBet: $selectedBet,
                                showingBetDetail: $showingBetDetail,
                                selectedBetOption: $selectedBetOption,
                                showingPlaceBet: $showingPlaceBet,
                                isShowingTimestamps: isShowingTimestamps,
                                getUserFullName: { email in
                                    return self.getUserFullName(from: email)
                                }
                            )
                            }
                        }
                    }
                }
                

                
                // Auto-scroll indicator when new messages arrive
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    // Group messages by date for display
    private var groupedMessages: [MessageGroup] {
        let calendar = Calendar.current
        
        let grouped = Dictionary(grouping: firestoreService.messages) { message in
            calendar.startOfDay(for: message.timestamp)
        }
        
        return grouped.map { date, messages in
            let dateHeader: String
            if calendar.isDateInToday(date) {
                dateHeader = "Today"
            } else if calendar.isDateInYesterday(date) {
                dateHeader = "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE, MMM d"
                dateHeader = formatter.string(from: date)
            }
            
            return MessageGroup(date: date, dateHeader: dateHeader, messages: messages.sorted { $0.timestamp < $1.timestamp })
        }
        .sorted { $0.date < $1.date }
    }
    
    private var emptyMessagesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 50))
                .foregroundColor(Color.slingBlue.opacity(0.3))
            
            Text("Start the conversation!")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
            
            Text("Be the first to share your thoughts with the community.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
    
    private var messageInputView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Type a message...", text: $messageText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(25)
                    .onTapGesture {
                        isKeyboardActive = true
                    }
                    .onSubmit {
                        sendMessage()
                    }
                
                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .slingBlue)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
        }
    }
        }



// MARK: - Community Info Modal

struct CommunityInfoModal: View {
    @Environment(\.dismiss) private var dismiss
    let community: FirestoreCommunity
    @ObservedObject var firestoreService: FirestoreService
    @State private var selectedTab = 0 // 0 = Bets, 1 = Members
    
    private var communityBets: [FirestoreBet] {
        return firestoreService.bets.filter { $0.community_id == (community.id ?? "") }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    // Community icon and name centered
                    VStack(spacing: 8) {
                        if let profileImageUrl = community.profile_image_url {
                            // Show custom community image
                            AsyncImage(url: URL(string: profileImageUrl)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle()
                                    .fill(AnyShapeStyle(Color.slingGradient))
                                    .overlay(
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    )
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                        } else {
                            // Show community initials
                        Circle()
                            .fill(AnyShapeStyle(Color.slingGradient))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text(String(community.name.prefix(1)).uppercased())
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                        }
                        
                        Text(community.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        
                        Text("\(community.member_count) members")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 30)
                
                // Tab selector
                Picker("", selection: $selectedTab) {
                    Text("Bets").tag(0)
                    Text("Leaderboard").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 16)
                
                // Content
                TabView(selection: $selectedTab) {
                    // Bets tab
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if communityBets.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "dice")
                                        .font(.system(size: 48))
                                        .foregroundColor(Color.slingBlue.opacity(0.6))
                                    
                                    Text("No Bets Yet")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.black)
                                    
                                    Text("Community bets will appear here")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                .padding(.top, 60)
                            } else {
                                ForEach(communityBets) { bet in
                                    EnhancedBetCardView(
                                        bet: bet,
                                        currentUserEmail: firestoreService.currentUser?.email,
                                        firestoreService: firestoreService,
                                        isCommunityNameClickable: true
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                    }
                    .tag(0)
                    
                    // Members tab
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(0..<community.member_count, id: \.self) { index in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.slingLightBlue)
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Text("M\(index + 1)")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.slingBlue)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Member \(index + 1)")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.black)
                                        

                                    }
                                    
                                    Spacer()
                                    
                                    if index == 0 {
                                        Text("Admin")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.orange.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                    }
                    .tag(1)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .background(Color.white)
            .navigationTitle("")
            .navigationBarHidden(true)
            .overlay(
                // Top right controls
                HStack(spacing: 12) {
                    // Do not disturb bell icon
                    Button(action: {
                        if let communityId = community.id {
                            firestoreService.toggleMuteForCommunity(communityId) { success in
                                if success {
                                    print("✅ Mute status toggled successfully")
                                } else {
                                    print("❌ Failed to toggle mute status")
                                }
                            }
                        }
                    }) {
                        Image(systemName: firestoreService.mutedCommunities.contains(community.id ?? "") ? "bell.slash.fill" : "bell.fill")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 32, height: 32)
                    }
                    
                    // Close button
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                }
                .padding(.top, 16)
                .padding(.trailing, 16),
                alignment: .topTrailing
            )
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: CommunityMessage
    let isCurrentUser: Bool
    
    var body: some View {
        HStack {
            if isCurrentUser { Spacer() }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isCurrentUser {
                    Text(message.senderName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.gray)
                }
                
                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(isCurrentUser ? .white : .black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isCurrentUser ? AnyShapeStyle(Color.slingGradient) : AnyShapeStyle(Color.white))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.15), lineWidth: isCurrentUser ? 0 : 1)
                    )
                
                Text(formatMessageTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: 250, alignment: isCurrentUser ? .trailing : .leading)
            
            if !isCurrentUser { Spacer() }
        }
    }
    
    private func formatMessageTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}



// MARK: - Bet Announcement Card

struct BetAnnouncementCard: View {
    let message: CommunityMessage
    let firestoreService: FirestoreService
    let onBetTap: () -> Void
    let onOptionTap: (String) -> Void
    
    @State private var bet: FirestoreBet?
    @State private var isLoading = true
    @State private var communityName: String = ""
    @State private var creatorFirstName: String = ""
    @State private var userFullNames: [String: String] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                // Loading state
                HStack {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Loading bet details...")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            } else if let bet = bet {
                // Bet image and details
                HStack(spacing: 8) {
                    // Bet image - smaller size
                    if let imageURL = bet.image_url, !imageURL.isEmpty {
                        AsyncImage(url: URL(string: imageURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 40, height: 40)
                                    .clipped()
                                    .cornerRadius(6)
                            case .failure(_):
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    )
                            case .empty:
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        ProgressView()
                                            .scaleEffect(0.5)
                                    )
                            @unknown default:
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 40, height: 40)
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bet.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            
                            Text(communityName)
                                .font(.caption2)
                                .foregroundColor(.gray)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            
                            Text("by \(creatorFirstName)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        
                        Text("Betting closes: \(formatDeadline(bet.deadline))")
                            .font(.caption2)
                            .foregroundColor(.slingBlue)
                    }
                    
                    Spacer()
                }
                
                // Betting options - stack vertically if more than 3 options
                VStack(spacing: 6) {
                    let displayOptions = bet.options.count > 3 ? Array(bet.options.prefix(3)) : bet.options
                    
                    ForEach(displayOptions, id: \.self) { option in
                        Button(action: {
                            onOptionTap(option)
                        }) {
                            HStack {
                                Text(option)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                                
                                Spacer()
                                
                                Text(bet.odds[option] ?? "-110")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.slingLightBlue)
                            .cornerRadius(6)
                        }
                    }
                    
                    // Show "view other options" if there are more than 3
                    if bet.options.count > 3 {
                        Button(action: {
                            onBetTap() // Navigate to bet details to see all options
                        }) {
                            HStack {
                                Text("View \(bet.options.count - 3) more options")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.slingBlue)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.slingBlue)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.slingLightBlue)
                            .cornerRadius(6)
                        }
                    }
                }
            } else {
                // Error state
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Could not load bet details")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            onBetTap()
        }
        .onAppear {
            loadBetDetails()
        }
    }
    
    private func loadBetDetails() {
        guard let betId = message.betId else {
            isLoading = false
            return
        }
        
        firestoreService.fetchBet(by: betId) { fetchedBet in
            DispatchQueue.main.async {
                self.bet = fetchedBet
                self.isLoading = false
                
                if let fetchedBet = fetchedBet {
                    // Get community name - first try userCommunities, then fetch from Firestore if needed
                    if let community = firestoreService.userCommunities.first(where: { $0.id == fetchedBet.community_id }) {
                        self.communityName = community.name
                    } else {
                        // If not in userCommunities, fetch the community directly
                        self.fetchCommunityName(communityId: fetchedBet.community_id)
                    }
                    
                    // Get creator's full name
                    self.creatorFirstName = getUserFullName(from: fetchedBet.creator_email)
                }
            }
        }
    }
    
    private func fetchCommunityName(communityId: String) {
        // Fetch community name directly from Firestore
        firestoreService.db.collection("community")
            .whereField("id", isEqualTo: communityId)
            .getDocuments { snapshot, _ in
                DispatchQueue.main.async {
                    if snapshot == nil {
                        self.communityName = "Community"
                        return
                    }
                    
                    if let document = snapshot?.documents.first,
                       let communityData = try? document.data(as: FirestoreCommunity.self) {
                        self.communityName = communityData.name
                    } else {
                        // Fallback to community ID if name can't be fetched
                        self.communityName = "Community"
                    }
                }
            }
    }
    
    private func extractFirstName(from email: String) -> String {
        // Try to get the first part of the email (before @)
        let emailPrefix = email.components(separatedBy: "@").first ?? email
        
        // If it contains dots or underscores, take the first part
        let firstName = emailPrefix.components(separatedBy: CharacterSet(charactersIn: "._")).first ?? emailPrefix
        
        // Capitalize first letter
        return firstName.prefix(1).uppercased() + firstName.dropFirst().lowercased()
    }
    
    // Function to get user's full name, with caching
    private func getUserFullName(from email: String) -> String {
        // Check cache first
        if let cachedName = userFullNames[email] {
            return cachedName
        }
        
        // For current user, use local data
        if let user = firestoreService.currentUser, user.email == email {
            let fullName = "\(user.first_name ?? "") \(user.last_name ?? "")".trimmingCharacters(in: .whitespaces)
            userFullNames[email] = fullName
            return fullName
        }
        
        // For other users, fetch from Firestore and cache
        firestoreService.getUserDetails(email: email) { fullName, _ in
            DispatchQueue.main.async {
                self.userFullNames[email] = fullName
            }
        }
        
        // Return first name as fallback while fetching
        return email.components(separatedBy: "@").first ?? email
    }
    
    private func formatDeadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d 'at' h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Bet Result Card

struct BetResultCard: View {
    let message: CommunityMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("🎯")
                    .font(.title3)
                
                Text("Bet Settled!")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
            
            Text(message.text)
                .font(.subheadline)
                .foregroundColor(.black)
            
            Text("Check your winnings! 💰")
                .font(.caption)
                .foregroundColor(.green)
                .fontWeight(.medium)
        }
        .padding(16)
        .background(Color.green.opacity(0.05))
        .cornerRadius(16)
    }
}








// MARK: - Place Bet View

struct PlaceBetView: View {
    let bet: FirestoreBet
    let presetOption: String? // Add preset option parameter
    @ObservedObject var firestoreService: FirestoreService
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedOption = ""
    @State private var betAmount = ""
    @State private var showingConfirmation = false
    @State private var isLoading = false
    @FocusState private var isBetAmountFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Bet Title
                VStack(alignment: .leading, spacing: 8) {
                    Text(bet.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text("Place your bet on this market")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    // Show selected option if preset
                    if let preset = presetOption, !preset.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Pre-selected: \(preset)")
                                .font(.subheadline)
                                .foregroundColor(.green)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                
                // Betting Options
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Your Pick")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    ForEach(Array(bet.options.enumerated()), id: \.offset) { index, option in
                        Button(action: {
                            selectedOption = option
                        }) {
                            HStack {
                                Text(option)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedOption == option ? .white : .black)
                                
                                Spacer()
                                
                                Text(bet.odds[option] ?? "-110")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedOption == option ? .white : .gray)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(selectedOption == option ? AnyShapeStyle(Color.slingGradient) : AnyShapeStyle(Color.gray.opacity(0.1)))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedOption == option ? Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)) : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                
                // Bet Amount
                VStack(alignment: .leading, spacing: 12) {
                    Text("Bet Amount")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    TextField("Enter amount", text: $betAmount)
                        .keyboardType(.decimalPad)
                        .focused($isBetAmountFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .onChange(of: betAmount) { _, newValue in
                            updateBetAmount(newValue)
                        }
                }
                .padding(.horizontal, 20)
                
                // Info about multiple bets
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)))
                    Text("You can place multiple bets on this market while it's open")
                        .font(.caption)
                        .foregroundColor(Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)))
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Place Bet Button
                Button(action: {
                    showingConfirmation = true
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Text("Place Bet")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedOption.isEmpty || betAmount.isEmpty ? AnyShapeStyle(Color.gray) : AnyShapeStyle(Color.slingGradient))
                    .cornerRadius(12)
                }
                .disabled(selectedOption.isEmpty || betAmount.isEmpty || isLoading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Place Bet")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if isLoading {
                            // Don't allow dismissal during bet placement
                            return
                        }
                        dismiss()
                    }
                    .disabled(isLoading)
                }
            }
            .onAppear {
                // Auto-select preset option if provided
                if let preset = presetOption, !preset.isEmpty {
                    selectedOption = preset
                }
                
                // Auto-focus the bet amount field after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isBetAmountFocused = true
                }
            }
            .interactiveDismissDisabled(isLoading) // Prevent dismissal during bet placement
        }
        .alert("Confirm Bet", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Place Bet") {
                placeBet()
            }
        } message: {
            Text("Are you sure you want to place a bet of \(formatCurrency(Double(betAmount) ?? 0)) Sling Points on '\(selectedOption)'?")
        }
    }
    
    private func placeBet() {
        guard let amount = Double(betAmount), amount > 0 else { 
            print("❌ Invalid bet amount: \(betAmount)")
            return 
        }
        
        // Validate amount is reasonable (between 1 and 10000 points)
        guard amount >= 1 && amount <= 10000 else {
            print("❌ Bet amount out of range: \(amount)")
            return
        }
        
        isLoading = true
        
        guard let betId = bet.id else { 
            print("❌ No bet ID found")
            isLoading = false
            return 
        }
        
        print("🎯 Placing bet: \(amount) points on '\(selectedOption)' for bet '\(bet.title)'")
        
        firestoreService.joinBet(
            betId: betId,
            chosenOption: selectedOption,
            stakeAmount: Int(amount) // Use points directly, not cents
        ) { success, error in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    print("✅ Bet placed successfully!")
                    // Add a small delay to ensure data is processed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    dismiss()
                    }
                } else {
                    print("❌ Error placing bet: \(error ?? "Unknown error")")
                }
            }
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
    
    private func updateBetAmount(_ newValue: String) {
        // Filter out non-numeric characters except decimal point
        let filtered = newValue.filter { "0123456789.".contains($0) }
        // Ensure only one decimal point
        let components = filtered.components(separatedBy: ".")
        if components.count > 2 {
            betAmount = String(components.prefix(2).joined(separator: "."))
        } else {
            betAmount = filtered
        }
    }
}

// MARK: - Choose Winner View

struct ChooseWinnerView: View {
    let bet: FirestoreBet
    @ObservedObject var firestoreService: FirestoreService
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedWinner = ""
    @State private var showingConfirmation = false
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Bet Title
                VStack(alignment: .leading, spacing: 8) {
                    Text(bet.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text("Select the winning outcome")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                
                // Betting Options
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Winner")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    ForEach(Array(bet.options.enumerated()), id: \.offset) { index, option in
                        Button(action: {
                            selectedWinner = option
                        }) {
                            HStack {
                                Text(option)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedWinner == option ? .white : .black)
                                
                                Spacer()
                                
                                Text(bet.odds[option] ?? "-110")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedWinner == option ? .white : .gray)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(selectedWinner == option ? AnyShapeStyle(Color.slingGradient) : AnyShapeStyle(Color.gray.opacity(0.1)))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Choose Winner Button
                Button(action: {
                    showingConfirmation = true
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Text("Choose Winner")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedWinner.isEmpty ? AnyShapeStyle(Color.gray) : AnyShapeStyle(Color.slingGradient))
                    .cornerRadius(12)
                }
                .disabled(selectedWinner.isEmpty || isLoading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Choose Winner")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Confirm Winner", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Choose Winner") {
                chooseWinner()
            }
        } message: {
            Text("Are you sure you want to select '\(selectedWinner)' as the winner? This will settle the bet and distribute winnings.")
        }
    }
    
    private func chooseWinner() {
        guard let betId = bet.id else { return }
        
        isLoading = true
        
        firestoreService.settleBet(betId: betId, winnerOption: selectedWinner) { success in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    dismiss()
                } else {
                    print("Error settling bet: Unknown error")
                }
            }
        }
    }
}

// MARK: - Communities View

struct CommunitiesView: View {
    let firestoreService: FirestoreService
    let onNavigateToHome: ((String) -> Void)?
    @State private var showingJoinCommunityModal = false
    @State private var showingCreateCommunityModal = false
    @State private var outstandingBalances: [OutstandingBalance] = []
    @State private var showingAllBalances = false
    
    
    var body: some View {
        ScrollView {
                    VStack(spacing: 16) {
                        // Communities Header
                        HStack {
                            Text("Communities")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Spacer()
                            
                            // Create/Join Community Button with Dropdown
                            Menu {
                                Button(action: { showingCreateCommunityModal = true }) {
                                    Label("Create Community", systemImage: "plus.circle")
                                }
                                
                                Button(action: { showingJoinCommunityModal = true }) {
                                    Label("Join Community", systemImage: "person.badge.plus")
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                    
                                                        Text("Add")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AnyShapeStyle(Color.slingGradient))
                                .cornerRadius(20)
                            }
                        }
                        .padding(.vertical, 12)
                        .background(Color.white)
                        
                        // Outstanding Balances Section
                        outstandingBalancesSection
                        
                        // Communities Section
                        communitiesSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100) // Space for bottom tab bar
        }
        .refreshable {
            await refreshData()
        }
        .background(Color.white)
        .onAppear {
            loadOutstandingBalances()
            firestoreService.fetchUserCommunities()
            updateCommunityStatistics()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            firestoreService.fetchUserCommunities()
            updateCommunityStatistics()
        }
        .sheet(isPresented: $showingJoinCommunityModal) {
            JoinCommunityPage(firestoreService: firestoreService)
        }
        .sheet(isPresented: $showingCreateCommunityModal) {
            CreateCommunityPage(firestoreService: firestoreService)
        }
        .sheet(isPresented: $showingAllBalances) {
            AllBalancesView(balances: outstandingBalances)
        }
    }
    

    
    // MARK: - Outstanding Balances Section
    private var outstandingBalancesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outstanding Balances")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
            
            // Main Outstanding Balances Card
            HStack(spacing: 16) {
                // Status Indicator (Left)
                HStack(spacing: 8) {
                    // Green checkmark circle
                    Circle()
                        .fill(Color.green)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundColor(.white)
                        )
                    
                    // Status text
                    Text("All Bets Settled 🎉")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                }
                
                Spacer()
                
                // View All button
                Button(action: {
                    showingAllBalances = true
                }) {
                    Text("View All")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    
    // MARK: - Communities Section
    private var communitiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
                                    if !firestoreService.userCommunities.isEmpty {
                HStack {
                    Text("Your Communities")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Text("\(firestoreService.userCommunities.count) communities")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    }
                
                // Horizontal line under Your Communities section
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1)
                
                
                LazyVStack(spacing: 16) {
                    ForEach(firestoreService.userCommunities) { community in
                        ModernCommunityCard(
                            community: community,
                            firestoreService: firestoreService,
                            onViewCommunity: onNavigateToHome
                        )
                    }
                }
                .padding(.top, 16) // Spacing after horizontal line
            } else {
                EmptyCommunitiesView(firestoreService: firestoreService)
            }
        }
    }
    
    
    // MARK: - Helper Methods
    private func getUserInitials() -> String {
        let user = firestoreService.currentUser
        if let firstName = user?.first_name, let lastName = user?.last_name, !firstName.isEmpty, !lastName.isEmpty {
            let firstInitial = String(firstName.prefix(1)).uppercased()
            let lastInitial = String(lastName.prefix(1)).uppercased()
            return "\(firstInitial)\(lastInitial)"
        } else if let displayName = user?.display_name, !displayName.isEmpty {
            let components = displayName.components(separatedBy: " ")
            if components.count >= 2 {
                let firstInitial = String(components[0].prefix(1)).uppercased()
                let lastInitial = String(components[1].prefix(1)).uppercased()
                return "\(firstInitial)\(lastInitial)"
            } else if components.count == 1 {
                return String(components[0].prefix(1)).uppercased()
            }
        } else if let email = user?.email {
            return String(email.prefix(1)).uppercased()
        }
        return "U"
    }
    
    private func loadOutstandingBalances() {
        // Fetch outstanding balances from Firestore
        firestoreService.fetchOutstandingBalances { balances in
            DispatchQueue.main.async {
                self.outstandingBalances = balances
                print("✅ Loaded \(balances.count) outstanding balances from Firestore")
            }
        }
    }
    
    private func updateCommunityStatistics() {
            for community in firestoreService.userCommunities {
                if let communityId = community.id {
                    firestoreService.updateCommunityStatistics(communityId: communityId) { success, error in
                        if let error = error {
                            print("❌ Error updating statistics for community \(communityId): \(error)")
                        }
                    }
                }
            }
        }
    
    private func refreshData() async {
            firestoreService.fetchUserCommunities()
        loadOutstandingBalances()
    }
}

// MARK: - Outstanding Balance Model

struct OutstandingBalance: Identifiable {
    let id: String
    let profilePicture: String?
    let username: String
    let name: String
    let netAmount: Double // Net amount (positive = they owe you, negative = you owe them)
    let transactions: [BalanceTransaction] // Individual transactions that make up this balance
    let counterpartyId: String // ID of the other user
    
    // Computed properties for easier use
    var isOwed: Bool { netAmount < 0 } // true = you owe them, false = they owe you
    var displayAmount: Double { abs(netAmount) }
    var isPositive: Bool { netAmount > 0 }
}

struct BalanceTransaction: Identifiable {
    let id: String
    let betId: String
    let betTitle: String
    let amount: Double
    let isOwed: Bool // true = you owe them, false = they owe you
    let date: Date
    let communityName: String
}

// MARK: - All Balances View

struct AllBalancesView: View {
    let balances: [OutstandingBalance]
    @Environment(\.dismiss) private var dismiss
    
    // Computed property for sorted balances to avoid complex inline sorting
    private var sortedBalances: [OutstandingBalance] {
        balances.sorted { first, second in
            if first.isOwed == second.isOwed {
                if first.isOwed {
                    return first.displayAmount < second.displayAmount
                } else {
                    return first.displayAmount > second.displayAmount
                }
            } else {
                return !first.isOwed && second.isOwed
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.gray)
                            .frame(width: 40, height: 40)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("Outstanding Balances")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    // Placeholder for balance
                    Color.clear
                        .frame(width: 40, height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Color.white)
                
                // Content
                if sortedBalances.isEmpty {
                    // Empty state when no balances
                    VStack(spacing: 20) {
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.slingBlue)
                        
                        Text("All Caught Up!")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        Text("You don't have any outstanding balances at the moment. Everyone is square!")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(sortedBalances) { balance in
                                DetailedBalanceRow(balance: balance)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                    }
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Detailed Balance Row

struct DetailedBalanceRow: View {
    let balance: OutstandingBalance
    @State private var showingResolutionModal = false
    @State private var showingBreakdownModal = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main balance row
            HStack(spacing: 16) {
            // Profile Picture
            if let profilePicture = balance.profilePicture, !profilePicture.isEmpty {
                AsyncImage(url: URL(string: profilePicture)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(AnyShapeStyle(Color.slingGradient))
                        .overlay(
                            Text(String(balance.name.prefix(1)).uppercased())
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(AnyShapeStyle(Color.slingGradient))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(String(balance.name.prefix(1)).uppercased())
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )
            }
            
            // User Info
            VStack(alignment: .leading, spacing: 6) {
                Text(balance.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                
                Text(balance.username)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Amount
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(balance.isOwed ? .red : .green)
                    
                        Text("\(String(format: "%.0f", balance.displayAmount))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(balance.isOwed ? .red : .green)
                }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (balance.isOwed ? Color.red : Color.green).opacity(0.1)
                    )
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 20)
            
            // Bet breakdown section
            VStack(spacing: 12) {
                // Bet breakdown header
                HStack {
                    Text("Breakdown")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text("\(balance.transactions.count) total")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 20)
                
                // Show up to 3 bets
                VStack(spacing: 8) {
                    ForEach(Array(balance.transactions.prefix(3)), id: \.id) { transaction in
                        BetBreakdownRow(transaction: transaction)
                    }
                    
                    // Show "View All" if there are more than 3 bets
                    if balance.transactions.count > 3 {
                        Button(action: {
                            showingBreakdownModal = true
                        }) {
                            HStack(spacing: 8) {
                                Text("View All \(balance.transactions.count) Bets")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.slingBlue)
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.slingBlue)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.slingBlue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .sheet(isPresented: $showingBreakdownModal) {
            BalanceBreakdownModal(balance: balance)
        }
        .onTapGesture {
            showingResolutionModal = true
        }
        .sheet(isPresented: $showingResolutionModal) {
            BalanceResolutionModal(balance: balance)
        }
    }
}

// MARK: - Bet Breakdown Row

struct BetBreakdownRow: View {
    let transaction: BalanceTransaction
    
    var body: some View {
        HStack(spacing: 12) {
            // Bet icon
            Circle()
                .fill(transaction.isOwed ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "list.bullet.clipboard")
                        .font(.caption)
                        .foregroundColor(transaction.isOwed ? .red : .green)
                )
            
            // Bet details
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.betTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.black)
                    .lineLimit(1)
                
                Text(transaction.communityName)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(transaction.isOwed ? .red : .green)
                    
                    Text("\(String(format: "%.0f", transaction.amount))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(transaction.isOwed ? .red : .green)
                }
                
                Text(transaction.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Balance Breakdown Modal

struct BalanceBreakdownModal: View {
    let balance: OutstandingBalance
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.gray)
                            .frame(width: 40, height: 40)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 4) {
                        Text("Balance Breakdown")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        Text("with \(balance.name)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Placeholder for balance
                    Color.clear
                        .frame(width: 40, height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Color.white)
                
                // Summary card
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        // Profile Picture
                        if let profilePicture = balance.profilePicture, !profilePicture.isEmpty {
                            AsyncImage(url: URL(string: profilePicture)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle()
                                    .fill(AnyShapeStyle(Color.slingGradient))
                                    .overlay(
                                        Text(String(balance.name.prefix(1)).uppercased())
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                    )
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(AnyShapeStyle(Color.slingGradient))
                                .frame(width: 64, height: 64)
                                .overlay(
                                    Text(String(balance.name.prefix(1)).uppercased())
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(balance.name)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Text(balance.username)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // Total amount
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                    .font(.title3)
                                    .foregroundColor(balance.isOwed ? .red : .green)
                                
                                Text("\(String(format: "%.0f", balance.displayAmount))")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(balance.isOwed ? .red : .green)
                            }
                            
                            Text("Total Balance")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                
                // All transactions list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(balance.transactions) { transaction in
                            DetailedBetBreakdownRow(transaction: transaction)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Detailed Bet Breakdown Row

struct DetailedBetBreakdownRow: View {
    let transaction: BalanceTransaction
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Bet icon
                Circle()
                    .fill(transaction.isOwed ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "list.bullet.clipboard")
                            .font(.title3)
                            .foregroundColor(transaction.isOwed ? .red : .green)
                    )
                
                // Bet details
                VStack(alignment: .leading, spacing: 6) {
                    Text(transaction.betTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    HStack(spacing: 8) {
                        Text(transaction.communityName)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text(transaction.date, style: .date)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Amount
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(String(format: "%.0f", transaction.amount))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(transaction.isOwed ? .red : .green)
                    
                    Text(transaction.isOwed ? "You Owe" : "They Owe")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(transaction.isOwed ? .red : .green)
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Outstanding Balance Card

struct OutstandingBalanceCard: View {
    let balance: OutstandingBalance
    @State private var showingResolutionModal = false
    
    var body: some View {
        Button(action: {
            showingResolutionModal = true
        }) {
            VStack(spacing: 12) {
            // Profile Picture
            if let profilePicture = balance.profilePicture, !profilePicture.isEmpty {
                AsyncImage(url: URL(string: profilePicture)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(AnyShapeStyle(Color.slingGradient))
                        .overlay(
                            Text(String(balance.name.prefix(1)).uppercased())
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(AnyShapeStyle(Color.slingGradient))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(String(balance.name.prefix(1)).uppercased())
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )
            }
            
            // User Info
            VStack(spacing: 4) {
                Text(balance.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .lineLimit(1)
                
                Text(balance.username)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            // Amount
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundColor(balance.isOwed ? .red : .green)
                
                Text("\(String(format: "%.0f", balance.displayAmount))")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(balance.isOwed ? .red : .green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (balance.isOwed ? Color.red : Color.green).opacity(0.1)
            )
            .cornerRadius(8)
            

            }
            .frame(width: 80)
            .padding(16)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingResolutionModal) {
            BalanceResolutionModal(balance: balance)
        }
    }
}

// MARK: - Balance Resolution Modal

struct BalanceResolutionModal: View {
    let balance: OutstandingBalance
    @Environment(\.dismiss) private var dismiss
    @State private var showingConfirmation = false
    @State private var isResolving = false
    @State private var paymentAmount: String = ""


    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.gray)
                            .frame(width: 40, height: 40)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("Settle Balance")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    // Placeholder for balance
                    Color.clear
                        .frame(width: 40, height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Color.white)
                
                // Content - Single Flow Design
                ScrollView {
                    VStack(spacing: 24) {
                        // 1. Balance Summary & Context
                        balanceSummarySection
                        
                        // 2. Bet Breakdown
                        betBreakdownSection
                        

                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100) // Space for sticky button
                }
                
                // Sticky Action Button
                stickyActionButton
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .alert(balance.isOwed ? "Mark as Paid" : "Mark as Received", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button(balance.isOwed ? "Mark as Paid" : "Mark as Received") {
                    resolveBalance()
                }
            } message: {
                Text(balance.isOwed ? 
                     "Are you sure you want to mark this balance as paid? This will remove it from your outstanding balances." :
                     "Are you sure you want to mark this balance as received? This will remove it from your outstanding balances.")
            }

        }
    }
    
    // MARK: - Balance Summary Section
    
    private var balanceSummarySection: some View {
        VStack(spacing: 16) {
            // Profile Picture and Name - Non-clickable
            VStack(spacing: 16) {
                VStack(spacing: 16) {
                    // Profile Picture
                    if let profilePicture = balance.profilePicture, !profilePicture.isEmpty {
                        AsyncImage(url: URL(string: profilePicture)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle()
                                .fill(AnyShapeStyle(Color.slingGradient))
                                .overlay(
                                    Text(String(balance.name.prefix(1)).uppercased())
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(AnyShapeStyle(Color.slingGradient))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Text(String(balance.name.prefix(1)).uppercased())
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                    }
                    
                    // User Info
                    VStack(spacing: 8) {
                        Text(balance.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        
                        Text(balance.username)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            // Amount Display
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.title2)
                    .foregroundColor(balance.isOwed ? .red : .green)
                
                Text("\(String(format: "%.0f", balance.displayAmount))")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(balance.isOwed ? .red : .green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                (balance.isOwed ? Color.red : Color.green).opacity(0.1)
            )
            .cornerRadius(16)
            
            // Context Message
            Text(balance.isOwed ? 
                 "You owe \(balance.name) from \(balance.transactions.count) bet\(balance.transactions.count == 1 ? "" : "s")" :
                 "\(balance.name) owes you from \(balance.transactions.count) bet\(balance.transactions.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Bet Breakdown Section
    
    private var betBreakdownSection: some View {
        VStack(spacing: 16) {
            // Section Header
            HStack {
                Text("Breakdown")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // Bet Transactions
            LazyVStack(spacing: 12) {
                ForEach(balance.transactions) { transaction in
                    BalanceTransactionRow(transaction: transaction)
                }
            }
        }
        .padding(.horizontal, 4)
    }
    

    
    // MARK: - Sticky Action Button
    
    private var stickyActionButton: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.gray.opacity(0.2))
            
            Button(action: {
                showingConfirmation = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                    Text(balance.isOwed ? "Mark as Paid" : "Mark as Received")
                        .foregroundColor(.white)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AnyShapeStyle(Color.slingGradient))
                .cornerRadius(16)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white)
        }
    }
    
    // MARK: - Helper Functions
    
    private func resolveBalance() {
        isResolving = true
        
        // Simulate API call
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isResolving = false
            dismiss()
            
            // Show success feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }
    }
}

// MARK: - Balance Transaction Row

struct BalanceTransactionRow: View {
    let transaction: BalanceTransaction
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.betTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .lineLimit(2)
                    
                    Text(transaction.communityName)
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text(formatDate(transaction.date))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundColor(transaction.isOwed ? .red : .green)
                        
                        Text("\(String(format: "%.0f", transaction.amount))")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(transaction.isOwed ? .red : .green)
                    }
                    

                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Community Card with Admin Status

struct CommunityCardWithAdmin: View {
    let community: FirestoreCommunity
    let firestoreService: FirestoreService
    let onViewCommunity: ((String) -> Void)?
    @State private var isAdmin: Bool = false
    
    var body: some View {
        CommunityCard(
            community: community,
            isAdmin: isAdmin,
            firestoreService: firestoreService,
            onViewCommunity: onViewCommunity
        )
        .onAppear {
            checkAdminStatus()
        }
    }
    
    private func checkAdminStatus() {
        guard let userEmail = firestoreService.currentUser?.email else { return }
        firestoreService.isUserAdminInCommunity(communityId: community.id ?? "", userEmail: userEmail) { adminStatus in
            DispatchQueue.main.async {
                self.isAdmin = adminStatus
            }
        }
    }
}

// MARK: - Modern Community Card

struct ModernCommunityCard: View {
    let community: FirestoreCommunity
    let firestoreService: FirestoreService
    let onViewCommunity: ((String) -> Void)?
    @State private var showingCommunityDetail = false
    @State private var isAdmin: Bool = false
    
    var body: some View {
        Button(action: {
            showingCommunityDetail = true
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with community info and admin badge
                HStack(alignment: .center, spacing: 10) {
                    // Community Avatar
                    if let profileImageUrl = community.profile_image_url {
                        // Show custom community image
                        AsyncImage(url: URL(string: profileImageUrl)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle()
                                .fill(AnyShapeStyle(Color.slingGradient))
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                )
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    } else {
                        // Show community initials
                    Circle()
                        .fill(AnyShapeStyle(Color.slingGradient))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(String(community.name.prefix(1)).uppercased())
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(community.name)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            // Crown icon for admin users
                            if isAdmin {
                                Image(systemName: "crown.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                        }
            
                        // Community stats - greyed out for less importance
                        HStack(spacing: 12) {
                HStack(spacing: 4) {
                                Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                                Text("\(community.member_count)")
                                    .font(.caption)
                        .foregroundColor(.gray)
                                Text("members")
                                    .font(.caption)
                        .foregroundColor(.gray)
                }
                
                HStack(spacing: 4) {
                                Image(systemName: "list.bullet.clipboard")
                        .font(.caption)
                        .foregroundColor(.gray)
                                Text("\(community.total_bets)")
                                    .font(.caption)
                        .foregroundColor(.gray)
                                Text("bets")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Right Arrow
                    Image(systemName: "chevron.right")
                            .font(.subheadline)
                                    .foregroundColor(.gray)
                            .frame(width: 20, height: 20)
                }
                

            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
                    }
                    .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingCommunityDetail) {
            EnhancedCommunityDetailView(
                community: community, 
                firestoreService: firestoreService,
                onChatTap: {
                    // Navigate to chat for this community
                    // This will be handled by the parent view
                }
            )
        }
        .onAppear {
            checkAdminStatus()
        }
    }
    
    private func checkAdminStatus() {
        guard let userEmail = firestoreService.currentUser?.email else { return }
        firestoreService.isUserAdminInCommunity(communityId: community.id ?? "", userEmail: userEmail) { adminStatus in
            DispatchQueue.main.async {
                self.isAdmin = adminStatus
            }
        }
    }
}

// MARK: - Community Card

struct CommunityCard: View {
    let community: FirestoreCommunity
    let isAdmin: Bool
    let firestoreService: FirestoreService
    let onViewCommunity: ((String) -> Void)?
    @State private var showingCommunityDetail = false
    @State private var showingShareSheet = false
    @State private var showingSettingsModal = false
    
    var body: some View {
        Button(action: {
            showingCommunityDetail = true
        }) {
        VStack(alignment: .leading, spacing: 12) {
            // Header with Admin Badge and Three Dots Menu
            HStack {
                Text(community.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                Spacer()
                
                if isAdmin {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundColor(.purple)
                        Text("Admin")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.purple)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.purple, lineWidth: 1)
                    )
                }
                
                // Three Dots Menu
                Menu {
                    Button(action: {
                        UIPasteboard.general.string = community.invite_code
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }) {
                            Label("Copy Invite Code", systemImage: "list.bullet.clipboard")
                    }
                    
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        Label("Share Community", systemImage: "square.and.arrow.up")
                    }
                    
                    if isAdmin {
                    Button(action: {
                        showingSettingsModal = true
                    }) {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    
                    Button(action: {
                        onViewCommunity?(community.name)
                    }) {
                        Label("View Community", systemImage: "arrow.up.right.square")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .frame(width: 24, height: 24)
                }
            }
            
            // Statistics
            HStack(spacing: 16) {
                        HStack(spacing: 4) {
                    Image(systemName: "person.2")
                                .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(community.member_count) members")
                                .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(community.total_bets) bets")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            // Footer with creation date
            HStack {
                Text("Created \(formatDate(community.created_date))")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingCommunityDetail) {
            EnhancedCommunityDetailView(
                community: community, 
                firestoreService: firestoreService,
                onChatTap: {
                    // Navigate to chat for this community
                    // This will be handled by the parent view
                }
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: ["Join my community on Sling! Use invite code: \(community.invite_code)"])
        }
        .sheet(isPresented: $showingSettingsModal) {
            CommunitySettingsView(community: community, isAdmin: isAdmin, firestoreService: firestoreService)
        }
    }
    

}

// MARK: - Create View

struct CreateView: View {
    let firestoreService: FirestoreService
    @State private var showingCreateBetModal = false
    @State private var showingCreateCommunityModal = false
    @State private var showingJoinCommunityModal = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Create Options
                VStack(spacing: 16) {
                    // Create Bet Option
                    Button(action: {
                        if firestoreService.userCommunities.isEmpty {
                            showingCreateCommunityModal = true
                        } else {
                            showingCreateBetModal = true
                        }
                    }) {
                        HStack(spacing: 16) {
                            Circle()
                                .fill(Color.slingLightBlue)
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .font(.title2)
                                        .foregroundColor(.slingBlue)
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Create Bet")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Text("Start a new prediction market")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    }
                    .disabled(firestoreService.userCommunities.isEmpty)
                    
                    // Create Community Option
                    Button(action: {
                        showingCreateCommunityModal = true
                    }) {
                        HStack(spacing: 16) {
                            Circle()
                                .fill(Color.slingLightPurple)
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Image(systemName: "person.2")
                                        .font(.title2)
                                        .foregroundColor(.slingPurple)
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Create Community")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Text("Start a new betting group")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    }
                    
                    // Join Community Option
                    Button(action: {
                        showingJoinCommunityModal = true
                    }) {
                        HStack(spacing: 16) {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Image(systemName: "person.badge.plus")
                                        .font(.title2)
                                        .foregroundColor(.green)
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Join Community")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Text("Join an existing community")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    }
                }
                .padding(.horizontal, 16)
                
                // Info Section
                if firestoreService.userCommunities.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                        
                        Text("You need to join or create a community before you can create bets.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .background(Color.slingLightBlue)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }
            }
            .refreshable {
                // Refresh data when user pulls down
                await refreshData()
            }
            .padding(.bottom, 100)
        }
        .background(Color.white)
        .onAppear {
            firestoreService.fetchUserCommunities()
        }
        .sheet(isPresented: $showingCreateBetModal) {
            CreateBetView(firestoreService: firestoreService, preSelectedCommunity: nil)
        }
        .sheet(isPresented: $showingCreateCommunityModal) {
            CreateCommunityPage(firestoreService: firestoreService, onSuccess: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Navigate to communities tab
                }
            })
        }
        .sheet(isPresented: $showingJoinCommunityModal) {
            JoinCommunityPage(firestoreService: firestoreService, onSuccess: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Navigate to communities tab
                }
            })
        }
    }
    
    private func refreshData() async {
        // Fetch fresh data from Firestore
        firestoreService.fetchUserCommunities()
    }
}

// MARK: - Community Settings View

struct CommunitySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let community: FirestoreCommunity
    let isAdmin: Bool
    @ObservedObject var firestoreService: FirestoreService
    @State private var selectedTab = 0 // 0 = General, 1 = Members
    @State private var communityName: String
    @State private var isEditingName = false
    @State private var showingShareSheet = false
    @State private var members: [CommunityMemberInfo] = []
    @State private var isLoading = false
    
    init(community: FirestoreCommunity, isAdmin: Bool, firestoreService: FirestoreService) {
        self.community = community
        self.isAdmin = isAdmin
        self.firestoreService = firestoreService
        self._communityName = State(initialValue: community.name)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab Bar
                HStack(spacing: 0) {
                    Button(action: { selectedTab = 0 }) {
                        Text("General")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(selectedTab == 0 ? .black : .gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selectedTab == 0 ? Color.white : Color(.systemGray6))
                    }
                    
                    Button(action: { selectedTab = 1 }) {
                        Text("Members")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(selectedTab == 1 ? .black : .gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selectedTab == 1 ? Color.white : Color(.systemGray6))
                    }
                }
                .background(Color(.systemGray6))
                
                // Content
                if selectedTab == 0 {
                    GeneralSettingsTab(community: community, isAdmin: isAdmin, firestoreService: firestoreService, communityName: $communityName, isEditingName: $isEditingName, showingShareSheet: $showingShareSheet)
                } else {
                    MembersTab(community: community, isAdmin: isAdmin, firestoreService: firestoreService, members: $members, isLoading: $isLoading)
                }
            }
            .navigationTitle("Community Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadMembers()
        }
    }
    
    private func loadMembers() {
        isLoading = true
        firestoreService.fetchCommunityMembers(communityId: community.id ?? "") { fetchedMembers in
            DispatchQueue.main.async {
                self.members = fetchedMembers
                self.isLoading = false
            }
        }
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    let community: FirestoreCommunity
    let isAdmin: Bool
    let firestoreService: FirestoreService
    @Binding var communityName: String
    @Binding var isEditingName: Bool
    @Binding var showingShareSheet: Bool
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var showingCopyFeedback = false
    @State private var showingDeleteAlert = false
    @State private var showingLeaveAlert = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Community Name Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Community Name")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        Spacer()
                        
                        if isAdmin {
                            Button(action: {
                                isEditingName.toggle()
                            }) {
                                Text(isEditingName ? "Cancel" : "Edit")
                                    .font(.subheadline)
                                    .foregroundColor(.slingBlue)
                            }
                        }
                    }
                    
                    if isEditingName {
                        VStack(spacing: 8) {
                            HStack {
                                TextField("Community Name", text: $communityName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                Button("Save") {
                                    saveCommunityName()
                                }
                                .foregroundColor(.slingBlue)
                                .disabled(communityName.isEmpty || isSaving)
                            }
                            
                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    } else {
                        Text(communityName)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Invite Code Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Invite Code")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center) {
                            Text(community.invite_code)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Spacer()
                            
                            Button(action: {
                                UIPasteboard.general.string = community.invite_code
                                // Provide haptic feedback
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                
                                // Show copy feedback
                                showingCopyFeedback = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    showingCopyFeedback = false
                                }
                            }) {
                                ZStack {
                                    if showingCopyFeedback {
                                        // Show checkmark when copied
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.green)
                                    } else {
                                        // Show copy icon
                                Image(systemName: "list.bullet.clipboard")
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        
                        Text("Share this code with friends to invite them to your community.")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Button(action: {
                            showingShareSheet = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share Invite Code")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.slingGradient)
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal, 16)
                
                // Community Stats Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Community Stats")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    VStack(spacing: 8) {
                        HStack {
                            Text("Members")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(community.member_count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                        }
                        
                        HStack {
                            Text("Total Bets")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(community.total_bets)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                        }
                        
                        HStack {
                            Text("Created")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(formatDate(community.created_date))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                        }
                        
                        HStack {
                            Text("Status")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(community.is_active == true ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(community.is_active == true ? "Active" : "Inactive")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 16)
                
                // Actions Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Actions")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    VStack(spacing: 0) {
                        if isAdmin {
                            // Admin-only: Delete Community
                            Button(action: {
                                showDeleteCommunityAlert()
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                        .font(.title3)
                                        .foregroundColor(.red)
                                        .frame(width: 24, height: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Delete Community")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.red)
                                        Text("Permanently delete this community for all members")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Divider()
                                .padding(.horizontal, 12)
                        }
                        
                        // Leave Community (available to all members)
                        Button(action: {
                            showLeaveCommunityAlert()
                        }) {
                            HStack {
                                Image(systemName: "person.badge.minus")
                                    .font(.title3)
                                    .foregroundColor(.orange)
                                    .frame(width: 24, height: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Leave Community")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.orange)
                                    Text("You can rejoin later using the invite code")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 20)
        }
        .background(Color.white)
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: ["Join my community on Sling! Use invite code: \(community.invite_code)"])
        }
        .alert("Leave Community", isPresented: $showingLeaveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                leaveCommunity()
            }
        } message: {
            Text("Are you sure you want to leave this community? You can rejoin later using the invite code.")
        }
        .alert("Delete Community", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCommunity()
            }
        } message: {
            Text("Are you sure you want to delete this community? This action cannot be undone and all data will be permanently lost.")
        }
    }
    
    private func showLeaveCommunityAlert() {
        showingLeaveAlert = true
    }
    
    private func showDeleteCommunityAlert() {
        showingDeleteAlert = true
    }
    
    private func leaveCommunity() {
        guard let userEmail = firestoreService.currentUser?.email else { return }
        
        firestoreService.leaveCommunity(communityId: community.id ?? "", userEmail: userEmail) { success in
            DispatchQueue.main.async {
                if success {
                    SlingLogInfo("User left community: \(self.community.name)")
                    // Dismiss the settings view
                    dismiss()
                }
            }
        }
    }
    
    private func deleteCommunity() {
        firestoreService.deleteCommunity(communityId: community.id ?? "") { success in
            DispatchQueue.main.async {
                if success {
                    SlingLogInfo("Admin deleted community: \(self.community.name)")
                    // Dismiss the settings view
                    dismiss()
                }
            }
        }
    }
    
    private func saveCommunityName() {
        guard !communityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Community name cannot be empty"
            return
        }
        
        isSaving = true
        errorMessage = ""
        
        firestoreService.updateCommunityName(communityId: community.id ?? "", newName: communityName.trimmingCharacters(in: .whitespacesAndNewlines)) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    isEditingName = false
                } else {
                    errorMessage = "Failed to update community name"
                }
            }
        }
    }
}

// MARK: - Members Tab

struct MembersTab: View {
    let community: FirestoreCommunity
    let isAdmin: Bool
    let firestoreService: FirestoreService
    @Binding var members: [CommunityMemberInfo]
    @Binding var isLoading: Bool
    @State private var showingShareSheet = false
    @State private var memberToKick: CommunityMemberInfo?
    @State private var showingKickAlert = false
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(members, id: \.email) { member in
                        HStack(spacing: 12) {
                            // Profile Picture
                            Circle()
                                .fill(Color.slingGradient)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(String(member.name.prefix(1)).uppercased())
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(member.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.black)
                                    
                                    if member.isAdmin {
                                        HStack(spacing: 4) {
                                            Image(systemName: "crown.fill")
                                                .font(.caption)
                                                .foregroundColor(.slingPurple)
                                            Text("Admin")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.slingPurple)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.slingPurple.opacity(0.1))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.slingPurple, lineWidth: 0.5)
                                        )
                                    }
                                }
                                
                                Text(member.email)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            if isAdmin && !member.isAdmin && member.email != firestoreService.currentUser?.email {
                                Button(action: {
                                    memberToKick = member
                                    showingKickAlert = true
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(8)
                                        .background(Color.red.opacity(0.1))
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Share Button at bottom
                    Section {
                        Button(action: {
                            showingShareSheet = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.title3)
                                    .foregroundColor(.slingBlue)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Share Community")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.black)
                                    Text("Invite friends to join")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .background(Color.white)
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: ["Join my community on Sling! Use invite code: \(community.invite_code)"])
        }
        .alert("Remove Member", isPresented: $showingKickAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                if let member = memberToKick {
                    kickMember(member)
                }
            }
        } message: {
            if let member = memberToKick {
                Text("Are you sure you want to remove \(member.name) from this community? They can rejoin later using the invite code.")
            }
        }
    }
    
    private func kickMember(_ member: CommunityMemberInfo) {
        firestoreService.kickMemberFromCommunity(communityId: community.id ?? "", memberEmail: member.email) { success in
            DispatchQueue.main.async {
                if success {
                    // Remove member from local list
                    members.removeAll { $0.email == member.email }
                    SlingLogInfo("Admin removed member from community", file: #file, function: #function, line: #line)
                }
                memberToKick = nil
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Profile View

struct ProfileView: View {
    let firestoreService: FirestoreService
    @Binding var showingEditProfile: Bool
    @State private var selectedCommunity: FirestoreCommunity?
    @State private var showingCommunityDetail = false
    
    private func getUserInitials() -> String {
        let user = firestoreService.currentUser
        if let firstName = user?.first_name, let lastName = user?.last_name, !firstName.isEmpty, !lastName.isEmpty {
            let firstInitial = String(firstName.prefix(1)).uppercased()
            let lastInitial = String(lastName.prefix(1)).uppercased()
            return "\(firstInitial)\(lastInitial)"
        } else if let displayName = user?.display_name, !displayName.isEmpty {
            let components = displayName.components(separatedBy: " ")
            if components.count >= 2 {
                let firstInitial = String(components[0].prefix(1)).uppercased()
                let lastInitial = String(components[1].prefix(1)).uppercased()
                return "\(firstInitial)\(lastInitial)"
            } else if components.count == 1 {
                return String(components[0].prefix(1)).uppercased()
            }
        } else if let email = user?.email {
            return String(email.prefix(1)).uppercased()
        }
        return "U"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile Information Card
                VStack(spacing: 24) {
                    // Profile Summary
                    HStack(spacing: 16) {
                        // Profile Picture or Initials
                        if let profilePictureUrl = firestoreService.currentUser?.profile_picture_url {
                            // Show user's profile picture
                            AsyncImage(url: URL(string: profilePictureUrl)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 64, height: 64)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 4)
                                        )
                                case .failure(_):
                                    // Fallback to initials on error
                                    Circle()
                                        .fill(Color.slingGradient)
                                        .frame(width: 64, height: 64)
                                        .overlay(
                                            Text(getUserInitials())
                                                .font(.title2)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 4)
                                        )
                                case .empty:
                                    // Show initials while loading
                                    Circle()
                                        .fill(Color.slingGradient)
                                        .frame(width: 64, height: 64)
                                        .overlay(
                                            Text(getUserInitials())
                                                .font(.title2)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 4)
                                        )
                                @unknown default:
                                    Circle()
                                        .fill(Color.slingGradient)
                                        .frame(width: 64, height: 64)
                                        .overlay(
                                            Text(getUserInitials())
                                                .font(.title2)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 4)
                                        )
                                }
                            }
                        } else {
                            // Fallback to initials
                            Circle()
                                .fill(Color.slingGradient)
                            .frame(width: 64, height: 64)
                            .overlay(
                                Text(getUserInitials())
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 4)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(firestoreService.currentUser?.display_name ?? "User")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                
                                // Small Edit Profile Button
                                Button(action: {
                                    showingEditProfile = true
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.title3)
                                        .foregroundColor(.slingBlue)
                                        .frame(width: 32, height: 32)
                                        .background(Color.slingLightBlue)
                                        .clipShape(Circle())
                                }
                            }
                            
                            Text(firestoreService.currentUser?.email ?? "user@example.com")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                    

                }
                
                // Points Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.slingBlue)
                                .font(.title3)
                            Text("Points")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        Spacer()
                        
                        Menu {
                            Button("All Communities Overview") {
                                // This will show overview of all communities combined
                            }
                            ForEach(firestoreService.userCommunities, id: \.id) { community in
                                Button(community.name) {
                                    // This will filter to show specific community
                                }
                            }
                        } label: {
                            HStack {
                                Text("All Communities Overview")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Total Winnings Card
                    VStack(spacing: 12) {
                        HStack {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.slingGradient)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                    )
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Total Winnings")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.black)
                                    
                                    Text("Across all communities")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.slingBlue)
                                    .font(.title3)
                                Text("0.00")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .background(Color.slingLightBlue)
                        .cornerRadius(16)
                    }
                    .padding(.horizontal, 16)
                    
                    // Community Balances
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Balance by Community")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                        
                        LazyVStack(spacing: 8) {
                            ForEach(firestoreService.userCommunities, id: \.id) { community in
                                Button(action: {
                                    selectedCommunity = community
                                    showingCommunityDetail = true
                                }) {
                                    HStack {
                                        Text(community.name)
                                            .font(.subheadline)
                                            .foregroundColor(.black)
                                        
                                        Spacer()
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: "bolt.fill")
                                                .foregroundColor(.slingBlue)
                                                .font(.caption)
                                            Text("0.00")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.black)
                                        }
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
                
                Spacer()
            }
        }
        .background(Color.white)
        .onAppear {
            // loadCommunityBalances()
        }
        .refreshable {
            // loadCommunityBalances()
        }
        .sheet(isPresented: $showingCommunityDetail) {
            if let community = selectedCommunity {
                CommunityDetailView(
                    community: community,
                    firestoreService: firestoreService
                )
            }
        }
    }
    

}

// MARK: - User Activity Models and Views

enum UserActivityType {
    case betPlaced
    case betWon
    case betLost
    case betCreated
    case communityJoined
}

struct UserActivityItem: Identifiable {
    let id: String
    let type: UserActivityType
    let title: String
    let subtitle: String
    let communityName: String?
    let timestamp: Date
    let icon: String
    let iconColor: Color
}

struct ActivityRow: View {
    let activityItem: UserActivityItem
    
    private func formatTimestamp(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "Just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h ago"
        } else if timeInterval < 2592000 {
            let days = Int(timeInterval / 86400)
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Activity Icon
            ZStack {
                Circle()
                    .fill(activityItem.iconColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: activityItem.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(activityItem.iconColor)
            }
            
            // Activity Content
            VStack(alignment: .leading, spacing: 6) {
                Text(activityItem.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                
                Text(activityItem.subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(formatTimestamp(activityItem.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let communityName = activityItem.communityName {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "person.2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(communityName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }
}

// MARK: - Community Balance Row

struct CommunityBalanceRow: View {
    let name: String
    let balance: String
    
    var body: some View {
        HStack {
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.black)
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundColor(.slingBlue)
                Text(balance)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.black)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }
}

// MARK: - Community Detail View

struct CommunityDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let community: FirestoreCommunity
    let firestoreService: FirestoreService
    @State private var members: [CommunityMemberInfo] = []
    @State private var isLoading = false
    @State private var showingTransactionHistory = false
    @State private var selectedMember: CommunityMemberInfo?
    @State private var userBalance: Double = 0.0
    @State private var memberBalances: [String: Double] = [:]
    @State private var hasLoadedBalances = false
    
    // Computed property to sort members by activity/balance
    private var sortedMembers: [CommunityMemberInfo] {
        return members.sorted { member1, member2 in
            let balance1 = memberBalances[member1.email] ?? 0.0
            let balance2 = memberBalances[member2.email] ?? 0.0
            
            // First: Members who owe you money (positive balances) - highest first
            if balance1 > 0 && balance2 <= 0 {
                return true
            } else if balance1 <= 0 && balance2 > 0 {
                return false
            } else if balance1 > 0 && balance2 > 0 {
                return balance1 > balance2
            }
            
            // Second: Members you owe money to (negative balances) - least debt first (closer to 0)
            else if balance1 < 0 && balance2 < 0 {
                return balance1 > balance2  // -10 comes before -20
            }
            
            // Third: Members with zero balance (least active) - alphabetical order
            else {
                return member1.name < member2.name
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with back button and dropdown
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.title3)
                                .foregroundColor(.black)
                        }
                        
                        Spacer()
                        
                        Menu {
                            Button("All Members") {
                                // Filter action
                            }
                            Button("Active Bets") {
                                // Filter action
                            }
                            Button("Settled Bets") {
                                // Filter action
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(community.name)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    // Subtitle
                    Text("Your balance in \(community.name)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                    
                    // Your Balance Card
                    VStack(spacing: 12) {
                        HStack {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.slingLightBlue)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "person.2")
                                            .font(.title3)
                                            .foregroundColor(.slingBlue)
                                    )
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Your Balance")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.black)
                                    Text(firestoreService.currentUser?.email ?? "user@example.com")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.caption)
                                    .foregroundColor(.slingBlue)
                                if userBalance == 0.0 && isLoading {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 60, height: 16)
                                } else {
                                    Text(formatBalance(userBalance))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(userBalance >= 0 ? .black : .red)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.slingLightBlue)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    
                    // Check if there are any transactions
                    if hasLoadedBalances && memberBalances.values.allSatisfy({ $0 == 0.0 }) && userBalance == 0.0 {
                        // No transactions exist - show clear message
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 48))
                                .foregroundColor(Color.slingBlue.opacity(0.6))
                            
                            Text("No transactions yet")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                            
                            Text("Bets and settlements will appear here once you start predicting in this community.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 40)
                        .padding(.horizontal, 16)
                    } else if isLoading {
                        // Loading state
                        VStack(spacing: 16) {
                            ForEach(0..<min(3, members.count), id: \.self) { index in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 32, height: 32)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 100, height: 14)
                                        
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 150, height: 12)
                                    }
                                    
                                    Spacer()
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 60, height: 16)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                    } else if !members.isEmpty {
                        // Member Balances List
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Member Balances")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 16)
                            
                            VStack(spacing: 0) {
                                ForEach(sortedMembers, id: \.email) { member in
                                    Button(action: {
                                        selectedMember = member
                                        showingTransactionHistory = true
                                    }) {
                                        MemberBalanceRow(
                                            member: member,
                                            balance: formatBalance(memberBalances[member.email] ?? 0.0)
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    if member.email != sortedMembers.last?.email {
                                        Divider()
                                            .padding(.leading, 16)
                                    }
                                }
                            }
                            .background(Color.white)
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .onAppear {
                loadMembers()
                loadBalances()
            }
            .sheet(isPresented: $showingTransactionHistory) {
                if let member = selectedMember {
                    TransactionHistoryView(
                        community: community,
                        member: member,
                        firestoreService: firestoreService
                    )
                }
            }
        }
    }
    
    private func loadMembers() {
        isLoading = true
        firestoreService.fetchCommunityMembers(communityId: community.id ?? "") { fetchedMembers in
            DispatchQueue.main.async {
                self.members = fetchedMembers
                self.isLoading = false
            }
        }
    }
    
    private func loadBalances() {
        guard let userEmail = firestoreService.currentUser?.email else { return }
        isLoading = true
        hasLoadedBalances = false
        
        // Load user's balance
        firestoreService.calculateNetBalance(
            communityId: community.id ?? "", 
            userEmail: userEmail
        ) { balance in
            DispatchQueue.main.async {
                self.userBalance = balance
                
                // Load member balances
                self.firestoreService.calculateMemberBalances(
                    communityId: self.community.id ?? ""
                ) { balances in
                    DispatchQueue.main.async {
                        self.memberBalances = balances
                        self.isLoading = false
                        self.hasLoadedBalances = true
                    }
                }
            }
        }
        
        // Load all member balances
        let memberEmails = members.map { $0.email }
        let group = DispatchGroup()
        
        for memberEmail in memberEmails {
            group.enter()
            firestoreService.calculateNetBalance(
                communityId: community.id ?? "", 
                userEmail: memberEmail
            ) { balance in
                DispatchQueue.main.async {
                    self.memberBalances[memberEmail] = balance
                }
                group.leave()
            }
        }
        
        // Mark as loaded when all balances are calculated
        group.notify(queue: .main) {
            self.hasLoadedBalances = true
        }
    }
    
    private func formatBalance(_ balance: Double) -> String {
        let prefix = balance >= 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.2f", balance))"
    }
}

// MARK: - Member Balance Row

struct MemberBalanceRow: View {
    let member: CommunityMemberInfo
    let balance: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile Picture
            Circle()
                .fill(Color.slingGradient)
                .frame(width: 32, height: 32)
                .overlay(
                    Text(String(member.name.prefix(1)).uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.black)
                
                Text(member.email)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundColor(.slingBlue)
                Text(balance)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.black)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }
}

// MARK: - Transaction History View

struct TransactionHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let community: FirestoreCommunity
    let member: CommunityMemberInfo
    let firestoreService: FirestoreService
    @State private var transactions: [TransactionItem] = []
    @State private var isLoading = false
    @State private var netBalance: Double = 0.0
    
    private func loadTransactionHistory() {
        isLoading = true
        guard let currentUserEmail = firestoreService.currentUser?.email else { return }
        
        firestoreService.fetchTransactions(communityId: community.id ?? "", userEmail: currentUserEmail) { fetchedTransactions in
            // For now, show all transactions for the current user in this community
            // In the future, this could be enhanced to show transactions between specific users
            let transformedTransactions = fetchedTransactions.map { transaction in
                TransactionItem(
                    type: transaction.final_payout != nil ? .settlement : .bet,
                    amount: transaction.final_payout != nil ? Double(transaction.final_payout!) : -Double(transaction.stake_amount),
                    description: "Bet on \(transaction.chosen_option)",
                    date: transaction.created_date,
                    betTitle: nil,
                    isWin: transaction.final_payout != nil && transaction.final_payout! > 0
                )
            }
            
            DispatchQueue.main.async {
                self.transactions = transformedTransactions
                self.netBalance = transformedTransactions.reduce(0.0) { $0 + $1.amount }
                self.isLoading = false
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.title3)
                            .foregroundColor(.black)
                    }
                    
                    Spacer()
                    
                    Text("Transaction History")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    // Placeholder for balance
                    Text("")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Member Info
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.slingGradient)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(String(member.name.prefix(1)).uppercased())
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                            Text(member.email)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    
                    // Net Balance
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundColor(.slingBlue)
                        Text("Net Balance: \(formatBalance(netBalance))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(netBalance >= 0 ? .black : .red)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
                .background(Color.white)
                
                // Transactions List
                if isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                    Spacer()
                } else if transactions.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(Color.slingBlue.opacity(0.6))
                        
                        Text("No transactions yet")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        Text("Bets and settlements will appear here")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(transactions) { transaction in
                                TransactionRow(transaction: transaction)
                                
                                if transaction.id != transactions.last?.id {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .onAppear {
                loadTransactionHistory()
            }
        }
    }

    
    private func transactionTypeFromString(_ type: String) -> TransactionType {
        switch type.lowercased() {
        case "bet":
            return .bet
        case "settlement":
            return .settlement
        case "refund":
            return .refund
        default:
            return .bet
        }
    }
    
    private func formatBalance(_ balance: Double) -> String {
        let prefix = balance >= 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.2f", balance))"
    }
}

// MARK: - Transaction Item

struct TransactionItem: Identifiable {
    let id = UUID()
    let type: TransactionType
    let amount: Double
    let description: String
    let date: Date
    let betTitle: String?
    let isWin: Bool?
}

enum TransactionType {
    case bet
    case settlement
    case refund
}

// MARK: - Transaction Row

struct TransactionRow: View {
    let transaction: TransactionItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Transaction Icon
            Circle()
                .fill(transactionTypeColor.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: transactionTypeIcon)
                        .font(.caption)
                        .foregroundColor(transactionTypeColor)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.black)
                
                if let betTitle = transaction.betTitle {
                    Text(betTitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Text(formatTransactionDate(transaction.date))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(.slingBlue)
                    Text(formatAmount(transaction.amount))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(transactionAmountColor)
                }
                
                if let isWin = transaction.isWin {
                    Text(isWin ? "Won" : "Lost")
                        .font(.caption)
                        .foregroundColor(isWin ? .green : .red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }
    
    private var transactionTypeColor: Color {
        switch transaction.type {
        case .bet:
            return .slingBlue
        case .settlement:
            return .green
        case .refund:
            return .orange
        }
    }
    
    private var transactionTypeIcon: String {
        switch transaction.type {
        case .bet:
            return "target"
        case .settlement:
            return "checkmark.circle"
        case .refund:
            return "arrow.clockwise"
        }
    }
    
    private var transactionAmountColor: Color {
        if transaction.amount > 0 {
            return .green
        } else if transaction.amount < 0 {
            return .red
        } else {
            return .black
        }
    }
    
    private func formatAmount(_ amount: Double) -> String {
        let prefix = amount > 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.2f", amount))"
    }
    
    private func formatTransactionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}



// MARK: - Notifications View

// MARK: - Notification Filter Enum

enum NotificationFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
}

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    let firestoreService: FirestoreService
    @State private var isLoadingNotifications = false
    @State private var selectedFilter: NotificationFilter = .all
    @State private var hasMarkedAllAsRead = false
    
    // Computed property to filter notifications based on selected filter
    private var filteredNotifications: [FirestoreNotification] {
        switch selectedFilter {
        case .all:
            return firestoreService.notifications
        case .unread:
            return firestoreService.notifications.filter { !$0.is_read }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Enhanced Header with better styling
                VStack(spacing: 16) {
                    // Navigation Bar
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                                .frame(width: 44, height: 44)
                        }
                        
                        Spacer()
                        
                        VStack(spacing: 2) {
                            Text("Notifications")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            // Show unread count
                            let unreadCount = firestoreService.notifications.filter { !$0.is_read }.count
                            if unreadCount > 0 {
                                Text("\(unreadCount) unread")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Filter button
                        Menu {
                            ForEach(NotificationFilter.allCases, id: \.self) { filter in
                                Button(filter.rawValue) {
                                    selectedFilter = filter
                                }
                            }
                        } label: {
                            ZStack {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.title2)
                                    .foregroundColor(.black)
                                
                                // Small indicator for current filter
                                if selectedFilter == .unread {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 8, y: -8)
                                }
                            }
                            .frame(width: 44, height: 44)
                        }
                    }
                    

                    

                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .background(Color.white)
                
                // Enhanced Notifications List
                if filteredNotifications.isEmpty {
                    // Empty State or Loading State
                    VStack(spacing: 20) {
                        Spacer()
                        
                        if isLoadingNotifications {
                            // Loading State
                            ProgressView()
                                .scaleEffect(1.2)
                                .progressViewStyle(CircularProgressViewStyle(tint: .slingBlue))
                            
                            Text("Loading notifications...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        } else {
                            // Empty State
                            Image(systemName: "bell.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.gray.opacity(0.5))
                            
                            VStack(spacing: 8) {
                                Text(selectedFilter == .all ? "No notifications yet" : "No unread notifications")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Text(selectedFilter == .all ? "When you receive notifications, they'll appear here" : "All notifications have been read")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 40)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(filteredNotifications) { notification in
                                EnhancedNotificationRow(
                                    notification: convertToNotificationItem(notification),
                                    firestoreService: firestoreService
                                )
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                        .padding(.top, 8)
                        .animation(.easeInOut(duration: 0.3), value: filteredNotifications.count)
                    }

                }
            }
            .background(Color.white)
            .navigationBarHidden(true)

            .onAppear {
                print("🔍 NotificationsView: onAppear triggered")
                print("🔍 NotificationsView: Current user email: \(firestoreService.currentUser?.email ?? "nil")")
                print("🔍 NotificationsView: Current notifications count: \(firestoreService.notifications.count)")
                
                // Fetch notifications if none exist
                if firestoreService.notifications.isEmpty {
                    isLoadingNotifications = true
                    firestoreService.fetchNotifications()
                }
                
                // Mark all unread notifications as read when the notification page is opened
                if !hasMarkedAllAsRead {
                    markAllUnreadNotificationsAsRead()
                    hasMarkedAllAsRead = true
                }
            }
            .onReceive(firestoreService.$notifications) { notifications in
                print("🔍 NotificationsView: Notifications updated, count: \(notifications.count)")
                // Notifications are automatically marked as read when they appear on screen
                isLoadingNotifications = false
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func markAllUnreadNotificationsAsRead() {
        let unreadNotifications = firestoreService.notifications.filter { !$0.is_read }
        print("🔍 NotificationsView: Marking \(unreadNotifications.count) unread notifications as read")
        
        for notification in unreadNotifications {
            if let notificationId = notification.id {
                firestoreService.markNotificationAsRead(notificationId: notificationId) { success in
                    if success {
                        print("✅ NotificationsView: Marked notification as read: \(notificationId)")
                    } else {
                        print("❌ NotificationsView: Failed to mark notification as read: \(notificationId)")
                    }
                }
            }
        }
    }
}

// MARK: - Filter Button Component

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected ? 
                    AnyShapeStyle(Color.slingGradient) : 
                    AnyShapeStyle(Color.white)
                )
                .cornerRadius(20)
                .frame(height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(0.3), lineWidth: isSelected ? 0 : 1)
                )
        }
    }
}

// MARK: - Enhanced Notification Row

struct EnhancedNotificationRow: View {
    let notification: NotificationItem
    let firestoreService: FirestoreService
    
    var body: some View {
        Button(action: {
            // Notifications are automatically marked as read when they appear on screen
            // This button can be used for future navigation or actions
            // No manual action needed for marking as read
        }) {
            HStack(spacing: 16) {
                // Enhanced Icon with better styling
                ZStack {
                    Circle()
                        .fill(notification.iconColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: notification.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(notification.iconColor)
                }
                
                // Enhanced Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(notification.text)
                        .font(.system(size: 15, weight: notification.isUnread ? .semibold : .regular))
                        .foregroundColor(notification.isUnread ? .primary : .secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    
                    HStack(spacing: 8) {
                        Text(notification.timestamp)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let communityName = notification.communityName {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let communityIcon = notification.communityIcon {
                                Image(systemName: communityIcon)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(communityName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                

            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            )


        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .onAppear {
            // Automatically mark notification as read when it appears on screen
            if notification.isUnread, let notificationId = notification.id {
                firestoreService.markNotificationAsRead(notificationId: notificationId) { success in
                    if success {
                        print("✅ Notification automatically marked as read: \(notificationId)")
                    } else {
                        print("❌ Failed to automatically mark notification as read: \(notificationId)")
                    }
                }
            }
        }
    }
}

// MARK: - Notification Item

struct NotificationItem {
    let id: String?
    let icon: String
    let iconColor: Color
    let text: String
    let timestamp: String
    let isUnread: Bool
    let communityName: String?
    let communityIcon: String?
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var firestoreService: FirestoreService
    @State private var displayName: String
    @State private var firstName: String
    @State private var lastName: String
    @State private var isLoading = false
    @State private var showingSaveSuccess = false
    @State private var showingUnsavedChangesAlert = false
    @State private var showingImagePicker = false
    @State private var showingPhotoOptions = false
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage?
    @State private var profileImageUrl: String?
    
    init(firestoreService: FirestoreService) {
        self.firestoreService = firestoreService
        self._displayName = State(initialValue: firestoreService.currentUser?.display_name ?? "")
        self._firstName = State(initialValue: firestoreService.currentUser?.first_name ?? "")
        self._lastName = State(initialValue: firestoreService.currentUser?.last_name ?? "")
        self._profileImageUrl = State(initialValue: firestoreService.currentUser?.profile_picture_url)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Clean white background
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: { 
                            if hasUnsavedChanges() {
                                showingUnsavedChangesAlert = true
                            } else {
                                dismiss()
                            }
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.title2)
                                .foregroundColor(.black)
                                .frame(width: 44, height: 44)
                        }
                        
                        Spacer()
                        
                        Text("Edit Profile")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        
                        Spacer()
                        
                        Button(action: {
                            saveChanges()
                        }) {
                            Text("Save")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.slingBlue)
                        }
                        .disabled(isLoading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Content
                    VStack(spacing: 32) {
                        // Profile Picture Section
                        VStack(spacing: 16) {
                            Text("Profile Picture")
                                .font(.headline)
                                .fontWeight(.semibold)
                            .foregroundColor(.black)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                        
                            // Profile Picture Display and Edit Button
                            Button(action: {
                                showingPhotoOptions = true
                            }) {
                                ZStack {
                                    if let selectedImage = selectedImage {
                                        // Show selected image
                                        Image(uiImage: selectedImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 120, height: 120)
                                            .clipShape(Circle())
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.slingBlue, lineWidth: 3)
                                            )
                                    } else if let profileImageUrl = profileImageUrl {
                                        // Show current profile image
                                        AsyncImage(url: URL(string: profileImageUrl)) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Circle()
                                                .fill(Color.slingGradient)
                                                .overlay(
                                                    ProgressView()
                                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                        .scaleEffect(0.8)
                                                )
                                        }
                                        .frame(width: 120, height: 120)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                    } else {
                                        // Show initials fallback
                                        Circle()
                                            .fill(Color.slingGradient)
                                            .frame(width: 120, height: 120)
                                            .overlay(
                                                Text(getUserInitials())
                                                    .font(.largeTitle)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.white)
                                            )
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                            )
                                    }
                                    
                                    // Swap icon overlay at 3-6 o'clock position
                                    Circle()
                                        .fill(Color.slingBlue)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Image(systemName: "arrow.2.squarepath")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(.white)
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 2)
                                        )
                                        .offset(x: 42, y: 42) // Position at 3-6 o'clock (half on, half off)
                                }
                            }
                            
                            Text("Tap to change your profile picture")
                                .font(.caption)
                            .foregroundColor(.gray)
                        }
                        
                        // User details input fields
                        VStack(alignment: .leading, spacing: 16) {
                            // First and Last name on same row
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("First Name")
                                        .font(.headline)
                                        .foregroundColor(.black)
                                    
                                    TextField("First", text: $firstName)
                                        .textFieldStyle(ModernTextFieldStyle())
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Last Name")
                                        .font(.headline)
                                        .foregroundColor(.black)
                                    
                                    TextField("Last", text: $lastName)
                                        .textFieldStyle(ModernTextFieldStyle())
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Display Name")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                
                                HStack(spacing: 0) {
                                    Text("@")
                                        .font(.title2)
                                        .foregroundColor(.gray)
                                        .padding(.leading, 20)
                                    
                                    TextField("username", text: $displayName)
                                        .textFieldStyle(ModernTextFieldStyle())
                                        .padding(.leading, 8)
                                        .onChange(of: displayName) { newValue in
                                            // Remove spaces from display name
                                            let formattedName = newValue.replacingOccurrences(of: " ", with: "")
                                            if formattedName != newValue {
                                                displayName = formattedName
                                            }
                                        }
                                }
                            }
                            
                            Text("This is how other users will see you")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer()
                    }
                    .padding(.top, 40)
                }
            }
            .navigationBarHidden(true)
            .alert("Profile Updated", isPresented: $showingSaveSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your profile has been successfully updated.")
            }
            .alert("Unsaved Changes", isPresented: $showingUnsavedChangesAlert) {
                Button("Leave", role: .destructive) { dismiss() }
                Button("Stay", role: .cancel) { }
            } message: {
                Text("You have unsaved changes. Are you sure you want to leave?")
            }
            .confirmationDialog("Choose Profile Picture", isPresented: $showingPhotoOptions, titleVisibility: .visible) {
                Button("Choose from Photos") {
                    showingPhotoPicker = true
                }
                
                Button("Take Photo") {
                    showingCamera = true
                }
                
                Button("Cancel", role: .cancel) { }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedItem, matching: .images, photoLibrary: .shared())
            .sheet(isPresented: $showingCamera) {
                CameraView { image in
                    selectedImage = image
                    showingCamera = false
                }
            }
            .onChange(of: selectedItem) { _ in
                loadPhotoFromPicker()
            }
        }
    }
    
    private func getUserInitials() -> String {
        let user = firestoreService.currentUser
        if let firstName = user?.first_name, let lastName = user?.last_name, !firstName.isEmpty, !lastName.isEmpty {
            let firstInitial = String(firstName.prefix(1)).uppercased()
            let lastInitial = String(lastName.prefix(1)).uppercased()
            return "\(firstInitial)\(lastInitial)"
        } else if let displayName = user?.display_name, !displayName.isEmpty {
            let components = displayName.components(separatedBy: " ")
            if components.count >= 2 {
                let firstInitial = String(components[0].prefix(1)).uppercased()
                let lastInitial = String(components[1].prefix(1)).uppercased()
                return "\(firstInitial)\(lastInitial)"
            } else if components.count == 1 {
                return String(components[0].prefix(1)).uppercased()
            }
        } else if let email = user?.email {
            return String(email.prefix(1)).uppercased()
        }
        return "U"
    }
    
    private func loadPhotoFromPicker() {
        guard let selectedItem = selectedItem else { return }
        
        Task {
            do {
                if let data = try await selectedItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        self.selectedImage = image
                    }
                }
            } catch {
                print("❌ Error loading photo: \(error)")
            }
        }
    }
    
    private func hasUnsavedChanges() -> Bool {
        let originalDisplayName = firestoreService.currentUser?.display_name ?? ""
        let originalFirstName = firestoreService.currentUser?.first_name ?? ""
        let originalLastName = firestoreService.currentUser?.last_name ?? ""
        
        return displayName != originalDisplayName || 
               firstName != originalFirstName || 
               lastName != originalLastName ||
               selectedImage != nil
    }
    
    private func saveChanges() {
        // Prevent multiple simultaneous save operations
        guard !isLoading else {
            print("⚠️ Save operation already in progress")
            return
        }
        
        isLoading = true
        
        // Validate input
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isLoading = false
            return
        }
        
        print("💾 Starting profile save process...")
        
        // If there's a new profile image, upload it first
        if let selectedImage = selectedImage {
            print("📷 Uploading new profile image...")
            firestoreService.uploadUserProfileImage(selectedImage) { success, error in
                DispatchQueue.main.async {
                    
                    if success {
                        print("✅ Profile image uploaded successfully")
                        // Clear the selected image and update local URL
                        self.selectedImage = nil
                        self.profileImageUrl = self.firestoreService.currentUser?.profile_picture_url
                        
                        // Force UI refresh by updating the published property
                        print("🔄 Refreshing UI with new profile picture URL: \(self.firestoreService.currentUser?.profile_picture_url ?? "nil")")
                        
                        // Force UI refresh by triggering objectWillChange
                        self.firestoreService.objectWillChange.send()
                        
                        // Now update the text fields
                        self.updateTextFields()
                    } else {
                        print("❌ Failed to upload profile image: \(error ?? "Unknown error")")
                        self.isLoading = false
                        // Show error feedback to user
                        // You could add an error state here
                    }
                }
            }
        } else {
            // No new image, just update text fields
            print("📝 No new image, updating text fields only...")
            updateTextFields()
        }
    }
    
    private func updateTextFields() {
        // Update user profile text fields in Firestore
        let updateData: [String: Any] = [
            "display_name": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "first_name": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            "last_name": lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            "updated_date": Date()
        ]
        
        firestoreService.updateUserSettings(settings: updateData) { success in
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    print("✅ Profile updated successfully")
                    self.showingSaveSuccess = true
                } else {
                    print("❌ Failed to update profile")
                    // You could show an error alert here
                }
            }
        }
    }
}



// MARK: - Create Bet View

struct CreateBetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var firestoreService: FirestoreService
    let preSelectedCommunity: String? // New parameter for pre-selecting community
    @State private var currentStep = 1
    @State private var selectedMarketType = "Yes/No"
    @State private var marketQuestion = ""
    @State private var selectedCommunity = ""
    @State private var outcomes: [String] = ["Yes", "No"]
    @State private var odds: [String] = ["-110", "-110"]
    @State private var percentages: [String] = ["52.4%", "52.4%"]
    @State private var spreadLine = ""
    @State private var overUnderLine = ""
    @State private var bettingCloseDate = Date().addingTimeInterval(72 * 60 * 60) // 72 hours from now
    @State private var showingDatePicker = false
    @State private var showingAdjustOdds = false
    @State private var selectedOutcomeIndex = 0
    @State private var newOptionText = ""
    
    // Mention system state
    @State private var showingMentions = false
    @State private var mentionSearchText = ""
    @State private var mentionedUsers: [String] = []
    @State private var currentMentionPosition: Int = 0
    @State private var allCommunityMembers: [CommunityMemberInfo] = []
    @State private var userFullNames: [String: String] = [:] // Cache for user full names
    @State private var userDisplayNames: [String: String] = [:] // Cache for user display names
    
    let marketTypes = [
        ("Yes/No", "target", "Binary outcome", "Perfect for simple predictions"),
        ("Multiple Choice", "chart.bar", "Several options", "Great for complex scenarios"),
        ("Spread", "number", "Point handicap", "Ideal for sports betting"),
        ("Over/Under", "arrow.up.arrow.down", "Above or below", "Perfect for numerical predictions"),
        ("Prop Bet", "person.2", "Custom wager", "Create unique betting opportunities")
    ]
    
        var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with Progress
                VStack(spacing: 16) {
                    // Top Navigation
                    HStack {
                        Button(action: {
                            if currentStep > 1 {
                                currentStep -= 1
                            } else {
                                dismiss()
                            }
                        }) {
                            Image(systemName: currentStep > 1 ? "chevron.left" : "xmark")
                                .font(.title3)
                                .foregroundColor(.black)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemGray5))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        // Progress Indicator
                        HStack(spacing: 8) {
                            Text("\(min(currentStep, 3)) of 3")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.slingBlue)
                            
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 4, height: 4)
                            
                            Text(getStepTitle())
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // Progress Bar
                        HStack(spacing: 2) {
                            ForEach(1...3, id: \.self) { step in
                                Rectangle()
                                    .fill(step <= min(currentStep, 3) ? Color.slingBlue : Color.gray.opacity(0.3))
                                    .frame(width: 20, height: 4)
                                    .cornerRadius(2)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                
                // Content Area
                ScrollView {
                    VStack(spacing: 32) {
                                        switch currentStep {
                case 1:
                    marketTypeStep
                case 2:
                    betDetailsStep
                case 3:
                    outcomesStep
                case 4:
                    reviewStep
                default:
                    EmptyView()
                }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 32)
                    .padding(.bottom, 100)
                }
                
                // Continue Button
                VStack(spacing: 0) {
                    Button(action: {
                        if currentStep < 4 {
                            currentStep += 1
                        } else {
                            createBet()
                        }
                    }) {
                        HStack {
                            if currentStep == 4 {
                                Image(systemName: "checkmark")
                                    .font(.subheadline)
                            }
                            
                            Text(getContinueButtonText())
                                .fontWeight(.semibold)
                            
                            if currentStep < 4 {
                                Image(systemName: "arrow.right")
                                    .font(.subheadline)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canContinueToNextStep() ? Color.slingBlue : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(!canContinueToNextStep())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .background(Color.white)
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingDatePicker) {
                DatePickerView(selectedDate: $bettingCloseDate, isPresented: $showingDatePicker)
            }
            .sheet(isPresented: $showingAdjustOdds) {
                AdjustOddsView(
                    odds: $odds[selectedOutcomeIndex],
                    percentage: $percentages[selectedOutcomeIndex],
                    isPresented: $showingAdjustOdds
                )
            }
            .onAppear {
                firestoreService.fetchCommunities()
                
                // Set pre-selected community if provided
                if let preSelectedCommunity = preSelectedCommunity {
                    selectedCommunity = preSelectedCommunity
                }
                
                // Load community members for mention system
                loadAllCommunityMembers()
            }
        }
    }
    
    // MARK: - Step 1: Market Type
    private var marketTypeStep: some View {
        VStack(spacing: 24) {
            // Title
            VStack(spacing: 8) {
                Text("Market Type")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                Text("Choose your bet format")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            // Market Type Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(marketTypes, id: \.0) { type, icon, subtitle, description in
                    Button(action: {
                        selectedMarketType = type
                        updateOutcomesForMarketType()
                    }) {
                        VStack(spacing: 8) {
                            // Icon
                            ZStack {
                                Circle()
                                    .fill(selectedMarketType == type ? Color.slingBlue : Color.gray.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                
                                Image(systemName: icon)
                                    .font(.title3)
                                    .foregroundColor(selectedMarketType == type ? .white : .slingBlue)
                            }
                            
                            // Title
                            Text(type)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(selectedMarketType == type ? .slingBlue : .black)
                            
                            // Description
                            VStack(spacing: 2) {
                                Text(subtitle)
                                    .font(.caption2)
                                    .foregroundColor(selectedMarketType == type ? .slingBlue : .gray)
                                
                                Text(description)
                                    .font(.caption2)
                                    .foregroundColor(selectedMarketType == type ? .slingBlue.opacity(0.8) : .gray.opacity(0.8))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 12)
                        .background(selectedMarketType == type ? Color.slingBlue.opacity(0.1) : Color.white)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(selectedMarketType == type ? Color.slingBlue : Color.gray.opacity(0.3), lineWidth: selectedMarketType == type ? 2 : 1)
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Step 2: Bet Details
    private var betDetailsStep: some View {
        VStack(spacing: 24) {
            // Title
            VStack(spacing: 8) {
                Text("Your Bet")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                Text("Set up your market details")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            // Market Question Card
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.slingBlue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Market Question")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        Text("Use @ to mention users (hides bet from them)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
                
                VStack(spacing: 0) {
                    ColoredTextView(
                        text: $marketQuestion,
                        placeholder: "e.g., Who will win the championship?",
                        onTextChange: { oldValue, newValue in
                            handleMentionInput(oldValue: oldValue, newValue: newValue)
                        }
                    )
                    .frame(minHeight: 44, maxHeight: 120)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Mention suggestions list
                    if showingMentions {
                        mentionSuggestionsView
                    }
                }
                
                HStack {
                    Spacer()
                    Text("\(marketQuestion.count)/100")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            
            // Spread Line Section (only for Spread type)
            if selectedMarketType == "Spread" {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "number")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Spread Line")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                            
                            Text("Enter the point handicap")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    
                    TextField("e.g., -3.5", text: $spreadLine)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.subheadline)
                        .keyboardType(.decimalPad)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .onChange(of: spreadLine) { oldValue, newValue in
                            // Filter to only allow numbers, decimal points, and minus signs
                            let filtered = newValue.filter { "0123456789.-".contains($0) }
                            if filtered != newValue {
                                spreadLine = filtered
                            }
                            updateSpreadOutcomes()
                        }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundColor(.slingBlue)
                        
                        Text("Negative favors Team A, positive favors Team B")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(20)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
            
            // Over/Under Line Section (only for Over/Under type)
            if selectedMarketType == "Over/Under" {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Over/Under Line")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                            
                            Text("Enter the threshold number")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    
                    TextField("e.g., 27.5", text: $overUnderLine)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.subheadline)
                        .keyboardType(.decimalPad)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .onChange(of: overUnderLine) { oldValue, newValue in
                            // Filter to only allow numbers, decimal points, and minus signs
                            let filtered = newValue.filter { "0123456789.-".contains($0) }
                            if filtered != newValue {
                                overUnderLine = filtered
                            }
                            updateOverUnderOutcomes()
                        }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundColor(.slingBlue)
                        
                        Text("Bettors predict if the total will be above or below this number")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(20)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
            
            // Community Card
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.title2)
                        .foregroundColor(.slingBlue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Community")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        Text("Where will people bet on this?")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
                
                Menu {
                    ForEach(firestoreService.userCommunities) { community in
                        Button(community.name) {
                            selectedCommunity = community.name
                        }
                    }
                } label: {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(selectedCommunity.isEmpty ? Color.slingBlue : Color.green)
                                .frame(width: 20, height: 20)
                            
                            Image(systemName: selectedCommunity.isEmpty ? "plus" : "checkmark")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        
                        Text(selectedCommunity.isEmpty ? "Select a community" : selectedCommunity)
                            .foregroundColor(selectedCommunity.isEmpty ? .gray : .black)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
                        .padding(20)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
    
    // MARK: - Step 3: Outcomes & Odds
    private var outcomesStep: some View {
        VStack(spacing: 24) {
            // Title
            VStack(spacing: 8) {
                Text("Outcomes & Odds")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                Text("Configure betting options and probabilities")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
                        // Outcomes
            VStack(spacing: 16) {
                ForEach(Array(outcomes.enumerated()), id: \.offset) { index, outcome in
                    Button(action: {
                        selectedOutcomeIndex = index
                        showingAdjustOdds = true
                    }) {
                        HStack(spacing: 16) {
                            // Outcome Label
                            if selectedMarketType == "Yes/No" {
                                // Yes/No outcomes are not editable
                                HStack(spacing: 4) {
                                    Text(outcome)
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.black)
                                    
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .frame(width: 80, alignment: .leading)
                            } else if selectedMarketType == "Spread" || selectedMarketType == "Over/Under" {
                                // Spread and Over/Under outcomes are not editable
                                HStack(spacing: 4) {
                                    Text(outcome)
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.black)
                                    
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .frame(width: 120, alignment: .leading)
                            } else {
                                // Multiple Choice and Prop Bet outcomes are editable
                                HStack(spacing: 4) {
                                    TextField("Outcome", text: $outcomes[index])
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.black)
                                    
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.slingBlue)
                                }
                                .frame(width: 120, alignment: .leading)
                            }
                            
                            // Odds Input
                            TextField("Odds", text: $odds[index])
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .frame(width: 70)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            
                            // Percentage Badge
                            Text(percentages[index])
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.slingBlue)
                                .cornerRadius(12)
                            
                            Spacer(minLength: 20)
                            
                            // Chevron or Remove Button
                            if selectedMarketType == "Multiple Choice" || selectedMarketType == "Prop Bet" {
                                if outcomes.count > 2 {
                                    Button(action: {
                                        outcomes.remove(at: index)
                                        odds.remove(at: index)
                                        percentages.remove(at: index)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(selectedMarketType == "Multiple Choice" || selectedMarketType == "Prop Bet" ? Color.slingBlue.opacity(0.05) : Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    (selectedMarketType == "Multiple Choice" || selectedMarketType == "Prop Bet") ? Color.slingBlue.opacity(0.3) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Add new option for Multiple Choice and Prop Bet
                if selectedMarketType == "Multiple Choice" || selectedMarketType == "Prop Bet" {
                    HStack(spacing: 16) {
                        TextField("Add another option...", text: $newOptionText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.subheadline)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        
                        Button(action: {
                            if !newOptionText.isEmpty {
                                outcomes.append(newOptionText)
                                odds.append("-110")
                                percentages.append("52.4%")
                                newOptionText = ""
                            }
                        }) {
                            HStack {
                                Image(systemName: "plus")
                                    .font(.subheadline)
                                Text("Add")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(Color.slingBlue)
                            .cornerRadius(12)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Step 4: Review
    private var reviewStep: some View {
        VStack(spacing: 24) {
            // Title
            VStack(spacing: 8) {
                Text("Review")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                Text("Double-check everything before creating")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            // Market Details Card
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.slingBlue)
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Question")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text(attributedText)
                            .font(.subheadline)
                    }
                    
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.title2)
                        .foregroundColor(.slingBlue)
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Type")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text(selectedMarketType)
                            .font(.subheadline)
                            .foregroundColor(.black)
                    }
                    
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.title2)
                        .foregroundColor(.slingBlue)
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Community")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text(selectedCommunity)
                            .font(.subheadline)
                            .foregroundColor(.black)
                    }
                    
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet")
                        .font(.title2)
                        .foregroundColor(.slingBlue)
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Outcomes")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(outcomes.enumerated()), id: \.offset) { index, outcome in
                                HStack {
                                    Text(outcome)
                                        .font(.subheadline)
                                        .foregroundColor(.black)
                                    
                                    Spacer()
                                    
                                    Text(odds[index])
                                        .font(.subheadline)
                                        .foregroundColor(.slingBlue)
                                        .fontWeight(.medium)
                                    
                                    Text("(\(percentages[index]))")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                
                // Mentioned Users Section (only show if there are mentions)
                if !mentionedUsers.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "at")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hidden Users")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(mentionedUsers, id: \.self) { email in
                                    Text(getUserFullName(from: email))
                                        .font(.subheadline)
                                        .foregroundColor(.black)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            
            // Deadline Card
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.fill")
                        .font(.title2)
                        .foregroundColor(.slingBlue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deadline")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        Text("When betting closes")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
                
                Button(action: {
                    showingDatePicker = true
                }) {
                    HStack {
                        Text("Closes: \(formatDateForDisplay(bettingCloseDate))")
                            .font(.subheadline)
                            .foregroundColor(.black)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
    
    // MARK: - Helper Functions
    private func getStepTitle() -> String {
        switch currentStep {
        case 1: return "Market Type"
        case 2: return "Details"
        case 3: return "Outcomes"
        case 4: return "Review"
        default: return ""
        }
    }
    
    private func getContinueButtonText() -> String {
        switch currentStep {
        case 1, 2: return "Continue"
        case 3: return "Review & Create"
        case 4: return "Create Market"
        default: return "Continue"
        }
    }
    
    private func canContinueToNextStep() -> Bool {
        switch currentStep {
        case 1:
            return !selectedMarketType.isEmpty
        case 2:
            return !marketQuestion.isEmpty && !selectedCommunity.isEmpty
        case 3:
            return true
        case 4:
            return true
        default:
            return false
        }
    }
    
    private func formatDateForDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }
    
    private func updateOutcomesForMarketType() {
        switch selectedMarketType {
        case "Yes/No":
            outcomes = ["Yes", "No"]
            odds = ["-110", "-110"]
            percentages = ["52.4%", "52.4%"]
            spreadLine = ""
            overUnderLine = ""
        case "Multiple Choice":
            outcomes = ["Option 1", "Option 2", "Option 3"]
            odds = ["-110", "-110", "-110"]
            percentages = ["33.3%", "33.3%", "33.3%"]
            spreadLine = ""
            overUnderLine = ""
        case "Spread":
            outcomes = ["Team A", "Team B"]
            odds = ["-110", "-110"]
            percentages = ["52.4%", "52.4%"]
            spreadLine = ""
            overUnderLine = ""
        case "Over/Under":
            outcomes = ["Over", "Under"]
            odds = ["-110", "-110"]
            percentages = ["52.4%", "52.4%"]
            spreadLine = ""
            overUnderLine = ""
        case "Prop Bet":
            outcomes = ["Option 1", "Option 2"]
            odds = ["-110", "-110"]
            percentages = ["52.4%", "52.4%"]
            spreadLine = ""
            overUnderLine = ""
        default:
            break
        }
        
        // Update outcomes based on spread/over-under lines
        updateSpreadOutcomes()
        updateOverUnderOutcomes()
    }
    
    private func updateSpreadOutcomes() {
        guard selectedMarketType == "Spread" else { return }
        if !spreadLine.isEmpty, let spreadValue = Double(spreadLine) {
            outcomes[0] = "Team A \(spreadValue >= 0 ? "+" : "")\(String(format: "%.1f", spreadValue))"
            outcomes[1] = "Team B \(spreadValue >= 0 ? "-" : "+")\(String(format: "%.1f", abs(spreadValue)))"
        } else {
            outcomes[0] = "Team A"
            outcomes[1] = "Team B"
        }
    }
    
    private func updateOverUnderOutcomes() {
        guard selectedMarketType == "Over/Under" else { return }
        if !overUnderLine.isEmpty, let lineValue = Double(overUnderLine) {
            outcomes[0] = "Over \(String(format: "%.1f", lineValue))"
            outcomes[1] = "Under \(String(format: "%.1f", lineValue))"
        } else {
            outcomes[0] = "Over"
            outcomes[1] = "Under"
        }
    }
    

    
    private func createBet() {
        // Validate required fields
        guard !marketQuestion.isEmpty else { return }
        guard !selectedCommunity.isEmpty else { return }
        
        // Find the selected community
        guard let community = firestoreService.userCommunities.first(where: { $0.name == selectedCommunity }) else {
            print("❌ CreateBet: Community not found for name: \(selectedCommunity)")
            return
        }
        
        // Use community.id if available, otherwise use documentId as fallback
        let communityId = community.id ?? community.documentId ?? ""
        
        print("🔍 CreateBet: Selected community - Name: \(community.name), ID: \(community.id ?? "nil"), DocumentID: \(community.documentId ?? "nil"), Final ID: \(communityId)")
        
        // Convert odds array to dictionary
        var oddsDict: [String: String] = [:]
        for (index, option) in outcomes.enumerated() {
            if index < odds.count {
                oddsDict[option] = odds[index]
            }
        }
        
        // Determine bet type
        let betType: String
        switch selectedMarketType {
        case "Yes/No":
            betType = "yes_no"
        case "Multiple Choice":
            betType = "multiple_choice"
        case "Spread":
            betType = "spread"
        case "Over/Under":
            betType = "over_under"
        case "Prop Bet":
            betType = "prop_bet"
        default:
            betType = "yes_no"
        }
        
        // Ensure deadline is in the future with a 1-hour buffer
        let currentDate = Date()
        let minimumDeadline = currentDate.addingTimeInterval(60 * 60) // At least 1 hour from now
        let finalDeadline = bettingCloseDate > minimumDeadline ? bettingCloseDate : minimumDeadline
        
        let betData: [String: Any] = [
            "title": marketQuestion,
            "community_id": communityId,
            "options": outcomes,
            "odds": oddsDict,
            "deadline": finalDeadline,
            "bet_type": betType,
            "spread_line": spreadLine.isEmpty ? NSNull() : spreadLine,
            "over_under_line": overUnderLine.isEmpty ? NSNull() : overUnderLine,
            "status": "open",
            "created_by": firestoreService.currentUser?.email ?? "",
            "creator_email": firestoreService.currentUser?.email ?? "",
            "created_by_id": firestoreService.currentUser?.id ?? "",
            "description": marketQuestion, // Use the title as description for now
            "image_url": NSNull(), // Will be populated later with Unsplash image
            "pool_by_option": Dictionary(uniqueKeysWithValues: outcomes.map { ($0, 0) }), // Initialize pool with 0 for each option
            "total_pool": NSNull(), // Initialize total pool to null
            "total_participants": NSNull(), // Initialize total participants to null
            "winner_option": NSNull(), // Will be set when bet is settled
            "created_date": Date(),
            "updated_date": Date(),
            "mentioned_users": mentionedUsers, // Users who are mentioned and should not see the bet until it expires
            "hidden_from_users": mentionedUsers // Alternative field name for clarity
        ]
        
        print("🔍 CreateBet: Bet data - Title: \(marketQuestion), Community ID: \(communityId)")
        print("🔍 CreateBet: Original deadline: \(bettingCloseDate)")
        print("🔍 CreateBet: Current date: \(currentDate)")
        print("🔍 CreateBet: Minimum deadline: \(minimumDeadline)")
        print("🔍 CreateBet: Final deadline: \(finalDeadline)")
        print("🔍 CreateBet: Final deadline (ISO): \(ISO8601DateFormatter().string(from: finalDeadline))")
        print("🔍 CreateBet: Time difference (seconds): \(finalDeadline.timeIntervalSince(currentDate))")
        print("🔍 CreateBet: Time difference (hours): \(finalDeadline.timeIntervalSince(currentDate) / 3600)")
        print("🔍 CreateBet: Available communities: \(firestoreService.userCommunities.map { "\($0.name): \($0.id ?? "nil")" })")
        
        firestoreService.createBet(betData: betData) { success, betId in
            DispatchQueue.main.async {
                if success, let betId = betId {
                    // After successful bet creation, fetch and update the image
                    self.fetchAndUpdateBetImage(betId: betId, betTitle: marketQuestion)
                    dismiss()
                } else {
                    print("Error creating bet: Unknown error")
                }
            }
        }
    }
    
    private func fetchAndUpdateBetImage(betId: String, betTitle: String) {
        // Create an instance of UnsplashImageService to fetch the image
        let imageService = UnsplashImageService()
        
        imageService.getImageForBet(title: betTitle) { imageURL in
            if let imageURL = imageURL {
                // Update the bet document with the fetched image URL
                self.firestoreService.updateBetImage(betId: betId, imageURL: imageURL) { success in
                    if success {
                        print("✅ Bet image updated successfully: \(imageURL)")
                    } else {
                        print("❌ Failed to update bet image")
                    }
                }
            } else {
                print("⚠️ No image found for bet: \(betTitle)")
            }
        }
    }
    
    // MARK: - Mention System
    
    private var attributedText: AttributedString {
        var attributedString = AttributedString(marketQuestion)
        
        // Only color actual user names that were inserted from dropdown
        // Look for patterns like @FirstName LastName (with proper capitalization)
        let mentionPattern = "@[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)+"
        let regex = try? NSRegularExpression(pattern: mentionPattern)
        let range = NSRange(location: 0, length: marketQuestion.utf16.count)
        
        if let matches = regex?.matches(in: marketQuestion, range: range) {
            for match in matches.reversed() {
                let matchRange = Range(match.range, in: marketQuestion)!
                let mentionText = String(marketQuestion[matchRange])
                
                if let mentionRange = attributedString.range(of: mentionText) {
                    // Apply sling gradient color
                    attributedString[mentionRange].foregroundColor = .slingBlue
                    attributedString[mentionRange].font = .subheadline.weight(.medium)
                }
            }
        }
        
        return attributedString
    }
    
    private func handleMentionInput(oldValue: String, newValue: String) {
        // Check if user typed "@"
        if newValue.count > oldValue.count && newValue.last == "@" {
            showingMentions = true
            mentionSearchText = ""
            currentMentionPosition = newValue.count - 1
        } else if showingMentions {
            // Check if user is typing after "@"
            if let atIndex = newValue.lastIndex(of: "@") {
                let afterAt = String(newValue[newValue.index(after: atIndex)...])
                if afterAt.contains(" ") || afterAt.contains("\n") {
                    // User typed space or newline, hide mentions
                    showingMentions = false
                } else {
                    // Update search text
                    mentionSearchText = afterAt
                }
            } else {
                // No "@" found, hide mentions
                showingMentions = false
            }
        }
        
        // Check if any mentions were deleted and remove them from mentionedUsers list
        let oldMentions = extractMentions(from: oldValue)
        let newMentions = extractMentions(from: newValue)
        
        // Find mentions that were removed
        let removedMentions = oldMentions.filter { !newMentions.contains($0) }
        
        // Remove corresponding users from mentionedUsers list
        for removedMention in removedMentions {
            // Find the user email for this mention
            for (index, email) in mentionedUsers.enumerated().reversed() {
                let fullName = getUserFullName(from: email)
                if removedMention == "@\(fullName)" {
                    mentionedUsers.remove(at: index)
                    break
                }
            }
        }
    }
    
    private func extractMentions(from text: String) -> [String] {
        let mentionPattern = "@[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)+"
        let regex = try? NSRegularExpression(pattern: mentionPattern)
        let range = NSRange(location: 0, length: text.utf16.count)
        
        var mentions: [String] = []
        if let matches = regex?.matches(in: text, range: range) {
            for match in matches {
                let mentionText = (text as NSString).substring(with: match.range)
                mentions.append(mentionText)
            }
        }
        
        return mentions
    }
    
    private var mentionSuggestionsView: some View {
        VStack(spacing: 0) {
            // Use the loaded community members
            let filteredMembers = filterMembers(allCommunityMembers, searchText: mentionSearchText)
            
            if filteredMembers.isEmpty {
                HStack {
                    Spacer()
                    Text("No members found")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.vertical, 12)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredMembers, id: \.email) { member in
                            Button(action: {
                                selectMention(member: member)
                            }) {
                                HStack(spacing: 12) {
                                    // Member avatar
                                    Circle()
                                        .fill(Color.slingGradient)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Text(getMemberInitials(member))
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(getMemberFullName(member))
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.black)
                                        
                                        Text(getUserDisplayName(from: member.email))
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.white)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            if member.email != filteredMembers.last?.email {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func loadAllCommunityMembers() {
        var allMembers: [CommunityMemberInfo] = []
        let group = DispatchGroup()
        
        for community in firestoreService.userCommunities {
            if let communityId = community.id {
                group.enter()
                firestoreService.fetchCommunityMembers(communityId: communityId) { members in
                    allMembers.append(contentsOf: members)
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            // Remove duplicates based on email
            let uniqueMembers = Dictionary(grouping: allMembers, by: { $0.email })
                .compactMapValues { $0.first }
                .values
                .sorted { $0.name < $1.name }
            
            self.allCommunityMembers = Array(uniqueMembers)
        }
    }
    
    private func filterMembers(_ members: [CommunityMemberInfo], searchText: String) -> [CommunityMemberInfo] {
        if searchText.isEmpty {
            return members
        }
        
        return members.filter { member in
            // Search by display name from Firestore
            getUserDisplayName(from: member.email).localizedCaseInsensitiveContains(searchText) ||
            // Search by email (which contains username)
            member.email.localizedCaseInsensitiveContains(searchText) ||
            // Search by full name from Firestore
            getMemberFullName(member).localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func getUserFullName(from email: String) -> String {
        // Check cache first
        if let cachedName = userFullNames[email] {
            return cachedName
        }
        
        // Fetch from Firestore
        firestoreService.getUserDetails(email: email) { fullName, username in
            DispatchQueue.main.async {
                self.userFullNames[email] = fullName
            }
        }
        
        // Return email as fallback while fetching
        return email
    }
    
    private func getUserDisplayName(from email: String) -> String {
        // Check cache first
        if let cachedName = userDisplayNames[email] {
            return cachedName
        }
        
        // Fetch from Firestore
        firestoreService.getUserDetails(email: email) { fullName, username in
            DispatchQueue.main.async {
                // Extract display name from the username (remove @)
                let displayName = username.hasPrefix("@") ? String(username.dropFirst()) : username
                self.userDisplayNames[email] = displayName
            }
        }
        
        // Return email username as fallback while fetching
        let emailUsername = email.components(separatedBy: "@").first ?? email
        return emailUsername
    }
    
    private func getMemberFullName(_ member: CommunityMemberInfo) -> String {
        return getUserFullName(from: member.email)
    }
    
    private func getMemberInitials(_ member: CommunityMemberInfo) -> String {
        let components = member.name.components(separatedBy: " ")
        if components.count >= 2 {
            let firstInitial = String(components[0].prefix(1)).uppercased()
            let lastInitial = String(components[1].prefix(1)).uppercased()
            return "\(firstInitial)\(lastInitial)"
        } else if components.count == 1 {
            return String(components[0].prefix(1)).uppercased()
        } else {
            return String(member.email.prefix(1)).uppercased()
        }
    }
    
    private func selectMention(member: CommunityMemberInfo) {
        // Replace the "@" and search text with @FullName
        let fullName = getMemberFullName(member)
        let mentionText = "@\(fullName)"
        
        // Find the position of the "@" in the current text
        if let atIndex = marketQuestion.lastIndex(of: "@") {
            let beforeAt = String(marketQuestion[..<atIndex])
            let afterMention = String(marketQuestion[marketQuestion.index(after: atIndex)...])
            
            // Remove any text after "@" that was part of the search
            if let spaceIndex = afterMention.firstIndex(of: " ") {
                let afterSpace = String(afterMention[spaceIndex...])
                marketQuestion = beforeAt + mentionText + afterSpace
            } else {
                marketQuestion = beforeAt + mentionText
            }
        }
        
        // Add to mentioned users list
        if !mentionedUsers.contains(member.email) {
            mentionedUsers.append(member.email)
        }
        
        // Hide mentions
        showingMentions = false
        mentionSearchText = ""
    }
}

// MARK: - Colored TextField

struct ColoredTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onTextChange: (String, String) -> Void
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.delegate = context.coordinator
        textField.backgroundColor = UIColor.clear
        textField.borderStyle = .none
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
        updateTextColor(uiView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func updateTextColor(_ textField: UITextField) {
        let attributedString = NSMutableAttributedString(string: text)
        
        // Only color actual user names that were inserted from dropdown
        // Look for patterns like @FirstName LastName (with proper capitalization)
        let mentionPattern = "@[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)+"
        let regex = try? NSRegularExpression(pattern: mentionPattern)
        let range = NSRange(location: 0, length: text.utf16.count)
        
        if let matches = regex?.matches(in: text, range: range) {
            for match in matches.reversed() {
                let matchRange = match.range
                let mentionText = (text as NSString).substring(with: matchRange)
                
                // Apply sling blue color to mentions
                let slingBlueColor = UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)
                attributedString.addAttribute(.foregroundColor, value: slingBlueColor, range: matchRange)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 16, weight: .medium), range: matchRange)
            }
        }
        
        // Set default color for non-mention text
        attributedString.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: text.utf16.count))
        
        textField.attributedText = attributedString
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        let parent: ColoredTextField
        
        init(_ parent: ColoredTextField) {
            self.parent = parent
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let oldText = textField.text ?? ""
            
            // If user is deleting (string is empty), check if they're deleting part of a mention
            if string.isEmpty && range.length > 0 {
                let mentionPattern = "@[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)+"
                let regex = try? NSRegularExpression(pattern: mentionPattern)
                let textRange = NSRange(location: 0, length: oldText.utf16.count)
                
                if let matches = regex?.matches(in: oldText, range: textRange) {
                    for match in matches {
                        let mentionRange = match.range
                        // Check if the deletion range overlaps with any mention
                        if NSIntersectionRange(range, mentionRange).length > 0 {
                            // Delete the entire mention instead
                            let beforeMention = (oldText as NSString).substring(to: mentionRange.location)
                            let afterMention = (oldText as NSString).substring(from: mentionRange.location + mentionRange.length)
                            let newText = beforeMention + afterMention
                            
                            DispatchQueue.main.async {
                                self.parent.text = newText
                                self.parent.onTextChange(oldText, newText)
                            }
                            
                            return false // Prevent the original deletion
                        }
                    }
                }
            }
            
            let newText = (oldText as NSString).replacingCharacters(in: range, with: string)
            
            DispatchQueue.main.async {
                self.parent.text = newText
                self.parent.onTextChange(oldText, newText)
            }
            
            return true
        }
    }
}

// MARK: - Colored Text View

struct ColoredTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onTextChange: (String, String) -> Void
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.delegate = context.coordinator
        textView.backgroundColor = UIColor.clear
        textView.textContainerInset = UIEdgeInsets.zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Handle placeholder
        if text.isEmpty {
            uiView.text = placeholder
            uiView.textColor = UIColor.placeholderText
        } else {
            if uiView.text != text {
                uiView.text = text
                updateTextColor(uiView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func updateTextColor(_ textView: UITextView) {
        let attributedString = NSMutableAttributedString(string: text)
        
        // Only color actual user names that were inserted from dropdown
        // Look for patterns like @FirstName LastName (with proper capitalization)
        let mentionPattern = "@[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)+"
        let regex = try? NSRegularExpression(pattern: mentionPattern)
        let range = NSRange(location: 0, length: text.utf16.count)
        
        if let matches = regex?.matches(in: text, range: range) {
            for match in matches.reversed() {
                let matchRange = match.range
                let mentionText = (text as NSString).substring(with: matchRange)
                
                // Apply sling blue color to mentions
                let slingBlueColor = UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)
                attributedString.addAttribute(.foregroundColor, value: slingBlueColor, range: matchRange)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 16, weight: .medium), range: matchRange)
            }
        }
        
        // Set default color for non-mention text
        attributedString.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: text.utf16.count))
        
        textView.attributedText = attributedString
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        let parent: ColoredTextView
        
        init(_ parent: ColoredTextView) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            let oldText = parent.text
            
            DispatchQueue.main.async {
                self.parent.text = newText
                self.parent.onTextChange(oldText, newText)
            }
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            // Clear placeholder when user starts typing
            if textView.text == parent.placeholder {
                textView.text = ""
                textView.textColor = UIColor.label
                parent.text = ""
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            // Show placeholder if empty
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = UIColor.placeholderText
            }
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let oldText = textView.text ?? ""
            
            // If user is deleting (text is empty), check if they're deleting part of a mention
            if text.isEmpty && range.length > 0 {
                let mentionPattern = "@[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)+"
                let regex = try? NSRegularExpression(pattern: mentionPattern)
                let textRange = NSRange(location: 0, length: oldText.utf16.count)
                
                if let matches = regex?.matches(in: oldText, range: textRange) {
                    for match in matches {
                        let mentionRange = match.range
                        // Check if the deletion range overlaps with any mention
                        if NSIntersectionRange(range, mentionRange).length > 0 {
                            // Delete the entire mention instead
                            let beforeMention = (oldText as NSString).substring(to: mentionRange.location)
                            let afterMention = (oldText as NSString).substring(from: mentionRange.location + mentionRange.length)
                            let newText = beforeMention + afterMention
                            
                            DispatchQueue.main.async {
                                self.parent.text = newText
                                self.parent.onTextChange(oldText, newText)
                            }
                            
                            return false // Prevent the original deletion
                        }
                    }
                }
            }
            
            return true
        }
    }
}

// MARK: - Adjust Odds View

struct AdjustOddsView: View {
    @Binding var odds: String
    @Binding var percentage: String
    @Binding var isPresented: Bool
    @State private var sliderValue: Double = 0.0
    @State private var zoomLevel: Int = 0 // 0: default, 1: expanded, 2: full range
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Text("Adjust Odds")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    // Current Odds Display
                    VStack(spacing: 8) {
                        Text(odds)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.slingBlue)
                        
                        Text(percentage)
                            .font(.title3)
                            .foregroundColor(.black)
                    }
                    
                    // Odds Slider
                    VStack(spacing: 16) {
                        // Range Labels
                        HStack {
                            Text("\(getMinRangeText())")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            Text("\(getMaxRangeText())")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Slider(value: $sliderValue, in: getSliderRange(), step: 5)
                            .accentColor(.slingBlue)
                            .onChange(of: sliderValue) { oldValue, newValue in
                                updateOddsAndPercentage(from: newValue)
                                checkAndExpandRange()
                            }
                        
                        // How Odds Work Section
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.slingBlue)
                                
                                Text("How Betting Odds Work")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                            }
                            
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                    
                                    Text("Positive odds (+150): Bet $100 to win $150")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                    
                                    Text("Negative odds (-150): Bet $150 to win $100")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "equal.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    
                                    Text("Even odds (-110): Bet $110 to win $100")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                
                Spacer()
                
                // Done Button
                Button("Done") {
                    isPresented = false
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.slingBlue)
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .onAppear {
                // Initialize slider value based on current odds
                if odds.hasPrefix("+") {
                    sliderValue = Double(odds.dropFirst()) ?? 0.0
                } else {
                    sliderValue = Double(odds) ?? 0.0
                }
            }
        }
    }
    
    private func updateOddsAndPercentage(from sliderValue: Double) {
        // Update odds with proper sign
        if sliderValue > 0 {
            odds = "+" + String(format: "%.0f", sliderValue)
        } else {
            odds = String(format: "%.0f", sliderValue)
        }
        
        // Calculate percentage based on odds
        let percentageValue = calculatePercentage(from: sliderValue)
        percentage = String(format: "%.1f%%", percentageValue)
    }
    
    private func calculatePercentage(from odds: Double) -> Double {
        if odds > 0 {
            return 100.0 / (odds + 100.0) * 100.0
        } else {
            return abs(odds) / (abs(odds) + 100.0) * 100.0
        }
    }
    
    // MARK: - Auto-Expanding Range Helper Functions
    private func getSliderRange() -> ClosedRange<Double> {
        switch zoomLevel {
        case 0: return -500...500
        case 1: return -5000...5000
        case 2: return -100000...100000
        default: return -500...500
        }
    }
    
    private func getMinRangeText() -> String {
        switch zoomLevel {
        case 0: return "-500"
        case 1: return "-5000"
        case 2: return "-100k"
        default: return "-500"
        }
    }
    
    private func getMaxRangeText() -> String {
        switch zoomLevel {
        case 0: return "+500"
        case 1: return "+5000"
        case 2: return "+100k"
        default: return "+500"
        }
    }
    
    private func checkAndExpandRange() {
        let currentRange = getSliderRange()
        
        // If slider is at the edge, expand the range
        if sliderValue >= currentRange.upperBound - 50 {
            if zoomLevel == 0 {
                zoomLevel = 1
            } else if zoomLevel == 1 {
                zoomLevel = 2
            }
        } else if sliderValue <= currentRange.lowerBound + 50 {
            if zoomLevel == 0 {
                zoomLevel = 1
            } else if zoomLevel == 1 {
                zoomLevel = 2
            }
        }
        
        // If slider moves back toward center, contract the range
        if zoomLevel == 2 && sliderValue >= -5000 && sliderValue <= 5000 {
            zoomLevel = 1
        } else if zoomLevel == 1 && sliderValue >= -500 && sliderValue <= 500 {
            zoomLevel = 0
        }
    }
}

// MARK: - Date Picker View

struct DatePickerView: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Select a date and time at least 1 hour in the future for betting to close")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                DatePicker("Select Date", selection: $selectedDate, in: Date().addingTimeInterval(60 * 60)..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(WheelDatePickerStyle())
                    .padding()
                
                Button("Done") {
                    isPresented = false
                }
                .padding()
            }
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Join Community Page

struct JoinCommunityPage: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var firestoreService: FirestoreService
    let onSuccess: (() -> Void)?
    @State private var inviteCode = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @FocusState private var isTextFieldFocused: Bool
    
    // Computed property to validate invite code
    private var isValidInviteCode: Bool {
        let trimmed = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 6 && !trimmed.isEmpty
    }
    
    // Computed property for border color
    private var borderColor: Color {
        if inviteCode.count == 6 {
            return .green
        } else if isTextFieldFocused {
            return .blue
        } else {
            return .clear
        }
    }
    
    // Computed property for validation message
    private var validationMessage: String {
        if inviteCode.isEmpty {
            return ""
        } else if inviteCode.count < 6 {
            return "Enter \(6 - inviteCode.count) more character\(6 - inviteCode.count == 1 ? "" : "s")"
        } else if inviteCode.count == 6 {
            return "Perfect! Code is ready"
        } else {
            return "Code is too long"
        }
    }
    
    init(firestoreService: FirestoreService, onSuccess: (() -> Void)? = nil) {
        self.firestoreService = firestoreService
        self.onSuccess = onSuccess
    }
    
    var body: some View {
            VStack(spacing: 0) {
            // Modern Header - like Sign Up pages
                HStack {
                    Button(action: { dismiss() }) {
                    Image(systemName: "arrow.left")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            
            // Main Content with modern spacing
            VStack(spacing: 40) {
                // Title Section - modern style like Sign Up
                    VStack(spacing: 16) {
                    Text("Join Community")
                        .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                        
                        Text("Enter the 6-character invite code to join a betting group")
                        .font(.body)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                }
                .padding(.top, 40)
                    
                // Input Section with modern styling
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Invite Code")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        ZStack(alignment: .trailing) {
                            TextField("ENTER 6-DIGIT CODE", text: $inviteCode)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                                .textCase(.uppercase)
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(borderColor, lineWidth: 2)
                                        )
                                )
                                .onChange(of: inviteCode) { _, newValue in
                                    // Limit to 6 characters
                                    if newValue.count > 6 {
                                        inviteCode = String(newValue.prefix(6))
                                        // Show brief feedback that input was truncated
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            errorMessage = "Code limited to 6 characters"
                                            // Clear this message after 2 seconds
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                                if errorMessage == "Code limited to 6 characters" {
                                                    errorMessage = ""
                                                }
                                            }
                                        }
                                    } else {
                                        // Only clear error message if it's not a validation error
                                        if errorMessage != "Code limited to 6 characters" {
                                            errorMessage = ""
                                        }
                                    }
                                }
                                .focused($isTextFieldFocused)
                                .onAppear {
                                    isTextFieldFocused = true
                                }
                            
                            // Character counter
                            Text("\(inviteCode.count)/6")
                                .font(.caption)
                                .foregroundColor(inviteCode.count == 6 ? .green : .gray)
                                .fontWeight(.medium)
                                .padding(.trailing, 16)
                        }
                    
                    // Validation message - modern style
                    if !validationMessage.isEmpty {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundColor(inviteCode.count == 6 ? .green : .gray)
                            .animation(.easeInOut(duration: 0.2), value: validationMessage)
                    }
                }
                .padding(.horizontal, 24)
                
                // Error message - modern style
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .animation(.easeInOut(duration: 0.2), value: errorMessage)
                    }
                    
                    Spacer()
            }
                    
            // Bottom Button Section - like Sign Up pages
            VStack(spacing: 16) {
                    Button(action: joinCommunity) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "person.2")
                                    .font(.title3)
                                    .foregroundColor(.white)
                            }
                            
                            Text(isLoading ? "Joining..." : "Join Community")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                            .fill(isValidInviteCode && !isLoading ? Color.slingBlue : Color.gray.opacity(0.3))
                        )
                    }
                    .disabled(!isValidInviteCode || isLoading)
                .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
    }
    
    // MARK: - Actions
    
    private func joinCommunity() {
        let trimmedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🔍 JoinCommunity: Attempting to join with code: '\(trimmedCode)'")
        print("🔍 JoinCommunity: Code length: \(trimmedCode.count)")
        
        isLoading = true
        errorMessage = ""
        
        firestoreService.joinCommunity(inviteCode: trimmedCode) { success, error in
            DispatchQueue.main.async {
                print("🔍 JoinCommunity: Result - Success: \(success), Error: \(error ?? "nil")")
                isLoading = false
                if success {
                    print("✅ JoinCommunity: Successfully joined community")
                    dismiss()
                    onSuccess?()
                } else {
                    let errorMsg = error ?? "Invalid community code. Please try again."
                    print("❌ JoinCommunity: Failed to join - \(errorMsg)")
                    errorMessage = errorMsg
                    // Clear the invite code on error for better UX
                    withAnimation(.easeInOut(duration: 0.2)) {
                        inviteCode = ""
                    }
                }
            }
        }
    }
}

// MARK: - Create Community Page

struct CreateCommunityPage: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var firestoreService: FirestoreService
    let onSuccess: (() -> Void)?
    @State private var communityName = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingShareModal = false
    @State private var createdCommunityId: String?
    @FocusState private var isTextFieldFocused: Bool
    
    init(firestoreService: FirestoreService, onSuccess: (() -> Void)? = nil) {
        self.firestoreService = firestoreService
        self.onSuccess = onSuccess
    }
    
    var body: some View {
            VStack(spacing: 0) {
            // Modern Header - like Sign Up pages
                HStack {
                    Button(action: {
                        isTextFieldFocused = false
                        dismiss()
                    }) {
                    Image(systemName: "arrow.left")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            
            // Main Content with modern spacing
            VStack(spacing: 40) {
                // Title Section - modern style like Sign Up
                    VStack(spacing: 16) {
                    Text("Create Community")
                        .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                        
                        Text("Start a betting group for friends, family, or colleagues")
                        .font(.body)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                }
                .padding(.top, 40)
                    
                // Input Section with modern styling
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Community Name")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        TextField("Enter community name", text: $communityName)
                        .textFieldStyle(ModernTextFieldStyle())
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                .stroke(isTextFieldFocused ? Color.slingBlue : Color.clear, lineWidth: 2)
                            )
                            .focused($isTextFieldFocused)
                            .onAppear {
                                isTextFieldFocused = true
                            }
                            .onChange(of: communityName) { _, newValue in
                                errorMessage = ""
                            }
                    
                    // Character count and validation
                    HStack {
                        if !communityName.isEmpty {
                            if isValidCommunityName {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    Text("Looks good!")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            } else if communityName.count > 50 {
                                Text("Too long")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Spacer()
                        
                        Text("\(communityName.count)/50")
                            .font(.caption)
                            .foregroundColor(communityName.count > 50 ? .red : .gray)
                    }
                    .animation(.easeInOut(duration: 0.2), value: communityName)
                }
                .padding(.horizontal, 24)
                
                // Error message - modern style
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .animation(.easeInOut(duration: 0.2), value: errorMessage)
                    }
                    
                    Spacer()
            }
                    
            // Bottom Button Section - like Sign Up pages
            VStack(spacing: 16) {
                    Button(action: createCommunity) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "person.2")
                                    .font(.title3)
                                    .foregroundColor(.white)
                            }
                            
                            Text(isLoading ? "Creating..." : "Create Community")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                            .fill(isValidCommunityName && !isLoading ? Color.slingBlue : Color.gray.opacity(0.3))
                        )
                    }
                    .disabled(!isValidCommunityName || isLoading)
                .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
        .sheet(isPresented: $showingShareModal) {
            ShareCommunityModal(
                communityName: communityName,
                communityId: createdCommunityId ?? "",
                onDismiss: {
                    dismiss()
                    onSuccess?()
                }
            )
        }
    }
    
    // MARK: - Computed Properties
    
    private var isValidCommunityName: Bool {
        let trimmed = communityName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 50
    }
    
    // MARK: - Actions
    
    private func createCommunity() {
        let trimmedName = communityName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard isValidCommunityName else {
            if trimmedName.isEmpty {
            errorMessage = "Please enter a community name"
            } else if trimmedName.count > 50 {
                errorMessage = "Community name must be 50 characters or less"
            }
            return
        }
        
        isLoading = true
        errorMessage = ""
        isTextFieldFocused = false
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        let inviteCode = UUID().uuidString.prefix(6).uppercased()
        
        SlingLogInfo("Generated 6-character invite code for community: \(trimmedName)")
        
        let communityData: [String: Any] = [
            "name": trimmedName,
            "description": "A new betting community",
            "created_by": firestoreService.currentUser?.email ?? "",
            "created_date": Date(),
            "invite_code": inviteCode,
            "member_count": 1,
            "bet_count": 0,
            "total_bets": 0,
            "is_active": true,
            "is_private": false,
            "updated_date": Date()
        ]
        
        firestoreService.createCommunity(communityData: communityData) { success, error in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    createdCommunityId = error // The error parameter contains the community ID on success
                    showingShareModal = true
                    
                    // Success haptic feedback
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                } else {
                    errorMessage = error ?? "Failed to create community. Please try again."
                    
                    // Error haptic feedback
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                }
            }
        }
    }
}



// MARK: - Share Community Modal

struct ShareCommunityModal: View {
    @Environment(\.dismiss) private var dismiss
    let communityName: String
    let communityId: String
    let onDismiss: () -> Void

    @State private var showConfetti = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { onDismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.black.opacity(0.6))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                
                // Main Success Content
                VStack(spacing: 32) {
                    // Animated Success Icon with Confetti
                    ZStack {
                        // Confetti effect
                        if showConfetti {
                            ConfettiView()
                                .allowsHitTesting(false)
                        }
                        
                        // Success Icon
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                            .scaleEffect(showConfetti ? 1.1 : 1.0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showConfetti)
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showConfetti = true
                        }
                    }
                    
                    // Personalized Headline
                    VStack(spacing: 12) {
                        Text("Welcome to \(communityName) 🎉")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                        
                        Text("Your community is live and ready for action!")
                            .font(.title3)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                    
                    // Quick Share Button
                    Button(action: {
                        shareCommunityLink()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundColor(.white)
                            
                            Text("Share Community Link")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.slingGradient)
                        .cornerRadius(28)
                    }
                    .padding(.horizontal, 20)
                    

                    
                    // Continue to Community Button
                    Button(action: {
                        onDismiss()
                    }) {
                        Text("Continue to Community")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 8)
                }
                
                Spacer()
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }

    }
    
    private func shareCommunityLink() {
        let communityLink = "sling://community/\(communityId)"
        let activityVC = UIActivityViewController(
            activityItems: [
                "Join my community \"\(communityName)\" on Sling! \(communityLink)"
            ],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    @State private var showConfetti = false
    
    var body: some View {
        ZStack {
            if showConfetti {
                ForEach(0..<20, id: \.self) { index in
                    ConfettiPiece(
                        color: [.red, .blue, .green, .yellow, .orange, .purple, .pink][index % 7],
                        size: CGFloat.random(in: 4...8),
                        delay: Double(index) * 0.1
                    )
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showConfetti = true
            }
        }
    }
}

struct ConfettiPiece: View {
    let color: Color
    let size: CGFloat
    let delay: Double
    
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(
                x: isAnimating ? CGFloat.random(in: (-80)...80) : 0,
                y: isAnimating ? CGFloat.random(in: (-120)...(-40)) : 0
            )
            .opacity(isAnimating ? 0 : 1)
            .animation(
                .easeOut(duration: 1.5)
                .delay(delay),
                value: isAnimating
            )
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Invite Members Modal

struct InviteMembersModal: View {
    @Environment(\.dismiss) private var dismiss
    let communityName: String
    let communityId: String
    @State private var emailAddresses = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Text("Invite Members")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text("Invite friends to join \"\(communityName)\"")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Email Input
                VStack(alignment: .leading, spacing: 12) {
                    Text("Email Addresses")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text("Enter email addresses separated by commas")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    TextEditor(text: $emailAddresses)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 20)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal, 20)
                }
                
                if !successMessage.isEmpty {
                    Text(successMessage)
                        .foregroundColor(.green)
                        .font(.caption)
                        .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    
                    Button("Send Invites") {
                        sendInvites()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(emailAddresses.isEmpty || isLoading ? AnyShapeStyle(Color.gray) : AnyShapeStyle(Color.slingGradient))
                    .cornerRadius(10)
                    .disabled(emailAddresses.isEmpty || isLoading)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
    }
    
    private func sendInvites() {
        guard !emailAddresses.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter at least one email address"
            return
        }
        
        isLoading = true
        errorMessage = ""
        successMessage = ""
        
        // Parse email addresses
        let emails = emailAddresses
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // Here you would typically call your FirestoreService to send invites
        // For now, we'll simulate the process
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isLoading = false
            successMessage = "Invites sent to \(emails.count) email(s)!"
            
            // Clear the form after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                emailAddresses = ""
                successMessage = ""
            }
        }
    }
}

// MARK: - Join Bet View

struct JoinBetView: View {
    @Environment(\.dismiss) private var dismiss
    let bet: FirestoreBet
    @ObservedObject var firestoreService: FirestoreService
    let onCommunityTap: (() -> Void)? // Callback for community navigation
    @State private var selectedOption = ""
    @State private var showingBettingInterface = false
    @State private var showingShareSheet = false
    @State private var isRulesExpanded = false
    @State private var betParticipants: [BetParticipant] = []
    @State private var otherBets: [FirestoreBet] = []
    @State private var showingBetDetail = false
    @State private var selectedBetForDetail: FirestoreBet? = nil
    @State private var showingCommunityDetails = false
    @State private var showingCreateBet = false
    @State private var userFullNames: [String: String] = [:]
    
    private var communityName: String {
        if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
            return community.name
        }
        return "Community"
    }
    
    // Function to get user's full name, with caching
    private func getUserFullName(from email: String) -> String {
        // Check cache first
        if let cachedName = userFullNames[email] {
            return cachedName
        }
        
        // For current user, use local data
        if let user = firestoreService.currentUser, user.email == email {
            let fullName = "\(user.first_name ?? "") \(user.last_name ?? "")".trimmingCharacters(in: .whitespaces)
            userFullNames[email] = fullName
            return fullName
        }
        
        // For other users, fetch from Firestore and cache
        firestoreService.getUserDetails(email: email) { fullName, _ in
            DispatchQueue.main.async {
                self.userFullNames[email] = fullName
            }
        }
        
        // Return first name as fallback while fetching
        return email.components(separatedBy: "@").first ?? email
    }
    
    private var creatorName: String {
        let creatorEmail = bet.creator_email
        if let currentUserEmail = firestoreService.currentUser?.email, creatorEmail == currentUserEmail {
            return "You"
        } else {
            return getUserFullName(from: creatorEmail)
        }
    }
    
    private var formattedDeadline: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d'st', yyyy"
        return formatter.string(from: bet.deadline)
    }
    
    private var shortRulesText: String {
        "Every bet on Sling requires two sides to be matched before it's active. Once both users have staked an equal number of Sling Points, the bet becomes locked and cannot be edited or canceled."
    }
    
    private var fullRulesText: String {
        "Every bet on Sling requires two sides to be matched before it's active. Once both users have staked an equal number of Sling Points, the bet becomes locked and cannot be edited or canceled. If only one person has joined, the bet remains unmatched and inactive. After the event concludes, the outcome must be settled by the users, and Sling Points are awarded to the winner accordingly. All bets are tracked within the community they were created in, and participants are responsible for resolving results honestly."
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Top Navigation Bar
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.title3)
                            .foregroundColor(.black)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Bet Title & Meta Information with Image
                        HStack(alignment: .top, spacing: 16) {
                            BetImageView(title: bet.title, imageURL: bet.image_url, size: 64)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(bet.title)
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .multilineTextAlignment(.leading)
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "person.2")
                                        .font(.caption)
                                        .foregroundColor(.slingBlue)
                                    
                                    // Clickable community name
                                    Button(action: {
                                        onCommunityTap?() // Call the callback for community navigation
                                    }) {
                                        Text(communityName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.slingBlue)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Text("• by \(creatorName)")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    Text("Deadline: \(formattedDeadline)")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.leading, 16)
                        
                        // Outcome Selection Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Choose an outcome:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 16)
                            
                            VStack(spacing: 8) {
                                ForEach(bet.options, id: \.self) { option in
                                    Button(action: {
                                        selectedOption = option
                                        showingBettingInterface = true
                                    }) {
                                        HStack {
                                            Text(option)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.black)
                                            
                                            Spacer()
                                            
                                            Text(bet.odds[option] ?? "-110")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.black)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Color.slingLightBlue)
                                        .cornerRadius(12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        
                        // Participant List Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Participant List:")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                            
                            if let participants = getBetParticipants() {
                                if participants.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "person.2.slash")
                                            .font(.title2)
                                            .foregroundColor(.gray.opacity(0.6))
                                        
                                        Text("No active bettors yet")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                            .fontWeight(.medium)
                                        
                                        Text("Be the first to place a bet!")
                                            .font(.caption)
                                            .foregroundColor(.gray.opacity(0.8))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                                } else {
                                    VStack(spacing: 8) {
                                        ForEach(participants, id: \.user_email) { participant in
                                            HStack(spacing: 12) {
                                                Circle()
                                                    .fill(Color.slingGradient)
                                                    .frame(width: 32, height: 32)
                                                    .overlay(
                                                        Text(String(participant.user_email.prefix(1)).uppercased())
                                                            .font(.caption)
                                                            .fontWeight(.semibold)
                                                            .foregroundColor(.white)
                                                    )
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(getUserFullName(from: participant.user_email))
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(.black)
                                                    
                                                    HStack(spacing: 4) {
                                                        Text(participant.chosen_option)
                                                            .font(.caption)
                                                            .foregroundColor(.gray)
                                                        
                                                        Text("•")
                                                            .font(.caption)
                                                            .foregroundColor(.gray)
                                                        
                                                        Image(systemName: "bolt.fill")
                                                            .font(.caption)
                                                            .foregroundColor(.yellow)
                                                        
                                                        Text(String(format: "%.2f", Double(participant.stake_amount)))
                                                            .font(.caption)
                                                            .foregroundColor(.gray)
                                                    }
                                                }
                                                
                                                Spacer()
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                        }
                                    }
                                }
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "person.2.slash")
                                        .font(.title2)
                                        .foregroundColor(.gray.opacity(0.6))
                                    
                                    Text("No active bettors yet")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .fontWeight(.medium)
                                    
                                    Text("Be the first to place a bet!")
                                        .font(.caption)
                                        .foregroundColor(.gray.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                            }
                        }
                        
                        // Betting Rules Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How Betting on Sling Works:")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(isRulesExpanded ? fullRulesText : shortRulesText)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .lineSpacing(4)
                                    .padding(.horizontal, 16)
                                
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        isRulesExpanded.toggle()
                                    }
                                }) {
                                    Text(isRulesExpanded ? "Read Less" : "Read More")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        
                        // Other Bets Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Other Bets to Trade")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                            
                            if let otherBets = getOtherBets() {
                                if otherBets.isEmpty {
                                    VStack(spacing: 16) {
                                        Image(systemName: "tray")
                                            .font(.title2)
                                            .foregroundColor(.gray.opacity(0.6))
                                        
                                        Text("No other bets available")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                                } else {
                                    VStack(spacing: 12) {
                                        ForEach(otherBets.prefix(3), id: \.id) { otherBet in
                                            Button(action: {
                                                // Navigate to bet details
                                                selectedBetForDetail = otherBet
                                                showingBetDetail = true
                                            }) {
                                            HStack(spacing: 12) {
                                                    // Add bet image
                                                    BetImageView(title: otherBet.title, imageURL: otherBet.image_url, size: 40)
                                                    
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(otherBet.title)
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                        .foregroundColor(.black)
                                                        .lineLimit(2)
                                                            .multilineTextAlignment(.leading)
                                                    
                                                    Text("\(getCommunityName(for: otherBet)) • Created by \(getCreatorName(for: otherBet))")
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                                            .multilineTextAlignment(.leading)
                                                        
                                                        // Add deadline info
                                                        Text("Ends \(formatDate(otherBet.deadline))")
                                                            .font(.caption)
                                                            .foregroundColor(.blue)
                                                }
                                                
                                                Spacer()
                                                    
                                                    // Add navigation chevron
                                                    Image(systemName: "chevron.right")
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                            }
                                            .padding(.horizontal, 16)
                                                .padding(.vertical, 12)
                                                .background(Color.white)
                                                .cornerRadius(12)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            } else {
                                VStack(spacing: 16) {
                                    Image(systemName: "tray")
                                        .font(.title2)
                                        .foregroundColor(.gray.opacity(0.6))
                                    
                                    Text("No other bets available")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                            }
                        }
                        
                        Spacer(minLength: 50)
                    }
                    .padding(.top, 20)
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingBettingInterface) {
                if !selectedOption.isEmpty {
                    BettingInterfaceView(
                        bet: bet,
                        selectedOption: selectedOption,
                        firestoreService: firestoreService
                    )
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: ["Check out this bet on Sling: \"\(bet.title)\" created by \(creatorName). Join the action!"])
            }
            .sheet(isPresented: $showingBetDetail) {
                if let selectedBet = selectedBetForDetail {
                    JoinBetView(
                        bet: selectedBet, 
                        firestoreService: firestoreService,
                        onCommunityTap: {
                            // Navigate to community details
                            // This will be handled by the parent view
                        }
                    )
                }
            }
            .sheet(isPresented: $showingCreateBet) {
                CreateBetView(firestoreService: firestoreService, preSelectedCommunity: nil)
            }
            .onAppear {
                loadBetParticipants()
                loadOtherBets()
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func extractUsername(from email: String) -> String {
        return String(email.split(separator: "@").first ?? "Unknown")
    }
    
    private func getBetParticipants() -> [BetParticipant]? {
        return betParticipants
    }
    
    private func getOtherBets() -> [FirestoreBet]? {
        return otherBets
    }
    
    private func getCommunityName(for bet: FirestoreBet) -> String {
        if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
            return community.name
        }
        return "Community"
    }
    
    private func getCreatorName(for bet: FirestoreBet) -> String {
        let creatorEmail = bet.creator_email
        if let currentUserEmail = firestoreService.currentUser?.email, creatorEmail == currentUserEmail {
            return "You"
        } else {
            return getUserFullName(from: creatorEmail)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
    
    private func getFirstNameFromEmail(_ email: String) -> String {
        // Extract first name from email (everything before @)
        let components = email.components(separatedBy: "@")
        if let username = components.first {
            // Capitalize first letter and return
            return username.prefix(1).uppercased() + username.dropFirst()
        }
        return email
    }
    
    private func loadBetParticipants() {
        guard let betId = bet.id else { return }
        
        // Use the existing userBetParticipations and filter for this specific bet
        let participants = firestoreService.userBetParticipations.filter { participant in
            participant.bet_id == betId
        }
        
        DispatchQueue.main.async {
            self.betParticipants = participants
        }
    }
    
    private func loadOtherBets() {
        // Get other active bets from user's communities, excluding the current bet
        let userCommunityIds = firestoreService.userCommunities.compactMap { $0.id }
        let otherActiveBets = firestoreService.bets.filter { bet in
            guard let betId = bet.id, let currentBetId = self.bet.id else { return false }
            return betId != currentBetId && 
                   bet.status.lowercased() == "open" &&
                   userCommunityIds.contains(bet.community_id)
        }
        
        DispatchQueue.main.async {
            self.otherBets = Array(otherActiveBets.prefix(5)) // Limit to 5 bets
        }
    }
}

// MARK: - Settle Bet View
struct SettleBetView: View {
    @Environment(\.dismiss) private var dismiss
    let bet: FirestoreBet
    @ObservedObject var firestoreService: FirestoreService
    @State private var selectedOutcome = ""
    @State private var showingConfirmation = false
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Text("Settle Bet")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        
                        Text(bet.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Outcome Options
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Select Outcome")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        
                        VStack(spacing: 12) {
                            ForEach(bet.options, id: \.self) { option in
                                Button(action: {
                                    selectedOutcome = option
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(option)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(selectedOutcome == option ? .white : .black)
                                        }
                                        
                                        Spacer()
                                        
                                        if selectedOutcome == option {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.white)
                                                .font(.title3)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(selectedOutcome == option ? Color.green : Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                                }
                            }
                            
                            // Void Option
                            Button(action: {
                                selectedOutcome = "void"
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Void Market")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(selectedOutcome == "void" ? .white : .red)
                                        
                                        Text("Refund all participants")
                                            .font(.caption)
                                            .foregroundColor(selectedOutcome == "void" ? .white.opacity(0.8) : .gray)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedOutcome == "void" {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.white)
                                            .font(.title3)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(selectedOutcome == "void" ? Color.red : Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Action Button
                    Button(action: {
                        showingConfirmation = true
                    }) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Settle Bet")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(selectedOutcome.isEmpty ? Color.gray : Color.green)
                    .cornerRadius(10)
                    .disabled(selectedOutcome.isEmpty || isLoading)
                    .padding(.horizontal, 20)
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .alert("Confirm Settlement", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Settle") {
                    settleBet()
                }
            } message: {
                Text("Are you sure you want to settle this bet with '\(selectedOutcome)' as the outcome?")
            }
        }
    }
    
    private func settleBet() {
        guard let betId = bet.id, selectedOutcome != "void" else {
            // Handle void case separately
            return
        }
        
        isLoading = true
        
        firestoreService.settleBet(betId: betId, winnerOption: selectedOutcome) { success in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    dismiss()
                } else {
                    // Handle error - could show an alert
                    print("Error settling bet: Unknown error")
                }
            }
        }
    }
}

// MARK: - Helper Functions

func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

func convertToNotificationItem(_ firestoreNotification: FirestoreNotification) -> NotificationItem {
        // Map icon string to system icon name
        let iconName: String
        let iconColor: Color
        
        switch firestoreNotification.icon.lowercased() {
        case "users", "person.2":
            iconName = "person.2"
            iconColor = .blue
        case "chart.line.uptrend.xyaxis":
            iconName = "chart.line.uptrend.xyaxis"
            iconColor = .purple
        case "person.2.slash":
            iconName = "person.2.slash"
            iconColor = .red
        case "checkmark.circle":
            iconName = "checkmark.circle"
            iconColor = .green
        case "xmark.circle":
            iconName = "xmark.circle"
            iconColor = .red
        case "person.badge.plus":
            iconName = "person.badge.plus"
            iconColor = .green
        case "plus.circle":
            iconName = "plus.circle"
            iconColor = .blue
        case "bell":
            iconName = "bell"
            iconColor = .orange
        default:
            iconName = "bell"
            iconColor = .gray
        }
        
        // Format timestamp
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timestamp = formatter.string(from: firestoreNotification.created_date)
        
        return NotificationItem(
            id: firestoreNotification.id,
            icon: iconName,
            iconColor: iconColor,
            text: firestoreNotification.message,
            timestamp: timestamp,
            isUnread: !firestoreNotification.is_read,
            communityName: firestoreNotification.community_name,
            communityIcon: firestoreNotification.community_icon
        )
}

// MARK: - Betting Interface View

struct BettingInterfaceView: View {
    @Environment(\.dismiss) private var dismiss
    let bet: FirestoreBet
    @State private var selectedOption: String
    @ObservedObject var firestoreService: FirestoreService
    @State private var betAmount = ""
    @State private var isLoading = false
    @State private var showingOptionPicker = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var userFullNames: [String: String] = [:]
    
    // Pre-set bet amounts
    private let presetAmounts = [10, 25, 50, 100]
    
    // Computed properties for validation
    private var currentBalance: Int {
        firestoreService.currentUser?.blitz_points ?? 0
    }
    
    private var betAmountDouble: Double {
        Double(betAmount) ?? 0
    }
    
    private var hasInsufficientFunds: Bool {
        betAmountDouble > Double(currentBalance)
    }
    
    private var canProceed: Bool {
        !betAmount.isEmpty && betAmountDouble > 0 && !hasInsufficientFunds
    }
    
    // Calculate total potential payout (including initial wager)
    private var potentialWinnings: Double {
        if let amount = Double(betAmount), amount > 0 {
            let payout = calculatePayout(amount: amount, odds: bet.odds[selectedOption] ?? "-110")
            return payout // Total payout including initial wager
        }
        return 0
    }
    
    // Number formatter for adding commas and ensuring 2 decimal places
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
    
    // Initialize with selected option
    init(bet: FirestoreBet, selectedOption: String, firestoreService: FirestoreService) {
        self.bet = bet
        // Ensure we have a valid selectedOption, fallback to first option if empty
        let validOption = selectedOption.isEmpty ? (bet.options.first ?? "Yes") : selectedOption
        self._selectedOption = State(initialValue: validOption)
        self.firestoreService = firestoreService
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Simple Header
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.black)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                // Event/Question Section
                eventQuestionSection
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer()
                
                // Large Amount Display
                    VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 40))
                            .foregroundColor(Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)))
                        
                        Text(betAmount.isEmpty ? "0.00" : (numberFormatter.string(from: NSNumber(value: Double(betAmount) ?? 0)) ?? String(format: "%.2f", Double(betAmount) ?? 0)))
                            .font(.system(size: 80, weight: .bold, design: .default))
                            .foregroundColor(.black)
                    }
                        
                    HStack(spacing: 4) {
                        Text("Available:")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Image(systemName: "bolt.fill")
                            .font(.subheadline)
                            .foregroundColor(Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)))
                        
                        Text(numberFormatter.string(from: NSNumber(value: Double(currentBalance))) ?? String(format: "%.2f", Double(currentBalance)))
                                .font(.subheadline)
                        .foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 40)
                
                // Error message for insufficient funds
                if hasInsufficientFunds {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Insufficient Sling Points. You have \(String(format: "%.2f", Double(currentBalance))) points.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                    
                // Fixed height container for preset buttons or submit button
                bettingActionSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                
                // Simple Numeric Keypad
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(1...3, id: \.self) { number in
                            SimpleKeypadButton(number: "\(number)", action: { appendToBetAmount("\(number)") })
                        }
                    }
                    
                    HStack(spacing: 12) {
                        ForEach(4...6, id: \.self) { number in
                            SimpleKeypadButton(number: "\(number)", action: { appendToBetAmount("\(number)") })
                        }
                    }
                    
                    HStack(spacing: 12) {
                        ForEach(7...9, id: \.self) { number in
                            SimpleKeypadButton(number: "\(number)", action: { appendToBetAmount("\(number)") })
                        }
                    }
                    
                    HStack(spacing: 12) {
                        SimpleKeypadButton(number: ".", action: { appendToBetAmount(".") })
                        SimpleKeypadButton(number: "0", action: { appendToBetAmount("0") })
                        Button(action: { deleteLastCharacter() }) {
                            Image(systemName: "delete.left")
                                .font(.title2)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 60)
                                .background(Color.white)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .actionSheet(isPresented: $showingOptionPicker) {
                ActionSheet(
                    title: Text("Choose Your Bet"),
                    buttons: bet.options.map { option in
                        .default(Text("\(option) (\(bet.odds[option] ?? "-110"))")) {
                            selectedOption = option
                        }
                    } + [.cancel()]
                )
            }
        }
    }
    
    private func extractUsername(from email: String) -> String {
        return String(email.split(separator: "@").first ?? "Unknown")
    }
    
    // Function to get user's full name, with caching
    private func getUserFullName(from email: String) -> String {
        // Check cache first
        if let cachedName = userFullNames[email] {
            return cachedName
        }
        
        // For current user, use local data
        if let user = firestoreService.currentUser, user.email == email {
            let fullName = "\(user.first_name ?? "") \(user.last_name ?? "")".trimmingCharacters(in: .whitespaces)
            userFullNames[email] = fullName
            return fullName
        }
        
        // For other users, fetch from Firestore and cache
        firestoreService.getUserDetails(email: email) { fullName, _ in
            DispatchQueue.main.async {
                self.userFullNames[email] = fullName
            }
        }
        
        // Return first name as fallback while fetching
        return email.components(separatedBy: "@").first ?? email
    }
    
    private func appendToBetAmount(_ character: String) {
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        if character == "." {
            if !betAmount.contains(".") {
                betAmount += character
            }
        } else {
            betAmount += character
        }
    }
    
    private func deleteLastCharacter() {
        if !betAmount.isEmpty {
            // Add haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            betAmount.removeLast()
        }
    }
    
    private func calculatePayout(amount: Double, odds: String) -> Double {
        // Simple payout calculation based on American odds
        if odds.hasPrefix("-") {
            // Negative odds (favorite)
            let oddsValue = Double(odds.dropFirst()) ?? 110
            return amount * (100 / oddsValue) + amount
        } else {
            // Positive odds (underdog)
            let oddsValue = Double(odds) ?? 110
            return amount * (oddsValue / 100) + amount
        }
    }
    
    private func confirmBet() {
        print("🎯 confirmBet called")
        print("📊 betAmount: \(betAmount)")
        print("📊 selectedOption: \(selectedOption)")
        print("📊 bet.id: \(bet.id ?? "nil")")
        
        guard let betAmountDouble = Double(betAmount), betAmountDouble > 0,
              let betId = bet.id else { 
            print("❌ Invalid bet data - betAmountDouble: \(Double(betAmount) ?? 0), betId: \(bet.id ?? "nil")")
            return 
        }
        
        print("✅ Valid bet data - betAmountDouble: \(betAmountDouble), betId: \(betId)")
        
        isLoading = true
        errorMessage = ""
        
        firestoreService.joinBet(
            betId: betId,
            chosenOption: selectedOption,
            stakeAmount: Int(betAmountDouble)
        ) { success, error in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    print("✅ Bet placed successfully")
                    showSuccess = true
                    firestoreService.refreshCurrentUser()
                    
                    // Auto-dismiss after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        dismiss()
                    }
                } else {
                    print("❌ Failed to place bet: \(error ?? "Unknown error")")
                    errorMessage = error ?? "Failed to place bet. Please try again."
                    showError = true
                }
            }
        }
    }
    
    @ViewBuilder
    private var eventQuestionSection: some View {
        HStack(spacing: 12) {
            // Profile picture with actual image
            AsyncImage(url: URL(string: bet.image_url ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(bet.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                
                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
                        Text(community.name)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Text("• by \(getUserFullName(from: bet.creator_email))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Button(action: {
                    showingOptionPicker = true
                }) {
                    HStack(spacing: 8) {
                        Text("Your choice:")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text("\(selectedOption)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)))
                        
                        Text(bet.odds[selectedOption] ?? "-110")
                            .font(.subheadline)
                            .foregroundColor(.black)
                        
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)))
                    }
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var bettingActionSection: some View {
        VStack {
            // Preset Amount Buttons (2x2 grid) - show when amount is 0
            if betAmountDouble == 0 {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach([10, 25], id: \.self) { amount in
                            Button(action: {
                                betAmount = "\(amount)"
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                        .font(.caption)
                                        .foregroundColor(Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)))
                                    Text("\(amount)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        .background(Color.white)
                                )
                            }
                        }
                    }
                    
                    HStack(spacing: 12) {
                        ForEach([50, 100], id: \.self) { amount in
                            Button(action: {
                                betAmount = "\(amount)"
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                        .font(.caption)
                                        .foregroundColor(Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)))
                                    Text("\(amount)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        .background(Color.white)
                                )
                            }
                        }
                    }
                }
            } else if betAmountDouble > 0 && canProceed {
                // Submit Button (shows winnings when amount entered)
                Button(action: {
                    confirmBet()
                }) {
                    VStack(spacing: 4) {
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                                Text("Placing Bet...")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                                }
                            } else if showSuccess {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Bet Placed!")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                }
                            } else {
                                Text("Submit Bet")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                HStack(spacing: 4) {
                                    Text("Total Payout:")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Image(systemName: "bolt.fill")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                    
                                    Text(numberFormatter.string(from: NSNumber(value: potentialWinnings)) ?? String(format: "%.2f", potentialWinnings))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(showSuccess ? AnyShapeStyle(Color.green) : (isLoading ? AnyShapeStyle(Color.gray) : AnyShapeStyle(Color.slingGradient)))
                        )
                    }
                    .disabled(!canProceed || isLoading || showSuccess)
                } else {
                    // Empty placeholder to maintain consistent height when amount is invalid
                    Color.clear
                        .frame(height: 76) // Same height as preset button rows
                }
            }
            .frame(height: 76) // Fixed height container
        }
    }

// MARK: - Simple Keypad Button

struct SimpleKeypadButton: View {
    let number: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(number)
                .font(.system(size: 28, weight: .medium, design: .default))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color.white)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Legacy Keypad Button (for compatibility)

struct KeypadButton: View {
    let number: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(number)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }
}

// MARK: - Bet Review View

struct BetReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let bet: FirestoreBet
    let selectedOption: String
    let betAmount: String
    let firestoreService: FirestoreService
    let onConfirm: () -> Void
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Review Your Bet")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text("Double-check your bet before confirming")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(.top, 20)
                
                // Bet Details Card
                VStack(spacing: 20) {
                    // Event details
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Event")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .textCase(.uppercase)
                        
                        Text(bet.title)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                    
                    // Your pick
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Pick")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .textCase(.uppercase)
                        
                        HStack {
                            Text(selectedOption)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                            
                            Spacer()
                            
                            Text(bet.odds[selectedOption] ?? "-110")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                    
                    // Bet amount
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Bet Amount")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .textCase(.uppercase)
                        
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.subheadline)
                                    .foregroundColor(.yellow)
                                Text(betAmount)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                            }
                            
                            Spacer()
                            
                            if let betAmountDouble = Double(betAmount), betAmountDouble > 0 {
                                let payout = calculatePayout(amount: betAmountDouble, odds: bet.odds[selectedOption] ?? "-110")
                                Text("Payout: \(String(format: "%.0f", payout))")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        confirmBet()
                    }) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else if showSuccess {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                                Text("Bet Placed!")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        } else {
                            Text("Confirm Bet")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(showSuccess ? AnyShapeStyle(Color.green) : (isLoading ? AnyShapeStyle(Color.gray) : AnyShapeStyle(Color.slingGradient)))
                    .cornerRadius(12)
                    .disabled(isLoading || showSuccess)
                    .opacity(isLoading || showSuccess ? 0.6 : 1.0)
                    
                    if !showSuccess {
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Back to Edit")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func confirmBet() {
        print("🎯 confirmBet called")
        print("📊 betAmount: \(betAmount)")
        print("📊 selectedOption: \(selectedOption)")
        print("📊 bet.id: \(bet.id ?? "nil")")
        
        guard let betAmountDouble = Double(betAmount), betAmountDouble > 0,
              let betId = bet.id else { 
            print("❌ Invalid bet data - betAmountDouble: \(Double(betAmount) ?? 0), betId: \(bet.id ?? "nil")")
            return 
        }
        
        print("✅ Valid bet data - betAmountDouble: \(betAmountDouble), betId: \(betId)")
        print("💰 Stake amount (points): \(Int(betAmountDouble))")
        
        isLoading = true
        
        // Add a timeout to prevent getting stuck
        var timeoutTask: DispatchWorkItem?
        timeoutTask = DispatchWorkItem {
            if isLoading {
                
                print("⏰ Timeout reached - resetting loading state")
                isLoading = false
                errorMessage = "Request timed out. Please try again."
                showError = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeoutTask!)
        
        firestoreService.joinBet(
            betId: betId,
            chosenOption: selectedOption,
            stakeAmount: Int(betAmountDouble) // Use points directly, not cents
        ) { success, error in
            DispatchQueue.main.async {
                // Cancel timeout task
                timeoutTask?.cancel()
                isLoading = false
                if success {
                    print("✅ Bet placed successfully!")
                    showSuccess = true
                    // Dismiss after a short delay to show success message
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        print("🎉 Calling onConfirm and dismiss")
                        onConfirm()
                        dismiss()
                    }
                } else {
                    // Handle error - show alert to user
                    print("❌ Error placing bet: \(error ?? "Unknown error")")
                    errorMessage = error ?? "Unknown error occurred while placing your bet"
                    showError = true
                }
            }
        }
    }
    
    private func calculatePayout(amount: Double, odds: String) -> Double {
        // Simple payout calculation based on American odds
        if odds.hasPrefix("-") {
            // Negative odds (favorite)
            let oddsValue = Double(odds.dropFirst()) ?? 110
            return amount * (100 / oddsValue) + amount
        } else {
            // Positive odds (underdog)
            let oddsValue = Double(odds) ?? 110
            return amount * (oddsValue / 100) + amount
        }
    }
}

// MARK: - Enhanced Bet Card (handles all user states)

// MARK: - Swipeable Bet Card with Modern Design
struct SwipeableBetCard: View {
    // MARK: - Properties
    let bet: FirestoreBet
    let currentUserEmail: String?
    @ObservedObject private var firestoreService: FirestoreService
    
    // MARK: - State
    @State private var offset: CGFloat = 0
    @State private var showingCancelAlert = false
    @State private var showingChooseWinnerSheet = false
    @State private var showingPlaceBetSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingShareSheet = false
    @State private var showingBetDetail = false
    @State private var showingBettingInterface = false
    @State private var selectedBettingOption = ""
    @State private var showingCommunityDetails = false
    @State private var userBets: [BetParticipant] = []
    @State private var hasUserParticipated: Bool = false
    @State private var hasAnyBets: Bool = false
    @State private var hasRemindedCreator = false
    @State private var optionCounts: [String: Int] = [:]
    @State private var creatorName: String = ""
    @State private var userFullNames: [String: String] = [:]
    
    // MARK: - Constants
    private let swipeThreshold: CGFloat = 80
    private let maxSwipeDistance: CGFloat = 240
    
    // MARK: - Initialization
    init(bet: FirestoreBet,
         currentUserEmail: String?,
         firestoreService: FirestoreService)
    {
        self.bet = bet
        self.currentUserEmail = currentUserEmail
        self._firestoreService = ObservedObject(wrappedValue: firestoreService)
    }
    
    // MARK: - Computed Properties
    private var communityName: String {
        if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
            return community.name
        }
        return "Community"
    }
    
    private var isCreator: Bool {
        return currentUserEmail == bet.creator_email
    }
    
    private var userParticipation: BetParticipant? {
        return firestoreService.userBetParticipations.first { participation in
            participation.bet_id == bet.id && participation.user_email == currentUserEmail
        }
    }
    
    private var hasWager: Bool {
        return userParticipation != nil
    }
    
    private var formattedClosingDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d 'at' h:mm a"
        return formatter.string(from: bet.deadline)
    }
    
    private var timeUntilDeadline: String {
        let now = Date()
        let timeInterval = bet.deadline.timeIntervalSince(now)
        
        if timeInterval <= 0 {
            return "Closed"
        } else if timeInterval < 3600 { // Less than 1 hour
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m left"
        } else if timeInterval < 86400 { // Less than 24 hours
            let hours = Int(timeInterval / 3600)
            return "\(hours)h left"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days)d left"
        }
    }
    
    // Helper function to get creator initials
    private func getCreatorInitials() -> String {
        if isCreator {
            return getCurrentUserInitials()
        } else {
            return getOtherCreatorInitials()
        }
    }
    
    private func getCurrentUserInitials() -> String {
        let user = firestoreService.currentUser
        if let firstName = user?.first_name, let lastName = user?.last_name, !firstName.isEmpty, !lastName.isEmpty {
            let firstInitial = String(firstName.prefix(1)).uppercased()
            let lastInitial = String(lastName.prefix(1)).uppercased()
            return "\(firstInitial)\(lastInitial)"
        } else if let displayName = user?.display_name, !displayName.isEmpty {
            let components = displayName.components(separatedBy: " ")
            if components.count >= 2 {
                let firstInitial = String(components[0].prefix(1)).uppercased()
                let lastInitial = String(components[1].prefix(1)).uppercased()
                return "\(firstInitial)\(lastInitial)"
            } else if components.count == 1 {
                return String(components[0].prefix(1)).uppercased()
            }
        } else if let email = user?.email {
            return String(email.prefix(1)).uppercased()
        }
        return "U"
    }
    
    private func getOtherCreatorInitials() -> String {
        if !creatorName.isEmpty && creatorName != "You" {
            let components = creatorName.components(separatedBy: " ")
            if components.count >= 2 {
                let firstInitial = String(components[0].prefix(1)).uppercased()
                let lastInitial = String(components[1].prefix(1)).uppercased()
                return "\(firstInitial)\(lastInitial)"
            } else if components.count == 1 {
                return String(components[0].prefix(1)).uppercased()
            }
        }
        // Fallback to email initial
        return String(bet.creator_email.prefix(1)).uppercased()
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Background action buttons - only show when swiped
            if offset < 0 {
                HStack {
                    Spacer()
                    actionButtonsView
                }
            }
            
            // Main card content with new design matching the image
            VStack(alignment: .leading, spacing: 12) {
                // Header with profile picture and question
                Button(action: {
                    showingBetDetail = true
                }) {
                    HStack(alignment: .top, spacing: 12) {
                        // Profile Picture
                        Circle()
                            .fill(Color.slingGradient)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(getCreatorInitials())
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // Question title with creator pill on the right
                            HStack(alignment: .top) {
                                Text(bet.title)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Creator crown pill for creators (top right)
                                if isCreator {
                                    HStack(spacing: 4) {
                                        Image(systemName: "crown.fill")
                                            .font(.caption)
                                            .foregroundColor(.purple)
                                        Text("Creator")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.purple)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.1))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.purple, lineWidth: 0.5)
                                    )
                                }
                            }
                            
                            // Community and creator info
                            HStack(spacing: 4) {
                                Image(systemName: "person.2")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Text("\(communityName) • by \(isCreator ? "You" : (creatorName.isEmpty ? getUserFullName(from: bet.creator_email) : creatorName))")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                
                                Spacer()
                            }
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Betting deadline
                Button(action: {
                    showingBetDetail = true
                }) {
                    Text("Betting closes: \(formattedClosingDate)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PlainButtonStyle())
                
                // User's pick and wager section (always present to maintain consistent card size)
                if hasWager, let participation = userParticipation {
                    Button(action: {
                        showingBetDetail = true
                    }) {
                        HStack(alignment: .top) {
                            // Left side - You Picked
                            VStack(alignment: .leading, spacing: 4) {
                                Text("You Picked")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                
                                // Option with odds
                                let optionOdds = bet.odds[participation.chosen_option] ?? ""
                                Text("\(participation.chosen_option) \(optionOdds)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                            }
                            
                            Spacer()
                            
                            // Right side - Wager
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Wager")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                    Text(String(format: "%.2f", Double(participation.stake_amount)))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Empty space with same height to maintain consistent card size
                    VStack {
                        Spacer()
                    }
                    .frame(height: 88) // Same height as the wager section above
                }
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            .offset(x: offset)
            .onTapGesture {
                // Only handle tap if card is not swiped
                if offset != 0 {
                    // Reset swipe when tapping on the card
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        offset = 0
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let translation = value.translation.width
                        if translation < 0 { // Only allow left swipe
                            offset = max(translation, -maxSwipeDistance)
                        } else if offset < 0 { // Allow right swipe only if already swiped left
                            offset = min(offset + translation, 0)
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if offset < -swipeThreshold {
                                offset = -240 // Show all three actions
                            } else {
                                offset = 0 // Hide actions
                            }
                        }
                    }
            )
        }
        .clipped()
        .onAppear {
            loadUserParticipation()
            loadBetStatus()
            loadCreatorName()
        }
        .sheet(isPresented: $showingChooseWinnerSheet) {
            ChooseWinnerView(bet: bet, firestoreService: firestoreService)
        }
        .sheet(isPresented: $showingPlaceBetSheet) {
            PlaceBetView(bet: bet, presetOption: nil, firestoreService: firestoreService)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [generateShareText()])
        }
        .sheet(isPresented: $showingBetDetail) {
            JoinBetView(
                bet: bet, 
                firestoreService: firestoreService,
                onCommunityTap: {
                    // Navigate to community details
                    // This will be handled by the parent view
                }
            )
        }
        .sheet(isPresented: $showingBettingInterface) {
            if !selectedBettingOption.isEmpty {
                BettingInterfaceView(
                    bet: bet,
                    selectedOption: selectedBettingOption,
                    firestoreService: firestoreService
                )
            }
        }
        .sheet(isPresented: $showingCommunityDetails) {
            if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
                EnhancedCommunityDetailView(
                    community: community, 
                    firestoreService: firestoreService,
                    onChatTap: {
                        // Navigate to chat for this community
                        // This will be handled by the parent view
                    }
                )
            }
        }
        .alert("Cancel Market", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Market", role: .destructive) {
                deleteMarket()
            }
        } message: {
            Text("Are you sure you want to delete this market? This action cannot be undone.")
        }
        .alert("Cancel Bet", isPresented: $showingCancelAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Cancel Bet", role: .destructive) {
                cancelBet()
            }
        } message: {
            Text("Are you sure you want to cancel your bet? Your wager will be returned.")
        }
    }
    
    // MARK: - Action Buttons View
    @ViewBuilder
    private var actionButtonsView: some View {
        HStack(spacing: 0) {
            if isCreator {
                // Creator actions: Share, Settle Bet, Delete Market
                
                // Share button
                Button(action: {
                    withAnimation { offset = 0 }
                    showingShareSheet = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                        Text("Share")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(width: 80)
                    .frame(maxHeight: .infinity)
                    .background(Color.gray)
                    .cornerRadius(0)
                }
                
                // Settle bet button
                Button(action: {
                    withAnimation { offset = 0 }
                    showingChooseWinnerSheet = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.title2)
                        Text("Settle")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(width: 80)
                    .frame(maxHeight: .infinity)
                    .background(Color.slingGradient)
                    .cornerRadius(0)
                }
                
                // Delete market button
                Button(action: {
                    withAnimation { offset = 0 }
                    showingDeleteAlert = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.title2)
                        Text("Trash")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(width: 80)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                    .cornerRadius(0)
                }
                
            } else {
                // Participant actions: Remind Creator, Delete Bet, Share
                
                // Remind creator button
                Button(action: {
                    withAnimation { offset = 0 }
                    remindCreator()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "bell.fill")
                            .font(.title2)
                        Text("Remind")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(width: 80)
                    .frame(maxHeight: .infinity)
                    .background(Color.slingGradient)
                    .cornerRadius(0)
                }
                
                // Delete bet button (cancel user's bet)
                Button(action: {
                    withAnimation { offset = 0 }
                    showingCancelAlert = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                        Text("Delete Bet")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(width: 80)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                    .cornerRadius(0)
                }
                
                // Share button
                Button(action: {
                    withAnimation { offset = 0 }
                    showingShareSheet = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                        Text("Share")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(width: 80)
                    .frame(maxHeight: .infinity)
                    .background(Color.gray)
                    .cornerRadius(0)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func extractUsername(from email: String) -> String {
        return String(email.split(separator: "@").first ?? "Unknown")
    }
    
    // Function to get user's full name, with caching
    private func getUserFullName(from email: String) -> String {
        // Check cache first
        if let cachedName = userFullNames[email] {
            return cachedName
        }
        
        // For current user, use local data
        if let user = firestoreService.currentUser, user.email == email {
            let fullName = "\(user.first_name ?? "") \(user.last_name ?? "")".trimmingCharacters(in: .whitespaces)
            userFullNames[email] = fullName
            return fullName
        }
        
        // For other users, fetch from Firestore and cache
        firestoreService.getUserDetails(email: email) { fullName, _ in
            DispatchQueue.main.async {
                self.userFullNames[email] = fullName
            }
        }
        
        // Return first name as fallback while fetching
        return email.components(separatedBy: "@").first ?? email
    }
    
    private func generateShareText() -> String {
        let creatorName = isCreator ? "I" : getUserFullName(from: bet.creator_email)
        return "Check out this bet on Sling: \"\(bet.title)\" created by \(creatorName). Join the action!"
    }
    
    private func loadUserParticipation() {
        guard let _ = bet.id,
              let _ = currentUserEmail else { return }
        
        firestoreService.fetchUserIndividualBets { userBets in
            DispatchQueue.main.async {
                self.userBets = userBets
                self.hasUserParticipated = !userBets.isEmpty
            }
        }
    }
    
    private func loadBetStatus() {
        guard let _ = bet.id else { return }
        
        firestoreService.fetchBetStatus(betId: bet.id ?? "") { status in
            DispatchQueue.main.async {
                // For now, we'll set hasAnyBets based on whether there are user bets
                self.hasAnyBets = !self.userBets.isEmpty
                // optionCounts will need to be populated separately if needed
            }
        }
    }
    
    private func remindCreator() {
        guard let _ = bet.id else { return }
        firestoreService.remindCreator(betId: bet.id ?? "") { success in
            if success {
                DispatchQueue.main.async {
                    hasRemindedCreator = true
                }
            }
        }
    }
    
    private func loadCreatorName() {
        guard currentUserEmail != bet.creator_email else {
            creatorName = "You"
            return
        }
        
        // Try to get user details from Firestore Users collection
        firestoreService.db.collection("Users").document(bet.creator_email).getDocument { document, error in
            DispatchQueue.main.async {
                if let document = document, document.exists,
                   let data = document.data(),
                   let firstName = data["first_name"] as? String,
                   let lastName = data["last_name"] as? String,
                   !firstName.isEmpty, !lastName.isEmpty {
                    self.creatorName = "\(firstName) \(lastName)"
                } else if let document = document, document.exists,
                          let data = document.data(),
                          let displayName = data["display_name"] as? String,
                          !displayName.isEmpty {
                    self.creatorName = displayName
                } else {
                    // Fallback to email username if no name data found
                    self.creatorName = bet.creator_email.components(separatedBy: "@").first ?? bet.creator_email
                }
            }
        }
    }
    
    private func deleteMarket() {
        guard let _ = bet.id else { return }
        firestoreService.deleteBet(betId: bet.id ?? "") { success in
            if success {
                // Refresh the bets list
                firestoreService.fetchUserBets { _ in }
            }
        }
    }
    
    private func cancelBet() {
        guard let _ = bet.id else { return }
        
        firestoreService.cancelUserBet(betId: bet.id ?? "") { success in
            if success {
                DispatchQueue.main.async {
                    hasUserParticipated = false
                    userBets = []
                }
                firestoreService.fetchUserBets { _ in }
            }
        }
    }
}

struct EnhancedBetCard: View {
    // MARK: - Properties
    let bet: FirestoreBet
    let currentUserEmail: String?
    @ObservedObject private var firestoreService: FirestoreService
    
    // MARK: - State
    @State private var showingCancelAlert = false
    @State private var showingChooseWinnerSheet = false
    @State private var showingPlaceBetSheet = false
    @State private var userBets: [BetParticipant] = []
    @State private var hasUserParticipated: Bool = false
    @State private var hasAnyBets: Bool = false
    @State private var hasRemindedCreator = false
    @State private var optionCounts: [String: Int] = [:]
    @State private var userFullNames: [String: String] = [:]
    
    // MARK: - Initialization
    init(bet: FirestoreBet,
         currentUserEmail: String?,
         firestoreService: FirestoreService)
    {
        self.bet = bet
        self.currentUserEmail = currentUserEmail
        self._firestoreService = ObservedObject(wrappedValue: firestoreService)
    }
    
    // MARK: - Computed Properties
    private var communityName: String {
        if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
            return community.name
        }
        return "Community"
    }
    
    private var isCreator: Bool {
        return currentUserEmail == bet.creator_email
    }
    
    private var userPick: String {
        if let userBet = userBets.first {
            return userBet.chosen_option
        }
        return "N/A"
    }
    
    private var userOdds: String {
        if let userBet = userBets.first,
           let odds = bet.odds[userBet.chosen_option] {
            return odds
        }
        return "N/A"
    }
    
    private var userWager: Double {
        if let userBet = userBets.first {
            return Double(userBet.stake_amount)
        }
        return 0.0
    }
    
    private var formattedClosingDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d 'at' h:mm a"
        return formatter.string(from: bet.deadline)
    }
    
    // Function to get user's full name, with caching
    private func getUserFullName(from email: String) -> String {
        // Check cache first
        if let cachedName = userFullNames[email] {
            return cachedName
        }
        
        // For current user, use local data
        if let user = firestoreService.currentUser, user.email == email {
            let fullName = "\(user.first_name ?? "") \(user.last_name ?? "")".trimmingCharacters(in: .whitespaces)
            userFullNames[email] = fullName
            return fullName
        }
        
        // For other users, fetch from Firestore and cache
        firestoreService.getUserDetails(email: email) { fullName, _ in
            DispatchQueue.main.async {
                self.userFullNames[email] = fullName
            }
        }
        
        // Return first name as fallback while fetching
        return email.components(separatedBy: "@").first ?? email
    }
    
    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Section
            VStack(alignment: .leading, spacing: 8) {
                // Market Title
                Text(bet.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .lineLimit(2)
                
                // Community Name & Creator
                                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("\(communityName) • by \(isCreator ? "You" : getUserFullName(from: bet.creator_email))")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
            }
            
            // Content based on state
            if isCreator {
                // Creator states
                if !hasAnyBets {
                    // State 1: Creator with no bets placed
                    creatorNoBetsContent
                } else if !hasUserParticipated {
                    // State 2: Creator with other bets placed, creator hasn't bet
                    creatorOthersBetContent
                } else {
                    // State 4: Creator who also placed a bet
                    creatorParticipatedContent
                }
            } else if hasUserParticipated {
                // State 3: Non-creator who placed a bet
                participantContent
            } else {
                // Default case for non-participants
                nonParticipantContent
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .onAppear {
            loadUserParticipation()
            loadBetStatus()
        }
        .sheet(isPresented: $showingChooseWinnerSheet) {
            ChooseWinnerView(bet: bet, firestoreService: firestoreService)
        }
        .sheet(isPresented: $showingPlaceBetSheet) {
            PlaceBetView(bet: bet, presetOption: nil, firestoreService: firestoreService)
        }
        .alert("Cancel Market", isPresented: $showingCancelAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Cancel Market", role: .destructive) {
                cancelMarket()
            }
        } message: {
            Text("Are you sure you want to cancel this market? This will return all wagers to participants.")
        }
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private var creatorNoBetsContent: some View {
        // State 1: Creator with no bets placed
        VStack(alignment: .leading, spacing: 16) {
            // Info message
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    Text("You created this market")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                Text("No bets placed yet. You can also place a bet yourself, or once someone else places a bet, you'll be able to choose the winner when it's time to settle.")
                    .font(.subheadline)
                    .foregroundColor(Color.slingBlue)
                    .lineLimit(nil)
            }
            .padding(16)
            .background(Color.slingLightBlue)
            .cornerRadius(12)
            
            // Betting closes time
            Text("Betting closes: \(formattedClosingDate)")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    showingCancelAlert = true
                }) {
                    Text("Cancel Market")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    showingPlaceBetSheet = true
                }) {
                    Text("Place a Bet")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.slingGradient)
                        .cornerRadius(10)
                }
            }
        }
    }
    
    @ViewBuilder
    private var creatorOthersBetContent: some View {
        // State 2: Creator with other bets placed, creator hasn't bet
        VStack(alignment: .leading, spacing: 16) {
            // Info message
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundColor(Color.slingBlue)
                    Text("You created this market")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Color.slingBlue)
                }
                
                Text("You created this market but haven't placed a bet. Other players have placed bets, so you'll need to choose the winner when it's time to settle.")
                    .font(.subheadline)
                    .foregroundColor(Color.slingBlue)
                    .lineLimit(nil)
            }
            .padding(16)
            .background(Color.slingLightBlue)
            .cornerRadius(12)
            
            // Betting closes time
            Text("Betting closes: \(formattedClosingDate)")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    showingCancelAlert = true
                }) {
                    Text("Cancel Market")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    showingChooseWinnerSheet = true
                }) {
                    Text("Choose Winner")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.slingGradient)
                        .cornerRadius(10)
                }
            }
        }
    }
    
    @ViewBuilder
    private var creatorParticipatedContent: some View {
        // State 4: Creator who also placed a bet
        VStack(alignment: .leading, spacing: 16) {
            // Betting closes time
            Text("Betting closes: \(formattedClosingDate)")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            // Your bet details
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    // You Picked Section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You Picked")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(userPick) \(userOdds)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                    }
                    
                    Spacer()
                    
                    // Wager Section
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Wager")
                            .font(.caption)
                            .foregroundColor(.gray)
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.caption)
                                .foregroundColor(Color.slingBlue)
                            Text(String(format: "%.2f", userWager))
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    showingCancelAlert = true
                }) {
                    Text("Cancel Market")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    showingChooseWinnerSheet = true
                }) {
                    Text("Choose Winner")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.slingGradient)
                        .cornerRadius(10)
                }
            }
        }
    }
    
    @ViewBuilder
    private var participantContent: some View {
        // State 3: Non-creator who placed a bet
        VStack(alignment: .leading, spacing: 16) {
            // Betting closes time
            Text("Betting closes: \(formattedClosingDate)")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            // Your bet details
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    // You Picked Section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You Picked")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(userPick) \(userOdds)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                    }
                    
                    Spacer()
                    
                    // Wager Section
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Wager")
                            .font(.caption)
                            .foregroundColor(.gray)
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.caption)
                                .foregroundColor(Color.slingBlue)
                            Text(String(format: "%.2f", userWager))
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Remind Creator button
            if !hasRemindedCreator {
                HStack {
                    Spacer()
                    Button(action: remindCreator) {
                        HStack(spacing: 8) {
                            Image(systemName: "bell")
                                .font(.caption)
                            Text("Remind Creator")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray, lineWidth: 1)
                        )
                        .cornerRadius(10)
                    }
                    Spacer()
                }
            }
        }
    }
    
    @ViewBuilder
    private var nonParticipantContent: some View {
        // Default content for non-participants (similar to original ActiveBetCard)
        VStack(alignment: .leading, spacing: 12) {
            Text("Betting closes: \(formattedClosingDate)")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            if bet.status.lowercased() == "open" {
                Button(action: { showingPlaceBetSheet = true }) {
                    Text("Place Bet")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.slingGradient)
                        .cornerRadius(10)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func loadUserParticipation() {
        firestoreService.fetchUserIndividualBets { userBets in
            DispatchQueue.main.async {
                self.userBets = userBets
                self.hasUserParticipated = !userBets.isEmpty
            }
        }
    }
    
    private func loadBetStatus() {
        guard let betId = bet.id else { return }
        
        firestoreService.fetchBetStatus(betId: betId) { status in
            DispatchQueue.main.async {
                // For now, we'll set hasAnyBets based on whether there are user bets
                self.hasAnyBets = !self.userBets.isEmpty
                // optionCounts will need to be populated separately if needed
            }
        }
    }
    
    private func cancelMarket() {
        guard let betId = bet.id else { return }
        
        firestoreService.cancelMarket(betId: betId) { success in
            if success {
                print("✅ Market cancelled successfully")
            } else {
                print("❌ Error cancelling market")
            }
        }
    }
    
    private func remindCreator() {
        guard let betId = bet.id else { return }
        firestoreService.remindCreator(betId: betId) { success in
            if success {
                DispatchQueue.main.async {
                    hasRemindedCreator = true
                }
            }
        }
    }
    
    private func extractUsername(from email: String) -> String {
        return String(email.split(separator: "@").first ?? "Unknown")
    }
    
    private func getDisplayNameFromEmail(_ email: String) -> String {
        // Extract first name from email (everything before @)
        let components = email.components(separatedBy: "@")
        if let username = components.first {
            // Capitalize first letter and return
            return username.prefix(1).uppercased() + username.dropFirst()
        }
        return email
    }
}

// MARK: - Enhanced Community Detail View

struct EnhancedCommunityDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let community: FirestoreCommunity
    @ObservedObject var firestoreService: FirestoreService
    let onChatTap: (() -> Void)? // Callback for chat navigation
    @State private var selectedTab = 0 // 0 = Overview, 1 = Bets, 2 = Members, 3 = Settings
    @State private var communityBets: [FirestoreBet] = []
    @State private var isLoadingBets = false
    @State private var showingCreateBetModal = false
    @State private var showingInviteModal = false
    @State private var showingMemberProfile = false
    @State private var selectedMemberIndex = 0
    @State private var membersWithPoints: [CommunityMemberWithPoints]?
    @State private var showingTradingProfile = false
    @State private var selectedMemberForProfile: CommunityMemberWithPoints?
    @State private var showingCopyFeedback = false
    @State private var isAdmin: Bool = false
    
    // Settings sheet states
    @State private var showingNotificationSettings = false
    @State private var showingMemberManagement = false
    @State private var showingCommunitySettings = false
    @State private var showingAdminControls = false
    
    // Alert states
    @State private var showingLeaveAlert = false
    @State private var showingDeleteAlert = false
    
    // Image picker state
    @State private var showingImagePicker = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                headerSection
                tabSelectorSection
                tabContentSection
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .onAppear {
                loadCommunityBets()
                checkAdminStatus()
            }
            .animation(.easeInOut(duration: 0.3), value: selectedTab)
            .sheet(isPresented: $showingCreateBetModal) {
                CreateBetView(firestoreService: firestoreService, preSelectedCommunity: community.name)
            }
            .sheet(isPresented: $showingInviteModal) {
                ShareCommunityModal(
                    communityName: community.name,
                    communityId: community.id ?? "",
                    onDismiss: { showingInviteModal = false }
                )
            }
            .sheet(isPresented: $showingMemberProfile) {
                MemberProfileView(
                    community: community,
                    memberIndex: selectedMemberIndex,
                    firestoreService: firestoreService
                )
            }
            .sheet(isPresented: $showingTradingProfile) {
                if let selectedMember = selectedMemberForProfile {
                    TradingProfileView(
                        userId: selectedMember.email,
                        userName: selectedMember.name,
                        displayName: nil, // Community members don't have display_name
                        isCurrentUser: false,
                        firestoreService: firestoreService
                    )
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                CommunityImagePicker(
                    community: community,
                    firestoreService: firestoreService
                )
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        ZStack {
            // Background with gradient
            Rectangle()
                .fill(AnyShapeStyle(Color.slingGradient))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all, edges: .top)
            
            // Content overlay - compact layout
            VStack(spacing: 8) {
                // Header Buttons with proper spacing
                HStack(spacing: 0) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    // Share Button
                    Button(action: {
                        showingInviteModal = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                
                // Community Info - compact layout
                VStack(spacing: 6) {
                    // Avatar - Tappable to change profile image
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        ZStack {
                            if let profileImageUrl = community.profile_image_url {
                                // Show custom community image
                                AsyncImage(url: URL(string: profileImageUrl)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                    Circle()
                        .fill(Color.white)
                                        .overlay(
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .slingBlue))
                                        )
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                            } else {
                                // Show community initials
                                Circle()
                                    .fill(Color.white)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Text(String(community.name.prefix(1)).uppercased())
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.slingBlue)
                        )
                            }
                            
                            // Camera overlay indicator
                            Circle()
                                .fill(Color.black.opacity(0.5))
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                )
                                .opacity(0) // Hidden by default, could add hover effect later
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Community Name with Admin Badge
                    HStack(spacing: 8) {
                        Text(community.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        // Crown icon for admin users
                        if isAdmin {
                            Image(systemName: "crown.fill")
                                .font(.title3)
                                .foregroundColor(.yellow)
                        }
                    }
                        
                    // Stats with icons and labels
                    HStack(spacing: 16) {
                        // Member Count
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                            Text("\(community.member_count)")
                            .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            Text("members")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        // Bet Count
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet.clipboard")
                                .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                            Text("\(community.total_bets)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            Text("bets")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 36)
        }
        .frame(height: 200)
    }
    
    // MARK: - Tab Selector Section
    private var tabSelectorSection: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                tabButton(for: index)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .bottom
        )
    }
    
    private func tabButton(for index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            VStack(spacing: 4) {
                Text(tabTitle(for: index))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(selectedTab == index ? .slingBlue : .gray)
                
                Rectangle()
                    .fill(selectedTab == index ? Color.slingBlue : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Tab Content Section
    private var tabContentSection: some View {
        TabView(selection: $selectedTab) {
            overviewTab.tag(0)
            betsTab.tag(1)
            membersTab.tag(2)
            settingsTab.tag(3)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .background(Color.white)
    }
    
    // MARK: - Tab Content Views
    
    private var overviewTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Invite Code Section - Compact Design
                VStack(spacing: 12) {
                    Text("Invite Code")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Invite Code Card - Same size as action cards
                    HStack(spacing: 12) {
                        // Invite Code Text
                            Text(community.invite_code)
                            .font(.subheadline)
                            .fontWeight(.medium)
                                .foregroundColor(.black)
                        
                        Spacer()
                        
                        // Copy Button with feedback
                        Button(action: {
                            UIPasteboard.general.string = community.invite_code
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            
                            // Show checkmark temporarily
                            showingCopyFeedback = true
                            
                            // Hide checkmark after delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showingCopyFeedback = false
                            }
                        }) {
                            Image(systemName: showingCopyFeedback ? "checkmark" : "doc.on.clipboard")
                                .font(.caption)
                                .foregroundColor(showingCopyFeedback ? .green : .gray)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.06))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
                }
                .padding(.horizontal, 16)
                
                // Quick actions
                VStack(spacing: 12) {
                    Text("Quick Actions")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Button(action: {
                        showingCreateBetModal = true
                    }) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(AnyShapeStyle(Color.slingGradient))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create New Bet")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                                Text("Start a new prediction market")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        showingInviteModal = true
                    }) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(AnyShapeStyle(Color.slingGradient))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "person.badge.plus")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Invite Friends")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                                Text("Share invite code with others")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
                
                // Recent activity
                if !communityBets.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Activity")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        LazyVStack(spacing: 12) {
                            ForEach(communityBets.prefix(3)) { bet in
                                RecentBetRow(bet: bet)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                
                // Community Stats Section
                VStack(spacing: 12) {
                    Text("Community Stats")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Performance Grid - Horizontal scroll
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            CommunityPerformanceCard(icon: "bolt.fill", value: "\(getTotalVolume())", label: "Total Volume", color: .slingBlue)
                            CommunityPerformanceCard(icon: "chart.line.uptrend.xyaxis", value: getWinRate(), label: "Win Rate", color: .slingBlue)
                            CommunityPerformanceCard(icon: "target", value: "\(community.total_bets)", label: "Total Bets", color: .slingBlue)
                            CommunityPerformanceCard(icon: "person.2", value: "\(community.member_count)", label: "Active Members", color: .slingBlue)
                            CommunityPerformanceCard(icon: "trophy.fill", value: getSettledBetsCount(), label: "Settled Bets", color: .slingBlue)
                            CommunityPerformanceCard(icon: "clock.fill", value: getPendingBetsCount(), label: "Pending Bets", color: .slingBlue)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 20)
        }
    }
    
    private var betsTab: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if isLoadingBets {
                    ForEach(0..<3, id: \.self) { _ in
                        BetLoadingRow()
                    }
                } else if communityBets.isEmpty {
                    EmptyBetsView(firestoreService: firestoreService)
                } else {
                    ForEach(communityBets) { bet in
                        EnhancedBetCardView(
                            bet: bet,
                            currentUserEmail: firestoreService.currentUser?.email,
                            firestoreService: firestoreService,
                            isCommunityNameClickable: false
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }
    
        private var membersTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Leaderboard Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Leaderboard")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        
                        Text("Members ranked by net points")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "trophy.fill")
                        .font(.title2)
                        .foregroundColor(.slingBlue)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                
                if let membersWithPoints = membersWithPoints {
                    let sortedMembers = membersWithPoints.sorted { $0.netPoints > $1.netPoints }
                    // Always show leaderboard even with just one member
                    if !sortedMembers.isEmpty {
                    ForEach(Array(sortedMembers.enumerated()), id: \.element.id) { index, memberWithPoints in
                        MemberRowView(
                            memberWithPoints: memberWithPoints,
                            rank: index + 1,
                            onTap: {
                                selectedMemberForProfile = memberWithPoints
                                showingTradingProfile = true
                            }
                        )
                        }
                    } else {
                        // Show empty state if no members loaded
                        VStack(spacing: 16) {
                            Image(systemName: "person.2")
                                .font(.system(size: 48))
                                .foregroundColor(Color.slingBlue.opacity(0.6))
                            
                            Text("Loading Members...")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                        }
                        .padding(.top, 60)
                    }
                } else {
                    // Fallback to basic member display if advanced loading fails
                    // Always show leaderboard even with just one member
                    ForEach(0..<max(1, community.member_count), id: \.self) { index in
                        HStack(spacing: 16) {
                            // Rank Badge
                            ZStack {
                                Circle()
                                    .fill(index == 0 ? Color.slingBlue : Color.gray.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(index == 0 ? .white : .gray)
                            }
                            
                            // Profile Picture
                            Circle()
                                .fill(AnyShapeStyle(Color.slingGradient))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Text("M\(index + 1)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Member \(index + 1)")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                                
                                Text("Loading points...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            // Placeholder for net points
                            VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.caption)
                                        .foregroundColor(.slingBlue)
                                
                                Text("--")
                                        .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.gray)
                            }
                                
                                Text("Net Points")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .onAppear {
            loadMembersWithPoints()
        }
    }
    
    private var settingsTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isAdmin {
                    // Admin settings
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "bell", 
                            title: "Notifications", 
                            subtitle: "Manage notification preferences",
                            action: { showNotificationSettings() }
                        )
                        
                        SettingsRow(
                            icon: "person.2", 
                            title: "Member Management", 
                            subtitle: "Add or remove members",
                            action: { showMemberManagement() }
                        )
                        
                        SettingsRow(
                            icon: "gear", 
                            title: "Community Settings", 
                            subtitle: "Edit community details",
                            action: { showCommunitySettings() }
                        )
                        
                        SettingsRow(
                            icon: "shield", 
                            title: "Admin Controls", 
                            subtitle: "Manage community permissions",
                            action: { showAdminControls() }
                        )
                        
                        SettingsRow(
                            icon: "trash", 
                            title: "Delete Community", 
                            subtitle: "Permanently delete this community", 
                            isDestructive: true,
                            action: { showDeleteConfirmation() }
                        )
                    }
                    .background(Color.white)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                } else {
                    // Regular member settings
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "bell", 
                            title: "Notifications", 
                            subtitle: "Manage notification preferences",
                            action: { showNotificationSettings() }
                        )
                        
                        SettingsRow(
                            icon: "person.2", 
                            title: "Member Management", 
                            subtitle: "View community members",
                            action: { showMemberManagement() }
                        )
                        
                        SettingsRow(
                            icon: "gear", 
                            title: "Community Settings", 
                            subtitle: "View community details",
                            action: { showCommunitySettings() }
                        )
                        
                        SettingsRow(
                            icon: "trash", 
                            title: "Leave Community", 
                            subtitle: "Leave this community", 
                            isDestructive: true,
                            action: { showLeaveConfirmation() }
                        )
                    }
                    .background(Color.white)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 20)
        }
        .sheet(isPresented: $showingNotificationSettings) {
            NotificationSettingsView(
                community: community,
                firestoreService: firestoreService,
                isAdmin: isAdmin
            )
        }
        .sheet(isPresented: $showingMemberManagement) {
            MemberManagementView(
                community: community,
                firestoreService: firestoreService,
                isAdmin: isAdmin
            )
        }
        .sheet(isPresented: $showingCommunitySettings) {
            CommunitySettingsDetailView(
                community: community,
                firestoreService: firestoreService,
                isAdmin: isAdmin
            )
        }
        .sheet(isPresented: $showingAdminControls) {
            AdminControlsView(
                community: community,
                firestoreService: firestoreService
            )
        }
        .alert("Leave Community", isPresented: $showingLeaveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                leaveCommunity()
            }
        } message: {
            Text("Are you sure you want to leave this community? You can rejoin later using the invite code.")
        }
        .alert("Delete Community", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCommunity()
            }
        } message: {
            Text("Are you sure you want to delete this community? This action cannot be undone and all data will be permanently lost.")
        }
    }
    
    // MARK: - Helper Methods
    
    private func tabTitle(for index: Int) -> String {
        switch index {
        case 0: return "Overview"
        case 1: return "Bets"
        case 2: return "Leaderboard"
        case 3: return "Settings"
        default: return ""
        }
    }
    
    private func loadCommunityBets() {
        isLoadingBets = true
        // Filter bets for this community
        communityBets = firestoreService.bets.filter { $0.community_id == (community.id ?? "") }
        isLoadingBets = false
    }
    
    private func loadMembersWithPoints() {
        print("🔄 Loading members with points for community: \(community.id ?? "nil")")
        
        // Add a timeout in case the Firestore calls take too long
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if self.membersWithPoints == nil {
                print("⏰ Timeout reached, showing fallback member list")
                // Force the fallback to show by setting an empty array
                self.membersWithPoints = []
            }
        }
        
        firestoreService.getCommunityMembersWithNetPoints(communityId: community.id ?? "") { members in
            print("✅ Loaded \(members.count) members with points")
            DispatchQueue.main.async {
                self.membersWithPoints = members
            }
        }
    }
    
    private func formatDateShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    // MARK: - Community Stats Helper Methods
    
    private func getTotalVolume() -> String {
        let communityBets = firestoreService.bets.filter { $0.community_id == (community.id ?? "") }
        let totalVolume = communityBets.reduce(0.0) { total, bet in
            total + Double(bet.total_pool ?? 0)
        }
        return String(format: "%.0f", totalVolume)
    }
    
    private func getWinRate() -> String {
        let communityBets = firestoreService.bets.filter { $0.community_id == (community.id ?? "") }
        let settledBets = communityBets.filter { $0.status.lowercased() == "settled" }
        
        guard !settledBets.isEmpty else { return "0%" }
        
        // TODO: This needs to be updated with actual win/loss logic
        // For now, using a placeholder - would need to check winner_option vs actual outcome
        let winRate = 68.0 // Placeholder - would need actual win/loss logic
        return String(format: "%.0f%%", winRate)
    }
    
    private func getSettledBetsCount() -> String {
        let communityBets = firestoreService.bets.filter { $0.community_id == (community.id ?? "") }
        let settledBets = communityBets.filter { $0.status.lowercased() == "settled" }
        return "\(settledBets.count)"
    }
    
    private func getPendingBetsCount() -> String {
        let communityBets = firestoreService.bets.filter { $0.community_id == (community.id ?? "") }
        let pendingBets = communityBets.filter { $0.status.lowercased() == "open" }
        return "\(pendingBets.count)"
    }
    
    private func checkAdminStatus() {
        guard let userEmail = firestoreService.currentUser?.email else { return }
        firestoreService.isUserAdminInCommunity(communityId: community.id ?? "", userEmail: userEmail) { adminStatus in
            DispatchQueue.main.async {
                self.isAdmin = adminStatus
            }
        }
    }
    
    // MARK: - Settings Helper Methods
    
    private func showNotificationSettings() {
        showingNotificationSettings = true
    }
    
    private func showMemberManagement() {
        showingMemberManagement = true
    }
    
    private func showCommunitySettings() {
        showingCommunitySettings = true
    }
    
    private func showAdminControls() {
        showingAdminControls = true
    }
    
    private func showLeaveConfirmation() {
        showingLeaveAlert = true
    }
    
    private func showDeleteConfirmation() {
        showingDeleteAlert = true
    }
    
    private func leaveCommunity() {
        guard let userEmail = firestoreService.currentUser?.email else { return }
        
        firestoreService.leaveCommunity(communityId: community.id ?? "", userEmail: userEmail) { success in
            DispatchQueue.main.async {
                if success {
                    // Dismiss the view and go back to communities list
                    dismiss()
                }
            }
        }
    }
    
    private func deleteCommunity() {
        firestoreService.deleteCommunity(communityId: community.id ?? "") { success in
            DispatchQueue.main.async {
                if success {
                    // Dismiss the view and go back to communities list
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isDestructive: Bool
    let showArrow: Bool
    let action: () -> Void
    
    init(icon: String, title: String, subtitle: String, isDestructive: Bool = false, showArrow: Bool = true, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isDestructive = isDestructive
        self.showArrow = showArrow
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isDestructive ? .red : .slingBlue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isDestructive ? .red : .black)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if showArrow {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.slingBlue)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

struct CommunityPerformanceCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(width: 120, height: 100)
        .padding(.vertical, 16)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Member Profile View

struct MemberProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let community: FirestoreCommunity
    let memberIndex: Int
    @ObservedObject var firestoreService: FirestoreService
    @State private var selectedTab = 0 // 0 = Overview, 1 = All Bets, 2 = Head-to-Head
    @State private var memberBets: [FirestoreBet] = []
    @State private var isLoadingBets = false
    
    // Mock data for demonstration - in real app, fetch from Firestore
    private var memberName: String {
        if memberIndex == 0 {
            return "Admin User"
        } else {
            return "Member \(memberIndex + 1)"
        }
    }
    
    private var memberUsername: String {
        if memberIndex == 0 {
            return "@admin"
        } else {
            return "@member\(memberIndex + 1)"
        }
    }
    
    private var memberJoinDate: String {
        if memberIndex == 0 {
            return "Member since Jan 2024"
        } else {
            return "Member since Feb 2024"
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Performance Section
                performanceSection
                
                // Tab Selector
                tabSelectorSection
                
                // Tab Content
                tabContentSection
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
            .onAppear {
                loadMemberBets()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "arrow.left")
                        .font(.title2)
                        .foregroundColor(.slingBlue)
                }
                
                Spacer()
                
                Text("Trading Profile")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                Spacer()
                
                Button(action: {
                    // Chat action
                }) {
                    Image(systemName: "bubble.left")
                        .font(.title2)
                        .foregroundColor(.slingBlue)
                }
            }
            
            // Member Info
            HStack(spacing: 16) {
                // Avatar
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle()
                            .fill(Color.black)
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 8, height: 8)
                            )
                    )
                
                // Member Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(memberName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text(memberUsername)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Text(memberJoinDate)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Settle Button
                Button(action: {
                    // Settle action
                }) {
                    Text("Settle")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.slingBlue)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .background(Color.white)
    }
    
    // MARK: - Performance Section
    private var performanceSection: some View {
        VStack(spacing: 16) {
            Text("Performance")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                PerformanceCard(icon: "bolt.fill", value: "$608", label: "Net Balance", color: .slingBlue)
                PerformanceCard(icon: "bolt.fill", value: "$2,500", label: "Total Volume", color: .slingBlue)
                PerformanceCard(icon: "chart.line.uptrend.xyaxis", value: "$850", label: "Total P&L", color: .slingBlue)
                PerformanceCard(icon: "percent", value: "68%", label: "Win Rate", color: .slingBlue)
                PerformanceCard(icon: "target", value: "35", label: "Total Bets", color: .slingBlue)
                PerformanceCard(icon: "person.2", value: "12", label: "Bets with You", color: .slingBlue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .background(Color.white)
    }
    
    // MARK: - Tab Selector Section
    private var tabSelectorSection: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                Button(action: { selectedTab = index }) {
                    Text(tabTitle(for: index))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(selectedTab == index ? .slingBlue : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedTab == index ? Color.slingLightBlue : Color.clear)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .bottom
        )
    }
    
    // MARK: - Tab Content Section
    private var tabContentSection: some View {
        TabView(selection: $selectedTab) {
            overviewTab.tag(0)
            allBetsTab.tag(1)
            headToHeadTab.tag(2)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }
    
    // MARK: - Tab Content Views
    private var overviewTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    Text("Recent Activity Summary")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    Text("\(memberName) has been active in 3 communities this week")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 40)
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var allBetsTab: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if isLoadingBets {
                    ForEach(0..<3, id: \.self) { _ in
                        BetLoadingRow()
                    }
                } else if memberBets.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "target")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.6))
                        
                        Text("No Bets Yet")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        Text("This member hasn't placed any bets yet")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(memberBets) { bet in
                        EnhancedBetCardView(
                            bet: bet,
                            currentUserEmail: firestoreService.currentUser?.email,
                            firestoreService: firestoreService,
                            isCommunityNameClickable: true
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }
    
    private var headToHeadTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("Head-to-Head")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
            
            Text("Compare your performance with this member")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 60)
    }
    
    // MARK: - Helper Methods
    private func tabTitle(for index: Int) -> String {
        switch index {
        case 0: return "Overview"
        case 1: return "All Bets"
        case 2: return "Head-to-Head"
        default: return ""
        }
    }
    
    private func loadMemberBets() {
        isLoadingBets = true
        // Filter bets for this member in this community
        memberBets = firestoreService.bets.filter { bet in
            bet.community_id == (community.id ?? "") && 
            bet.creator_email == "member\(memberIndex + 1)@example.com" // Mock email
        }
        isLoadingBets = false
    }
}

// MARK: - Trading Profile View

struct TradingProfileView: View {
    let userId: String
    let userName: String
    let displayName: String?
    let isCurrentUser: Bool
    let firestoreService: FirestoreService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0 // 0 = Activity, 1 = Recent Bets
    @State private var userBets: [FirestoreBet] = []
    @State private var isLoadingBets = false
    @State private var userData: FirestoreUser?
    @State private var isLoadingUserData = false
    @State private var showingUserSettings = false
    @State private var userActivityItems: [UserActivityItem] = []
    @State private var isLoadingActivity = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                headerSection
                quickStatsSection
                tabSelectorSection
                tabContentSection
            }
        .background(Color.white)
            .navigationBarHidden(true)
            .animation(.easeInOut(duration: 0.3), value: selectedTab)
            .onAppear {
                loadUserData()
                loadUserBets()
                loadUserActivity()
            }
            .onChange(of: selectedTab) { oldValue, newValue in
                if newValue == 0 { // Activity tab
                    loadUserActivity()
                }
            }
            .sheet(isPresented: $showingUserSettings) {
                UserSettingsView(
                    userData: userData,
                    firestoreService: firestoreService
                )
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 0) {
            // Navigation Header
            HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "arrow.left")
                                .font(.title2)
                                .foregroundColor(.black)
                                .frame(width: 44, height: 44)
                        }
                
                Spacer()
                
                Text("Profile")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                Spacer()
                
                if isCurrentUser {
                    Button(action: {
                        showingUserSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                    }
                } else {
                    Button(action: {
                        // Share functionality for member profiles
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .background(Color.white)
            
            // User Info Card
                    VStack(spacing: 16) {
                HStack(spacing: 16) {
                    // Avatar - User Profile Picture or Initials
                    if let profilePictureUrl = userData?.profile_picture_url {
                        // Show user's profile picture
                        AsyncImage(url: URL(string: profilePictureUrl)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(Circle())
                            case .failure(_):
                                // Fallback to initials on error
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        Text(getUserInitialsFromName())
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.slingBlue)
                                    )
                            case .empty:
                                // Show initials while loading
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        Text(getUserInitialsFromName())
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.slingBlue)
                                    )
                            @unknown default:
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        Text(getUserInitialsFromName())
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.slingBlue)
                                    )
                            }
                        }
                    } else {
                        // Fallback to initials
                            Circle()
                                .fill(Color.white)
                        .frame(width: 56, height: 56)
                                .overlay(
                                    Text(String(userName.prefix(1)).uppercased())
                                .font(.title2)
                                        .fontWeight(.bold)
                                .foregroundColor(.slingBlue)
                                )
                    }
                            
                    VStack(alignment: .leading, spacing: 4) {
                        // User Name
                        Text(userData?.full_name ?? userName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                        // Display Name
                        Text("@\(userData?.display_name ?? displayName ?? "user")")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                
                        // Member since date
                        Text("Member since \(getAbbreviatedDate())")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                    
                    Spacer()
                    

                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AnyShapeStyle(Color.slingGradient))
            )
            .padding(.horizontal, 16)
        }
        .background(Color.white)
    }
    
        // MARK: - Quick Stats Section
    private var quickStatsSection: some View {
        VStack(spacing: 8) {
            Text("Quick Stats")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)
            
            // Performance Grid - Horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    CommunityPerformanceCard(icon: "person.2", value: "\(getUserCommunityCount())", label: "Communities", color: .slingBlue)
                    CommunityPerformanceCard(icon: "target", value: "\(userData?.total_bets ?? 0)", label: "Total Bets", color: .slingBlue)
                    CommunityPerformanceCard(icon: "bolt.fill", value: "\(formatNumber(userData?.blitz_points ?? 0))", label: "Sling Points", color: .slingBlue)
                    CommunityPerformanceCard(icon: "flame.fill", value: "\(getUserStreak())", label: "Streak", color: .slingBlue)
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Tab Selector Section
    private var tabSelectorSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(action: { selectedTab = 0 }) {
                    VStack(spacing: 4) {
                        Text("Activity")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(selectedTab == 0 ? .slingBlue : .gray)
                        
                        Rectangle()
                            .fill(selectedTab == 0 ? Color.slingBlue : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Button(action: { selectedTab = 1 }) {
                    VStack(spacing: 4) {
                        Text("Recent Bets")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(selectedTab == 1 ? .slingBlue : .gray)
                        
                        Rectangle()
                            .fill(selectedTab == 1 ? Color.slingBlue : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
            
            // Horizontal line under tabs
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.gray.opacity(0.3))
        }
    }
                
    // MARK: - Tab Content Section
    private var tabContentSection: some View {
                TabView(selection: $selectedTab) {
            overviewTab.tag(0)
            recentBetsTab.tag(1)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
    
    // MARK: - Tab Content Views
    private var overviewTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                if userActivityItems.isEmpty {
                    // Empty State
                    VStack(spacing: 20) {
                        Spacer()
                        
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.5))
                        
                        VStack(spacing: 8) {
                            Text("No activity yet")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("Your betting activity will appear here")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 60)
                } else {
                    // Activity List
                    LazyVStack(spacing: 1) {
                        ForEach(userActivityItems) { activityItem in
                            ActivityRow(activityItem: activityItem)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .padding(.top, 8)
                    .animation(.easeInOut(duration: 0.3), value: userActivityItems.count)
                }
            }
        }
        .refreshable {
            loadUserActivity()
        }
    }
    
    private var recentBetsTab: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if isLoadingBets {
                    ForEach(0..<3, id: \.self) { _ in
                        BetLoadingRow()
                    }
                } else if userBets.isEmpty {
                    EmptyActiveBetsView(firestoreService: firestoreService)
                } else {
                    ForEach(userBets.prefix(5), id: \.id) { bet in
                        RecentBetRow(bet: bet)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .refreshable {
            await refreshBets()
        }
    }
    

    
    // MARK: - Helper Methods
    private func loadUserBets() {
        isLoadingBets = true
        
        // Get bets where the user is either the creator or a participant
        let userEmail = firestoreService.currentUser?.email ?? ""
        
        // Filter bets where user is creator
        let userCreatedBets = firestoreService.bets.filter { bet in
            bet.creator_email == userEmail
        }
        
        // Sort by creation date (newest first)
        let sortedBets = userCreatedBets.sorted { $0.created_date > $1.created_date }
        
        DispatchQueue.main.async {
            self.userBets = sortedBets
            self.isLoadingBets = false
        }
    }
    
    private func loadUserActivity() {
        isLoadingActivity = true
        
        // Create activity items from user's betting history
        var activityItems: [UserActivityItem] = []
        
        // Get user's bet participations
        let userParticipations = firestoreService.userBetParticipations.filter { $0.user_email == userId }
        
        for participation in userParticipations {
            if let bet = firestoreService.bets.first(where: { $0.id == participation.bet_id }) {
                // Create activity item for placing a bet
                let activityItem = UserActivityItem(
                    id: "\(participation.bet_id ?? "")_\(participation.user_email)_placed",
                    type: .betPlaced,
                    title: "Placed bet on '\(bet.title)'",
                    subtitle: "Chose: \(participation.chosen_option) • ⚡ \(participation.stake_amount)",
                    communityName: getCommunityName(for: bet.community_id),
                    timestamp: bet.created_date,
                    icon: "bolt.fill",
                    iconColor: .yellow
                )
                activityItems.append(activityItem)
                
                // If bet is settled, create activity item for result
                if bet.status == "settled", let winnerOption = bet.winner_option {
                    let isWinner = participation.chosen_option == winnerOption
                    let resultActivityItem = UserActivityItem(
                        id: "\(participation.bet_id ?? "")_\(participation.user_email)_result",
                        type: isWinner ? .betWon : .betLost,
                        title: isWinner ? "Won bet on '\(bet.title)'" : "Lost bet on '\(bet.title)'",
                        subtitle: isWinner ? "Won ⚡ \(participation.stake_amount)" : "Lost ⚡ \(participation.stake_amount)",
                        communityName: getCommunityName(for: bet.community_id),
                        timestamp: bet.deadline, // Use deadline as settlement time
                        icon: isWinner ? "trophy.fill" : "xmark.circle.fill",
                        iconColor: isWinner ? .green : .red
                    )
                    activityItems.append(resultActivityItem)
                }
            }
        }
        
        // Sort by timestamp (most recent first)
        activityItems.sort { $0.timestamp > $1.timestamp }
        
        DispatchQueue.main.async {
            self.userActivityItems = activityItems
            self.isLoadingActivity = false
        }
    }
    
    private func getCommunityName(for communityId: String) -> String? {
        if let community = firestoreService.userCommunities.first(where: { $0.id == communityId }) {
            return community.name
        }
        return nil
    }
    
    private func refreshBets() async {
        await MainActor.run {
            loadUserBets()
        }
    }
    
    private func getUserBetCount() -> Int {
        return userBets.count
    }
    
    private func getUserCommunityCount() -> Int {
        return firestoreService.userCommunities.count
    }
    
    private func getUserStreak() -> Int {
        // Calculate consecutive correct bets
        var currentStreak = 0
        var maxStreak = 0
        
        // Get user's email (not currently used but available for future use)
        _ = firestoreService.currentUser?.email ?? ""
        
        // Filter completed bets where user participated and won
        let userParticipations = firestoreService.userBetParticipations.filter { participant in
            participant.is_winner == true
        }
        
        // Sort participations by date (most recent first)
        let sortedParticipations = userParticipations.sorted { participation1, participation2 in
            participation1.created_date > participation2.created_date
        }
        
        // Calculate streak
        for participation in sortedParticipations {
            // Find the corresponding bet to check if it's completed
            if let bet = userBets.first(where: { $0.id == participation.bet_id }),
               bet.status == "completed" {
                currentStreak += 1
                maxStreak = max(maxStreak, currentStreak)
            } else {
                // If bet is not completed or not found, reset streak
                currentStreak = 0
            }
        }
        
        return maxStreak
    }
    
    private func getAbbreviatedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: Date())
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    private func loadUserData() {
        isLoadingUserData = true
        
        Task {
            do {
                let user = try await firestoreService.getUser(userId: userId)
                await MainActor.run {
                    self.userData = user
                    self.isLoadingUserData = false
                    
                    // Log all user data from Firestore
                    print("📱 User Profile Data Loaded:")
                    print("   User ID: \(user.id ?? "nil")")
                    print("   UID: \(user.uid ?? "nil")")
                    print("   Email: \(user.email)")
                    print("   First Name: \(user.first_name ?? "nil")")
                    print("   Last Name: \(user.last_name ?? "nil")")
                    print("   Full Name: \(user.full_name ?? "nil")")
                    print("   Display Name: \(user.display_name ?? "nil")")
                    print("   Sling Points: \(user.sling_points ?? 0)")
                    print("   Blitz Points: \(user.blitz_points ?? 0)")
                    print("   Total Bets: \(user.total_bets ?? 0)")
                    print("   Total Winnings: \(user.total_winnings ?? 0)")
                    print("   Document ID: \(user.documentId ?? "nil")")
                    
                    // Log computed properties
                    print("   Computed Display Name: \(user.displayName)")
                    print("   Computed First Name: \(user.firstName ?? "nil")")
                    print("   Computed Last Name: \(user.lastName ?? "nil")")
                }
            } catch {
                print("❌ Error loading user data: \(error)")
                await MainActor.run {
                    self.isLoadingUserData = false
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func getUserInitialsFromName() -> String {
        if let displayName = displayName, !displayName.isEmpty {
            let components = displayName.components(separatedBy: " ")
            if components.count >= 2 {
                let firstInitial = String(components[0].prefix(1)).uppercased()
                let lastInitial = String(components[1].prefix(1)).uppercased()
                return "\(firstInitial)\(lastInitial)"
            } else if components.count == 1 {
                return String(components[0].prefix(1)).uppercased()
            }
        } else if !userName.isEmpty {
            let components = userName.components(separatedBy: " ")
            if components.count >= 2 {
                let firstInitial = String(components[0].prefix(1)).uppercased()
                let lastInitial = String(components[1].prefix(1)).uppercased()
                return "\(firstInitial)\(lastInitial)"
            } else {
                return String(userName.prefix(1)).uppercased()
            }
        }
        return "U"
    }
}

// MARK: - Supporting Views for Trading Profile

struct UserSettingsView: View {
    let userData: FirestoreUser?
    let firestoreService: FirestoreService
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditProfile = false
    @State private var showingDeleteAccount = false
    @State private var showingSignOut = false
    @State private var darkModeEnabled = false
    @State private var showingPushNotifications = false
    @State private var showingEmailNotifications = false
    @State private var showingProfileVisibility = false
    @State private var showingChangePassword = false
    @State private var showingLanguageSettings = false
    @State private var showingContactSupport = false
    @State private var showingTermsOfService = false
    @State private var showingPrivacyPolicy = false
    @State private var showingLanguageError = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Settings Content
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile Section
                        profileSection
                        
                        // Notifications Section
                        notificationsSection
                        
                        // Privacy & Security Section
                        privacySecuritySection
                        
                        // App Preferences Section
                        appPreferencesSection
                        
                        // Account Management Section
                        accountManagementSection
                        
                        // Support Section
                        supportSection
                        
                        // Danger Zone
                        dangerZoneSection
                }
                .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView(firestoreService: firestoreService)
                    .onAppear {
                        print("🔧 Sheet presenting: EditProfileView")
                    }
            }

            .sheet(isPresented: $showingPushNotifications) {
                PushNotificationsView(firestoreService: firestoreService)
                    .onAppear {
                        print("🔧 Sheet presenting: PushNotificationsView")
                    }
            }
            .sheet(isPresented: $showingEmailNotifications) {
                EmailNotificationsView(firestoreService: firestoreService)
            }

            .sheet(isPresented: $showingProfileVisibility) {
                ProfileVisibilityView(firestoreService: firestoreService)
            }
            .sheet(isPresented: $showingChangePassword) {
                ChangePasswordView()
                    .onAppear {
                        print("🔧 Sheet presenting: ChangePasswordView")
                    }
            }
            .sheet(isPresented: $showingLanguageSettings) {
                LanguageSettingsView(firestoreService: firestoreService)
                    .onAppear {
                        print("🔧 Sheet presenting: LanguageSettingsView")
                    }
            }
            .sheet(isPresented: $showingContactSupport) {
                ContactSupportView(firestoreService: firestoreService)
            }

            .sheet(isPresented: $showingTermsOfService) {
                TermsOfServiceView()
            }
            .sheet(isPresented: $showingPrivacyPolicy) {
                PrivacyPolicyView()
            }

            .sheet(isPresented: $showingDeleteAccount) {
                DeleteAccountView()
            }
            .sheet(isPresented: $showingSignOut) {
                SignOutView(firestoreService: firestoreService)
            }
            .alert("Feature Coming Soon", isPresented: $showingLanguageError) {
                Button("OK") { }
            } message: {
                Text("Language selection will be available in a future update. For now, the app is only available in English.")
            }
            .onAppear {
                print("🔧 UserSettingsView body rendered")
                // Ensure user settings exist in Firestore
                firestoreService.ensureUserSettingsExist { success in
                    if success {
                        print("✅ User settings ensured in Firestore")
                        // Load current user settings
                        self.loadCurrentUserSettings()
                    } else {
                        print("❌ Failed to ensure user settings in Firestore")
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadCurrentUserSettings() {
        guard let user = firestoreService.currentUser else { return }
        
        // Load dark mode setting
        if let darkMode = user.dark_mode_enabled {
            darkModeEnabled = darkMode
        }
        
        // Load language setting
        if let language = user.language {
            // Update the language display in the UI
            print("🔧 Loaded language setting: \(language)")
        }
        
        print("🔧 Loaded current user settings")
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "arrow.left")
                    .font(.title2)
                    .foregroundColor(.slingBlue)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.black)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.gray)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(Color.white)
    }
    
    // MARK: - Profile Section
    private var profileSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Profile")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Spacer()
            }
            
            VStack(spacing: 0) {
                SettingsRow(icon: "person.circle", title: "Edit Profile", subtitle: "Update your personal information", isDestructive: false, action: {
                    print("🔧 Edit Profile button tapped")
                    showingEditProfile = true
                    print("🔧 showingEditProfile set to: \(showingEditProfile)")
                })
                Divider().padding(.leading, 56)
                SettingsRow(icon: "key", title: "Change Password", subtitle: "Update your password", isDestructive: false, action: {
                    print("🔧 Change Password button tapped")
                    showingChangePassword = true
                    print("🔧 showingChangePassword set to: \(showingChangePassword)")
                })
                Divider().padding(.leading, 56)
                SettingsRow(icon: "eye", title: "Profile Visibility", subtitle: "What's displayed on your profile page", isDestructive: false, action: {
                    print("🔧 Profile Visibility button tapped")
                    showingProfileVisibility = true
                    print("🔧 showingProfileVisibility set to: \(showingProfileVisibility)")
                })
            }
            .background(Color.white)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Notifications Section
    private var notificationsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Notifications")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Spacer()
            }
            
            VStack(spacing: 0) {
                SettingsRow(icon: "bell", title: "Push Notifications", subtitle: "Bet updates and community alerts", isDestructive: false, action: {
                    print("🔧 Push Notifications button tapped")
                    showingPushNotifications = true
                    print("🔧 showingPushNotifications set to: \(showingPushNotifications)")
                })
                Divider().padding(.leading, 56)
                SettingsRow(icon: "envelope", title: "Email Notifications", subtitle: "Weekly summaries and updates", isDestructive: false, action: {
                    print("🔧 Email Notifications button tapped")
                    showingEmailNotifications = true
                    print("🔧 showingEmailNotifications set to: \(showingEmailNotifications)")
                })
            }
            .background(Color.white)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Privacy & Security Section
    private var privacySecuritySection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Privacy & Security")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Spacer()
            }
            
            VStack(spacing: 0) {
                // Privacy settings can be added here in the future
            }
            .background(Color.white)
            .cornerRadius(12)
        }
    }
    
    // MARK: - App Preferences Section
    private var appPreferencesSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("App Preferences")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Spacer()
            }
            
            VStack(spacing: 0) {
                HStack {
                    SettingsRow(icon: "moon.fill", title: "Dark Mode", subtitle: "Switch to dark theme", isDestructive: false, showArrow: false, action: {})
                    Spacer()
                    Toggle("", isOn: $darkModeEnabled)
                        .labelsHidden()
                        .scaleEffect(0.8)
                        .tint(.slingBlue)
                        .padding(.trailing, 16)
                        .onChange(of: darkModeEnabled) { _, newValue in
                            print("🔧 Dark mode changed to: \(newValue)")
                            firestoreService.updateDarkModeSetting(enabled: newValue) { success in
                                if success {
                                    print("✅ Dark mode setting saved to Firestore")
                                } else {
                                    print("❌ Failed to save dark mode setting")
                                }
                            }
                        }
                }
            }
            .background(Color.white)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Account Management Section
    private var accountManagementSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Account Management")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Spacer()
            }
            
            VStack(spacing: 0) {
                SettingsRow(icon: "globe", title: "Language", subtitle: "English", isDestructive: false, showArrow: false, action: {
                    print("🔧 Language button tapped - feature coming soon!")
                    showingLanguageError = true
                })
            }
            .background(Color.white)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Support Section
    private var supportSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Help & Support")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Spacer()
            }
            
            VStack(spacing: 0) {
                SettingsRow(icon: "message", title: "Contact Us", subtitle: "Get help from our team", isDestructive: false, action: {
                    print("🔧 Contact Us button tapped")
                    showingContactSupport = true
                    print("🔧 showingContactSupport set to: \(showingContactSupport)")
                })
                Divider().padding(.leading, 56)
                SettingsRow(icon: "doc.text", title: "Terms of Service", subtitle: "Read our terms and conditions", isDestructive: false, action: {
                    print("🔧 Terms of Service button tapped")
                    showingTermsOfService = true
                    print("🔧 showingTermsOfService set to: \(showingTermsOfService)")
                })
                Divider().padding(.leading, 56)
                SettingsRow(icon: "hand.raised", title: "Privacy Policy", subtitle: "Learn about data privacy", isDestructive: false, action: {
                    print("🔧 Privacy Policy button tapped")
                    showingPrivacyPolicy = true
                    print("🔧 showingPrivacyPolicy set to: \(showingPrivacyPolicy)")
                })
            }
            .background(Color.white)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Danger Zone Section
    private var dangerZoneSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Danger Zone")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                Spacer()
            }
            
            VStack(spacing: 0) {
                SettingsRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign Out", subtitle: "Sign out of your account", isDestructive: true, action: {
                    print("🔧 Sign Out button tapped")
                    showingSignOut = true
                    print("🔧 showingSignOut set to: \(showingSignOut)")
                })
                Divider().padding(.leading, 56)
                SettingsRow(icon: "trash", title: "Delete Account", subtitle: "Permanently delete your account", isDestructive: true, action: {
                    print("🔧 Delete Account button tapped")
                    showingDeleteAccount = true
                    print("🔧 showingDeleteAccount set to: \(showingDeleteAccount)")
                })
            }
            .background(Color.white)
            .cornerRadius(12)
        }
    }
}

// MARK: - Profile Picture View
struct ProfilePictureView: View {
    let userData: FirestoreUser?
    let firestoreService: FirestoreService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("Profile Picture")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color.white)
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        // Current Picture
                        VStack(spacing: 16) {
                            HStack {
                                Text("Current Picture")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 120, height: 120)
                                .overlay(
                                    Text(String(userData?.full_name?.prefix(1) ?? "U").uppercased())
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundColor(.slingBlue)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.slingBlue, lineWidth: 3)
                                )
                        }
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(12)
                        
                        // Upload Options
                        VStack(spacing: 16) {
                            HStack {
                                Text("Upload New Picture")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            VStack(spacing: 12) {
                                Button(action: {
                                    // TODO: Implement camera capture
                                    print("Camera tapped")
                                }) {
                                    HStack {
                                        Image(systemName: "camera")
                                            .font(.title2)
                                            .foregroundColor(.slingBlue)
                                        Text("Take Photo")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.black)
                                        Spacer()
                                    }
                                    .padding(16)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                
                                Button(action: {
                                    // TODO: Implement photo library
                                    print("Photo library tapped")
                                }) {
                                    HStack {
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.title2)
                                            .foregroundColor(.slingBlue)
                                        Text("Choose from Library")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.black)
                                        Spacer()
                                    }
                                    .padding(16)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 16)
            .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Push Notifications View
struct PushNotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var firestoreService: FirestoreService
    @State private var betUpdates = true
    @State private var communityAlerts = true
    @State private var newMessages = true
    @State private var weeklySummaries = false
    @State private var newMembersJoined = true
    @State private var membersLeft = true
    @State private var hotBetsTrending = true
    @State private var outstandingBalances = true
    @State private var isLoading = false
    @State private var showingSaveSuccess = false
    @State private var showingUnsavedChangesAlert = false
    
    // Original values to track changes
    @State private var originalBetUpdates = true
    @State private var originalCommunityAlerts = true
    @State private var originalNewMessages = true
    @State private var originalWeeklySummaries = false
    @State private var originalNewMembersJoined = true
    @State private var originalMembersLeft = true
    @State private var originalHotBetsTrending = true
    @State private var originalOutstandingBalances = true
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { 
                        if hasUnsavedChanges() {
                            showingUnsavedChangesAlert = true
                        } else {
                            dismiss()
                        }
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("Push Notifications")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: {
                        savePreferences()
                    }) {
                        Text("Save")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.slingBlue)
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Content
        ScrollView {
                    VStack(spacing: 24) {
            VStack(spacing: 16) {
                            HStack {
                                Text("Bet & Community")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            VStack(spacing: 0) {
                                HStack {
                                    SettingsRow(icon: "target", title: "Bet Updates", subtitle: "Get notified about your bets", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $betUpdates)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "person.3", title: "Community Alerts", subtitle: "New community activities", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $communityAlerts)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "message", title: "New Messages", subtitle: "Direct messages and mentions", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $newMessages)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "chart.bar", title: "Weekly Summaries", subtitle: "Your weekly performance", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $weeklySummaries)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                            }
                            .background(Color.white)
                            .cornerRadius(12)
                        }
                        
                        VStack(spacing: 16) {
                            HStack {
                                Text("Community Updates")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            VStack(spacing: 0) {
                                HStack {
                                    SettingsRow(icon: "person.badge.plus", title: "New Members Joined", subtitle: "When someone joins your community", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $newMembersJoined)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "person.badge.minus", title: "Members Left", subtitle: "When someone leaves your community", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $membersLeft)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "flame.fill", title: "Hot Bets Trending", subtitle: "Popular bets in your communities", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $hotBetsTrending)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "exclamationmark.triangle", title: "Outstanding Balances", subtitle: "Updates on pending balances", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $outstandingBalances)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                            }
                            .background(Color.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
            .alert("Preferences Saved", isPresented: $showingSaveSuccess) {
                Button("OK") { }
            } message: {
                Text("Your notification preferences have been updated.")
            }
            .alert("Unsaved Changes", isPresented: $showingUnsavedChangesAlert) {
                Button("Leave", role: .destructive) { dismiss() }
                Button("Stay", role: .cancel) { }
            } message: {
                Text("You have unsaved changes. Are you sure you want to leave?")
            }
            .onAppear {
                loadCurrentUserSettings()
            }
        }
    }
    
    private func hasUnsavedChanges() -> Bool {
        return betUpdates != originalBetUpdates ||
               communityAlerts != originalCommunityAlerts ||
               newMessages != originalNewMessages ||
               weeklySummaries != originalWeeklySummaries ||
               newMembersJoined != originalNewMembersJoined ||
               membersLeft != originalMembersLeft ||
               hotBetsTrending != originalHotBetsTrending ||
               outstandingBalances != originalOutstandingBalances
    }
    
    private func savePreferences() {
        isLoading = true
        
        print("🔧 Saving push notification preferences")
        
        // Save push notification preferences to Firestore
        firestoreService.updatePushNotificationSettings(enabled: true) { success in
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    print("✅ Push notification preferences saved to Firestore")
                    self.showingSaveSuccess = true
                    
                    // Update original values after successful save
                    self.originalBetUpdates = self.betUpdates
                    self.originalCommunityAlerts = self.communityAlerts
                    self.originalNewMessages = self.newMessages
                    self.originalWeeklySummaries = self.weeklySummaries
                    self.originalNewMembersJoined = self.newMembersJoined
                    self.originalMembersLeft = self.membersLeft
                    self.originalHotBetsTrending = self.hotBetsTrending
                    self.originalOutstandingBalances = self.outstandingBalances
                    
                    // Dismiss after showing success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.dismiss()
                    }
                } else {
                    print("❌ Failed to save push notification preferences")
                    // You could show an error alert here
                }
            }
        }
    }
    
    private func loadCurrentUserSettings() {
        guard let user = firestoreService.currentUser else { return }
        
        // Load current push notification settings
        if let pushEnabled = user.push_notifications_enabled {
            // Update the UI based on current settings
            print("🔧 Loaded push notification settings from Firestore: \(pushEnabled)")
        }
        
        // Set original values to track changes
        originalBetUpdates = betUpdates
        originalCommunityAlerts = communityAlerts
        originalNewMessages = newMessages
        originalWeeklySummaries = weeklySummaries
        originalNewMembersJoined = newMembersJoined
        originalMembersLeft = membersLeft
        originalHotBetsTrending = hotBetsTrending
        originalOutstandingBalances = outstandingBalances
        
        print("🔧 Loaded push notification settings from Firestore")
    }
}

// MARK: - Email Notifications View
struct EmailNotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var firestoreService: FirestoreService
    @State private var weeklySummaries = true
    @State private var betResults = true
    @State private var communityUpdates = false
    @State private var promotionalEmails = false
    @State private var isLoading = false
    @State private var showingSaveSuccess = false
    @State private var showingUnsavedChangesAlert = false
    
    // Original values to track changes
    @State private var originalWeeklySummaries = true
    @State private var originalBetResults = true
    @State private var originalCommunityUpdates = false
    @State private var originalPromotionalEmails = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { 
                        if hasUnsavedChanges() {
                            showingUnsavedChangesAlert = true
                        } else {
                            dismiss()
                        }
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("Email Notifications")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: {
                        savePreferences()
                    }) {
                        Text("Save")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.slingBlue)
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Email Preferences")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            VStack(spacing: 0) {
                                HStack {
                                    SettingsRow(icon: "chart.bar", title: "Weekly Summaries", subtitle: "Your weekly performance", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $weeklySummaries)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "target", title: "Bet Results", subtitle: "Final outcomes of your bets", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $betResults)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "person.3", title: "Community Updates", subtitle: "New community activities", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $communityUpdates)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "megaphone", title: "Promotional Emails", subtitle: "Special offers and updates", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $promotionalEmails)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                            }
                            .background(Color.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
            .alert("Preferences Saved", isPresented: $showingSaveSuccess) {
                Button("OK") { }
            } message: {
                Text("Your email notification preferences have been updated.")
            }
            .alert("Unsaved Changes", isPresented: $showingUnsavedChangesAlert) {
                Button("Leave", role: .destructive) { dismiss() }
                Button("Stay", role: .cancel) { }
            } message: {
                Text("You have unsaved changes. Are you sure you want to leave?")
            }
            .onAppear {
                loadCurrentUserSettings()
            }
        }
    }
    
    private func hasUnsavedChanges() -> Bool {
        return weeklySummaries != originalWeeklySummaries ||
               betResults != originalBetResults ||
               communityUpdates != originalCommunityUpdates ||
               promotionalEmails != originalPromotionalEmails
    }
    
    private func savePreferences() {
        isLoading = true
        
        print("🔧 Saving email notification preferences")
        
        // Save email notification preferences to Firestore
        firestoreService.updateEmailNotificationSettings(
            weeklySummaries: weeklySummaries,
            betResults: betResults,
            communityUpdates: communityUpdates,
            promotionalEmails: promotionalEmails
        ) { success in
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    print("✅ Email notification preferences saved to Firestore")
                    self.showingSaveSuccess = true
                    
                    // Update original values after successful save
                    self.originalWeeklySummaries = self.weeklySummaries
                    self.originalBetResults = self.betResults
                    self.originalCommunityUpdates = self.communityUpdates
                    self.originalPromotionalEmails = self.promotionalEmails
                    
                    // Dismiss after showing success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.dismiss()
                    }
                } else {
                    print("❌ Failed to save email notification preferences")
                    // You could show an error alert here
                }
            }
        }
    }
    
    private func loadCurrentUserSettings() {
        guard let user = firestoreService.currentUser else { return }
        
        // Load current email notification settings
        if let weeklySummaries = user.weekly_summaries_enabled {
            self.weeklySummaries = weeklySummaries
        }
        if let betResults = user.bet_results_enabled {
            self.betResults = betResults
        }
        if let communityUpdates = user.community_updates_enabled {
            self.communityUpdates = communityUpdates
        }
        if let promotionalEmails = user.promotional_emails_enabled {
            self.promotionalEmails = promotionalEmails
        }
        
        // Set original values to track changes
        originalWeeklySummaries = weeklySummaries
        originalBetResults = betResults
        originalCommunityUpdates = communityUpdates
        originalPromotionalEmails = promotionalEmails
        
        print("🔧 Loaded email notification settings from Firestore")
    }
}

// MARK: - Sound Settings View
struct SoundSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var soundEnabled = true
    @State private var vibrationEnabled = true
    @State private var soundVolume: Double = 0.7
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("Sound & Vibration")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color.white)
                
                // Content
        ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Sound Settings")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            VStack(spacing: 0) {
                                HStack {
                                    SettingsRow(icon: "speaker.wave.2", title: "Sound", subtitle: "Enable notification sounds", isDestructive: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $soundEnabled)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "iphone.radiowaves.left.and.right", title: "Vibration", subtitle: "Enable haptic feedback", isDestructive: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $vibrationEnabled)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                }
                                Divider().padding(.leading, 56)
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Volume")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.black)
                                        Spacer()
                                        Text("\(Int(soundVolume * 100))%")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Slider(value: $soundVolume, in: 0...1)
                                        .accentColor(.slingBlue)
                                }
                    .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .background(Color.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Simple Placeholder Views for Other Settings
struct ProfileVisibilityView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var firestoreService: FirestoreService
    @State private var showTotalWinnings = true
    @State private var showTotalBets = true
    @State private var showSlingPoints = true
    @State private var showBlitzPoints = true
    @State private var showCommunities = true
    @State private var isLoading = false
    @State private var showingSaveSuccess = false
    @State private var showingUnsavedChangesAlert = false
    
    // Original values to track changes
    @State private var originalShowTotalWinnings = true
    @State private var originalShowTotalBets = true
    @State private var originalShowSlingPoints = true
    @State private var originalShowBlitzPoints = true
    @State private var originalShowCommunities = true
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { 
                        if hasUnsavedChanges() {
                            showingUnsavedChangesAlert = true
                        } else {
                            dismiss()
                        }
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("Profile Visibility")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: {
                        savePreferences()
                    }) {
                        Text("Save")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.slingBlue)
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Profile Content Display")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            VStack(spacing: 0) {
                                HStack {
                                    SettingsRow(icon: "dollarsign.circle", title: "Total Winnings", subtitle: "Show your total winnings amount", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $showTotalWinnings)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "target", title: "Total Bets", subtitle: "Show your total number of bets", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $showTotalBets)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "bolt.fill", title: "Sling Points", subtitle: "Show your Sling Points balance", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $showSlingPoints)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "flame.fill", title: "Blitz Points", subtitle: "Show your Blitz Points balance", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $showBlitzPoints)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                                Divider().padding(.leading, 56)
                                HStack {
                                    SettingsRow(icon: "person.2", title: "Communities", subtitle: "Show your community memberships", isDestructive: false, showArrow: false, action: {})
                                    Spacer()
                                    Toggle("", isOn: $showCommunities)
                                        .labelsHidden()
                                        .tint(.slingBlue)
                                        .padding(.trailing, 16)
                                }
                            }
                            .background(Color.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
            .alert("Preferences Saved", isPresented: $showingSaveSuccess) {
                Button("OK") { }
            } message: {
                Text("Your profile visibility preferences have been updated.")
            }
            .alert("Unsaved Changes", isPresented: $showingUnsavedChangesAlert) {
                Button("Leave", role: .destructive) { dismiss() }
                Button("Stay", role: .cancel) { }
            } message: {
                Text("You have unsaved changes. Are you sure you want to leave?")
            }
            .onAppear {
                loadCurrentUserSettings()
            }
        }
    }
    
    private func hasUnsavedChanges() -> Bool {
        return showTotalWinnings != originalShowTotalWinnings ||
               showTotalBets != originalShowTotalBets ||
               showSlingPoints != originalShowSlingPoints ||
               showBlitzPoints != originalShowBlitzPoints ||
               showCommunities != originalShowCommunities
    }
    
    private func savePreferences() {
        isLoading = true
        
        print("🔧 Saving profile visibility preferences")
        
        // Create ProfileVisibilitySettings object
        let visibilitySettings = ProfileVisibilitySettings(
            showTotalWinnings: showTotalWinnings,
            showTotalBets: showTotalBets,
            showSlingPoints: showSlingPoints,
            showBlitzPoints: showBlitzPoints,
            showCommunities: showCommunities
        )
        
        // Save profile visibility preferences to Firestore
        firestoreService.updateProfileVisibilitySettings(settings: visibilitySettings) { success in
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    print("✅ Profile visibility preferences saved to Firestore")
                    self.showingSaveSuccess = true
                    
                    // Update original values after successful save
                    self.originalShowTotalWinnings = self.showTotalWinnings
                    self.originalShowTotalBets = self.showTotalBets
                    self.originalShowSlingPoints = self.showSlingPoints
                    self.originalShowBlitzPoints = self.showBlitzPoints
                    self.originalShowCommunities = self.showCommunities
                    
                    // Dismiss after showing success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.dismiss()
                    }
                } else {
                    print("❌ Failed to save profile visibility preferences")
                    // You could show an error alert here
                }
            }
        }
    }
    
    private func loadCurrentUserSettings() {
        guard let user = firestoreService.currentUser,
              let profileSettings = user.profile_visibility_settings else { return }
        
        // Load current profile visibility settings
        showTotalWinnings = profileSettings.showTotalWinnings
        showTotalBets = profileSettings.showTotalBets
        showSlingPoints = profileSettings.showSlingPoints
        showBlitzPoints = profileSettings.showBlitzPoints
        showCommunities = profileSettings.showCommunities
        
        // Set original values to track changes
        originalShowTotalWinnings = showTotalWinnings
        originalShowTotalBets = showTotalBets
        originalShowSlingPoints = showSlingPoints
        originalShowBlitzPoints = showBlitzPoints
        originalShowCommunities = showCommunities
        
        print("🔧 Loaded profile visibility settings from Firestore")
    }
}

struct AccountPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("Account Privacy")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color.white)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Privacy Settings")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            VStack(spacing: 0) {
                                SettingsRow(icon: "eye", title: "Show Online Status", subtitle: "Let others see when you're online", isDestructive: false, action: {})
                                Divider().padding(.leading, 56)
                                SettingsRow(icon: "location", title: "Location Sharing", subtitle: "Share your location with friends", isDestructive: false, action: {})
                                Divider().padding(.leading, 56)
                                SettingsRow(icon: "chart.bar", title: "Activity Statistics", subtitle: "Show your betting statistics", isDestructive: false, action: {})
                            }
                            .background(Color.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
        }
    }
}

struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isChanging = false
    @State private var showCurrentPassword = false
    @State private var showNewPassword = false
    @State private var showConfirmPassword = false
    @State private var showingSaveSuccess = false
    @State private var errorMessage = ""
    @State private var showingUnsavedChangesAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Clean white background
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: { 
                            if hasUnsavedChanges() {
                                showingUnsavedChangesAlert = true
                            } else {
                                dismiss()
                            }
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.title2)
                                .foregroundColor(.black)
                                .frame(width: 44, height: 44)
                        }
                        
                        Spacer()
                        
                        Text("Change Password")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        
                        Spacer()
                        
                        Button(action: {
                            changePassword()
                        }) {
                            Text("Save")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.slingBlue)
                        }
                        .disabled(isChanging)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Content
                    VStack(spacing: 32) {
                        // Title
                        Text("Update Your Password")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        // Subtitle
                        Text("Choose a strong password to secure your account")
                            .font(.body)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        // Password input fields
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Current Password")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                
                                if showCurrentPassword {
                                    TextField("Enter current password", text: $currentPassword)
                                        .textFieldStyle(ModernTextFieldStyle())
                                        .overlay(
                                            HStack {
                                                Spacer()
                                                
                                                Button(action: { showCurrentPassword.toggle() }) {
                                                    Image(systemName: "eye.slash")
                                                        .foregroundColor(.gray)
                                                        .frame(width: 24, height: 24)
                                                }
                                                .padding(.trailing, 20)
                                            }
                                        )
                                } else {
                                    SecureField("Enter current password", text: $currentPassword)
                                        .textFieldStyle(ModernTextFieldStyle())
                                        .overlay(
                                            HStack {
                                                Spacer()
                                                
                                                Button(action: { showCurrentPassword.toggle() }) {
                                                    Image(systemName: showCurrentPassword ? "eye.slash" : "eye")
                                                        .foregroundColor(.gray)
                                                        .frame(width: 24, height: 24)
                                                }
                                                .padding(.trailing, 20)
                                            }
                                        )
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("New Password")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                
                                if showNewPassword {
                                    TextField("Enter new password", text: $newPassword)
                                        .textFieldStyle(ModernTextFieldStyle())
                                        .overlay(
                                            HStack {
                                                Spacer()
                                                
                                                Button(action: { showNewPassword.toggle() }) {
                                                    Image(systemName: "eye.slash")
                                                        .foregroundColor(.gray)
                                                        .frame(width: 24, height: 24)
                                                }
                                                .padding(.trailing, 20)
                                            }
                                        )
                                } else {
                                    SecureField("Enter new password", text: $newPassword)
                                        .textFieldStyle(ModernTextFieldStyle())
                                        .overlay(
                                            HStack {
                                                Spacer()
                                                
                                                Button(action: { showNewPassword.toggle() }) {
                                                    Image(systemName: showNewPassword ? "eye.slash" : "eye")
                                                        .foregroundColor(.gray)
                                                        .frame(width: 24, height: 24)
                                                }
                                                .padding(.trailing, 20)
                                            }
                                        )
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Confirm New Password")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                
                                if showConfirmPassword {
                                    TextField("Confirm new password", text: $confirmPassword)
                                        .textFieldStyle(ModernTextFieldStyle())
                                        .overlay(
                                            HStack {
                                                Spacer()
                                                
                                                Button(action: { showConfirmPassword.toggle() }) {
                                                    Image(systemName: "eye.slash")
                                                        .foregroundColor(.gray)
                                                        .frame(width: 24, height: 24)
                                                }
                                                .padding(.trailing, 20)
                                            }
                                        )
                                } else {
                                    SecureField("Confirm new password", text: $confirmPassword)
                                        .textFieldStyle(ModernTextFieldStyle())
                                        .overlay(
                                            HStack {
                                                Spacer()
                                                
                                                Button(action: { showConfirmPassword.toggle() }) {
                                                    Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                                                        .foregroundColor(.gray)
                                                        .frame(width: 24, height: 24)
                                                }
                                                .padding(.trailing, 20)
                                            }
                                        )
                                }
                            }
                            
                            Text("Must be at least 6 characters")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer()
                    }
                    .padding(.top, 40)
                }
            }
            .navigationBarHidden(true)
            .alert("Password Changed", isPresented: $showingSaveSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your password has been successfully updated.")
            }
            .alert("Error", isPresented: .constant(!errorMessage.isEmpty)) {
                Button("OK") { errorMessage = "" }
            } message: {
                Text(errorMessage)
            }
            .alert("Unsaved Changes", isPresented: $showingUnsavedChangesAlert) {
                Button("Leave", role: .destructive) { dismiss() }
                Button("Stay", role: .cancel) { }
            } message: {
                Text("You have unsaved changes. Are you sure you want to leave?")
            }
        }
    }
    
    private func hasUnsavedChanges() -> Bool {
        return !currentPassword.isEmpty || !newPassword.isEmpty || !confirmPassword.isEmpty
    }
    
    private func changePassword() {
        // Validate input
        guard !currentPassword.isEmpty && !newPassword.isEmpty && !confirmPassword.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        
        guard newPassword == confirmPassword else {
            errorMessage = "New passwords do not match"
            return
        }
        
        guard newPassword.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            return
        }
        
        isChanging = true
        
        // Simulate password change (you'll need to implement this in FirestoreService)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.isChanging = false
            self.showingSaveSuccess = true
        }
    }
}

// MARK: - Remaining Placeholder Views


struct ExportDataView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("Export Data")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color.white)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Data Export Options")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            VStack(spacing: 0) {
                                SettingsRow(icon: "doc.text", title: "Betting History", subtitle: "Export all your betting data", isDestructive: false, action: {})
                                Divider().padding(.leading, 56)
                                SettingsRow(icon: "person.3", title: "Community Data", subtitle: "Export community participation", isDestructive: false, action: {})
                                Divider().padding(.leading, 56)
                                SettingsRow(icon: "chart.bar", title: "Statistics", subtitle: "Export performance analytics", isDestructive: false, action: {})
                            }
        .background(Color.white)
        .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
        }
    }
}

struct LanguageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var firestoreService: FirestoreService
    @State private var selectedLanguage = "English"
    
    let languages = ["English", "Spanish", "French", "German", "Chinese", "Japanese"]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
        HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 44, height: 44)
                    }
                    
                    Button(action: {
                        saveLanguage()
                    }) {
                        Text("Save")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.slingBlue)
                    }
                    
                    Spacer()
                    
                    Text("Language")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color.white)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Select Language")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            VStack(spacing: 0) {
                                ForEach(languages, id: \.self) { language in
                                    HStack {
                                        SettingsRow(icon: "globe", title: language, subtitle: "", isDestructive: false, showArrow: false, action: {})
                                        Spacer()
                                        if selectedLanguage == language {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.slingBlue)
                                                .font(.caption)
                                                .scaleEffect(0.8)
                                        }
                                    }
                                    if language != languages.last {
                                        Divider().padding(.leading, 56)
                                    }
                                }
                            }
                            .background(Color.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
            .onAppear {
                loadCurrentUserSettings()
            }
        }
    }
    
    private func saveLanguage() {
        print("🔧 Saving language preference")
        
        // Save language preference to Firestore
        firestoreService.updateLanguageSetting(language: selectedLanguage) { success in
            DispatchQueue.main.async {
                if success {
                    print("✅ Language preference saved to Firestore")
                    self.dismiss()
                } else {
                    print("❌ Failed to save language preference")
                    // You could show an error alert here
                }
            }
        }
    }
    
    private func loadCurrentUserSettings() {
        guard let user = firestoreService.currentUser else { return }
        
        // Load current language setting
        if let language = user.language {
            selectedLanguage = language
            print("🔧 Loaded language setting from Firestore: \(language)")
        }
    }
}

// MARK: - Contact Us View
struct ContactSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var firestoreService: FirestoreService
    @State private var messageText = ""
    @State private var subject = ""
    @State private var isSubmitting = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 44, height: 44)
                    }
                    
                    Button(action: {
                        submitContactRequest()
                    }) {
                        Text("Submit")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.slingBlue)
                    }
                    .disabled(isSubmitting)
                    
                    Spacer()
                    
                    Text("Contact Us")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color.white)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Send us a message")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            VStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Subject")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.black)
                                    
                                    TextField("Enter subject", text: $subject)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Color.white)
                                        .cornerRadius(8)
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Message")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.black)
                                    
                                    TextEditor(text: $messageText)
                                        .frame(minHeight: 120)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Color.white)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                }
                                
                                Button(action: submitContactRequest) {
                                    HStack {
                                        if isSubmitting {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.8)
                                        } else {
                                            Text("Submit Request")
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.slingBlue)
                                    .cornerRadius(12)
                                }
                                .disabled(messageText.isEmpty || subject.isEmpty || isSubmitting)
                                .opacity(messageText.isEmpty || subject.isEmpty ? 0.6 : 1.0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .background(Color.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your message has been sent successfully. We'll get back to you soon!")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func submitContactRequest() {
        guard !messageText.isEmpty && !subject.isEmpty else { return }
        
        isSubmitting = true
        
        // Create contact request data
        let _: [String: Any] = [
            "subject": subject,
            "message": messageText,
            "timestamp": Date(),
            "status": "pending",
            "deviceInfo": getDeviceInfo(),
            "consoleLogs": getConsoleLogs()
        ]
        
        // Here you would save to Firestore "Contact" collection
        // For now, we'll simulate the submission
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSubmitting = false
            showSuccessAlert = true
        }
    }
    
    private func getDeviceInfo() -> String {
        let device = UIDevice.current
        return "\(device.model) - \(device.systemName) \(device.systemVersion)"
    }
    
    private func getConsoleLogs() -> String {
        // In a real app, you might want to capture console logs
        // For now, return a placeholder
        return "Console logs captured at \(Date())"
    }
}

struct RateAppView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("Rate App")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color.white)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Rate SlingApp")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            VStack(spacing: 16) {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "star.fill")
                                            .font(.largeTitle)
                                            .foregroundColor(.yellow)
                                        Text("Rate us on the App Store")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.black)
                                        Text("Your feedback helps us improve")
                .font(.subheadline)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                
                                Button(action: {
                                    // TODO: Open App Store rating
                                    print("Open App Store rating")
                                }) {
                                    Text("Rate Now")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 50)
                                        .background(Color.slingBlue)
                                        .cornerRadius(12)
                                }
                            }
                            .padding(20)
                            .background(Color.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
        }
    }
    

}

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("Terms of Service")
                        .font(.title2)
                        .fontWeight(.bold)
                .foregroundColor(.black)
            
            Spacer()
            
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color.white)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Terms & Conditions")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            Text("By using SlingApp, you agree to our terms of service...")
                                .font(.body)
                                .foregroundColor(.black)
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
        }
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("Privacy Policy")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color.white)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Privacy Information")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            Text("SlingApp is committed to protecting your privacy...")
                                .font(.body)
                                .foregroundColor(.black)
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
        }
    }
}

struct AboutAppView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("About SlingApp")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color.white)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("App Information")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            VStack(spacing: 16) {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "bolt.fill")
                                            .font(.largeTitle)
                                            .foregroundColor(.slingBlue)
                                        Text("SlingApp")
                                            .font(.title)
                                            .fontWeight(.bold)
                                            .foregroundColor(.black)
                                        Text("Version 1.0.0")
                .font(.subheadline)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                
                                VStack(spacing: 12) {
                                    SettingsRow(icon: "doc.text", title: "Build Number", subtitle: "2024.1.0", isDestructive: false, action: {})
                                    Divider().padding(.leading, 56)
                                    SettingsRow(icon: "calendar", title: "Release Date", subtitle: "January 2024", isDestructive: false, action: {})
                                    Divider().padding(.leading, 56)
                                    SettingsRow(icon: "person.2", title: "Developer", subtitle: "SlingApp Team", isDestructive: false, action: {})
                                }
                                .background(Color.white)
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
        }
    }
}

struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("Delete Account")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color.white)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("⚠️ Warning")
                                    .font(.headline)
                .fontWeight(.semibold)
                                    .foregroundColor(.red)
                                Spacer()
                            }
                            
                            Text("This action cannot be undone. All your data, bets, and community memberships will be permanently deleted.")
                                .font(.body)
                .foregroundColor(.black)
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white)
                                .cornerRadius(12)
                            
                            Button(action: {
                                // TODO: Implement account deletion
                                print("Delete account")
                            }) {
                                Text("Delete Account")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.red)
                                    .cornerRadius(12)
                            }
                        }
        }
        .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
        }
    }
}

struct SignOutView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var firestoreService: FirestoreService
    @State private var isSigningOut = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .foregroundColor(.slingBlue)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    Text("Sign Out")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color.white)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            HStack {
                                Text("Sign Out Confirmation")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            
                            Text("Are you sure you want to sign out? You'll need to sign in again to access your account.")
                                .font(.body)
                                .foregroundColor(.black)
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(12)
                            
                            Button(action: {
                                // Implement actual sign out
                                isSigningOut = true
                                firestoreService.signOut()
                                
                                // Add a small delay to ensure auth state change propagates
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    // The auth state change should have already triggered navigation
                                    // If for some reason it hasn't, we can manually dismiss
                                    if firestoreService.isAuthenticated {
                                        dismiss()
                                    }
                                }
                            }) {
                                HStack {
                                    if isSigningOut {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    }
                                    Text(isSigningOut ? "Signing Out..." : "Sign Out")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(isSigningOut ? Color.gray : Color.slingBlue)
                                .cornerRadius(12)
                            }
                            .disabled(isSigningOut)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
        }
    }
}

struct MemberManagementView: View {
    let community: FirestoreCommunity
    let firestoreService: FirestoreService
    let isAdmin: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var members: [CommunityMemberInfo] = []
    @State private var isLoading = false
    @State private var showingKickAlert = false
    @State private var selectedMember: CommunityMemberInfo?
    @State private var showingPromoteAlert = false
    @State private var showingDemoteAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.slingBlue)
                    
                    Spacer()
                    
                    Text("Member Management")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.slingBlue)
                }
                .padding()
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.gray.opacity(0.3)),
                    alignment: .bottom
                )
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                } else {
                    List {
                        ForEach(members, id: \.id) { member in
                            MemberManagementRowView(
                                member: member,
                                isAdmin: isAdmin,
                                onKick: { showKickAlert(for: member) },
                                onPromote: { showPromoteAlert(for: member) },
                                onDemote: { showDemoteAlert(for: member) }
                            )
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            loadMembers()
        }
        .alert("Kick Member", isPresented: $showingKickAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Kick", role: .destructive) {
                if let member = selectedMember {
                    kickMember(member)
                }
            }
        } message: {
            if let member = selectedMember {
                Text("Are you sure you want to kick \(member.name) from the community?")
            }
        }
        .alert("Promote to Admin", isPresented: $showingPromoteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Promote") {
                if let member = selectedMember {
                    promoteMember(member)
                }
            }
        } message: {
            if let member = selectedMember {
                Text("Are you sure you want to promote \(member.name) to admin?")
            }
        }
        .alert("Demote from Admin", isPresented: $showingDemoteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Demote") {
                if let member = selectedMember {
                    demoteMember(member)
                }
            }
        } message: {
            if let member = selectedMember {
                Text("Are you sure you want to demote \(member.name) from admin?")
            }
        }
    }
    
    private func loadMembers() {
        isLoading = true
        firestoreService.fetchCommunityMembers(communityId: community.id ?? "") { fetchedMembers in
            DispatchQueue.main.async {
                self.members = fetchedMembers
                self.isLoading = false
            }
        }
    }
    
    private func showKickAlert(for member: CommunityMemberInfo) {
        selectedMember = member
        showingKickAlert = true
    }
    
    private func showPromoteAlert(for member: CommunityMemberInfo) {
        selectedMember = member
        showingPromoteAlert = true
    }
    
    private func showDemoteAlert(for member: CommunityMemberInfo) {
        selectedMember = member
        showingDemoteAlert = true
    }
    
    private func kickMember(_ member: CommunityMemberInfo) {
        firestoreService.kickMemberFromCommunity(communityId: community.id ?? "", memberEmail: member.email) { success in
            if success {
                DispatchQueue.main.async {
                    // Remove member from local array
                    self.members.removeAll { $0.id == member.id }
                }
            }
        }
    }
    
    private func promoteMember(_ member: CommunityMemberInfo) {
        firestoreService.promoteMemberToAdmin(communityId: community.id ?? "", memberEmail: member.email) { success in
            if success {
                DispatchQueue.main.async {
                    // Update member in local array
                    if let index = self.members.firstIndex(where: { $0.id == member.id }) {
                        self.members[index] = CommunityMemberInfo(
                            id: member.id,
                            email: member.email,
                            name: member.name,
                            isActive: member.isActive,
                            joinDate: member.joinDate,
                            isAdmin: true
                        )
                    }
                }
            }
        }
    }
    
    private func demoteMember(_ member: CommunityMemberInfo) {
        firestoreService.demoteAdminToMember(communityId: community.id ?? "", memberEmail: member.email) { success in
            if success {
                DispatchQueue.main.async {
                    // Update member in local array
                    if let index = self.members.firstIndex(where: { $0.id == member.id }) {
                        self.members[index] = CommunityMemberInfo(
                            id: member.id,
                            email: member.email,
                            name: member.name,
                            isActive: member.isActive,
                            joinDate: member.joinDate,
                            isAdmin: false
                        )
                    }
                }
            }
        }
    }
}

struct CommunitySettingsDetailView: View {
    let community: FirestoreCommunity
    let firestoreService: FirestoreService
    let isAdmin: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var communityName: String
    @State private var communityDescription: String
    @State private var isPrivate: Bool
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var errorMessage = ""
    
    init(community: FirestoreCommunity, firestoreService: FirestoreService, isAdmin: Bool) {
        self.community = community
        self.firestoreService = firestoreService
        self.isAdmin = isAdmin
        self._communityName = State(initialValue: community.name)
        self._communityDescription = State(initialValue: community.description ?? "")
        self._isPrivate = State(initialValue: community.is_private ?? false)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.slingBlue)
                    
                    Spacer()
                    
                    Text("Community Settings")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    if isAdmin {
                        Button(isEditing ? "Save" : "Edit") {
                            if isEditing {
                                saveChanges()
                            } else {
                                isEditing = true
                            }
                        }
                        .foregroundColor(.slingBlue)
                        .disabled(isSaving)
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundColor(.slingBlue)
                    }
                }
                .padding()
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.gray.opacity(0.3)),
                    alignment: .bottom
                )
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Community Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Community Name")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            if isEditing && isAdmin {
                                TextField("Community Name", text: $communityName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            } else {
                                Text(communityName)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            }
                        }
                        
                        // Community Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            if isEditing && isAdmin {
                                TextField("Description", text: $communityDescription, axis: .vertical)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .lineLimit(3...6)
                            } else {
                                Text(communityDescription.isEmpty ? "No description" : communityDescription)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            }
                        }
                        
                        // Privacy Setting
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Privacy")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            if isEditing && isAdmin {
                                Toggle("Private Community", isOn: $isPrivate)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            } else {
                                HStack {
                                    Text(isPrivate ? "Private" : "Public")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                    
                                    Spacer()
                                    
                                    Image(systemName: isPrivate ? "lock.fill" : "globe")
                                        .foregroundColor(isPrivate ? .orange : .green)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                        
                        // Invite Code (Read-only)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Invite Code")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            HStack {
                                Text(community.invite_code)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                
                                Spacer()
                                
                                Button(action: {
                                    UIPasteboard.general.string = community.invite_code
                                }) {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.title3)
                                        .foregroundColor(.slingBlue)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    private func saveChanges() {
        isSaving = true
        errorMessage = ""
        
        let group = DispatchGroup()
        var hasError = false
        
        // Update community name if changed
        if communityName != community.name {
            group.enter()
            firestoreService.updateCommunityName(communityId: community.id ?? "", newName: communityName) { success in
                if !success {
                    hasError = true
                    errorMessage = "Failed to update community name"
                }
                group.leave()
            }
        }
        
        // Update community description if changed
        if communityDescription != (community.description ?? "") {
            group.enter()
            firestoreService.updateCommunityDescription(communityId: community.id ?? "", newDescription: communityDescription) { success in
                if !success {
                    hasError = true
                    errorMessage = "Failed to update community description"
                }
                group.leave()
            }
        }
        
        // Update privacy setting if changed
        if isPrivate != (community.is_private ?? false) {
            group.enter()
            firestoreService.toggleCommunityPrivacy(communityId: community.id ?? "", isPrivate: isPrivate) { success in
                if !success {
                    hasError = true
                    errorMessage = "Failed to update privacy setting"
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            isSaving = false
            if !hasError {
                isEditing = false
            }
        }
    }
}

struct AdminControlsView: View {
    let community: FirestoreCommunity
    let firestoreService: FirestoreService
    @Environment(\.dismiss) private var dismiss
    @State private var members: [CommunityMemberInfo] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.slingBlue)
                    
                    Spacer()
                    
                    Text("Admin Controls")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.slingBlue)
                }
                .padding()
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.gray.opacity(0.3)),
                    alignment: .bottom
                )
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Admin Statistics
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Admin Statistics")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Total Members")
                                    Spacer()
                                    Text("\(community.member_count)")
                                        .fontWeight(.medium)
                                }
                                
                                HStack {
                                    Text("Total Bets")
                                    Spacer()
                                    Text("\(community.total_bets)")
                                        .fontWeight(.medium)
                                }
                                
                                HStack {
                                    Text("Community Status")
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(community.is_active == true ? Color.green : Color.red)
                                            .frame(width: 8, height: 8)
                                        Text(community.is_active == true ? "Active" : "Inactive")
                                            .fontWeight(.medium)
                                    }
                                }
                            }
                            .font(.subheadline)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        
                        // Quick Actions
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Quick Actions")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            VStack(spacing: 8) {
                                Button(action: {
                                    // Toggle community status
                                    _ = !(community.is_active ?? true)
                                    // TODO: Implement toggle community status
                                }) {
                                    HStack {
                                        Image(systemName: "power")
                                            .foregroundColor(.slingBlue)
                                        Text("Toggle Community Status")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.gray)
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Button(action: {
                                    // Regenerate invite code
                                    // TODO: Implement regenerate invite code
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.clockwise")
                                            .foregroundColor(.slingBlue)
                                        Text("Regenerate Invite Code")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.gray)
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            loadMembers()
        }
    }
    
    private func loadMembers() {
        isLoading = true
        firestoreService.fetchCommunityMembers(communityId: community.id ?? "") { fetchedMembers in
            DispatchQueue.main.async {
                self.members = fetchedMembers
                self.isLoading = false
            }
        }
    }
}

struct MemberManagementRowView: View {
    let member: CommunityMemberInfo
    let isAdmin: Bool
    let onKick: () -> Void
    let onPromote: () -> Void
    let onDemote: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile Picture
            Circle()
                .fill(Color.slingGradient)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(member.name.prefix(1)).uppercased())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                    
                    if member.isAdmin {
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundColor(.slingPurple)
                            Text("Admin")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.slingPurple)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.slingPurple.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                
                Text(member.email)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if isAdmin && !member.isAdmin {
                // Show promote button for regular members
                Button(action: onPromote) {
                    Image(systemName: "arrow.up.circle")
                        .font(.title3)
                        .foregroundColor(.slingBlue)
                }
            } else if isAdmin && member.isAdmin {
                // Show demote button for other admins
                Button(action: onDemote) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
            }
            
            if isAdmin && !member.isAdmin {
                // Show kick button for regular members
                Button(action: onKick) {
                    Image(systemName: "xmark.circle")
                        .font(.title3)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct MemberRowView: View {
    let memberWithPoints: CommunityMemberWithPoints
    let rank: Int
    let onTap: () -> Void
    @State private var userFullName: String?
    @State private var isLoadingUserData = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Ranking number
                Text("\(rank)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
                    .frame(width: 16, alignment: .center)
                
                // Profile Picture
                Circle()
                    .fill(AnyShapeStyle(Color.slingGradient))
                    .frame(width: 40, height: 40)
        .overlay(
                        Text(String(memberWithPoints.name.prefix(1)).uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if isLoadingUserData {
                            Text("Loading...")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.gray)
                        } else {
                            Text(userFullName ?? memberWithPoints.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                        }
                        
                        // Admin badge
                        if memberWithPoints.isAdmin {
                            HStack(spacing: 2) {
                                Image(systemName: "crown.fill")
                                    .font(.caption2)
                                    .foregroundColor(.purple)
                                Text("Admin")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.purple)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
                
                Spacer()
                
                // Net points on the right
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(memberWithPoints.netPoints >= 0 ? .green : .red)
                    
                    Text("\(String(format: "%.0f", memberWithPoints.netPoints))")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(memberWithPoints.netPoints >= 0 ? .green : .red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (memberWithPoints.netPoints >= 0 ? Color.green : Color.red).opacity(0.1)
                )
                .cornerRadius(8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadUserFullName()
        }
    }
    
    private func loadUserFullName() {
        guard userFullName == nil && !isLoadingUserData else { return }
        
        isLoadingUserData = true
        
        Task {
            do {
                let user = try await FirestoreService().getUser(userId: memberWithPoints.email)
                await MainActor.run {
                    self.userFullName = user.full_name
                    self.isLoadingUserData = false
                }
            } catch {
                print("❌ Error loading user full name for \(memberWithPoints.email): \(error)")
                await MainActor.run {
                    self.isLoadingUserData = false
                }
            }
        }
    }
}

struct BetHistoryRow: View {
    let title: String
    let amount: String
    let status: String
    let date: String
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.black)
                
                Text(date)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(amount)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                
                Text(status)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(status == "Won" ? .green : .red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct BetLoadingRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 150, height: 16)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 100, height: 12)
            }
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 60, height: 24)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
    }
}

struct PerformanceCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(width: 120, height: 100)
        .padding(.vertical, 16)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct RecentBetRow: View {
    let bet: FirestoreBet
    
    var body: some View {
        HStack(spacing: 12) {
            // Bet Image or Fallback Icon
            if let imageUrl = bet.image_url, !imageUrl.isEmpty {
                AsyncImage(url: URL(string: imageUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // Fallback icon based on bet type
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: getBetTypeIcon(bet.bet_type))
                            .font(.caption)
                            .foregroundColor(.gray)
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(bet.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.black)
                    .lineLimit(1)
                
                Text("Deadline: \(formatDate(bet.deadline))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text(bet.status.uppercased())
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(bet.status == "open" ? Color.green : Color.gray)
                .cornerRadius(8)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func getBetTypeIcon(_ betType: String) -> String {
        switch betType.lowercased() {
        case "sports":
            return "sportscourt.fill"
        case "politics":
            return "building.columns.fill"
        case "entertainment":
            return "tv.fill"
        case "weather":
            return "cloud.sun.fill"
        case "finance":
            return "chart.line.uptrend.xyaxis"
        case "technology":
            return "laptopcomputer"
        case "health":
            return "heart.fill"
        case "education":
            return "book.fill"
        default:
            return "questionmark.circle.fill"
        }
    }
}

// MARK: - Community Settings Views

struct NotificationSettingsView: View {
    let community: FirestoreCommunity
    let firestoreService: FirestoreService
    let isAdmin: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isNotificationsMuted = false
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "bell")
                        .font(.system(size: 40))
                        .foregroundColor(.slingBlue)
                    
                    Text("Notification Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Manage how you receive notifications for \(community.name)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Settings
                VStack(spacing: 16) {
                    // Mute Notifications Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mute Notifications")
                                .font(.headline)
                                .fontWeight(.medium)
                            Text("Stop receiving notifications from this community")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $isNotificationsMuted)
                            .onChange(of: isNotificationsMuted) { _, newValue in
                                updateNotificationPreferences(muted: newValue)
                            }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Additional settings for admins
                    if isAdmin {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Admin Notifications")
                                .font(.headline)
                                .fontWeight(.medium)
                            
                            VStack(spacing: 8) {
                                HStack {
                                    Text("New member joins")
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.green)
                                }
                                
                                HStack {
                                    Text("New bet created")
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.green)
                                }
                                
                                HStack {
                                    Text("Bet settled")
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.green)
                                }
                            }
                            .font(.subheadline)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Done Button
                Button("Done") {
                    dismiss()
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.slingGradient)
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            loadNotificationPreferences()
        }
    }
    
    private func loadNotificationPreferences() {
        guard let userEmail = firestoreService.currentUser?.email else { return }
        
        isLoading = true
        firestoreService.getNotificationPreferences(communityId: community.id ?? "", userEmail: userEmail) { isMuted in
            DispatchQueue.main.async {
                self.isNotificationsMuted = isMuted
                self.isLoading = false
            }
        }
    }
    
    private func updateNotificationPreferences(muted: Bool) {
        guard let userEmail = firestoreService.currentUser?.email else { return }
        
        firestoreService.updateNotificationPreferences(communityId: community.id ?? "", userEmail: userEmail, isMuted: muted) { success in
            if success {
                print("✅ Notification preferences updated")
            } else {
                print("❌ Failed to update notification preferences")
                // Revert the toggle if update failed
                DispatchQueue.main.async {
                    self.isNotificationsMuted.toggle()
                }
            }
        }
    }
}

// MARK: - Community Image Picker Component

struct CommunityImagePicker: View {
    let community: FirestoreCommunity
    @ObservedObject var firestoreService: FirestoreService
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var isUploading = false
    @State private var showingCamera = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                
                // Header
                VStack(spacing: 16) {
                    Text("Change Community Icon")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text("Choose a new profile picture for \(community.name)")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 20)
                
                // Current Image Preview
                VStack(spacing: 16) {
                    if let selectedImage = selectedImage {
                        // Show selected image
                        Image(uiImage: selectedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    } else if let profileImageUrl = community.profile_image_url {
                        // Show current community image
                        AsyncImage(url: URL(string: profileImageUrl)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                                )
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    } else {
                        // Show community initials
                        Circle()
                            .fill(Color.slingLightBlue)
                            .frame(width: 120, height: 120)
                            .overlay(
                                Text(String(community.name.prefix(1)).uppercased())
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.slingBlue)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    Text("Current Profile Picture")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                // Image Selection Options
                VStack(spacing: 16) {
                    // Photo Library Button
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 16) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                                .foregroundColor(.slingBlue)
                                .frame(width: 24, height: 24)
                            
                            Text("Choose from Photo Library")
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(.slingBlue)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.headline)
                                .foregroundColor(.gray.opacity(0.6))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    
                    // Camera Button
                    Button(action: {
                        showingCamera = true
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: "camera")
                                .font(.title2)
                                .foregroundColor(.slingBlue)
                                .frame(width: 24, height: 24)
                            
                            Text("Take a Photo")
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(.slingBlue)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.headline)
                                .foregroundColor(.gray.opacity(0.6))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Upload Button
                if selectedImage != nil {
                    Button(action: uploadImage) {
                        HStack(spacing: 8) {
                            if isUploading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                            } else {
                                Text("Update Profile Picture")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.slingGradient)
                    .cornerRadius(16)
                    .shadow(color: Color.slingBlue.opacity(0.3), radius: 8, x: 0, y: 4)
                    .disabled(isUploading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
            .background(Color.gray.opacity(0.05))
            .navigationBarHidden(true)
            .overlay(
                // Custom navigation bar
                VStack {
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundColor(.black)
                                .frame(width: 44, height: 44)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    Spacer()
                },
                alignment: .top
            )
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                if let newItem = newItem {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        selectedImage = uiImage
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraView { image in
                selectedImage = image
                showingCamera = false
            }
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func uploadImage() {
        guard let image = selectedImage,
              let communityId = community.id else { return }
        
        isUploading = true
        
        firestoreService.uploadCommunityImage(image, communityId: communityId) { success, error in
            DispatchQueue.main.async {
                isUploading = false
                
                if success {
                    dismiss()
                } else {
                    errorMessage = error ?? "Failed to upload image"
                    showingErrorAlert = true
                }
            }
        }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - User Image Picker

struct UserImagePicker: View {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var showingCamera = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.slingBlue)
                    
                    Text("Choose Profile Picture")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text("Select from your photos or take a new picture")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                
                // Preview section
                if let selectedImage = selectedImage {
                    VStack(spacing: 16) {
                        Text("Preview")
                            .font(.headline)
                            .foregroundColor(.black)
                        
                        Image(uiImage: selectedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.slingBlue, lineWidth: 3)
                            )
                    }
                }
                
                // Action buttons
                VStack(spacing: 16) {
                    // Photo Library Button
                    PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                        HStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title3)
                                .foregroundColor(.slingBlue)
                            
                            Text("Choose from Photos")
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(.slingBlue)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color.slingLightBlue)
                        )
                    }
                    
                    // Camera Button
                    Button(action: {
                        showingCamera = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "camera")
                                .font(.title3)
                                .foregroundColor(.white)
                            
                            Text("Take Photo")
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color.slingBlue)
                        )
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .padding(.top, 20)
            .background(Color.white)
            .navigationBarHidden(true)
            .overlay(
                // Close button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.gray)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.gray.opacity(0.1)))
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 20)
                    }
                    Spacer()
                },
                alignment: .top
            )
        }
        .onChange(of: selectedItem) { _ in
            Task {
                if let newItem = selectedItem {
                    do {
                        if let data = try await newItem.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            await MainActor.run {
                                selectedImage = image
                                dismiss()
                            }
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = "Failed to load image"
                            showingErrorAlert = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraView { image in
                selectedImage = image
                showingCamera = false
                dismiss()
            }
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Photos Picker Sheet
struct PhotosPickerSheet: View {
    @Binding var selectedItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 60))
                            .foregroundColor(.slingBlue)
                        
                        Text("Choose from Photos")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        Text("Select a photo from your library")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                    .contentShape(Rectangle())
                }
                .onChange(of: selectedItem) { newItem in
                    if newItem != nil {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Select Photo")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

