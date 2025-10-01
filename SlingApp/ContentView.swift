import SwiftUI
import Firebase
import FirebaseCore
import FirebaseAnalytics
import AuthenticationServices
import CryptoKit
import GoogleSignIn

// MARK: - Global Utility Functions

// Function to format display name by removing spaces
func formatDisplayName(_ name: String) -> String {
    return name.replacingOccurrences(of: " ", with: "")
}

struct ContentView: View {
    @StateObject var firestoreService = FirestoreService()
    @State private var hasShownLoading = false
    @StateObject private var timeTracker = TimeTracker()
    
    var body: some View {
        Group {
            if !hasShownLoading {
                LoadingScreenView()
                    .onAppear {
                        // Initialize error logging with FirestoreService
                        ErrorLogger.shared.setFirestoreService(firestoreService)
                        
                        // Test the error logging system (you can remove this in production)
                        SlingLogInfo("App started successfully - Error logging system initialized")
                        
                        // Track app launch and loading screen
                        AnalyticsService.shared.trackUserFlowStep(step: .appLaunch)
                        AnalyticsService.shared.trackUserFlowStep(step: .loadingScreen)
                        timeTracker.startTracking(for: "loading_screen")
                        
                        // Show loading screen for at least 1.5 seconds, then check auth state
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                hasShownLoading = true
                                
                                // Track loading screen completion
                                if let duration = timeTracker.endTracking(for: "loading_screen") {
                                    AnalyticsService.shared.trackPageViewTime(page: "loading_screen", timeSpent: duration)
                                }
                            }
                        }
                    }
            } else if firestoreService.isAuthenticated {
                MainAppView(firestoreService: firestoreService)
                    .onAppear {
                        // Store FCM token in Firestore when user is authenticated
                        if let fcmToken = UserDefaults.standard.string(forKey: "FCMToken") {
                            firestoreService.updateUserFCMToken(fcmToken)
                        }
                    }
                    .onAppear {
                        // Start automatic odds tracking for authenticated users
                        firestoreService.startAutomaticOddsTracking()
                        
                        // Track analytics
                        AnalyticsService.shared.trackUserFlowStep(step: .mainApp)
                        AnalyticsService.shared.setUserProperties(user: firestoreService.currentUser)
                    }
            } else {
                AuthenticationView(firestoreService: firestoreService)
                    .onAppear {
                        AnalyticsService.shared.trackUserFlowStep(step: .authentication)
                        AnalyticsService.shared.trackAuthPageView(page: .welcome)
                        timeTracker.startTracking(for: "welcome_screen")
                    }
            }
        }
    }
}

// MARK: - Dynamic Authentication View

struct AuthenticationView: View {
    @ObservedObject var firestoreService: FirestoreService
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingEmailForm = false
    @State private var showingCommunityOnboarding = false
    @State private var currentNonce: String?
    @State private var errorMessageTimer: Timer?
    @State private var appleButtonPressed = false
    @State private var emailButtonPressed = false
    @State private var logoAnimationProgress: CGFloat = 0
    @StateObject private var timeTracker = TimeTracker()
    
    // Dynamic prediction categories that fade in/out
    private let predictionCategories = [
        "sports", "politics", "finance", "crypto", 
        "entertainment", "technology", "weather", "elections"
    ]
    
    // Function to set error message with auto-fade
    private func setErrorMessage(_ message: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            errorMessage = message
        }
        
        // Cancel any existing timer
        errorMessageTimer?.invalidate()
        
