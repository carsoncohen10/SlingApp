//
//  SlingAppApp.swift
//  SlingApp
//
//  Created by Carson J Cohen on 8/5/25.
//

import SwiftUI
import Firebase
import FirebaseCore
import FirebaseAuth

@main
struct SlingAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
