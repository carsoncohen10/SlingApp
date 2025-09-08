//
//  AppDelegate.swift
//  SlingApp
//
//  Created by Carson J Cohen on 8/6/25.
//


import UIKit
import Firebase
import FirebaseAuth
import FirebaseAnalytics
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Configure Firebase
        FirebaseApp.configure()
        
        // Configure Google Sign-In
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            print("❌ Failed to load GoogleService-Info.plist or CLIENT_ID")
            return true
        }
        
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        
        // Verify Firebase is properly initialized
        if let app = FirebaseApp.app() {
            print("✅ Firebase successfully initialized for project: \(app.options.projectID ?? "unknown")")
        } else {
            print("❌ Firebase failed to initialize")
        }
        
        // Test Firebase Auth availability
        Auth.auth().addStateDidChangeListener { auth, user in
            if let user = user {
                print("✅ Firebase Auth state changed - User signed in: \(user.email ?? "unknown")")
            } else {
                print("ℹ️ Firebase Auth state changed - No user signed in")
            }
        }
        
        // Setup Error Logging System
        ErrorLogger.shared.setupErrorLogging()
        
        // Initialize Analytics Service
        AnalyticsService.shared.trackSessionStart()
        
        return true
    }
    
    // Handle deep links when app is already running
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("🔗 Deep link opened: \(url)")
        
        // Handle Google Sign-In URL
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        
        handleDeepLink(url: url)
        return true
    }
    
    // Handle deep links when app is launched from a link
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            print("🔗 Universal link opened: \(url)")
            handleDeepLink(url: url)
            return true
        }
        return false
    }
    
    private func handleDeepLink(url: URL) {
        print("🔗 Processing deep link: \(url)")
        
        // Handle custom URL scheme (sling://)
        if url.scheme == "sling" {
            handleCustomSchemeDeepLink(url: url)
        } else {
            // Handle universal links (https://)
            handleUniversalLink(url: url)
        }
    }
    
    private func handleCustomSchemeDeepLink(url: URL) {
        // Extract path components for custom scheme
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        if pathComponents.count >= 2 {
            let entityType = pathComponents[0] // "bet" or "community"
            let entityId = pathComponents[1]
            
            print("🔗 Custom scheme deep link parsed - Type: \(entityType), ID: \(entityId)")
            
            // Store the deep link info for the app to handle
            DeepLinkManager.shared.handleDeepLink(type: entityType, id: entityId)
        } else {
            print("❌ Invalid custom scheme deep link format: \(url)")
        }
    }
    
    private func handleUniversalLink(url: URL) {
        // Extract path components for universal link
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        if pathComponents.count >= 2 {
            let entityType = pathComponents[0] // "bet" or "community"
            let entityId = pathComponents[1]
            
            print("🔗 Universal link parsed - Type: \(entityType), ID: \(entityId)")
            
            // Store the deep link info for the app to handle
            DeepLinkManager.shared.handleDeepLink(type: entityType, id: entityId)
        } else {
            print("❌ Invalid universal link format: \(url)")
        }
    }
}

// MARK: - Deep Link Manager

class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    @Published var pendingDeepLink: DeepLink?
    
    private init() {}
    
    func handleDeepLink(type: String, id: String) {
        let deepLink = DeepLink(type: type, id: id)
        DispatchQueue.main.async {
            self.pendingDeepLink = deepLink
        }
    }
    
    func clearPendingDeepLink() {
        pendingDeepLink = nil
    }
}

// MARK: - Deep Link Model

struct DeepLink {
    let type: String // "bet" or "community"
    let id: String
}

// MARK: - Error Logger

class ErrorLogger {
    static let shared = ErrorLogger()
    private var firestoreService: FirestoreService?
    
    private init() {}
    
    func setupErrorLogging() {
        print("🔧 Setting up error logging system...")
        
        // Setup global exception handler
        NSSetUncaughtExceptionHandler { exception in
            ErrorLogger.shared.logCriticalError(
                message: "Uncaught Exception: \(exception.name.rawValue)",
                stackTrace: exception.callStackSymbols.joined(separator: "\n")
            )
        }
        
        // Setup signal handler for crashes
        signal(SIGABRT) { signal in
            ErrorLogger.shared.logCriticalError(message: "SIGABRT signal received")
        }
        signal(SIGILL) { signal in
            ErrorLogger.shared.logCriticalError(message: "SIGILL signal received")
        }
        signal(SIGSEGV) { signal in
            ErrorLogger.shared.logCriticalError(message: "SIGSEGV signal received")
        }
        signal(SIGFPE) { signal in
            ErrorLogger.shared.logCriticalError(message: "SIGFPE signal received")
        }
        signal(SIGBUS) { signal in
            ErrorLogger.shared.logCriticalError(message: "SIGBUS signal received")
        }
        signal(SIGPIPE) { signal in
            ErrorLogger.shared.logCriticalError(message: "SIGPIPE signal received")
        }
        
        // Override print function to capture console logs
        setupConsoleCaptureIfNeeded()
        
        print("✅ Error logging system setup complete")
    }
    
    func setFirestoreService(_ service: FirestoreService) {
        self.firestoreService = service
    }
    
    private func setupConsoleCaptureIfNeeded() {
        // Create a custom log handler that captures print statements
        // This is a simplified approach - for production you might want to use os_log
        
        // Override Swift's print function would be complex, so instead we'll
        // provide helper functions that apps can use
        print("📝 Console capture ready - use SlingLog functions for automatic logging")
    }
    
    private func logCriticalError(message: String, stackTrace: String? = nil) {
        print("🚨 CRITICAL ERROR: \(message)")
        
        // Store the error for later upload if FirestoreService isn't available yet
        if let firestoreService = firestoreService {
            firestoreService.logError(
                message: message,
                type: "critical_error",
                level: "critical",
                stackTrace: stackTrace
            )
        } else {
            // Store for later if service not available
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if let firestoreService = self.firestoreService {
                    firestoreService.logError(
                        message: message,
                        type: "critical_error",
                        level: "critical",
                        stackTrace: stackTrace
                    )
                }
            }
        }
    }
    
    // Public logging functions that apps can use instead of print
    func logInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        print("ℹ️ \(message)")
        firestoreService?.logConsoleMessage(
            message: message,
            level: "info",
            functionName: function,
            fileName: file,
            lineNumber: line
        )
    }
    
    func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        print("⚠️ WARNING: \(message)")
        firestoreService?.logConsoleMessage(
            message: message,
            level: "warning",
            functionName: function,
            fileName: file,
            lineNumber: line
        )
    }
    
    func logError(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        print("❌ ERROR: \(message)")
        if let error = error {
            print("   Details: \(error.localizedDescription)")
        }
        
        var context: [String: String] = [:]
        if let error = error {
            context["error_details"] = error.localizedDescription
        }
        
        firestoreService?.logError(
            message: message,
            type: "runtime_error",
            level: "error",
            functionName: function,
            fileName: file,
            lineNumber: line,
            additionalContext: context
        )
    }
}

// MARK: - Global Logging Functions

// Global convenience functions for easy logging throughout the app
func SlingLogInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    ErrorLogger.shared.logInfo(message, file: file, function: function, line: line)
}

func SlingLogWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    ErrorLogger.shared.logWarning(message, file: file, function: function, line: line)
}

func SlingLogError(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
    ErrorLogger.shared.logError(message, error: error, file: file, function: function, line: line)
}