        // Set timer to clear error message after 4 seconds
        errorMessageTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.5)) {
                errorMessage = ""
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Clean white background
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top section - removed branding elements
                    VStack(spacing: 32) {
                        Spacer()
                        
                        Spacer()
                        
                        // Animated Logo
                        ZStack {
                            // Background rounded square (squircle) with sling gradient
                            RoundedRectangle(cornerRadius: 30)
                                .fill(Color.slingGradient)
                                .frame(width: 120, height: 120)
                                .shadow(color: Color.slingBlue.opacity(0.3), radius: 12, x: 0, y: 6)
                            
                            // Animated line chart with arrow - using exact vector path
                            Path { path in
                                // Original SVG path data
                                path.move(to: CGPoint(x: 31.0002, y: 315.673))
                                path.addLine(to: CGPoint(x: 178.673, y: 168))
                                path.addLine(to: CGPoint(x: 336.112, y: 253.175))
                                path.addLine(to: CGPoint(x: 621, y: 31))
                                // Arrow part
                                path.addLine(to: CGPoint(x: 437.939, y: 31)) // H437.939
                                path.move(to: CGPoint(x: 621, y: 31)) // M621 31
                                path.addLine(to: CGPoint(x: 621, y: 209)) // V209 (doubled from 120 to 209)
                            }
                            .trim(from: 0, to: logoAnimationProgress)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 35, lineCap: .round, lineJoin: .round))
                            .scaleEffect(0.12)
                            .offset(x: -18, y: -15)
                        }
                        .padding(.bottom, 12)
                        
                        // Main Tagline
                        VStack(spacing: 8) {
                            Text("Bet on Anything.")
                                .font(.largeTitle)
                                .fontWeight(.black)
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                            
                            Text("With Friends.")
                                .font(.largeTitle)
                                .fontWeight(.black)
                                .foregroundStyle(Color.slingGradient)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                        
                        // Authentication Buttons - Centered Content
                        VStack(spacing: 16) {
                            // Google Sign-In Button
                            GoogleSignInButton(action: {
                                AnalyticsService.shared.trackAuthButtonTap(button: .googleSignIn, page: .welcome)
                                AnalyticsService.shared.trackAuthMethodSelected(method: .google)
                                handleGoogleSignIn()
                            }, isLoading: isLoading)
                            
                            // Apple Sign-In Button - Custom implementation to match Google button
                            Button(action: {
                                AnalyticsService.shared.trackAuthButtonTap(button: .appleSignIn, page: .welcome)
                                AnalyticsService.shared.trackAuthMethodSelected(method: .apple)
                                
                                withAnimation(.easeInOut(duration: 0.218)) {
                                    appleButtonPressed = true
                                }
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.218) {
                                    
                                    appleButtonPressed = false
                                    // Trigger Apple Sign In
                                    triggerAppleSignIn()
                                }
                            }) {
                                ZStack {
                                    // Button state overlay (matches Google's animation)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.black.opacity(0.1))
                                        .opacity(appleButtonPressed ? 0.12 : 0)
                                        .animation(.easeInOut(duration: 0.218), value: appleButtonPressed)
                                    
                                    // Main button content
                                    HStack(spacing: 16) {
                                        Spacer()
                                        
                                        // Apple Logo
                                        Image(systemName: "applelogo")
                                            .font(.title2)
                                            .foregroundColor(.black)
                                            .frame(width: 24, height: 24)
                                        
                                        Text("Continue with Apple")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.black)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.white)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                            }
                            .disabled(isLoading)
                            .scaleEffect(appleButtonPressed ? 0.98 : 1.0)
                            .animation(.easeInOut(duration: 0.218), value: appleButtonPressed)
                            
                            // Email Sign-Up Button - Always goes to Sign Up
                            Button(action: {
                                AnalyticsService.shared.trackAuthButtonTap(button: .emailSignUp, page: .welcome)
                                AnalyticsService.shared.trackAuthMethodSelected(method: .email)
                                
                                withAnimation(.easeInOut(duration: 0.218)) {
                                    emailButtonPressed = true
                                }
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.218) {
                                    emailButtonPressed = false
                                    isSignUp = true
                                    showingEmailForm = true
                                    
                                    // Track navigation to email form
                                    AnalyticsService.shared.trackNavigation(from: "welcome", to: "email_signup", method: .buttonTap)
                                }
                            }) {
                                ZStack {
                                    // Button state overlay (matches Google's animation)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.slingBlue.opacity(0.1))
                                        .opacity(emailButtonPressed ? 0.12 : 0)
                                        .animation(.easeInOut(duration: 0.218), value: emailButtonPressed)
                                    
                                    // Main button content
                                    HStack(spacing: 16) {
                                        Spacer()
                                        
                                        // Email Icon
                                        Image(systemName: "envelope.fill")
                                            .font(.title2)
                                            .foregroundColor(.slingBlue)
                                            .frame(width: 24, height: 24)
                                        
                                        Text("Sign up with Email")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.slingBlue)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.white)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                            }
                            .disabled(isLoading)
                            .scaleEffect(emailButtonPressed ? 0.98 : 1.0)
                            .animation(.easeInOut(duration: 0.218), value: emailButtonPressed)
                        }
                        .padding(.horizontal, 24)
                        
                        // Always show "Already have an account? Sign In" button
                        Button(action: {
                            AnalyticsService.shared.trackAuthButtonTap(button: .toggleToSignIn, page: .welcome)
                            
                            withAnimation(.easeInOut(duration: 0.3)) {
                                // Always go to sign in page
                                isSignUp = false
                                showingEmailForm = true
                                errorMessage = ""
                                
                                // Track navigation to sign in
                                AnalyticsService.shared.trackNavigation(from: "welcome", to: "email_signin", method: .buttonTap)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text("Already have an account? ")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.gray.opacity(0.7))
                                
                                Text("Sign In")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.slingBlue)
                            }
                        }
                        .padding(.top, 8)
                        
                        // Legal disclaimer - moved up and improved
                        HStack(spacing: 4) {
                            Text("By continuing, you agree to our")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.6))
                            
                            Button(action: {
                                AnalyticsService.shared.trackAuthButtonTap(button: .termsOfService, page: .welcome)
                                
                                // Open terms of service
                                if let url = URL(string: "https://slingapp.com/terms") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 2) {
                                    Text("terms of service")
                                        .font(.caption)
                                        .foregroundColor(.gray.opacity(0.6))
                                    
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2)
                                        .foregroundColor(.gray.opacity(0.6))
                                }
                            }
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 60)
                        
                        Spacer(minLength: 80)
                    }
                    .padding(.top, 60) // Move everything down more
                }
                
                // Error message overlay
                if !errorMessage.isEmpty {
                    VStack {
                        Spacer()
                        
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.9))
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: errorMessage)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingEmailForm) {
            EmailAuthenticationView(
                firestoreService: firestoreService,
                isSignUp: $isSignUp,
                onDismiss: { showingEmailForm = false },
                onShowOnboarding: { 
                    showingEmailForm = false
                    showingCommunityOnboarding = true
                }
            )
        }
        .sheet(isPresented: $showingCommunityOnboarding) {
            CommunityOnboardingView(
                firestoreService: firestoreService,
                onDismiss: { showingCommunityOnboarding = false }
            )
        }
        .onAppear {
            // Apple Sign In state will be checked when button is clicked
            
            // Animate the logo drawing
            withAnimation(.easeInOut(duration: 2.0)) {
                logoAnimationProgress = 1.0
            }
        }
        .onDisappear {
            // Clean up timer when view disappears
            errorMessageTimer?.invalidate()
            errorMessageTimer = nil
        }
    }
    
    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        AnalyticsService.shared.trackAuthStarted(method: .apple)
        isLoading = true
        errorMessage = ""
        
        // Add debugging information
        print("🍎 Apple Sign-In started")
        print("🍎 Current nonce: \(currentNonce ?? "nil")")
        
        switch result {
        case .success(let authorization):
            print("🍎 Apple Sign-In authorization successful")
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                print("🍎 Got Apple ID credential for user: \(appleIDCredential.user)")
                handleAppleSignInSuccess(appleIDCredential)
            } else {
                print("🍎 Failed to get Apple ID credential from authorization")
                isLoading = false
                setErrorMessage("Apple sign-in failed. Please try again.")
            }
        case .failure(let error):
            print("🍎 Apple Sign-In failed with error: \(error)")
            AnalyticsService.shared.trackAuthFailure(method: .apple, error: error.localizedDescription)
            isLoading = false
            if let authError = error as? ASAuthorizationError {
                print("🍎 ASAuthorizationError code: \(authError.code.rawValue)")
                switch authError.code {
                case .canceled:
                    // User canceled, don't show error
                    print("🍎 User canceled Apple Sign-In")
                    break
                case .failed:
                    setErrorMessage("Apple sign-in failed. Please try again.")
                case .invalidResponse:
                    setErrorMessage("Invalid response from Apple. Please try again.")
                case .notHandled:
                    setErrorMessage("Apple sign-in not handled. Please try again.")
                case .unknown:
                    setErrorMessage("Unknown error occurred. Please try again.")
                case .notInteractive:
                    setErrorMessage("Sign in requires user interaction. Please try again.")
                @unknown default:
                    setErrorMessage("Apple sign-in failed. Please try again.")
                }
            } else {
                print("🍎 Non-ASAuthorizationError: \(error)")
                
                // Handle specific Apple ID errors
                if let nsError = error as NSError? {
                    print("🍎 NSError domain: \(nsError.domain), code: \(nsError.code)")
                    if nsError.domain == "AKAuthenticationError" && nsError.code == -7026 {
                        setErrorMessage("Apple ID configuration issue. Please check your Apple ID settings.")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.handleAppleIDConfigurationIssue()
                        }
                    } else if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" && nsError.code == 1000 {
                        setErrorMessage("Authorization failed. Please try signing out and signing back in.")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.handleAuthorizationError()
                        }
                    } else if nsError.localizedDescription.contains("MCPasscodeManager") {
                        setErrorMessage("This device doesn't support the required security features for Apple Sign In.")
                    } else {
                        setErrorMessage("Apple sign-in failed. Please try again.")
                    }
                } else {
                    setErrorMessage("Apple sign-in failed. Please try again.")
                }
            }
        }
    }
    

    
    private func handleAppleSignInSuccess(_ appleIDCredential: ASAuthorizationAppleIDCredential) {
        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            isLoading = false
            setErrorMessage("Failed to get Apple ID token. Please try again.")
            return
        }
        
        // Get the nonce that was used for this request
        guard let nonce = currentNonce else {
            isLoading = false
            setErrorMessage("Invalid nonce. Please try again.")
            return
        }
        
        let credential = OAuthProvider.credential(
            withProviderID: "apple.com",
            idToken: idTokenString,
            rawNonce: nonce
        )
        
        Auth.auth().signIn(with: credential) { result, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    print("🍎 Firebase Auth Error: \(error)")
                    if let nsError = error as NSError? {
                        switch nsError.code {
                        case AuthErrorCode.accountExistsWithDifferentCredential.rawValue:
                            self.setErrorMessage("An account with this email already exists. Please sign in with the original method.")
                        case AuthErrorCode.invalidCredential.rawValue:
                            self.setErrorMessage("Invalid credentials. Please try again.")
                        case AuthErrorCode.operationNotAllowed.rawValue:
                            self.setErrorMessage("Apple sign-in is not enabled. Please contact support.")
                        case AuthErrorCode.networkError.rawValue:
                            self.setErrorMessage("Network error. Please check your connection and try again.")
                        case AuthErrorCode.userNotFound.rawValue:
                            self.setErrorMessage("User not found. Please try again.")
                        case AuthErrorCode.tooManyRequests.rawValue:
                            self.setErrorMessage("Too many requests. Please try again later.")
                        case AuthErrorCode.userDisabled.rawValue:
                            self.setErrorMessage("Account disabled. Please contact support.")
                        default:
                            self.setErrorMessage("Authentication failed. Please try again.")
                        }
                    } else {
                        self.setErrorMessage("Authentication failed. Please try again.")
                    }
                    return
                }
                
                guard let firebaseUser = result?.user else {
                    self.setErrorMessage("Failed to get user information. Please try again.")
                    return
                }
                
                // Check if user already exists in Firestore
                self.firestoreService.db.collection("Users").document(firebaseUser.email ?? "").getDocument { document, error in
                    DispatchQueue.main.async {
                        if let document = document, document.exists {
                            self.firestoreService.currentUser = try? document.data(as: FirestoreUser.self)
                            AnalyticsService.shared.trackAuthSuccess(method: .apple, isNewUser: false)
                        } else {
                            // Create new user profile
                            self.createAppleUserProfile(firebaseUser: firebaseUser, appleIDCredential: appleIDCredential)
                            AnalyticsService.shared.trackAuthSuccess(method: .apple, isNewUser: true)
                        }
                        // Clear the nonce after successful authentication
                        self.currentNonce = nil
                    }
                }
            }
        }
    }
    
    private func createAppleUserProfile(firebaseUser: User, appleIDCredential: ASAuthorizationAppleIDCredential) {
        let fullName = appleIDCredential.fullName
        let firstName = fullName?.givenName ?? ""
        let lastName = fullName?.familyName ?? ""
        let rawDisplayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = formatDisplayName(rawDisplayName.isEmpty ? "User" : rawDisplayName)
        
        // Apple Sign-In doesn't provide gender, and rarely provides profile picture
        let gender: String? = nil
        var profilePictureURL: String? = nil
        
        // Check if Firebase user has a photoURL (rarely available with Apple Sign-In)
        if let photoURL = firebaseUser.photoURL?.absoluteString {
            profilePictureURL = photoURL
            print("🍎 Apple profile picture URL: \(profilePictureURL ?? "nil")")
        }
        
        // Log the data being collected from Apple
        print("🍎 Apple Sign-In Data Collected:")
        print("  - Full Name: \(fullName?.description ?? "nil")")
        print("  - First Name: \(firstName)")
        print("  - Last Name: \(lastName)")
        print("  - Display Name: \(displayName)")
        print("  - Email: \(firebaseUser.email ?? "nil")")
        print("  - Profile Picture URL: \(profilePictureURL ?? "nil")")
        print("  - Gender: \(gender ?? "nil")")
        print("  - Firebase UID: \(firebaseUser.uid)")
        
        let userProfile = FirestoreUser(
            documentId: nil,
            blitz_points: 10000, // Give new users starting points
            display_name: displayName.isEmpty ? "User" : displayName,
            email: firebaseUser.email ?? "",
            first_name: firstName,
            full_name: rawDisplayName.isEmpty ? "User" : rawDisplayName,
            last_name: lastName,
            gender: gender,
            profile_picture_url: profilePictureURL,
            total_bets: 0, // Initialize betting statistics
            total_winnings: 0, // Initialize winnings
            id: firebaseUser.uid,
            uid: firebaseUser.uid,
            sling_points: nil
        )
        
        do {
            try self.firestoreService.db.collection("Users").document(firebaseUser.email ?? "").setData(from: userProfile)
            self.firestoreService.currentUser = userProfile
        } catch {
            self.setErrorMessage("Failed to create user profile. Please try again.")
        }
    }
    
    private func signInExistingAppleUser(firebaseUser: User) {
        self.firestoreService.db.collection("Users").document(firebaseUser.email ?? "").getDocument { document, error in
            DispatchQueue.main.async {
                if let document = document, document.exists {
                    self.firestoreService.currentUser = try? document.data(as: FirestoreUser.self)
                } else {
                    self.setErrorMessage("Profile not found. Please contact support.")
                }
            }
        }
    }
    
    // MARK: - Helper Functions for Apple Sign-In
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    private func handleAppleIDConfigurationIssue() {
        let alert = UIAlertController(
            title: "Apple ID Configuration Required",
            message: "Please go to Settings > Apple ID > Sign In & Security to configure your Apple ID for this app.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Present the alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
    
    private func handleAuthorizationError() {
        let alert = UIAlertController(
            title: "Authorization Error",
            message: "There was an issue with your Apple ID authorization. Please try signing out and signing back in.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        // Present the alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }
    
    private func checkAppleSignInState() {
        // Check if running on simulator
        #if targetEnvironment(simulator)
        print("🍎 ⚠️ WARNING: Apple Sign In is running on simulator - this will cause errors!")
        print("🍎 Please test on a physical device for proper Apple Sign In functionality")
        setErrorMessage("Apple Sign In requires a physical device. Please test on a real device.")
        return
        #endif
        
        // Check bundle identifier
        if let bundleId = Bundle.main.bundleIdentifier {
            print("🍎 App Bundle ID: \(bundleId)")
        }
        
        // Check entitlements
        if let entitlementsPath = Bundle.main.path(forResource: "SlingApp", ofType: "entitlements") {
            print("🍎 Entitlements file found at: \(entitlementsPath)")
        } else {
            print("🍎 ⚠️ No entitlements file found - this may cause Apple Sign In issues")
        }
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        appleIDProvider.getCredentialState(forUserID: "current") { state, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🍎 Error checking Apple Sign In state: \(error)")
                    return
                }
                
                switch state {
                case .authorized:
                    print("🍎 Apple Sign In state: Authorized")
                case .revoked:
                    print("🍎 Apple Sign In state: Revoked")
                    setErrorMessage("Apple Sign In access revoked. Please sign in again.")
                case .notFound:
                    print("🍎 Apple Sign In state: Not Found")
                case .transferred:
                    print("🍎 Apple Sign In state: Transferred")
                @unknown default:
                    print("🍎 Apple Sign In state: Unknown")
                }
            }
        }
    }
    
    private func triggerAppleSignIn() {
        // Check Apple Sign In state only when button is clicked
        checkAppleSignInState()
        
        #if targetEnvironment(simulator)
        setErrorMessage("Apple Sign In requires a physical device. Please test on a real device.")
        return
        #endif
        
        // Generate a new nonce for this request
        let nonce = randomNonceString()
        currentNonce = nonce
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = AppleSignInDelegate(
            onSuccess: { credential in
                self.handleAppleSignInSuccess(credential)
            },
            onFailure: { error in
                self.setErrorMessage("Apple Sign In failed. Please try again.")
            }
        )
        authorizationController.presentationContextProvider = AppleSignInPresentationContextProvider()
        authorizationController.performRequests()
    }
    
    // MARK: - Google Sign-In Functions
    
    private func handleGoogleSignIn() {
        AnalyticsService.shared.trackAuthStarted(method: .google)
        isLoading = true
        errorMessage = ""
        
        guard let presentingViewController = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController else {
            isLoading = false
            setErrorMessage("Failed to present Google Sign-In. Please try again.")
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    let errorMessage = error.localizedDescription
                    AnalyticsService.shared.trackAuthFailure(method: .google, error: errorMessage)
                    
                    if let nsError = error as NSError? {
                        switch nsError.code {
                        case GIDSignInError.canceled.rawValue:
                            // User canceled, don't show error
                            break
                        case GIDSignInError.hasNoAuthInKeychain.rawValue:
                            self.setErrorMessage("No previous sign-in found. Please try again.")
                        case GIDSignInError.unknown.rawValue:
                            self.setErrorMessage("Unknown error occurred. Please try again.")
                        default:
                            self.setErrorMessage("Google sign-in failed. Please try again.")
                        }
                    } else {
                        self.setErrorMessage("Google sign-in failed. Please try again.")
                    }
                    return
                }
                
                guard let user = result?.user,
                      let idToken = user.idToken?.tokenString else {
                    self.setErrorMessage("Failed to get Google ID token. Please try again.")
                    return
                }
                
                let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)
                
                Auth.auth().signIn(with: credential) { result, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            if let nsError = error as NSError? {
                                switch nsError.code {
                                case AuthErrorCode.accountExistsWithDifferentCredential.rawValue:
                                    self.setErrorMessage("An account with this email already exists. Please sign in with the original method.")
                                case AuthErrorCode.invalidCredential.rawValue:
                                    self.setErrorMessage("Invalid credentials. Please try again.")
                                case AuthErrorCode.operationNotAllowed.rawValue:
                                    self.setErrorMessage("Google sign-in is not enabled. Please contact support.")
                                case AuthErrorCode.networkError.rawValue:
                                    self.setErrorMessage("Network error. Please check your connection and try again.")
                                case AuthErrorCode.userNotFound.rawValue:
                                    self.setErrorMessage("User not found. Please try again.")
                                case AuthErrorCode.tooManyRequests.rawValue:
                                    self.setErrorMessage("Too many requests. Please try again later.")
                                case AuthErrorCode.userDisabled.rawValue:
                                    self.setErrorMessage("Account disabled. Please contact support.")
                                default:
                                    self.setErrorMessage("Authentication failed. Please try again.")
                                }
                            } else {
                                self.setErrorMessage("Authentication failed. Please try again.")
                            }
                            return
                        }
                        
                        guard let firebaseUser = result?.user else {
                            self.setErrorMessage("Failed to get user information. Please try again.")
                            return
                        }
                        
                        // Check if user already exists in Firestore
                        self.firestoreService.db.collection("Users").document(firebaseUser.email ?? "").getDocument { document, error in
                            DispatchQueue.main.async {
                                if let document = document, document.exists {
                                    self.firestoreService.currentUser = try? document.data(as: FirestoreUser.self)
                                    AnalyticsService.shared.trackAuthSuccess(method: .google, isNewUser: false)
                                } else {
                                    // Create new user profile
                                    self.createGoogleUserProfile(firebaseUser: firebaseUser, googleUser: user)
                                    AnalyticsService.shared.trackAuthSuccess(method: .google, isNewUser: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func createGoogleUserProfile(firebaseUser: User, googleUser: GIDGoogleUser) {
        let fullName = googleUser.profile?.name ?? ""
        let firstName = googleUser.profile?.givenName ?? ""
        let lastName = googleUser.profile?.familyName ?? ""
        let rawDisplayName = fullName.isEmpty ? "User" : fullName
        let displayName = formatDisplayName(rawDisplayName)
        
        // Get profile picture URL if available
        var profilePictureURL: String? = nil
        
        // Check if Firebase user has a photoURL (this comes from Google Sign-In)
        if let photoURL = firebaseUser.photoURL?.absoluteString {
            // Request higher resolution by replacing s96-c with s400-c for better quality
            profilePictureURL = photoURL.replacingOccurrences(of: "s96-c", with: "s400-c")
            print("🔗 Google profile picture URL: \(profilePictureURL ?? "nil")")
        }
        
        // Note: Google doesn't provide gender information through their basic profile
        // This will remain nil for Google Sign-In users
        let gender: String? = nil
        
        // Log the data being collected from Google
        print("🔍 Google Sign-In Data Collected:")
        print("  - Full Name: \(fullName)")
        print("  - First Name: \(firstName)")
        print("  - Last Name: \(lastName)")
        print("  - Display Name: \(displayName)")
        print("  - Email: \(firebaseUser.email ?? "nil")")
        print("  - Profile Picture URL: \(profilePictureURL ?? "nil")")
        print("  - Gender: \(gender ?? "nil")")
        print("  - Firebase UID: \(firebaseUser.uid)")
        
        let userProfile = FirestoreUser(
            documentId: nil,
            blitz_points: 10000, // Give new users starting points
            display_name: displayName,
            email: firebaseUser.email ?? "",
            first_name: firstName,
            full_name: fullName.isEmpty ? "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) : fullName,
            last_name: lastName,
            gender: gender,
            profile_picture_url: profilePictureURL,
            total_bets: 0, // Initialize betting statistics
            total_winnings: 0, // Initialize winnings
            id: firebaseUser.uid,
            uid: firebaseUser.uid,
            sling_points: nil
        )
        
        do {
            try self.firestoreService.db.collection("Users").document(firebaseUser.email ?? "").setData(from: userProfile)
            self.firestoreService.currentUser = userProfile
        } catch {
            self.setErrorMessage("Failed to create user profile. Please try again.")
        }
    }
}

// MARK: - Google Sign-In Button Component

struct GoogleSignInButton: View {
    let action: () -> Void
    let isLoading: Bool
    
    @State private var isPressed = false
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.218)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.218) {
                isPressed = false
                action()
            }
        }) {
            ZStack {
                // Button state overlay (matches Google's .gsi-material-button-state)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0/255, green: 29/255, blue: 53/255))
                    .opacity(isPressed ? 0.12 : (isHovered ? 0.08 : 0))
                    .animation(.easeInOut(duration: 0.218), value: isPressed || isHovered)
                
                // Main button content
                HStack(spacing: 16) {
                    Spacer()
                    
                    // Google Logo from Assets
                    Image("GoogleLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                    
                    Text("Continue with Google")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
        .disabled(isLoading)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.218), value: isPressed)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.218)) {
                isHovered = hovering
            }
        }
    }
    

}

