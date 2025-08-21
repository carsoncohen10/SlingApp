# SlingApp Deep Linking System

## Overview
The SlingApp now supports deep linking, allowing users to share bets and communities via links that open the app directly to the relevant content.

## How It Works

### 1. Custom URL Scheme
The app registers a custom URL scheme: `sling://`

**Format:**
- **Bets:** `sling://bet/{betId}`
- **Communities:** `sling://community/{communityId}`

**Examples:**
- `sling://bet/abc123` - Opens a specific bet
- `sling://community/xyz789` - Opens a specific community

### 2. Universal Links (Web Fallback)
For users who don't have the app installed, web links are provided:
- **Bets:** `https://sling.app/bet/{betId}`
- **Communities:** `https://sling.app/community/{communityId}`

### 3. Share Functionality
When users share bets or communities, the share text now includes:
- The invite code (for communities)
- A direct app link (`sling://`)
- A web fallback link (`https://sling.app/`)

## Implementation Details

### AppDelegate.swift
- Handles incoming deep links via `application(_:open:options:)`
- Supports both custom URL schemes and universal links
- Parses URLs and routes to appropriate content

### DeepLinkManager
- Singleton class that manages pending deep links
- Provides `@Published` property for SwiftUI integration
- Handles link processing and cleanup

### MainAppView.swift
- Listens for deep link events via `onReceive`
- Automatically navigates to appropriate content
- Shows bet details or community info in modal sheets

### Views.swift
- Updated share functionality in bet and community views
- Generates proper deep links with both app and web options
- Maintains existing invite code functionality

## Usage Examples

### Sharing a Bet
When a user shares a bet, the generated text looks like:
```
Check out this bet on Sling: "Will Team A win?" created by John Doe. Join the action!

🔗 Open in app: sling://bet/abc123
🌐 Or visit: https://sling.app/bet/abc123
```

### Sharing a Community
When a user shares a community, the generated text looks like:
```
Join my community on Sling! Use invite code: INVITE123

🔗 Open in app: sling://community/xyz789
🌐 Or visit: https://sling.app/community/xyz789
```

## Technical Requirements

### Info.plist
The app includes URL scheme configuration:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.slingapp.deepLink</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>sling</string>
        </array>
    </dict>
</array>
```

### Deep Link Flow
1. User receives shared link
2. Tapping link opens app (if installed) or web browser
3. App parses link and navigates to content
4. Content loads in appropriate modal/view

## Future Enhancements
- Support for additional content types (user profiles, bet results)
- Analytics tracking for deep link usage
- A/B testing for different link formats
- Social media preview metadata for web links
