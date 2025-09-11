import SwiftUI
import FirebaseAnalytics

// MARK: - Color Extension for Hex Colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct MainAppView: View {
    @ObservedObject var firestoreService: FirestoreService
    @State private var selectedTab = 0 // 0 = Home, 1 = Chat, 2 = My Bets, 3 = Communities
    @State private var shouldNavigateToCommunities = false
    @State private var showingCreateBetModal = false
    @State private var showingJoinCommunityModal = false
    @State private var showingCreateCommunityModal = false
    @State private var showingEditProfile = false
    @State private var selectedCommunityFilter: String? = nil
    @State private var isKeyboardActive = false
    
    // Deep link handling
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @State private var deepLinkBet: FirestoreBet?
    @State private var deepLinkCommunity: FirestoreCommunity?
    @State private var showingDeepLinkBet = false
    @State private var showingDeepLinkCommunity = false
    @StateObject private var timeTracker = TimeTracker()
    @State private var previousTab = 0
    @State private var hideTabText = false
    
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
                // Main Content Area
                VStack {
                    switch selectedTab {
                    case 0:
                        // Home Feed - Display Bets
                        HomeView(firestoreService: firestoreService, showingEditProfile: $showingEditProfile, initialFilter: selectedCommunityFilter, showingJoinCommunityModal: $showingJoinCommunityModal, showingCreateCommunityModal: $showingCreateCommunityModal)
                    case 1:
                        // Chat View
                        MessagesView(firestoreService: firestoreService)
                    case 2:
                        // My Bets View
                        MyBetsView(firestoreService: firestoreService, selectedTab: $selectedTab)
                    case 3:
                        // Communities View
                        CommunitiesView(firestoreService: firestoreService, onNavigateToHome: { communityName in
                            navigateToHomeWithFilter(communityName)
                        })
                    default:
                        EmptyView()
                    }
                }
                
                // Custom Tab Bar with integrated plus button - hide when keyboard is active
                if !isKeyboardActive {
                    HStack(spacing: 0) {
                        // Home Tab
                    Button(action: { 
                        AnalyticsService.shared.trackTabSwitch(fromTab: getTabName(previousTab), toTab: "home")
                        AnalyticsService.shared.trackUserFlowStep(step: .homeTab)
                        previousTab = selectedTab
                        selectedTab = 0
                        // Reset community filter when home tab is clicked
                        selectedCommunityFilter = nil
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                                .font(.title2)
                                .frame(height: 24)
                            
                            Text("Home")
                                .font(.caption)
                                .fontWeight(.medium)
                                .frame(height: 16)
                        }
                        .foregroundColor(selectedTab == 0 ? Color.slingBlue : .gray)
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Chat Tab
                    Button(action: { 
                        AnalyticsService.shared.trackTabSwitch(fromTab: getTabName(previousTab), toTab: "chat")
                        AnalyticsService.shared.trackUserFlowStep(step: .chatTab)
                        previousTab = selectedTab
                        selectedTab = 1
                        // Refresh chat data when switching to chat tab (no loading state needed)
                        firestoreService.fetchUserCommunities()
                        firestoreService.fetchLastMessagesForUserCommunities()
                    }) {
                        VStack(spacing: 4) {
                            ZStack {
                                Image(systemName: selectedTab == 1 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                    .font(.title2)
                                    .frame(height: 24)
                                
                                // Unread message indicator - refined styling
                                if firestoreService.totalUnreadCount > 0 {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.red.opacity(0.8), Color.red],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: 10, height: 10)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 1.5)
                                        )
                                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                        .offset(x: 10, y: -10)
                                }
                            }
                            
                            Text("Chat")
                                .font(.caption)
                                .fontWeight(.medium)
                                .frame(height: 16)
                        }
                        .foregroundColor(selectedTab == 1 ? Color.slingBlue : .gray)
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Create Bet Button (Plus Sign)
                    Button(action: {
                        AnalyticsService.shared.trackFeatureUsage(feature: "create_bet_button", context: "tab_bar")
                        AnalyticsService.shared.trackUserFlowStep(step: .createBet)
                        showingCreateBetModal = true
                    }) {
                        ZStack {
                            Circle()
                                .fill(AnyShapeStyle(Color.slingGradient))
                                .frame(width: 56, height: 56)
                                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                            
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 56, height: 56)
                    
                    // My Bets Tab
                    Button(action: { 
                        AnalyticsService.shared.trackTabSwitch(fromTab: getTabName(previousTab), toTab: "my_bets")
                        AnalyticsService.shared.trackUserFlowStep(step: .myBetsTab)
                        previousTab = selectedTab
                        selectedTab = 2 
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: selectedTab == 2 ? "list.bullet.clipboard.fill" : "list.bullet.clipboard")
                                .font(.title2)
                                .frame(height: 24)
                            
                            Text("My Bets")
                                .font(.caption)
                                .fontWeight(.medium)
                                .frame(height: 16)
                        }
                        .foregroundColor(selectedTab == 2 ? Color.slingBlue : .gray)
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Communities Tab
                    Button(action: { 
                        AnalyticsService.shared.trackTabSwitch(fromTab: getTabName(previousTab), toTab: "communities")
                        AnalyticsService.shared.trackUserFlowStep(step: .communitiesTab)
                        previousTab = selectedTab
                        selectedTab = 3
                        // Update community statistics when Communities tab is selected
                        for community in firestoreService.userCommunities {
                            if let communityId = community.id {
                                firestoreService.updateCommunityStatistics(communityId: communityId) { success, error in
                                    if let error = error {
                                        print("❌ Error updating statistics for community \(communityId): \(error)")
                                    }
                                }
                            }
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: selectedTab == 3 ? "person.2.fill" : "person.2")
                                .font(.title2)
                                .frame(height: 24)
                            
                            // Show text only if screen is wide enough
                            if !hideTabText {
                                Text("Communities")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .frame(height: 16)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                        }
                        .foregroundColor(selectedTab == 3 ? Color.slingBlue : .gray)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.slingBlue.opacity(0.2)),
                    alignment: .top
                )
                                    .ignoresSafeArea(.container, edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                

            }
            .animation(.easeInOut(duration: 0.3), value: isKeyboardActive)
            .navigationBarHidden(true) // Hide navigation bar for custom header
            .navigationBarBackButtonHidden(true)
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView(firestoreService: firestoreService)
            }
            .sheet(isPresented: $showingCreateBetModal) {
                CreateBetView(firestoreService: firestoreService, preSelectedCommunity: nil)
            }
            .sheet(isPresented: $showingJoinCommunityModal) {
                JoinCommunityPage(firestoreService: firestoreService, onSuccess: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        selectedTab = 2 // Navigate to Communities tab
                    }
                })
            }
            .sheet(isPresented: $showingCreateCommunityModal) {
                CreateCommunityPage(firestoreService: firestoreService, onSuccess: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        selectedTab = 2 // Navigate to Communities tab
                    }
                })
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            // Track main app view appearance
            AnalyticsService.shared.trackUserFlowStep(step: .mainApp)
            timeTracker.startTracking(for: "main_app")
            
            // Check screen size and hide tab text if needed
            let screenWidth = UIScreen.main.bounds.width
            if screenWidth < 375 { // iPhone SE and smaller
                hideTabText = true
            }
        }
        .onDisappear {
            // Track time spent in main app
            if let duration = timeTracker.endTracking(for: "main_app") {
                AnalyticsService.shared.trackPageViewTime(page: "main_app", timeSpent: duration)
            }
        }
        .onReceive(deepLinkManager.$pendingDeepLink) { deepLink in
            if let deepLink = deepLink {
                handleDeepLink(deepLink)
            }
        }
        .sheet(isPresented: $showingDeepLinkBet) {
            if let bet = deepLinkBet {
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
        .sheet(isPresented: $showingDeepLinkCommunity) {
            if let community = deepLinkCommunity {
                CommunityInfoModal(community: community, firestoreService: firestoreService)
            }
        }
    }
    
    private func handleDeepLink(_ deepLink: DeepLink) {
        print("🔗 Handling deep link: \(deepLink.type) - \(deepLink.id)")
        
        switch deepLink.type {
        case "bet":
            // Fetch bet details and show bet view
            firestoreService.fetchBet(by: deepLink.id) { bet in
                DispatchQueue.main.async {
                    if let bet = bet {
                        self.deepLinkBet = bet
                        self.showingDeepLinkBet = true
                        print("✅ Deep link bet loaded: \(bet.title)")
                    } else {
                        print("❌ Failed to load deep link bet: \(deepLink.id)")
                    }
                    // Clear the pending deep link
                    self.deepLinkManager.clearPendingDeepLink()
                }
            }
            
        case "community":
            // Find community in user's communities
            if let community = firestoreService.userCommunities.first(where: { $0.id == deepLink.id }) {
                self.deepLinkCommunity = community
                self.showingDeepLinkCommunity = true
                print("✅ Deep link community found: \(community.name)")
            } else {
                print("❌ Deep link community not found or user not a member: \(deepLink.id)")
            }
            // Clear the pending deep link
            self.deepLinkManager.clearPendingDeepLink()
            
        default:
            print("❌ Unknown deep link type: \(deepLink.type)")
            self.deepLinkManager.clearPendingDeepLink()
        }
    }
    
    private func refreshHomeData() async {
        // Fetch fresh data from Firestore
        firestoreService.fetchUserCommunities()
        // fetchBets() is now called automatically after communities are loaded
    }
    
    private func navigateToHomeWithFilter(_ communityName: String) {
        selectedCommunityFilter = communityName
        selectedTab = 0 // Navigate to Home tab
    }
    
    private func getTabName(_ tabIndex: Int) -> String {
        switch tabIndex {
        case 0: return "home"
        case 1: return "chat"
        case 2: return "my_bets"
        case 3: return "communities"
        default: return "unknown"
        }
    }
}