// MARK: - Category Chip Component

struct CategoryChip: View {
    let text: String
    let isActive: Bool
    
    var body: some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(isActive ? .white : .gray)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isActive ? Color.slingBlue : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isActive ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(isActive ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}

// MARK: - Modern Email Authentication View

struct EmailAuthenticationView: View {
    @ObservedObject var firestoreService: FirestoreService
    @Binding var isSignUp: Bool
    let onDismiss: () -> Void
    let onShowOnboarding: (() -> Void)?
    
    @State private var currentStep = 0
    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @StateObject private var timeTracker = TimeTracker()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Clean white background
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: {
                            if currentStep > 0 {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentStep -= 1
                                    errorMessage = ""
                                }
                            } else {
                                onDismiss()
                            }
                        }) {
                            Image(systemName: currentStep > 0 ? "chevron.left" : "xmark")
                                .font(.title2)
                                .foregroundColor(.black)
                                .frame(width: 44, height: 44)
                        }
                        
                        Spacer()
                        
                        // Progress indicator for sign up - using dashes like in the design
                        if isSignUp {
                            HStack(spacing: 8) {
                                ForEach(0..<3, id: \.self) { step in
                                    Rectangle()
                                        .fill(step <= currentStep ? Color.slingBlue : Color.gray.opacity(0.3))
                                        .frame(width: 20, height: 3)
                                        .cornerRadius(1.5)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Invisible spacer to center the title
                        Color.clear
                            .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Multi-step content
                    VStack(spacing: 0) {
                        Spacer()
                        
                        // Step content
                        Group {
                            switch currentStep {
                            case 0:
                                EmailStepView(email: $email, isSignUp: $isSignUp, password: $password)
                            case 1:
                                PasswordStepView(password: $password, isSignUp: $isSignUp)
                            case 2:
                                UserDetailsStepView(
                                    firstName: $firstName,
                                    lastName: $lastName,
                                    displayName: $displayName,
                                    isSignUp: $isSignUp
                                )
                            default:
                                EmptyView()
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        
                        Spacer()
                        
                        // Action button
                        Button(action: handleNextStep) {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(1.2)
                                } else {
                                    Text(getButtonText())
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    
                                    if currentStep < 2 || !isSignUp {
                                        Image(systemName: "arrow.right")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(getButtonBackground())
                        .cornerRadius(16)
                        .shadow(color: getButtonShadowColor(), radius: 8, x: 0, y: 4)
                        .disabled(isLoading || !canProceed())
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                        
                        // Legal disclaimer - moved up and improved
                        HStack(spacing: 4) {
                            Text("By continuing, you agree to our")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.6))
                            
                            Button(action: {
                                AnalyticsService.shared.trackAuthButtonTap(button: .termsOfService, page: .welcome)
                                
                                // Open terms of service
                                if let url = URL(string: "https://slingapp.com/terms") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 2) {
                                    Text("terms of service")
                                        .font(.caption)
                                        .foregroundColor(.gray.opacity(0.6))
                                    
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2)
                                        .foregroundColor(.gray.opacity(0.6))
                                }
                            }
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 60)
                        .padding(.bottom, 80)
                    }
                }
                
                // Error message overlay
                if !errorMessage.isEmpty {
                    VStack {
                        Spacer()
                        
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.9))
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 120)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: errorMessage)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // Track email form view
            let page: AuthPage = isSignUp ? .emailSignUp : .emailSignIn
            AnalyticsService.shared.trackAuthPageView(page: page)
            timeTracker.startTracking(for: page.rawValue)
        }
        .onDisappear {
            // Track time spent on email form
            let page: AuthPage = isSignUp ? .emailSignUp : .emailSignIn
            if let duration = timeTracker.endTracking(for: page.rawValue) {
                AnalyticsService.shared.trackPageViewTime(page: page.rawValue, timeSpent: duration)
            }
        }
    }
    
    private func getButtonText() -> String {
        if isSignUp {
            switch currentStep {
            case 0, 1:
                return "Continue"
            case 2:
                return "Create Account"
            default:
                return "Continue"
            }
        } else {
            return "Sign In"
        }
    }
    
    private func getButtonBackground() -> AnyShapeStyle {
        if isSignUp {
            switch currentStep {
            case 0, 1:
                return AnyShapeStyle(Color.slingGradient)
            case 2:
                return AnyShapeStyle(Color.slingGradient)
            default:
                return AnyShapeStyle(Color.slingGradient)
            }
        } else {
            return AnyShapeStyle(Color.slingGradient)
        }
    }
    
    private func getButtonShadowColor() -> Color {
        if isSignUp {
            switch currentStep {
            case 0, 1:
                return Color.slingBlue.opacity(0.3)
            case 2:
                return Color.slingBlue.opacity(0.3)
            default:
                return Color.slingBlue.opacity(0.3)
            }
        } else {
            return Color.slingBlue.opacity(0.3)
        }
    }
    
    private func canProceed() -> Bool {
        switch currentStep {
        case 0:
            return !email.isEmpty && email.contains("@")
        case 1:
            return password.count >= 6
        case 2:
            return !firstName.isEmpty && !lastName.isEmpty && !displayName.isEmpty
        default:
            return false
        }
    }
    
    private func handleNextStep() {
        if isSignUp {
            if currentStep < 2 {
                // Track step completion
                let step: AuthStep
                switch currentStep {
                case 0: step = .emailEntry
                case 1: step = .passwordEntry
                default: step = .emailEntry
                }
                AnalyticsService.shared.trackAuthStepCompleted(step: step, method: .email)
                
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentStep += 1
                    errorMessage = ""
                }
            } else {
                // Final step - create account
                AnalyticsService.shared.trackAuthStepCompleted(step: .userDetailsEntry, method: .email)
                handleAuthentication()
            }
        } else {
            // Sign in flow
            AnalyticsService.shared.trackAuthStepCompleted(step: .emailEntry, method: .email)
            handleAuthentication()
        }
    }
    
    private func handleAuthentication() {
        AnalyticsService.shared.trackAuthStarted(method: .email)
        isLoading = true
        errorMessage = ""
        
        if isSignUp {
            firestoreService.signUp(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName,
                displayName: formatDisplayName(displayName)
            ) { success, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if !success {
                        let errorMsg = error ?? "Failed to create account. Please try again."
                        errorMessage = errorMsg
                        AnalyticsService.shared.trackAuthFailure(method: .email, error: errorMsg)
                        SlingLogError("User sign up failed", error: nil)
                    } else {
                        AnalyticsService.shared.trackAuthSuccess(method: .email, isNewUser: true)
                        SlingLogInfo("User successfully created account")
                        // Show community onboarding for new users
                        if let onShowOnboarding = onShowOnboarding {
                            onShowOnboarding()
                        } else {
                            onDismiss()
                        }
                    }
                }
            }
        } else {
            firestoreService.signIn(email: email, password: password) { success, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if !success {
                        let errorMsg = error ?? "Failed to sign in. Please try again."
                        errorMessage = errorMsg
                        AnalyticsService.shared.trackAuthFailure(method: .email, error: errorMsg)
                        SlingLogError("User sign in failed", error: nil)
                    } else {
                        AnalyticsService.shared.trackAuthSuccess(method: .email, isNewUser: false)
                        SlingLogInfo("User successfully signed in")
                        onDismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Email Step View

struct EmailStepView: View {
    @Binding var email: String
    @Binding var isSignUp: Bool
    @Binding var password: String
    @State private var isPasswordVisible = false
    
    var body: some View {
        VStack(spacing: 32) {
            // Title
            Text(isSignUp ? "Create Account" : "Welcome back to Sling")
                .font(isSignUp ? .largeTitle : .title)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Subtitle
            if isSignUp {
                Text("Join Sling and start predicting")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            // Email input field
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.headline)
                    .foregroundColor(.black)
                
                TextField("Enter your email", text: $email)
                    .textFieldStyle(ModernTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        AnalyticsService.shared.trackFormFieldFocus(field: "email", page: isSignUp ? "email_signup" : "email_signin")
                    }
                    .onChange(of: email) { newValue in
                        let isValid = !newValue.isEmpty && newValue.contains("@")
                        AnalyticsService.shared.trackFormValidation(field: "email", page: isSignUp ? "email_signup" : "email_signin", isValid: isValid, errorType: isValid ? nil : "invalid_email")
                    }
            }
            .padding(.horizontal, 24)
            
            // Toggle button for Create Account page - moved much closer to email input
            if isSignUp {
                Button(action: {
                    AnalyticsService.shared.trackAuthButtonTap(button: .toggleToSignIn, page: .emailSignUp)
                    
                    withAnimation(.easeInOut(duration: 0.3)) {
                        // Switch to sign in
                        isSignUp = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Text("Have an account? ")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text("Sign In")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.slingBlue)
                    }
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            }
            
                            // Password input field for Sign In
                if !isSignUp {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.headline)
                            .foregroundColor(.black)
                        
                        ZStack {
                            if isPasswordVisible {
                                TextField("Enter your password", text: $password)
                                    .textFieldStyle(ModernTextFieldStyle())
                            } else {
                                SecureField("Enter your password", text: $password)
                                    .textFieldStyle(ModernTextFieldStyle())
                            }
                        }
                        .overlay(
                            HStack {
                                Spacer()
                                
                                Button(action: {
                                    isPasswordVisible.toggle()
                                }) {
                                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                        .foregroundColor(.gray)
                                        .frame(width: 24, height: 24)
                                }
                                .padding(.trailing, 20)
                            }
                        )
                    }
                    .padding(.horizontal, 24)
                    
                    // Toggle button for Sign In page - moved directly under password input
                    Button(action: {
                        AnalyticsService.shared.trackAuthButtonTap(button: .toggleToSignUp, page: .emailSignIn)
                        
                        withAnimation(.easeInOut(duration: 0.3)) {
                            // Switch to sign up
                            isSignUp = true
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("Don't have an account? ")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Text("Sign Up")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.slingBlue)
                        }
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                }
            
            Spacer()
        }
        .padding(.top, 40)
    }
}

// MARK: - Password Step View

struct PasswordStepView: View {
    @Binding var password: String
    @Binding var isSignUp: Bool
    @State private var isPasswordVisible = false
    
    var body: some View {
        VStack(spacing: 32) {
            // Title
            Text("Create a password")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Subtitle
            Text("Choose a strong password to secure your account.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Password input field
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.headline)
                    .foregroundColor(.black)
                
                ZStack {
                    if isPasswordVisible {
                        TextField("Enter your password", text: $password)
                            .textFieldStyle(ModernTextFieldStyle())
                    } else {
                        SecureField("Enter your password", text: $password)
                            .textFieldStyle(ModernTextFieldStyle())
                    }
                }
                .overlay(
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            isPasswordVisible.toggle()
                        }) {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                                .frame(width: 24, height: 24)
                        }
                        .padding(.trailing, 20)
                    }
                )
                
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

// MARK: - User Details Step View

struct UserDetailsStepView: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var displayName: String
    @Binding var isSignUp: Bool
    @State private var isUsernameAvailable = false
    @State private var isCheckingUsername = false
    @State private var showingUsernameTakenAlert = false
    
    var body: some View {
        VStack(spacing: 32) {
            // Title
            Text("Create Your Profile")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Subtitle
            Text("Help us personalize your experience")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
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
                            .padding(.leading, 16)
                        
                        TextField("username", text: $displayName)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.body)
                            .foregroundColor(.black)
                            .padding(.leading, 8)
                            .padding(.trailing, 16)
                            .onChange(of: displayName) { newValue in
                                // Remove spaces from display name
                                let formattedName = formatDisplayName(newValue)
                                if formattedName != newValue {
                                    displayName = formattedName
                                }
                                checkUsernameAvailability(formattedName)
                            }
                            .overlay(
                                HStack {
                                    Spacer()
                                    
                                    // Checkmark for username validation
                                    if !displayName.isEmpty {
                                        if isCheckingUsername {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                                                .scaleEffect(0.8)
                                                .padding(.trailing, 16)
                                        } else if isUsernameAvailable {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.slingBlue)
                                                .font(.title3)
                                                .padding(.trailing, 16)
                                        } else {
                                            Image(systemName: "xmark")
                                                .foregroundColor(.red)
                                                .font(.title3)
                                                .padding(.trailing, 16)
                                        }
                                    }
                                }
                            )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
                
                Text("This is how other users will see you")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .padding(.top, 40)
        .alert("Display Name Taken", isPresented: $showingUsernameTakenAlert) {
            Button("OK") { }
        } message: {
            Text("This display name is already taken. Please choose a different one.")
        }
    }
    
    private func checkUsernameAvailability(_ username: String) {
        guard !username.isEmpty else {
            isUsernameAvailable = false
            isCheckingUsername = false
            return
        }
        
        isCheckingUsername = true
        
        // Check Firestore for existing display names
        let db = Firestore.firestore()
        db.collection("Users")
            .whereField("display_name", isEqualTo: username)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isCheckingUsername = false
                    
                    if let error = error {
                        print("Error checking username: \(error)")
                        isUsernameAvailable = false
                        return
                    }
                    
                    // Username is available if no documents found
                    isUsernameAvailable = snapshot?.documents.isEmpty ?? true
                    
                    // Show alert if username is taken
                    if !isUsernameAvailable {
                        showingUsernameTakenAlert = true
                    }
                }
            }
    }
}

