import SwiftUI
import Firebase
import FirebaseCore
import AuthenticationServices
import CryptoKit
import GoogleSignIn

struct ContentView: View {
    @StateObject var firestoreService = FirestoreService()
    @State private var hasShownLoading = false
    
    var body: some View {
        Group {
            if !hasShownLoading {
                LoadingScreenView()
                    .onAppear {
                        // Show loading screen for at least 1.5 seconds, then check auth state
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                hasShownLoading = true
                            }
                        }
                    }
            } else if firestoreService.isAuthenticated {
                MainAppView(firestoreService: firestoreService)
            } else {
                AuthenticationView(firestoreService: firestoreService)
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
    @State private var animatedCategoryIndex = 0
    
    // Dynamic prediction categories that fade in/out
    private let predictionCategories = [
        "sports", "politics", "finance", "crypto", 
        "entertainment", "technology", "weather", "elections"
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Clean white background
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top section with app branding and dynamic message
                    VStack(spacing: 32) {
                        Spacer()
                        
                        // App Logo and Name
                        VStack(spacing: 20) {
                            Image("Logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .cornerRadius(20)
                                .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
                
                            Text("Sling")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                        }
                        
                        // Dynamic main message with fading categories
                        VStack(spacing: 16) {
                            Text("Predict on anything")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                            
                            // Fading categories display
                            HStack(spacing: 0) {
                                Text("sports")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.gray)
                                    .opacity(animatedCategoryIndex == 0 ? 1 : 0.3)
                                    .animation(.easeInOut(duration: 0.5), value: animatedCategoryIndex)
                                
                                Text(" • ")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.gray.opacity(0.6))
                                
                                Text("politics")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.gray)
                                    .opacity(animatedCategoryIndex == 1 ? 1 : 0.3)
                                    .animation(.easeInOut(duration: 0.5), value: animatedCategoryIndex)
                                
                                Text(" • ")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.gray.opacity(0.6))
                                
                                Text("finance")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.gray)
                                    .opacity(animatedCategoryIndex == 2 ? 1 : 0.3)
                                    .animation(.easeInOut(duration: 0.5), value: animatedCategoryIndex)
                            }
                        }
                        
                        Spacer()
                        
                        // Authentication Buttons - Centered Content
                        VStack(spacing: 16) {
                            // Google Sign-In Button
                            GoogleSignInButton(action: handleGoogleSignIn, isLoading: isLoading)
                            
                            // Apple Sign-In Button
                            SignInWithAppleButton(
                                onRequest: { request in
                                    request.requestedScopes = [.fullName, .email]
                                },
                                onCompletion: { result in
                                    handleAppleSignIn(result)
                                }
                            )
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 56)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                            .disabled(isLoading)
                            .overlay(
                                HStack(spacing: 16) {
                                    Image(systemName: "applelogo")
                                        .font(.title2)
                                        .foregroundColor(.black)
                                        .frame(width: 24, height: 24)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .allowsHitTesting(false)
                            )
                            
                            // Email Sign-In Button
                            Button(action: { showingEmailForm = true }) {
                                HStack(spacing: 16) {
                                    Image(systemName: "envelope.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .frame(width: 24, height: 24)
                                    
                                    Text("Sign up with Email")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .padding(.horizontal, 20)
                                .background(Color.slingGradient)
                                .cornerRadius(16)
                                .shadow(color: Color.slingBlue.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .disabled(isLoading)
                        }
                        .padding(.horizontal, 24)
                        
                        // Toggle between sign in and sign up
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isSignUp.toggle()
                                errorMessage = ""
                            }
                        }) {
                            Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.gray.opacity(0.7))
                        }
                        .padding(.top, 8)
                        
                        Spacer()
                        
                        // Legal disclaimer moved much further down
                        Text("By continuing, you acknowledge and agree to Sling's terms of service")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 40)
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
                isSignUp: isSignUp,
                onDismiss: { showingEmailForm = false }
            )
        }
        .onAppear {
            // Start the category animation
            startCategoryAnimation()
        }
    }
    
    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        isLoading = true
        errorMessage = ""
        
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                handleAppleSignInSuccess(appleIDCredential)
            } else {
                isLoading = false
                errorMessage = "Apple sign-in failed. Please try again."
            }
        case .failure(let error):
            isLoading = false
            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled:
                    // User canceled, don't show error
                    break
                case .failed:
                    errorMessage = "Apple sign-in failed. Please try again."
                case .invalidResponse:
                    errorMessage = "Invalid response from Apple. Please try again."
                case .notHandled:
                    errorMessage = "Apple sign-in not handled. Please try again."
                case .unknown:
                    errorMessage = "Unknown error occurred. Please try again."
                @unknown default:
                    errorMessage = "Apple sign-in failed. Please try again."
                }
            } else {
                errorMessage = "Apple sign-in failed. Please try again."
            }
        }
    }
    
    private func startCategoryAnimation() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedCategoryIndex = (animatedCategoryIndex + 1) % 3
            }
        }
    }
    
    private func handleAppleSignInSuccess(_ appleIDCredential: ASAuthorizationAppleIDCredential) {
        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            isLoading = false
            errorMessage = "Failed to get Apple ID token. Please try again."
            return
        }
        
        let nonce = randomNonceString()
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let credential = OAuthProvider.credential(
            withProviderID: "apple.com",
            idToken: idTokenString,
            rawNonce: nonce
        )
        
        Auth.auth().signIn(with: credential) { result, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    if let nsError = error as NSError? {
                        switch nsError.code {
                        case AuthErrorCode.accountExistsWithDifferentCredential.rawValue:
                            self.errorMessage = "An account with this email already exists. Please sign in with the original method."
                        case AuthErrorCode.invalidCredential.rawValue:
                            self.errorMessage = "Invalid credentials. Please try again."
                        case AuthErrorCode.operationNotAllowed.rawValue:
                            self.errorMessage = "Apple sign-in is not enabled. Please contact support."
                        case AuthErrorCode.networkError.rawValue:
                            self.errorMessage = "Network error. Please check your connection and try again."
                        case AuthErrorCode.userNotFound.rawValue:
                            self.errorMessage = "User not found. Please try again."
                        case AuthErrorCode.tooManyRequests.rawValue:
                            self.errorMessage = "Too many requests. Please try again later."
                        case AuthErrorCode.userDisabled.rawValue:
                            self.errorMessage = "Account disabled. Please contact support."
                        default:
                            self.errorMessage = "Authentication failed. Please try again."
                        }
                    } else {
                        self.errorMessage = "Authentication failed. Please try again."
                    }
                    return
                }
                
                guard let firebaseUser = result?.user else {
                    self.errorMessage = "Failed to get user information. Please try again."
                    return
                }
                
                // Check if user already exists in Firestore
                self.firestoreService.db.collection("Users").document(firebaseUser.email ?? "").getDocument { document, error in
                    DispatchQueue.main.async {
                        if let document = document, document.exists {
                            self.firestoreService.currentUser = try? document.data(as: FirestoreUser.self)
                        } else {
                            // Create new user profile
                            self.createAppleUserProfile(firebaseUser: firebaseUser, appleIDCredential: appleIDCredential)
                        }
                    }
                }
            }
        }
    }
    
    private func createAppleUserProfile(firebaseUser: User, appleIDCredential: ASAuthorizationAppleIDCredential) {
        let fullName = appleIDCredential.fullName
        let firstName = fullName?.givenName ?? ""
        let lastName = fullName?.familyName ?? ""
        let displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Apple Sign-In doesn't provide gender or profile picture
        let gender: String? = nil
        let profilePictureURL: String? = nil
        
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
            blitz_points: nil,
            display_name: displayName.isEmpty ? "User" : displayName,
            email: firebaseUser.email ?? "",
            first_name: firstName,
            full_name: displayName.isEmpty ? "User" : displayName,
            last_name: lastName,
            gender: gender,
            profile_picture_url: profilePictureURL,
            total_bets: nil,
            total_winnings: nil,
            id: firebaseUser.uid,
            uid: firebaseUser.uid,
            sling_points: nil
        )
        
        do {
            try self.firestoreService.db.collection("Users").document(firebaseUser.email ?? "").setData(from: userProfile)
            self.firestoreService.currentUser = userProfile
        } catch {
            self.errorMessage = "Failed to create user profile. Please try again."
        }
    }
    
    private func signInExistingAppleUser(firebaseUser: User) {
        self.firestoreService.db.collection("Users").document(firebaseUser.email ?? "").getDocument { document, error in
            DispatchQueue.main.async {
                if let document = document, document.exists {
                    self.firestoreService.currentUser = try? document.data(as: FirestoreUser.self)
                } else {
                    self.errorMessage = "Profile not found. Please contact support."
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
    
    // MARK: - Google Sign-In Functions
    
    private func handleGoogleSignIn() {
        isLoading = true
        errorMessage = ""
        
        guard let presentingViewController = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController else {
            isLoading = false
            errorMessage = "Failed to present Google Sign-In. Please try again."
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    if let nsError = error as NSError? {
                        switch nsError.code {
                        case GIDSignInError.canceled.rawValue:
                            // User canceled, don't show error
                            break
                        case GIDSignInError.hasNoAuthInKeychain.rawValue:
                            self.errorMessage = "No previous sign-in found. Please try again."
                        case GIDSignInError.unknown.rawValue:
                            self.errorMessage = "Unknown error occurred. Please try again."
                        default:
                            self.errorMessage = "Google sign-in failed. Please try again."
                        }
                    } else {
                        self.errorMessage = "Google sign-in failed. Please try again."
                    }
                    return
                }
                
                guard let user = result?.user,
                      let idToken = user.idToken?.tokenString else {
                    self.errorMessage = "Failed to get Google ID token. Please try again."
                    return
                }
                
                let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)
                
                Auth.auth().signIn(with: credential) { result, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            if let nsError = error as NSError? {
                                switch nsError.code {
                                case AuthErrorCode.accountExistsWithDifferentCredential.rawValue:
                                    self.errorMessage = "An account with this email already exists. Please sign in with the original method."
                                case AuthErrorCode.invalidCredential.rawValue:
                                    self.errorMessage = "Invalid credentials. Please try again."
                                case AuthErrorCode.operationNotAllowed.rawValue:
                                    self.errorMessage = "Google sign-in is not enabled. Please contact support."
                                case AuthErrorCode.networkError.rawValue:
                                    self.errorMessage = "Network error. Please check your connection and try again."
                                case AuthErrorCode.userNotFound.rawValue:
                                    self.errorMessage = "User not found. Please try again."
                                case AuthErrorCode.tooManyRequests.rawValue:
                                    self.errorMessage = "Too many requests. Please try again later."
                                case AuthErrorCode.userDisabled.rawValue:
                                    self.errorMessage = "Account disabled. Please contact support."
                                default:
                                    self.errorMessage = "Authentication failed. Please try again."
                                }
                            } else {
                                self.errorMessage = "Authentication failed. Please try again."
                            }
                            return
                        }
                        
                        guard let firebaseUser = result?.user else {
                            self.errorMessage = "Failed to get user information. Please try again."
                            return
                        }
                        
                        // Check if user already exists in Firestore
                        self.firestoreService.db.collection("Users").document(firebaseUser.email ?? "").getDocument { document, error in
                            DispatchQueue.main.async {
                                if let document = document, document.exists {
                                    self.firestoreService.currentUser = try? document.data(as: FirestoreUser.self)
                                } else {
                                    // Create new user profile
                                    self.createGoogleUserProfile(firebaseUser: firebaseUser, googleUser: user)
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
        let displayName = fullName.isEmpty ? "User" : fullName
        
        // Get profile picture URL if available
        // Profile picture not available in current Google Sign-In SDK version
        let profilePictureURL: String? = nil
        
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
            blitz_points: nil,
            display_name: displayName,
            email: firebaseUser.email ?? "",
            first_name: firstName,
            full_name: displayName,
            last_name: lastName,
            gender: gender,
            profile_picture_url: profilePictureURL,
            total_bets: nil,
            total_winnings: nil,
            id: firebaseUser.uid,
            uid: firebaseUser.uid,
            sling_points: nil
        )
        
        do {
            try self.firestoreService.db.collection("Users").document(firebaseUser.email ?? "").setData(from: userProfile)
            self.firestoreService.currentUser = userProfile
        } catch {
            self.errorMessage = "Failed to create user profile. Please try again."
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
    let isSignUp: Bool
    let onDismiss: () -> Void
    
    @State private var currentStep = 0
    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    
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
                                .foregroundColor(.gray)
                                .frame(width: 44, height: 44)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        // Progress indicator for sign up
                        if isSignUp {
                            HStack(spacing: 8) {
                                ForEach(0..<3, id: \.self) { step in
                                    Circle()
                                        .fill(step <= currentStep ? Color.slingBlue : Color.gray.opacity(0.3))
                                        .frame(width: 8, height: 8)
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
                                EmailStepView(email: $email, isSignUp: isSignUp)
                            case 1:
                                PasswordStepView(password: $password, isSignUp: isSignUp)
                            case 2:
                                UserDetailsStepView(
                                    firstName: $firstName,
                                    lastName: $lastName,
                                    displayName: $displayName
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
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                            } else {
                                Text(getButtonText())
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(getButtonBackground())
                        .cornerRadius(16)
                        .shadow(color: getButtonShadowColor(), radius: 8, x: 0, y: 4)
                        .disabled(isLoading || !canProceed())
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
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
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentStep += 1
                    errorMessage = ""
                }
            } else {
                // Final step - create account
                handleAuthentication()
            }
        } else {
            // Sign in flow
            handleAuthentication()
        }
    }
    
    private func handleAuthentication() {
        isLoading = true
        errorMessage = ""
        
        if isSignUp {
            firestoreService.signUp(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName,
                displayName: displayName
            ) { success, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if !success {
                        errorMessage = error ?? "Failed to create account. Please try again."
                    } else {
                        onDismiss()
                    }
                }
            }
        } else {
            firestoreService.signIn(email: email, password: password) { success, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if !success {
                        errorMessage = error ?? "Failed to sign in. Please try again."
                    } else {
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
    let isSignUp: Bool
    
    var body: some View {
        VStack(spacing: 32) {
            // Title
            Text(isSignUp ? "What's your email?" : "Welcome back to Sling")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Email input field
            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textFieldStyle(ModernTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .frame(maxWidth: .infinity)
                

            }
            .padding(.horizontal, 24)
            
            // Login prompt for sign up
            if isSignUp {
                Button(action: {}) {
                    Text("Have an account? Sign In")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Color.slingBlue)
                        .underline()
                }
            }
            
            Spacer()
        }
        .padding(.top, 40)
    }
}

// MARK: - Password Step View

struct PasswordStepView: View {
    @Binding var password: String
    let isSignUp: Bool
    
    var body: some View {
        VStack(spacing: 32) {
            // Title
            Text("Create a password")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Password input field
            VStack(spacing: 16) {
                SecureField("Password", text: $password)
                    .textFieldStyle(ModernTextFieldStyle())
                    .frame(maxWidth: .infinity)
                
                Text("Must be at least 6 characters")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
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
    
    var body: some View {
        VStack(spacing: 32) {
            // Title
            Text("Tell us about yourself")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // User details input fields
            VStack(spacing: 16) {
                TextField("First Name", text: $firstName)
                    .textFieldStyle(ModernTextFieldStyle())
                    .frame(maxWidth: .infinity)
                
                TextField("Last Name", text: $lastName)
                    .textFieldStyle(ModernTextFieldStyle())
                    .frame(maxWidth: .infinity)
                
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(ModernTextFieldStyle())
                    .frame(maxWidth: .infinity)
                
                Text("This is how other users will see you")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .padding(.top, 40)
    }
}

// MARK: - Modern Text Field Style

struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
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