// MARK: - Home View

// MARK: - Simple Header Component
struct SimpleHeaderView: View {
    let title: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Sling Logo
            HStack(spacing: 8) {
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .cornerRadius(8)
                
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }
}

// MARK: - Home Header Component
struct HomeHeaderView: View {
    @ObservedObject var firestoreService: FirestoreService
    let onNotificationsTap: () -> Void
    let onProfileTap: () -> Void
    @Binding var showingPointsPopup: Bool
    
    private func getUserInitials() -> String {
        let user = firestoreService.currentUser
        
        // Prioritize first and last name to get both initials
        if let firstName = user?.first_name, let lastName = user?.last_name, !firstName.isEmpty, !lastName.isEmpty {
            let firstInitial = String(firstName.prefix(1)).uppercased()
            let lastInitial = String(lastName.prefix(1)).uppercased()
            return "\(firstInitial)\(lastInitial)"
        }
        
        // If we have first name but no last name, try to get second initial from display name
        if let firstName = user?.first_name, !firstName.isEmpty {
            let firstInitial = String(firstName.prefix(1)).uppercased()
            if let displayName = user?.display_name, !displayName.isEmpty {
                let components = displayName.components(separatedBy: " ")
                if components.count >= 2 {
                    let lastInitial = String(components[1].prefix(1)).uppercased()
                    return "\(firstInitial)\(lastInitial)"
                }
            }
            return firstInitial
        }
        
        // Fallback to display name parsing
        if let displayName = user?.display_name, !displayName.isEmpty {
            let components = displayName.components(separatedBy: " ")
            if components.count >= 2 {
                let firstInitial = String(components[0].prefix(1)).uppercased()
                let lastInitial = String(components[1].prefix(1)).uppercased()
                return "\(firstInitial)\(lastInitial)"
            } else if components.count == 1 {
                return String(components[0].prefix(1)).uppercased()
            }
        }
        
        // Final fallback to email
        if let email = user?.email {
            return String(email.prefix(1)).uppercased()
        }
        
        return "U"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Sling Logo
            HStack(spacing: 8) {
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .cornerRadius(8)
                
                Text("Sling")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
            }
            
            Spacer()
            
            // Points Badge - Clickable
            Button(action: {
                AnalyticsService.shared.trackFeatureUsage(feature: "points_balance", context: "home_header")
                showingPointsPopup = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    Text("\(firestoreService.currentUser?.blitz_points ?? 0)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(12)
            }
            

            
            // Notification Bell
            Button(action: {
                AnalyticsService.shared.trackFeatureUsage(feature: "notifications", context: "home_header")
                AnalyticsService.shared.trackUserFlowStep(step: .notifications)
                onNotificationsTap()
            }) {
                ZStack {
                    Image(systemName: "bell")
                        .font(.title2)
                        .foregroundColor(.gray)
                    
                    // Red notification dot - only show when there are unread notifications
                    if firestoreService.notifications.filter({ !$0.is_read }).count > 0 {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.8), Color.red],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 1.5)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .offset(x: 10, y: -10)
                    }
                }
            }
            