// MARK: - Modern Text Field Style

struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .font(.body)
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// MARK: - Apple Sign In Delegate

class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    let onSuccess: (ASAuthorizationAppleIDCredential) -> Void
    let onFailure: (Error) -> Void
    
    init(onSuccess: @escaping (ASAuthorizationAppleIDCredential) -> Void, onFailure: @escaping (Error) -> Void) {
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            onSuccess(appleIDCredential)
        } else {
            onFailure(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid credential"]))
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onFailure(error)
    }
}

// MARK: - Apple Sign In Presentation Context Provider

class AppleSignInPresentationContextProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available")
        }
        return window
    }
}

// MARK: - Community Onboarding View

struct CommunityOnboardingView: View {
    @ObservedObject var firestoreService: FirestoreService
    let onDismiss: () -> Void
    
    @State private var showingJoinCommunity = false
    @State private var showingCreateCommunity = false
    @StateObject private var timeTracker = TimeTracker()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    // Close button - small and grayed out as requested
                    HStack {
                        Spacer()
                        Button(action: { 
                            AnalyticsService.shared.trackAuthButtonTap(button: .skipOnboarding, page: .communityOnboarding)
                            onDismiss() 
                        }) {
                            Text("Skip")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.6))
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 20)
                    }
                    
                    // Title Section
                    VStack(spacing: 20) {
                        Image(systemName: "person.2.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.slingBlue)
                        
                        VStack(spacing: 12) {
                            Text("Join the Community")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                            
                            Text("Connect with friends and start betting together! Join an existing community or create your own.")
                                .font(.body)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 40)
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 16) {
                    // Join Community Button
                    Button(action: {
                        AnalyticsService.shared.trackAuthButtonTap(button: .joinCommunity, page: .communityOnboarding)
                        showingJoinCommunity = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.title2)
                                .foregroundColor(.white)
                            
                            Text("Join a Community")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color.slingBlue)
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    // Create Community Button
                    Button(action: {
                        AnalyticsService.shared.trackAuthButtonTap(button: .createCommunity, page: .communityOnboarding)
                        showingCreateCommunity = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle")
                                .font(.title2)
                                .foregroundColor(.slingBlue)
                            
                            Text("Create a Community")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.slingBlue)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(Color.slingBlue, lineWidth: 2)
                                .fill(Color.white)
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    // Help text
                    Text("You can always join or create more communities later in the app.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                }
                .padding(.bottom, 40)
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
        .onAppear {
            AnalyticsService.shared.trackAuthPageView(page: .communityOnboarding)
            AnalyticsService.shared.trackUserFlowStep(step: .communityOnboarding)
            timeTracker.startTracking(for: "community_onboarding")
        }
        .onDisappear {
            if let duration = timeTracker.endTracking(for: "community_onboarding") {
                AnalyticsService.shared.trackPageViewTime(page: "community_onboarding", timeSpent: duration)
            }
        }
        .sheet(isPresented: $showingJoinCommunity) {
            JoinCommunityPage(
                firestoreService: firestoreService,
                onSuccess: {
                    showingJoinCommunity = false
                    onDismiss()
                }
            )
        }
        .sheet(isPresented: $showingCreateCommunity) {
            CreateCommunityPage(
                firestoreService: firestoreService,
                onSuccess: {
                    showingCreateCommunity = false
                    onDismiss()
                }
            )
        }
    }
}
