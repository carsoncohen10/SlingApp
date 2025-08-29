//
//  AppDelegate.swift
//  SlingApp
//
//  Created by Carson J Cohen on 8/6/25.
//


import UIKit
import Firebase
import FirebaseAuth
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