            // Profile Avatar
            Button(action: {
                AnalyticsService.shared.trackFeatureUsage(feature: "profile", context: "home_header")
                AnalyticsService.shared.trackUserFlowStep(step: .profile)
                onProfileTap()
            }) {
                if let profilePictureURL = firestoreService.currentUser?.profile_picture_url, !profilePictureURL.isEmpty {
                    AsyncImage(url: URL(string: profilePictureURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        case .failure(_):
                            // Fallback to initials on error
                            Circle()
                                .fill(AnyShapeStyle(Color.slingGradient))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(getUserInitials())
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )
                        case .empty:
                            // Show initials while loading
                            Circle()
                                .fill(AnyShapeStyle(Color.slingGradient))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(getUserInitials())
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )
                        @unknown default:
                            Circle()
                                .fill(AnyShapeStyle(Color.slingGradient))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(getUserInitials())
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )
                        }
                    }
                } else {
                    Circle()
                        .fill(AnyShapeStyle(Color.slingGradient))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(getUserInitials())
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }
}

// MARK: - Filter Bar Component
struct FilterBarView: View {
    let categories: [String]
    @Binding var selectedFilter: String
    
    private func backgroundForCategory(_ category: String) -> AnyShapeStyle {
        if selectedFilter == category {
            return AnyShapeStyle(Color.slingGradient)
        } else {
            return AnyShapeStyle(Color.white)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(categories, id: \.self) { category in
                        Button(action: {
                            AnalyticsService.shared.trackFilterUsage(filterType: "community", filterValue: category, page: "home")
                            selectedFilter = category
                        }) {
                            Text(category)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(selectedFilter == category ? .white : .black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(backgroundForCategory(category))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: selectedFilter == category ? 0 : 1)
                                )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 2) // Reduced from 4 to 2
        .padding(.bottom, 2) // Reduced from 4 to 2
        .background(Color.white)
        
        // Horizontal line under community pills
        Rectangle()
            .frame(height: 0.5)
            .foregroundColor(Color.gray.opacity(0.3))
    }
}

// MARK: - Main Home View
struct HomeView: View {
    @ObservedObject var firestoreService: FirestoreService
    @Binding var showingEditProfile: Bool
    let initialFilter: String?
    @Binding var showingJoinCommunityModal: Bool
    @Binding var showingCreateCommunityModal: Bool
    @State private var selectedFilter = "All Bets"
    @State private var showingNotifications = false
    @State private var showingUserProfile = false
    @State private var showingPointsPopup = false

