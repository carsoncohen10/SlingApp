import SwiftUI
import UIKit
import FirebaseFirestore
import Network

// MARK: - Custom Colors Extension
extension Color {
    static let slingBlue = Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0))
    static let slingPurple = Color(uiColor: UIColor(red: 0x4E/255, green: 0x46/255, blue: 0xE5/255, alpha: 1.0))
    static let slingGradient: LinearGradient = LinearGradient(
        colors: [Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)), 
                 Color(uiColor: UIColor(red: 0x4E/255, green: 0x46/255, blue: 0xE5/255, alpha: 1.0))],
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
            for tag in image.tags {
                let tagName = tag.title.lowercased()
                for word in titleWords {
                    if tagName.contains(word) { score += 1.0 }
                }
            }
            
            // Social bias for people-related content
            if lowercasedTitle.contains("family") || lowercasedTitle.contains("dad") || lowercasedTitle.contains("mom") || lowercasedTitle.contains("person") || lowercasedTitle.contains("people") {
                if description.contains("person") || description.contains("people") || description.contains("family") {
                    score += 0.5
                }
            }
            
            // Likes tiebreaker
            score += Double(image.likes) * 0.001
            
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
    let likes: Int
    let urls: UnsplashURLs
    let tags: [UnsplashTag]
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
                
                Text("Get started by joining or creating a community. Connect with friends and start predicting!")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            
            // Action Buttons
            VStack(spacing: 12) {
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
            
            Text("No active bets found")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
            
            Text("You don't have any active bets right now.")
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
            CreateBetView(firestoreService: firestoreService)
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
            
            Text("No active bets found")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
            
            Text("You don't have any active bets right now.")
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
            CreateBetView(firestoreService: firestoreService)
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
            CreateBetView(firestoreService: firestoreService)
        }
    }
}

struct EmptyCommunitiesView: View {
    let firestoreService: FirestoreService
    @State private var showingJoinCommunityModal = false
    @State private var showingCreateCommunityModal = false
    
