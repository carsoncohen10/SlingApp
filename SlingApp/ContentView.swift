import SwiftUI
import Firebase
import FirebaseCore

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

// MARK: - Authentication View

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
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 60))
                            .foregroundColor(Color(uiColor: UIColor(red: 0x26/255.0, green: 0x63/255.0, blue: 0xEB/255.0, alpha: 1.0)))
                    
                    Text("Sling")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(isSignUp ? "Create your account" : "Welcome back")
                .font(.title2)
                    .foregroundColor(.gray)
                }
                
                // Form
                VStack(spacing: 20) {
                    if isSignUp {
                        TextField("First Name", text: $firstName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        TextField("Last Name", text: $lastName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                        TextField("Display Name", text: $displayName)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    TextField("Email", text: $email)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                                    
                    SecureField("Password", text: $password)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                                        .font(.caption)
                    }
                    
                    Button(action: handleAuthentication) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(isSignUp ? "Sign Up" : "Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                        .frame(maxWidth: .infinity)
                    .padding()
                        .background(Color.slingGradient)
                    .foregroundColor(.white)
                        .cornerRadius(10)
                    .disabled(isLoading)
            }
            .padding(.horizontal, 20)
                
                // Toggle between sign in and sign up
                Button(action: {
                    withAnimation {
                        isSignUp.toggle()
                        errorMessage = ""
                    }
                }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .foregroundColor(Color(uiColor: UIColor(red: 0x26/255.0, green: 0x63/255.0, blue: 0xEB/255.0, alpha: 1.0)))
                        }
                        
                        Spacer()
                    }
            .padding(.top, 50)
        }
    }
    
    private func handleAuthentication() {
        isLoading = true
        errorMessage = ""
        
        if isSignUp {
            // Validate sign up fields
            guard !firstName.isEmpty, !lastName.isEmpty, !displayName.isEmpty else {
                errorMessage = "Please fill in all fields"
                isLoading = false
                return
            }
            
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
                    }
                }
            }
        } else {
            firestoreService.signIn(email: email, password: password) { success, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if !success {
                        errorMessage = error ?? "Failed to sign in. Please try again."
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