    @State private var showingCreateBet = false
    @StateObject private var timeTracker = TimeTracker()

    
    // Dynamic filter categories based on user communities, sorted by bet count
    private var filterCategories: [String] {
        var categories = ["All Bets"]
        if !firestoreService.userCommunities.isEmpty {
            // Create array of (community, bet count) pairs
            let communitiesWithCounts = firestoreService.userCommunities.map { community in
                let betCount = firestoreService.bets.filter { bet in
                    return bet.community_id == community.id
                }.count
                
                return (community: community, betCount: betCount)
            }
            
            // Sort by bet count (descending) and then append to categories
            let sortedCommunities = communitiesWithCounts
                .sorted { $0.betCount > $1.betCount }
                .map { $0.community.name }
            
            categories.append(contentsOf: sortedCommunities)
        }
        
        return categories
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Custom Header
                            HomeHeaderView(
                    firestoreService: firestoreService,
                    onNotificationsTap: { showingNotifications = true },
                    onProfileTap: { showingUserProfile = true },
                    showingPointsPopup: $showingPointsPopup
                )
            

            
            // Main Content
            ScrollView {
                VStack(spacing: 8) { // Reduced from 16 to 8
                    // Filter Bar - only show if user has communities (now scrollable)
                    if !firestoreService.userCommunities.isEmpty {
                        FilterBarView(
                            categories: filterCategories,
                            selectedFilter: $selectedFilter
                        )
                        .padding(.horizontal, -16) // Counteract the horizontal padding
                    }
                    
                    // Show bet feed content
                    Group {
                        if firestoreService.userCommunities.isEmpty {
                            // Show action buttons for users with no communities
                            VStack(spacing: 20) {
                                Spacer()
                                
                                VStack(spacing: 16) {
                                    Image(systemName: "person.2")
                                        .font(.system(size: 48))
                                        .foregroundColor(.gray.opacity(0.6))
                                    
                                    Text("Welcome to Sling!")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    
                                    Text("Get started by joining or creating your first community!")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.horizontal, 24)
                                
                                VStack(spacing: 12) {
                                    Button(action: {
                                        AnalyticsService.shared.trackCommunityInteraction(action: .join, communityId: "new", communityName: "Join Community")
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
                                        AnalyticsService.shared.trackCommunityInteraction(action: .create, communityId: "new", communityName: "Create Community")
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
                                .padding(.horizontal, 32)
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // Feed of Bets from user's joined communities
                            let currentTime = Date()
                            let primaryBets = selectedFilter == "All Bets" 
                                ? firestoreService.bets.filter { bet in
                                    // Only show open bets that haven't expired
                                    let isOpen = bet.status.lowercased() == "open"
                                    let notExpired = bet.deadline > currentTime
                                    return isOpen && notExpired
                                }
                                : firestoreService.bets.filter { bet in
                                    // Only show open bets that haven't expired from the selected community
                                    let isOpen = bet.status.lowercased() == "open"
                                    let notExpired = bet.deadline > currentTime
                                    if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
                                        let nameMatches = community.name == selectedFilter
                                        return nameMatches && isOpen && notExpired
                                    }
                                    return false
                                }
                            
                            let otherCommunityBets = selectedFilter == "All Bets" 
                                ? []
                                : firestoreService.bets.filter { bet in
                                    // Only show open bets that haven't expired from other communities
                                    let isOpen = bet.status.lowercased() == "open"
                                    let notExpired = bet.deadline > currentTime
                                    if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
                                        let isDifferentCommunity = community.name != selectedFilter
                                        return isOpen && notExpired && isDifferentCommunity
                                    }
                                    return false
                                }
                            
                            // Show primary bets (selected community or all bets)
                            if primaryBets.isEmpty && selectedFilter != "All Bets" {
                                // No bets in selected community - using card format
                                VStack(alignment: .leading, spacing: 16) {
                                    // Header with icon and title
                                    HStack(alignment: .top, spacing: 12) {
                                        // Placeholder image area (same size as bet images)
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(AnyShapeStyle(Color.slingGradient))
                                            .frame(width: 60, height: 60)
                                            .overlay(
                                                Image(systemName: "list.bullet.clipboard")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(.white)
                                            )
                                        
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("No Active Bets")
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.black)
                                            
                                            Text("This community doesn't have any active bets yet.")
                                                .font(.subheadline)
                                                .foregroundColor(.gray)
                                        }
                                        
                                        Spacer()
                                    }
                                    
                                    // Create Bet Button
                                    Button(action: {
                                        AnalyticsService.shared.trackBetInteraction(action: .create, betId: "new", betTitle: "Create Bet", communityName: selectedFilter)
                                        showingCreateBet = true
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "plus")
                                                .font(.subheadline)
                                                .foregroundColor(.white)
                                            
                                            Text("Create a Bet")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.white)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .background(AnyShapeStyle(Color.slingGradient))
                                        .cornerRadius(10)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(16)
                                .background(Color.white)
                                .cornerRadius(16)
                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                            } else {
                                ForEach(primaryBets) { bet in
                                    HomeBetCard(
                                        bet: bet,
                                        currentUserEmail: firestoreService.currentUser?.email,
                                        firestoreService: firestoreService
                                    )
                                }
                            }
                            
                            // Show separator and other community bets if filtering by a specific community AND there are primary bets
                            if selectedFilter != "All Bets" && !primaryBets.isEmpty {
                                // Separator
                                VStack(spacing: 12) {
                                    HStack {
                                        Rectangle()
                                            .frame(height: 1)
                                            .foregroundColor(Color.gray.opacity(0.3))
                                        Text("Other Communities")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.gray)
                                            .fixedSize()
                                            .padding(.horizontal, 8)
                                        Rectangle()
                                            .frame(height: 1)
                                            .foregroundColor(Color.gray.opacity(0.3))
                                    }
                                    .padding(.vertical, 16)
                                    
                                    // Other community bets
                                    ForEach(otherCommunityBets) { bet in
                                        HomeBetCard(
                                            bet: bet,
                                            currentUserEmail: firestoreService.currentUser?.email,
                                            firestoreService: firestoreService
                                        )
                                    }
                                    
                                    // Show message if no other community bets exist
                                    if otherCommunityBets.isEmpty {
                                        VStack(alignment: .leading, spacing: 16) {
                                            // Header with icon and title
                                            HStack(alignment: .top, spacing: 12) {
                                                                                    // Placeholder image area (same size as bet images)
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(AnyShapeStyle(Color.slingGradient))
                                        .frame(width: 60, height: 60)
                                        .overlay(
                                            Image(systemName: "person.2")
                                                .font(.system(size: 24))
                                                .foregroundColor(.white)
                                        )
                                                
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("No Other Bets")
                                                        .font(.headline)
                                                        .fontWeight(.semibold)
                                                        .foregroundColor(.black)
                                                    
                                                    Text("No bets in other communities")
                                                        .font(.subheadline)
                                                        .foregroundColor(.gray)
                                                }
                                                
                                                Spacer()
                                            }
                                            
                                            // Create Bet Button
                                            Button(action: {
                                                AnalyticsService.shared.trackBetInteraction(action: .create, betId: "new", betTitle: "Create Bet", communityName: "other_communities")
                                                showingCreateBet = true
                                            }) {
                                                HStack(spacing: 8) {
                                                    Image(systemName: "plus")
                                                        .font(.subheadline)
                                                        .foregroundColor(.white)
                                                    
                                                    Text("Create a Bet")
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(.white)
                                                }
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 44)
                                                .background(AnyShapeStyle(Color.slingGradient))
                                                .cornerRadius(10)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        .padding(16)
                                        .background(Color.white)
                                        .cornerRadius(16)
                                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                                    }
                                }
                            }
                            
                            // Show empty state if no bets at all
                            if primaryBets.isEmpty && otherCommunityBets.isEmpty && selectedFilter == "All Bets" {
                                EmptyBetsView(firestoreService: firestoreService)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8) // Reduced from 16 to 8
            }
            .refreshable {
                // Reset filter to "All Bets" when refreshing
                selectedFilter = "All Bets"
                
                // Refresh data when user pulls down
                await refreshHomeData()
            }
            .onAppear {
                // Track home view appearance
                AnalyticsService.shared.trackUserFlowStep(step: .homeTab)
                timeTracker.startTracking(for: "home_view")
                
                // Reset filter to "All Bets" when page appears
                selectedFilter = "All Bets"
                
                firestoreService.fetchUserCommunities()
                // fetchBets() is now called automatically after communities are loaded
                firestoreService.fetchNotifications()
                firestoreService.refreshCurrentUser()
                
                // Set initial filter if provided (but only if it's not a refresh)
                if let filter = initialFilter, !filter.isEmpty {
                    selectedFilter = filter
                }
            }
            .onDisappear {
                // Track time spent on home view
                if let duration = timeTracker.endTracking(for: "home_view") {
                    AnalyticsService.shared.trackPageViewTime(page: "home_view", timeSpent: duration)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Reset filter to "All Bets" when app comes to foreground
                selectedFilter = "All Bets"
                
                firestoreService.fetchUserCommunities()
                // fetchBets() is now called automatically after communities are loaded
                firestoreService.fetchNotifications()
                firestoreService.refreshCurrentUser()
                
                // Check for expired bets when app comes to foreground
                firestoreService.checkAllExpiredBets()
            }
            .onChange(of: initialFilter) { _, newFilter in
                if let filter = newFilter {
                    selectedFilter = filter
                }
            }
        }
    }
    

    
    // MARK: - Computed Properties
    
    private var filteredBets: [FirestoreBet] {
        let currentTime = Date()
        
        // Filter bets based on selected community and exclude expired bets
        let filtered = selectedFilter == "All Bets" 
            ? firestoreService.bets.filter { bet in
                // Only show open bets that haven't expired
                let isOpen = bet.status.lowercased() == "open"
                let notExpired = bet.deadline > currentTime
                return isOpen && notExpired
            }
            : firestoreService.bets.filter { bet in
                // Find the community by ID, check if its name matches the selected filter, and exclude expired bets
                if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
                    let nameMatches = community.name == selectedFilter
                    let isOpen = bet.status.lowercased() == "open"
                    let notExpired = bet.deadline > currentTime
                    return nameMatches && isOpen && notExpired
                } else {
                    return false
                }
            }
        
        // If filtering by a specific community, add other community bets at the end
        if selectedFilter != "All Bets" {
            let otherCommunityBets = firestoreService.bets.filter { bet in
                // Only show open bets that haven't expired
                let isOpen = bet.status.lowercased() == "open"
                let notExpired = bet.deadline > currentTime
                
                // Check if bet is from a different community
                if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
                    let isDifferentCommunity = community.name != selectedFilter
                    return isOpen && notExpired && isDifferentCommunity
                }
                return false
            }
            
            // Combine filtered bets with other community bets
            return filtered + otherCommunityBets
        }
        
        return filtered
    }
    

    

    

    var body: some View {
        mainContent
            .background(Color.white)
            .sheet(isPresented: $showingNotifications) {
                NotificationsView(firestoreService: firestoreService)
            }

            .sheet(isPresented: $showingCreateBet) {
                CreateBetView(firestoreService: firestoreService, preSelectedCommunity: nil)
            }
            .sheet(isPresented: $showingJoinCommunityModal) {
                JoinCommunityPage(firestoreService: firestoreService)
            }
            .sheet(isPresented: $showingCreateCommunityModal) {
                CreateCommunityPage(firestoreService: firestoreService)
            }
            .sheet(isPresented: $showingUserProfile) {
                TradingProfileView(
                    userId: firestoreService.currentUser?.email ?? "",
                    userName: getUserFullName(),
                    displayName: firestoreService.currentUser?.display_name,
                    isCurrentUser: true,
                    firestoreService: firestoreService
                )
            }
            .overlay(
                // Points Popup - Centered on screen
                Group {
                    if showingPointsPopup {
                        ZStack {
                            // Background overlay
                            Color.black.opacity(0.4)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    showingPointsPopup = false
                                }
                            
                            // Popup content - centered
                            VStack(spacing: 24) {
                                // Close button
                                HStack {
                                    Button(action: {
                                        showingPointsPopup = false
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.title2)
                                            .fontWeight(.medium)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                
                                // Lightning bolt icon
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "FFF9E6"))
                                        .frame(width: 120, height: 120)
                                    
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(Color(hex: "FFD84D"))
                                }
                                
                                // Points count
                                Text("\(firestoreService.currentUser?.blitz_points ?? 0)")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                
                                // Description
                                VStack(spacing: 12) {
                                    Text("Blitz Points")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    
                                    Text("Points are earned by participating in bets and have no monetary value. Use them to track your betting activity and achievements!")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(nil)
                                }
                                
                                Spacer()
                            }
                            .padding(20)
                            .background(Color.white)
                            .cornerRadius(20)
                            .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                            .frame(maxWidth: 320)
                            .frame(maxHeight: 400)
                        }
                    }
                }
            )
    }
    
