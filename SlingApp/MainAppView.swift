import SwiftUI

struct MainAppView: View {
    @ObservedObject var firestoreService: FirestoreService
    @State private var selectedTab = 0 // 0 = Home, 1 = Chat, 2 = My Bets, 3 = Communities, 4 = Profile
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
                        MyBetsView(firestoreService: firestoreService)
                    case 3:
                        // Communities View
                        CommunitiesView(firestoreService: firestoreService, onNavigateToHome: { communityName in
                            navigateToHomeWithFilter(communityName)
                        })
                    case 4:
                        // Profile View
                        ProfileView(firestoreService: firestoreService, showingEditProfile: $showingEditProfile)
                    default:
                        EmptyView()
                    }
                }
                
                // Custom Tab Bar with integrated plus button - hide when keyboard is active
                if !isKeyboardActive {
                    HStack(spacing: 0) {
                        // Home Tab
                    Button(action: { selectedTab = 0 }) {
                        VStack(spacing: 4) {
                            Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                                .font(.title2)
                            Text("Home")
                                .font(.caption)
                        }
                        .foregroundColor(selectedTab == 0 ? Color.slingBlue : .gray)
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Chat Tab
                    Button(action: { selectedTab = 1 }) {
                        VStack(spacing: 4) {
                            ZStack {
                                Image(systemName: selectedTab == 1 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                    .font(.title2)
                                
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
                        }
                        .foregroundColor(selectedTab == 1 ? Color.slingBlue : .gray)
                        .frame(maxWidth: .infinity)
                    }
                    
                    // My Bets Tab
                    Button(action: { selectedTab = 2 }) {
                        VStack(spacing: 4) {
                            Image(systemName: selectedTab == 2 ? "list.bullet.clipboard.fill" : "list.bullet.clipboard")
                                .font(.title2)
                            Text("My Bets")
                                .font(.caption)
                        }
                        .foregroundColor(selectedTab == 2 ? Color.slingBlue : .gray)
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Communities Tab
                    Button(action: { 
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
                            Text("Communities")
                                .font(.caption)
                        }
                        .foregroundColor(selectedTab == 3 ? Color.slingBlue : .gray)
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Profile Tab
                    Button(action: { selectedTab = 4 }) {
                        VStack(spacing: 4) {
                            Image(systemName: selectedTab == 4 ? "person.circle.fill" : "person.circle")
                                .font(.title2)
                            Text("Profile")
                                .font(.caption)
                        }
                        .foregroundColor(selectedTab == 4 ? Color.slingBlue : .gray)
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
                CreateBetView(firestoreService: firestoreService)
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
        .onReceive(deepLinkManager.$pendingDeepLink) { deepLink in
            if let deepLink = deepLink {
                handleDeepLink(deepLink)
            }
        }
        .sheet(isPresented: $showingDeepLinkBet) {
            if let bet = deepLinkBet {
                JoinBetView(bet: bet, firestoreService: firestoreService)
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
}

// MARK: - Home View

// MARK: - Home Header Component
struct HomeHeaderView: View {
    @ObservedObject var firestoreService: FirestoreService
    let onNotificationsTap: () -> Void
    
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
            
            // Points Badge
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
            

            
            // Notification Bell
            Button(action: onNotificationsTap) {
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
            
            // User Profile - Removed as requested
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(categories, id: \.self) { category in
                    Button(action: {
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
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(Color.white)
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


    @State private var showingCreateBet = false

    
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
                    onNotificationsTap: { showingNotifications = true }
                )
            

            
            // Main Content
            ScrollView {
                VStack(spacing: 16) {
                    // Filter Bar - only show if user has communities (now scrollable)
                    if !firestoreService.userCommunities.isEmpty {
                        FilterBarView(
                            categories: filterCategories,
                            selectedFilter: $selectedFilter
                        )
                        .padding(.horizontal, -16) // Counteract the horizontal padding
                    }
                    
                    // Show bet feed content
                    betFeedContent
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .refreshable {
                // Refresh data when user pulls down
                await refreshHomeData()
            }
            .onAppear {
                firestoreService.fetchUserCommunities()
                // fetchBets() is now called automatically after communities are loaded
                firestoreService.fetchNotifications()
                firestoreService.refreshCurrentUser()
                
                // Set initial filter if provided
                if let filter = initialFilter {
                    selectedFilter = filter
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
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
    
    // MARK: - Bet Feed Content
    
    private var betFeedContent: some View {
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
                        
                        Text("Get started by joining or creating a community. Connect with friends and start predicting!")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                    
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
                    .padding(.horizontal, 32)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Feed of Bets from user's joined communities
                ForEach(filteredBets) { bet in
                    HomeBetCard(
                        bet: bet,
                        currentUserEmail: firestoreService.currentUser?.email,
                        firestoreService: firestoreService
                    )
                }
                
                // Show empty state if no bets
                if filteredBets.isEmpty {
                    EmptyBetsView(firestoreService: firestoreService)
                }
            }
        }
        .onAppear {
            // Debug logging when view appears
            debugLogBetFeedState()
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredBets: [FirestoreBet] {
        // Filter bets based on selected community and exclude expired bets
        let filtered = selectedFilter == "All Bets" 
            ? firestoreService.bets.filter { bet in
                // Only show open bets that haven't expired
                let isOpen = bet.status.lowercased() == "open"
                let notExpired = bet.deadline > Date()
                return isOpen && notExpired
            }
            : firestoreService.bets.filter { bet in
                // Find the community by ID, check if its name matches the selected filter, and exclude expired bets
                if let community = firestoreService.userCommunities.first(where: { $0.id == bet.community_id }) {
                    let nameMatches = community.name == selectedFilter
                    let isOpen = bet.status.lowercased() == "open"
                    let notExpired = bet.deadline > Date()
                    return nameMatches && isOpen && notExpired
                } else {
                    return false
                }
            }
        
        return filtered
    }
    
    // MARK: - Debug Methods
    
    private func debugLogBetFeedState() {
        // Debug logging removed for cleaner console
    }
    
    // MARK: - Floating Plus Button
    
    private var floatingPlusButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showingCreateBet = true
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.slingGradient)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
                .padding(.trailing, 24)
                .padding(.bottom, 20) // Positioned right on top of tab bar
            }
        }
    }
    

    

    
    var body: some View {
        mainContent
            .background(Color.white)
            .sheet(isPresented: $showingNotifications) {
                NotificationsView(firestoreService: firestoreService)
            }

            .sheet(isPresented: $showingCreateBet) {
                CreateBetView(firestoreService: firestoreService)
            }
            .sheet(isPresented: $showingJoinCommunityModal) {
                JoinCommunityPage(firestoreService: firestoreService)
            }
            .sheet(isPresented: $showingCreateCommunityModal) {
                CreateCommunityPage(firestoreService: firestoreService)
            }
            .overlay(floatingPlusButton)
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
                            Text("\(communityName) • by \(currentUserEmail == bet.creator_email ? "You" : creatorName)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    

                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Betting Options - each option is clickable to go to betting modal
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
                        .background(Color.slingLightPurple.opacity(0.75))
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Footer - clickable to go to bet details
            Button(action: {
                if bet.status.lowercased() == "open" {
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
            .buttonStyle(PlainButtonStyle())
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .sheet(isPresented: $showingJoinBet) {
            JoinBetView(bet: bet, firestoreService: firestoreService)
        }
        .sheet(isPresented: $showingBettingInterface) {
            BettingInterfaceView(
                bet: bet,
                selectedOption: "",
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







                