    var body: some View {
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
            
            VStack(spacing: 12) {
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
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.slingGradient)
                    .cornerRadius(10)
                }
                
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
                    .background(Color.slingGradient)
                    .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showingJoinCommunityModal) {
            JoinCommunityPage(firestoreService: firestoreService)
        }
        .sheet(isPresented: $showingCreateCommunityModal) {
            CreateCommunityPage(firestoreService: firestoreService)
        }
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
    @State private var showingJoinBet = false
    @State private var hasRemindedCreator = false
    @State private var showingBettingInterface = false
    @State private var selectedBettingOption = ""
    
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
                                .foregroundColor(.gray)
                            Text("\(communityName) • by \(currentUserEmail == bet.creator_email ? "You" : getFirstNameFromEmail(bet.creator_email))")
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
                        .buttonStyle(PlainButtonStyle())
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
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingJoinBet) {
            JoinBetView(bet: bet, firestoreService: firestoreService)
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
    @State private var selectedFilter = 0 // 0 = Active, 1 = Past Bets
    
    // Computed properties for statistics
    private var activeBets: [FirestoreBet] {
        let currentUserEmail = firestoreService.currentUser?.email
        let openBets = firestoreService.bets.filter { $0.status == "open" }
        
        return openBets.filter { bet in
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
            VStack(spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("My Bets")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text("Track all your predictions and their outcomes")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Statistics Cards
                HStack(spacing: 12) {
                    // Active
                    StatCard(
                        icon: "clock.arrow.circlepath",
                        iconColor: Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)),
                        value: "\(activeBets.count)",
                        label: "Active"
                    )
                    
                    // Won  
                    StatCard(
                        icon: "trophy.fill",
                        iconColor: .green,
                        value: "\(wonBets.count)",
                        label: "Won"
                    )
                    
                    // Past Bets
                    StatCard(
                        icon: "checkmark.circle.fill",
                        iconColor: .purple,
                        value: "\(pastBets.count)",
                        label: "Past Bets"
                    )
                    
                    // Total Bets
                    StatCard(
                        icon: "bolt.fill",
                        iconColor: .orange,
                        value: "\(totalBets)",
                        label: "Total Bets"
                    )
                }
                .padding(.horizontal, 16)
                
                // Filter Buttons - Blue and White styling
                HStack(spacing: 0) {
                    Button(action: { selectedFilter = 0 }) {
                        Text("Active")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(selectedFilter == 0 ? .white : Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selectedFilter == 0 ? AnyShapeStyle(Color.slingGradient) : AnyShapeStyle(Color.white))
                            .cornerRadius(8, corners: [.topLeft, .bottomLeft])
                    }
                    
                    Button(action: { selectedFilter = 1 }) {
                        Text("Past Bets")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(selectedFilter == 1 ? .white : Color(uiColor: UIColor(red: 0x26/255, green: 0x63/255, blue: 0xEB/255, alpha: 1.0)))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selectedFilter == 1 ? AnyShapeStyle(Color.slingGradient) : AnyShapeStyle(Color.white))
                            .cornerRadius(8, corners: [.topRight, .bottomRight])
                    }
                }
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                
                // Bet Cards
                if selectedFilter == 0 {
                    if activeBets.isEmpty {
                        EmptyActiveBetsView(firestoreService: firestoreService)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(activeBets) { bet in
                                MyBetCard(bet: bet, currentUserEmail: firestoreService.currentUser?.email, firestoreService: firestoreService)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                } else {
                    // Past Bets
                    if pastBets.isEmpty {
                        EmptyPastBetsView(firestoreService: firestoreService)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(pastBets) { bet in
                                MyBetCard(bet: bet, currentUserEmail: firestoreService.currentUser?.email, firestoreService: firestoreService)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
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
                JoinBetView(bet: bet, firestoreService: firestoreService)
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
    let timestamp: String
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
        HStack(alignment: .center) {
            // Left side - Avatar/Logo space (consistent for all message types)
            HStack(alignment: .top, spacing: 4) {
                if isBot {
                    // Sling logo - smaller and circular like user avatars
                    Image("Logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else if !isCurrentUser {
                    // User avatar for other users
                    Circle()
                        .fill(Color.slingLightBlue)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(message.senderName.prefix(1)).uppercased())
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(Color.slingBlue)
                        )
                }
            }
            .frame(width: 44, alignment: .leading)
            
            // Center content area
            VStack(alignment: .leading, spacing: 4) {
                if isBot {
                    // Bot message content
                    VStack(alignment: .leading, spacing: 4) {
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
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(AnyShapeStyle(Color.slingGradient))
                                .cornerRadius(18)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 0)
                    } else {
                        // Other users: align to left
                        VStack(alignment: .leading, spacing: 4) {
                            // Sender name
                            Text(message.senderName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.gray)
                            
                            // Message bubble with timestamp on the right when global state is active
                            Text(message.text)
                                .font(.subheadline)
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(18)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
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
                    firestoreService: firestoreService
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

    
    // Global timestamp state - activated by swiping anywhere on the page
    @State private var isShowingTimestamps = false
    
    // Helper function to generate chat list data from user's actual communities
    private func getChatList() -> [ChatListItem] {
        let chatItems = firestoreService.userCommunities.map { community in
            let unreadCount = unreadCounts[community.id ?? ""] ?? 0
            return ChatListItem(
                id: community.id ?? UUID().uuidString,
                communityId: community.id ?? "",
                communityName: community.name,
                lastMessage: getLastMessage(community),
                timestamp: getLastMessageTimestamp(community),
                unreadCount: unreadCount,
                imageUrl: getDefaultImageUrl(for: community.name)
            )
        }
        
        // Sort chat list: unread messages first, then by most recent activity
        return chatItems.sorted { item1, item2 in
            // First priority: communities with unread messages come first
            if item1.unreadCount > 0 && item2.unreadCount == 0 {
                return true
            } else if item1.unreadCount == 0 && item2.unreadCount > 0 {
                return false
            }
            
            // Second priority: if both have unread messages, sort by unread count (highest first)
            if item1.unreadCount > 0 && item2.unreadCount > 0 {
                if item1.unreadCount != item2.unreadCount {
                    return item1.unreadCount > item2.unreadCount
                }
            }
            
            // Third priority: sort by most recent activity (most recent first)
            // Convert relative timestamps to actual dates for proper sorting
            let date1 = parseRelativeTimestamp(item1.timestamp)
            let date2 = parseRelativeTimestamp(item2.timestamp)
            return date1 > date2
        }
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
            return "No messages yet"
        }
        
        // Return the actual last message text, truncated if too long
        let maxLength = 50
        if lastMessage.text.count > maxLength {
            return String(lastMessage.text.prefix(maxLength)) + "..."
        }
        return lastMessage.text
    }
    
    private func getLastMessageTimestamp(_ community: FirestoreCommunity) -> String {
        guard let communityId = community.id,
              let lastMessage = firestoreService.communityLastMessages[communityId] else {
            return formatTimestamp(community.created_date)
        }
        
        return formatTimestamp(lastMessage.timestamp)
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
    
    // Helper function to parse relative timestamps for sorting
    private func parseRelativeTimestamp(_ timestamp: String) -> Date {
        let now = Date()
        let calendar = Calendar.current
        
        if timestamp == "Today" {
            return now
        } else if timestamp == "Yesterday" {
            return calendar.date(byAdding: .day, value: -1, to: now) ?? now
        } else if timestamp.contains("ago") {
            // Parse relative time like "2h ago", "5m ago", etc.
            let components = timestamp.components(separatedBy: " ")
            if components.count >= 2, let value = Int(components[0]) {
                let unit = components[1].lowercased()
                switch unit {
                case "s", "sec", "secs", "second", "seconds":
                    return calendar.date(byAdding: .second, value: -value, to: now) ?? now
                case "m", "min", "mins", "minute", "minutes":
                    return calendar.date(byAdding: .minute, value: -value, to: now) ?? now
                case "h", "hr", "hrs", "hour", "hours":
                    return calendar.date(byAdding: .hour, value: -value, to: now) ?? now
                case "d", "day", "days":
                    return calendar.date(byAdding: .day, value: -value, to: now) ?? now
                case "w", "wk", "week", "weeks":
                    return calendar.date(byAdding: .weekOfYear, value: -value, to: now) ?? now
                case "mo", "month", "months":
                    return calendar.date(byAdding: .month, value: -value, to: now) ?? now
                case "y", "yr", "year", "years":
                    return calendar.date(byAdding: .year, value: -value, to: now) ?? now
                default:
                    break
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
                return calendar.date(from: components) ?? now
            }
        }
        
        // Fallback to a very old date if parsing fails
        return calendar.date(byAdding: .year, value: -100, to: now) ?? now
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

        firestoreService.fetchMessages(for: communityId)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Chat")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.black)
            
            Text("Message your community members")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 20)
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
            firestoreService.fetchUserCommunities()
            // Refresh unread counts and last messages
            firestoreService.fetchLastMessagesForUserCommunities()
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
                    Text(chatItem.timestamp)
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
            firestoreService.fetchUserCommunities()
            // Initialize unread counts immediately
            initializeUnreadCounts()
        }

        .onChange(of: firestoreService.messages) { _, newMessages in
    
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardActive = false
        }
        .sheet(isPresented: $showingCommunityInfo) {
            if let community = selectedCommunity {
                CommunityInfoModal(community: community, firestoreService: firestoreService)
            }
        }
        .sheet(isPresented: $showingBetDetail) {
            if let bet = selectedBet {
                JoinBetView(bet: bet, firestoreService: firestoreService)
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
                                    isShowingTimestamps: isShowingTimestamps
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
                        Circle()
                            .fill(AnyShapeStyle(Color.slingGradient))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text(String(community.name.prefix(1)).uppercased())
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                        
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
                    Text("Members").tag(1)
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
                                        firestoreService: firestoreService
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
                    
                    // Extract first name from creator email
                    self.creatorFirstName = extractFirstName(from: fetchedBet.creator_email)
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



// MARK: - Active Bet Card

struct ActiveBetCard: View {
    // MARK: - Properties
    let bet: FirestoreBet
    let currentUserEmail: String?
    @ObservedObject private var firestoreService: FirestoreService
    
    // MARK: - State
    @State private var showingCancelAlert = false
    @State private var showingPlaceBetSheet = false
    @State private var userBets: [BetParticipant] = []
    @State private var hasUserParticipated: Bool = false
    @State private var hasAnyBets: Bool = false
    @State private var optionCounts: [String: Int] = [:]
    @State private var showingChooseWinnerSheet = false
    @State private var hasRemindedCreator = false
    
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
        // Since BetParticipant doesn't store odds, we'll get it from the bet's odds
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
    
    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Community and Title
            HStack {
                Text(communityName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formattedClosingDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(bet.title)
                .font(.headline)
                .lineLimit(2)
            
            // User's bet info if participated
            if hasUserParticipated {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Pick: \(userPick)")
                        .font(.subheadline)
                    Text("Odds: \(userOdds)")
                        .font(.subheadline)
                    Text("Wager: $\(String(format: "%.2f", userWager))")
                        .font(.subheadline)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Action buttons
            HStack {
                if !hasUserParticipated {
                    Button(action: { showingPlaceBetSheet = true }) {
                        Text("Place Bet")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(AnyShapeStyle(Color.slingGradient))
                            .cornerRadius(8)
                    }
                }
                
                if isCreator && hasAnyBets {
                    Button(action: { showingChooseWinnerSheet = true }) {
                        Text("Choose Winner")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                }
                
                if !hasRemindedCreator && !isCreator && hasUserParticipated {
                    Button(action: remindCreator) {
                        Text("Remind Creator")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .onAppear {
            loadUserParticipation()
            loadBetStatus()
        }
        .sheet(isPresented: $showingPlaceBetSheet) {
            PlaceBetView(bet: bet, presetOption: nil, firestoreService: firestoreService)
        }
        .sheet(isPresented: $showingChooseWinnerSheet) {
            ChooseWinnerView(bet: bet, firestoreService: firestoreService)
        }
        .alert(isPresented: $showingCancelAlert) {
            Alert(
                title: Text("Cancel Bet"),
                message: Text("Are you sure you want to cancel this bet?"),
                primaryButton: .destructive(Text("Cancel Bet")) {
                    // TODO: Implement bet cancellation
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    // MARK: - Helper Methods
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
        guard let betId = bet.id else { return }
        
        firestoreService.fetchBetStatus(betId: betId) { status in
            DispatchQueue.main.async {
                // For now, we'll set hasAnyBets based on whether there are user bets
                self.hasAnyBets = !self.userBets.isEmpty
                // optionCounts will need to be populated separately if needed
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
                        dismiss()
                    }
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
                    dismiss()
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
    @State private var searchText = ""
    @State private var showingJoinCommunityModal = false
    @State private var showingCreateCommunityModal = false
    
    // Computed property to filter communities based on search text
    private var filteredCommunities: [FirestoreCommunity] {
        if searchText.isEmpty {
            return firestoreService.userCommunities
        } else {
            return firestoreService.userCommunities.filter { community in
                community.name.localizedCaseInsensitiveContains(searchText) ||
                community.invite_code.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Communities")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text("Manage your betting groups and join new ones")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Search Bar (styled like Chat page)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    ZStack(alignment: .leading) {
                        if searchText.isEmpty {
                            Text("Search communities and invite codes")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        
                        TextField("", text: $searchText)
                            .font(.subheadline)
                            .foregroundColor(.black)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    
                    // Clear button when search text is not empty
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.subheadline)
                        }
                    } else {
                        Spacer()
                    }
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
                
                // Action Buttons
                HStack(spacing: 12) {
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
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.slingGradient)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 16)
                
                // Community Cards
                if filteredCommunities.isEmpty {
                    if searchText.isEmpty {
                        EmptyCommunitiesView(firestoreService: firestoreService)
                    } else {
                        // Show "no results" view when search has no matches
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(Color.slingBlue.opacity(0.6))
                            
                            Text("No communities found")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                            
                            Text("Try adjusting your search terms or join a new community.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 16)
                    }
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredCommunities) { community in
                            CommunityCardWithAdmin(
                                community: community,
                                firestoreService: firestoreService,
                                onViewCommunity: onNavigateToHome
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 100) // Space for bottom tab bar
        }
        .refreshable {
            // Refresh data when user pulls down
            await refreshData()
        }
        .background(Color.white)
        .onAppear {
            firestoreService.fetchUserCommunities()
            // Update statistics for all communities when view appears
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            firestoreService.fetchUserCommunities()
            // Update statistics when app comes to foreground
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
        .sheet(isPresented: $showingJoinCommunityModal) {
            JoinCommunityPage(firestoreService: firestoreService)
        }
        .sheet(isPresented: $showingCreateCommunityModal) {
            CreateCommunityPage(firestoreService: firestoreService)
        }
    }
    
    private func refreshData() async {
        // Fetch fresh data from Firestore
        firestoreService.fetchUserCommunities()
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

// MARK: - Community Card

struct CommunityCard: View {
    let community: FirestoreCommunity
    let isAdmin: Bool
    let firestoreService: FirestoreService
    let onViewCommunity: ((String) -> Void)?
    @State private var showingSettingsModal = false
    @State private var showingShareSheet = false
    @State private var showingCopyFeedback = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with Admin Badge
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
            
            // Invite Code Section with Gray Background
            VStack(alignment: .leading, spacing: 8) {
                Text("Invite Code")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                HStack(alignment: .center) {
                    Text(community.invite_code)
                        .font(.subheadline)
                        .fontWeight(.semibold)
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
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.green)
                            } else {
                                // Show copy icon
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            // Footer
            HStack {
                Text("Created \(formatDate(community.created_date))")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Button(action: {
                        showingSettingsModal = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Button(action: {
                        // Navigate to home feed with this community's filter
                        navigateToHomeWithFilter()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                            Text("View")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.slingGradient)
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .sheet(isPresented: $showingSettingsModal) {
            CommunitySettingsView(community: community, isAdmin: isAdmin, firestoreService: firestoreService)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: ["Join my community on Sling! Use invite code: \(community.invite_code)"])
        }
    }
    
    private func navigateToHomeWithFilter() {
        onViewCommunity?(community.name)
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
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text("Create a new bet or community")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
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
            CreateBetView(firestoreService: firestoreService)
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
                                        Image(systemName: "doc.on.doc")
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
            }
            .padding(.bottom, 20)
        }
        .background(Color.white)
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: ["Join my community on Sling! Use invite code: \(community.invite_code)"])
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
                            
                            if isAdmin && !member.isAdmin {
                                Button(action: {
                                    // Kick member action
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
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Edit Profile")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Profile Information Card
                VStack(spacing: 24) {
                    // Profile Summary
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color.slingGradient)
                            .frame(width: 64, height: 64)
                            .overlay(
                                Text(getUserInitials())
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            )
                        
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
                                Text("+0.00")
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
                                            Text("+0.00")
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

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    let firestoreService: FirestoreService
    
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
                                .font(.title3)
                                .foregroundColor(.gray)
                                .frame(width: 32, height: 32)
                                .background(Color(.systemGray6))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        // Unread count badge
                        if firestoreService.notifications.filter({ !$0.is_read }).count > 0 {
                            Text("\(firestoreService.notifications.filter { !$0.is_read }.count)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                    }
                    
                    // Title and Description
                    VStack(spacing: 8) {
                        Text("Notifications")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("Stay updated with your latest activities")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Action Buttons Row
                    HStack(spacing: 12) {
                        // Mark all as read button
                        Button(action: {
                            firestoreService.markAllNotificationsAsRead { success in
                                if success {
                                    print("✅ All notifications marked as read")
                                } else {
                                    print("❌ Failed to mark all notifications as read")
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                Text("Mark All Read")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(20)
                        }
                        .disabled(firestoreService.notifications.filter { !$0.is_read }.count == 0)
                        .opacity(firestoreService.notifications.filter { !$0.is_read }.count == 0 ? 0.5 : 1.0)
                        
                        // Filter buttons
                        HStack(spacing: 8) {
                            FilterButton(title: "All", isSelected: true)
                            FilterButton(title: "Unread", isSelected: false)
                        }
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .background(Color.white)
                
                // Enhanced Notifications List
                if firestoreService.notifications.isEmpty {
                    // Empty State
                    VStack(spacing: 20) {
                        Spacer()
                        
                        Image(systemName: "bell.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.5))
                        
                        VStack(spacing: 8) {
                            Text("No notifications yet")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("When you receive notifications, they'll appear here")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 40)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(firestoreService.notifications) { notification in
                                EnhancedNotificationRow(
                                    notification: convertToNotificationItem(notification),
                                    firestoreService: firestoreService
                                )
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .onAppear {
                firestoreService.fetchNotifications()
            }
        }
    }
}

// MARK: - Filter Button Component

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    
    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue : Color(.systemGray5))
            )
    }
}

// MARK: - Enhanced Notification Row

struct EnhancedNotificationRow: View {
    let notification: NotificationItem
    let firestoreService: FirestoreService
    
    var body: some View {
        Button(action: {
            if notification.isUnread, let notificationId = notification.id {
                firestoreService.markNotificationAsRead(notificationId: notificationId) { success in
                    if success {
                        print("✅ Notification marked as read")
                    } else {
                        print("❌ Failed to mark notification as read")
                    }
                }
            }
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
                        
                        if notification.isUnread {
                            Text("• New")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Spacer()
                
                // Unread indicator
                if notification.isUnread {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        notification.isUnread ? Color.blue.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
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
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var firestoreService: FirestoreService
    @State private var displayName: String
    @State private var firstName: String
    @State private var lastName: String
    
    init(firestoreService: FirestoreService) {
        self.firestoreService = firestoreService
        self._displayName = State(initialValue: firestoreService.currentUser?.display_name ?? "")
        self._firstName = State(initialValue: firestoreService.currentUser?.first_name ?? "")
        self._lastName = State(initialValue: firestoreService.currentUser?.last_name ?? "")
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
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    // Back Button
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.title3)
                                .foregroundColor(.black)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemGray5))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                    }
                    
                    // Title
                    VStack(spacing: 8) {
                        Text("Edit Profile")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        
                        Text("Update your profile information.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Profile Information Card
                VStack(spacing: 24) {
                    // Profile Summary
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text(getUserInitials())
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName.isEmpty ? (firestoreService.currentUser?.displayName ?? "User") : displayName)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                            
                            Text(firestoreService.currentUser?.email ?? "user@example.com")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Form Fields
                    VStack(spacing: 20) {
                        // Display Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Display Name *")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                            
                            TextField("Display Name", text: $displayName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.subheadline)
                        }
                        
                        // First Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("First Name")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                            
                            TextField("First Name", text: $firstName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.subheadline)
                        }
                        
                        // Last Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Last Name")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                            
                            TextField("Last Name", text: $lastName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.subheadline)
                        }
                    }
                    .padding(.horizontal, 20)
                    
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
                        
                        Button(action: {
                            // Validate input
                            guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                // You could show an alert here for validation error
                                return
                            }
                            
                            // Save changes action - for now just dismiss
                            dismiss()
                        }) {
                            Text("Save Changes")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.slingGradient)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    
                    // Sign Out Button
                    Button(action: {
                        firestoreService.signOut()
                        dismiss()
                    }) {
                            Text("Sign Out")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.red)
                        .cornerRadius(10)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                
                Spacer()
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Create Bet View

struct CreateBetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var firestoreService: FirestoreService
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
                        
                        Text("Be specific and engaging")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
                
                TextField("e.g., Who will win the championship?", text: $marketQuestion)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.subheadline)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                
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
                        
                        Text(marketQuestion)
                            .font(.subheadline)
                            .foregroundColor(.black)
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
            return
        }
        
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
        
        let betData: [String: Any] = [
            "title": marketQuestion,
            "community_id": community.id ?? "",
            "options": outcomes,
            "odds": oddsDict,
            "deadline": bettingCloseDate,
            "bet_type": betType,
            "spread_line": spreadLine.isEmpty ? nil : (Double(spreadLine) as Any),
            "over_under_line": overUnderLine.isEmpty ? nil : (Double(overUnderLine) as Any),
            "status": "open",
            "created_by": firestoreService.currentUser?.display_name ?? firestoreService.currentUser?.full_name ?? "Unknown",
            "creator_email": firestoreService.currentUser?.email ?? "",
            "created_by_id": firestoreService.currentUser?.id ?? "",
            "image_url": "" as Any, // Will be populated later with Unsplash image
            "pool_by_option": Dictionary(uniqueKeysWithValues: outcomes.map { ($0, 0) }), // Initialize pool with 0 for each option
            "total_pool": 0, // Initialize total pool to 0
            "total_participants": 0, // Initialize total participants to 0
            "created_date": Date(),
            "updated_date": Date()
        ]
        
        firestoreService.createBet(betData: betData) { success, error in
            DispatchQueue.main.async {
                if success {
                    dismiss()
                } else {
                    print("Error creating bet: \(error ?? "Unknown error")")
                }
            }
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
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
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
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                    }
                    
                    Spacer()
                    
                    Text("Join Community")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    // Invisible spacer to center title
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                
                // Main content
                VStack(spacing: 32) {
                    // Icon and title
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Join an Existing Community")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                        
                        Text("Enter the 6-character invite code to join a betting group")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                    
                    // Input field
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Invite Code")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        HStack {
                            TextField("Enter 6-digit code", text: $inviteCode)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                                .textCase(.uppercase)
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)
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
                            
                            // Character counter
                            Text("\(inviteCode.count)/6")
                                .font(.caption)
                                .foregroundColor(inviteCode.count == 6 ? .green : .gray)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(borderColor, lineWidth: 2)
                        )
                        .focused($isTextFieldFocused)
                        .onAppear {
                            isTextFieldFocused = true
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Error message
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                    
                    // Join button
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
                                .fill(isValidInviteCode && !isLoading ? Color.blue : Color.gray.opacity(0.3))
                        )
                    }
                    .disabled(!isValidInviteCode || isLoading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Actions
    
    private func joinCommunity() {
        let trimmedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        isLoading = true
        errorMessage = ""
        
        firestoreService.joinCommunity(inviteCode: trimmedCode) { success, error in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    dismiss()
                    onSuccess?()
                } else {
                    errorMessage = error ?? "Invalid community code. Please try again."
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
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        isTextFieldFocused = false
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                    }
                    
                    Spacer()
                    
                    Text("Create Community")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    // Invisible spacer to center title
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                
                // Main content
                VStack(spacing: 32) {
                    // Icon and title
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Create a New Community")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                        
                        Text("Start a betting group for friends, family, or colleagues")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                    
                    // Input field
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Community Name")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        TextField("Enter community name", text: $communityName)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isTextFieldFocused ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .focused($isTextFieldFocused)
                            .onAppear {
                                isTextFieldFocused = true
                            }
                            .onChange(of: communityName) { _, newValue in
                                errorMessage = ""
                            }
                    }
                    .padding(.horizontal, 20)
                    
                    // Error message
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                    
                    // Create button
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
                                .fill(isValidCommunityName && !isLoading ? Color.blue : Color.gray.opacity(0.3))
                        )
                    }
                    .disabled(!isValidCommunityName || isLoading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
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
        
        let communityData: [String: Any] = [
            "name": trimmedName,
            "description": "A new betting community",
            "created_by": firestoreService.currentUser?.email ?? "",
            "created_date": Date(),
            "invite_code": UUID().uuidString.prefix(8).uppercased(),
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
    @State private var selectedOption = ""
    @State private var showingBettingInterface = false
    @State private var showingShareSheet = false
    @State private var isRulesExpanded = false
    @State private var betParticipants: [BetParticipant] = []
    @State private var otherBets: [FirestoreBet] = []
    @State private var showingBetDetail = false
    @State private var selectedBetForDetail: FirestoreBet? = nil
    
    private var communityName: String {
        if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
            return community.name
        }
        return "Community"
    }
    
    private var creatorName: String {
        let creatorEmail = bet.creator_email
        if let currentUserEmail = firestoreService.currentUser?.email, creatorEmail == currentUserEmail {
            return "You"
        } else {
            return String(creatorEmail.split(separator: "@").first ?? "Unknown")
        }
    }
    
    private var formattedDeadline: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d'st', yyyy"
        return formatter.string(from: bet.deadline)
    }
    
    private var shortRulesText: String {
        "Every bet on Blitz requires two sides to be matched before it's active. Once both users have staked an equal number of Blitz Points, the bet becomes locked and cannot be edited or canceled."
    }
    
    private var fullRulesText: String {
        "Every bet on Blitz requires two sides to be matched before it's active. Once both users have staked an equal number of Blitz Points, the bet becomes locked and cannot be edited or canceled. If only one person has joined, the bet remains unmatched and inactive. After the event concludes, the outcome must be settled by the users, and Blitz Points are awarded to the winner accordingly. All bets are tracked within the community they were created in, and participants are responsible for resolving results honestly."
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
                                        .foregroundColor(.gray)
                                    Text("\(communityName) • Created by \(creatorName)")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                
                                Text("Deadline: \(formattedDeadline)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal, 16)
                        
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
                                    .buttonStyle(PlainButtonStyle())
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
                                                    Text(extractUsername(from: participant.user_email))
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(.black)
                                                    
                                                    Text("\(participant.chosen_option) • \(String(format: "%.2f", Double(participant.stake_amount))) Blitz")
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
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
                            Text("How Betting on Blitz Works:")
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
                                    VStack(spacing: 8) {
                                        Image(systemName: "tray")
                                            .font(.title2)
                                            .foregroundColor(.gray.opacity(0.6))
                                        
                                        Text("No other bets available")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                            .fontWeight(.medium)
                                        
                                        Text("Check back later for new bets")
                                            .font(.caption)
                                            .foregroundColor(.gray.opacity(0.8))
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
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                }
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "tray")
                                        .font(.title2)
                                        .foregroundColor(.gray.opacity(0.6))
                                    
                                    Text("No other bets available")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .fontWeight(.medium)
                                    
                                    Text("Check back later for new bets")
                                        .font(.caption)
                                        .foregroundColor(.gray.opacity(0.8))
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
                    JoinBetView(bet: selectedBet, firestoreService: firestoreService)
                }
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
            return extractUsername(from: creatorEmail)
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
            isUnread: !firestoreNotification.is_read
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
    
    // Pre-set bet amounts
    private let presetAmounts = [10, 25, 50, 100]
    
    // Computed properties for validation
    private var currentBalance: Int {
        firestoreService.currentUser?.sling_points ?? 0
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
        self._selectedOption = State(initialValue: selectedOption)
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
                        Text("Insufficient Blitz Points. You have \(String(format: "%.2f", Double(currentBalance))) points.")
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
                    
                    Text("• by \(extractUsername(from: bet.creator_email))")
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
                .buttonStyle(PlainButtonStyle())
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
    @State private var userBets: [BetParticipant] = []
    @State private var hasUserParticipated: Bool = false
    @State private var hasAnyBets: Bool = false
    @State private var hasRemindedCreator = false
    @State private var optionCounts: [String: Int] = [:]
    @State private var creatorName: String = ""
    
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
            } else if let email = user?.email {
                return String(email.prefix(1)).uppercased()
            }
            return "U"
        } else {
            // For other creators, use their name initials or email
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
                                
                                Text("\(communityName) • by \(isCreator ? "You" : (creatorName.isEmpty ? extractUsername(from: bet.creator_email) : creatorName))")
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
            JoinBetView(bet: bet, firestoreService: firestoreService)
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
    
    private func generateShareText() -> String {
        let creatorName = isCreator ? "I" : extractUsername(from: bet.creator_email)
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
                    Text("\(communityName) • by \(isCreator ? "You" : extractUsername(from: bet.creator_email))")
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
}