    private func getUserFullName() -> String {
        let user = firestoreService.currentUser
        if let firstName = user?.first_name, let lastName = user?.last_name, !firstName.isEmpty, !lastName.isEmpty {
            return "\(firstName) \(lastName)"
        } else if let displayName = user?.display_name, !displayName.isEmpty {
            return displayName
        } else if let email = user?.email {
            let components = email.components(separatedBy: "@")
            return components.first ?? "User"
        }
        return "User"
    }
    
    private func refreshHomeData() async {
        // Fetch fresh data from Firestore
        firestoreService.fetchUserCommunities()
        // fetchBets() is now called automatically after communities are loaded
    }
}

// MARK: - Home Bet Card

struct HomeBetCard: View {
    let bet: FirestoreBet
    let currentUserEmail: String?
    let firestoreService: FirestoreService
    @State private var showingJoinBet = false
    @State private var showingBettingInterface = false
    @State private var selectedBettingOption = ""
    @State private var creatorName: String = ""
    @State private var showingShareSheet = false
    
    private var communityName: String {
        if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
            return community.name
        }
        return "Community"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with image and title - clickable to go to bet details
            Button(action: {
                if bet.status.lowercased() == "open" {
                    AnalyticsService.shared.trackBetInteraction(action: .view, betId: bet.id ?? "unknown", betTitle: bet.title, communityName: communityName)
                    showingJoinBet = true
                }
            }) {
                HStack(alignment: .top, spacing: 12) {
                    BetImageView(title: bet.title, imageURL: bet.image_url)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(bet.title)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Text("\(communityName) • by \(currentUserEmail == bet.creator_email ? "You" : formatCreatorName(creatorName))")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    

                }
            }
            .buttonStyle(.plain)
            
            // Betting Options - each option is clickable to go to betting modal
            VStack(spacing: 8) {
                ForEach(bet.options, id: \.self) { option in
                    Button(action: {
                        AnalyticsService.shared.trackBetInteraction(action: .placeBet, betId: bet.id ?? "unknown", betTitle: bet.title, communityName: communityName)
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
                        .background(Color.slingLightPurple.opacity(0.75))
                        .cornerRadius(10)
                                            }
                        .buttonStyle(.plain)
                    }
                }
            
            // Footer - clickable to go to bet details
            Button(action: {
                if bet.status.lowercased() == "open" {
                    AnalyticsService.shared.trackBetInteraction(action: .view, betId: bet.id ?? "unknown", betTitle: bet.title, communityName: communityName)
                    showingJoinBet = true
                }
            }) {
                HStack {
                    Text("Deadline: \(formatDate(bet.deadline))")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
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
                selectedOption: selectedBettingOption,
                firestoreService: firestoreService
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [generateBetShareText()])
        }
        .onAppear {
            loadCreatorName()
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
    
    private func formatCreatorName(_ fullName: String) -> String {
        let components = fullName.components(separatedBy: " ")
        if components.count >= 2 {
            let firstName = components[0]
            let lastName = components[1]
            let lastInitial = String(lastName.prefix(1))
            return "\(firstName) \(lastInitial)."
        } else if components.count == 1 {
            return components[0]
        } else {
            return fullName
        }
    }
    
    private func generateBetShareText() -> String {
        guard let betId = bet.id else {
            return "\(bet.title) | Sling"
        }
        
        return """
        \(bet.title) | Sling
        
        sling://bet/\(betId)
        """
    }
}

// MARK: - Profile Modal







                

