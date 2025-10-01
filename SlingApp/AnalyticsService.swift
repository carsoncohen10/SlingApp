//
//  AnalyticsService.swift
//  SlingApp
//
//  Created by Carson J Cohen on 8/6/25.
//

import Foundation
import FirebaseAnalytics
import FirebaseAuth

// MARK: - Analytics Service

class AnalyticsService: ObservableObject {
    static let shared = AnalyticsService()
    
    private init() {}
    
    // MARK: - User Properties
    
    func setUserProperties(user: FirestoreUser?) {
        guard let user = user else { return }
        
        Analytics.setUserID(user.id)
        Analytics.setUserProperty(user.email, forName: "email")
        Analytics.setUserProperty(user.display_name, forName: "display_name")
        Analytics.setUserProperty(user.first_name, forName: "first_name")
        Analytics.setUserProperty(user.last_name, forName: "last_name")
        Analytics.setUserProperty(user.gender, forName: "gender")
        Analytics.setUserProperty("\(user.blitz_points)", forName: "blitz_points")
        Analytics.setUserProperty("\(user.total_bets)", forName: "total_bets")
        Analytics.setUserProperty("\(user.total_winnings)", forName: "total_winnings")
        
        // Set custom user properties for segmentation
        Analytics.setUserProperty(user.profile_picture_url != nil ? "true" : "false", forName: "has_profile_picture")
        Analytics.setUserProperty((user.total_bets ?? 0) > 0 ? "experienced" : "new", forName: "user_type")
    }
    
    // MARK: - Authentication Events
    
    func trackAuthPageView(page: AuthPage) {
        Analytics.logEvent("auth_page_view", parameters: [
            "page_name": page.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackAuthButtonTap(button: AuthButton, page: AuthPage) {
        Analytics.logEvent("auth_button_tap", parameters: [
            "button_name": button.rawValue,
            "page_name": page.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackAuthMethodSelected(method: AuthMethod) {
        Analytics.logEvent("auth_method_selected", parameters: [
            "auth_method": method.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackAuthStarted(method: AuthMethod) {
        Analytics.logEvent("auth_started", parameters: [
            "auth_method": method.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackAuthSuccess(method: AuthMethod, isNewUser: Bool) {
        Analytics.logEvent("auth_success", parameters: [
            "auth_method": method.rawValue,
            "is_new_user": isNewUser,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackAuthFailure(method: AuthMethod, error: String) {
        Analytics.logEvent("auth_failure", parameters: [
            "auth_method": method.rawValue,
            "error_message": error,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackAuthStepCompleted(step: AuthStep, method: AuthMethod) {
        Analytics.logEvent("auth_step_completed", parameters: [
            "step_name": step.rawValue,
            "auth_method": method.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Time Tracking Events
    
    func trackPageViewTime(page: String, timeSpent: TimeInterval) {
        Analytics.logEvent("page_view_time", parameters: [
            "page_name": page,
            "time_spent_seconds": timeSpent,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackSessionStart() {
        Analytics.logEvent("session_start", parameters: [
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackSessionEnd(timeSpent: TimeInterval) {
        Analytics.logEvent("session_end", parameters: [
            "session_duration_seconds": timeSpent,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - User Flow Events
    
    func trackUserFlowStep(step: UserFlowStep, fromStep: UserFlowStep? = nil) {
        var parameters: [String: Any] = [
            "current_step": step.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let fromStep = fromStep {
            parameters["previous_step"] = fromStep.rawValue
        }
        
        Analytics.logEvent("user_flow_step", parameters: parameters)
    }
    
    func trackNavigation(from: String, to: String, method: NavigationMethod) {
        Analytics.logEvent("navigation", parameters: [
            "from_page": from,
            "to_page": to,
            "navigation_method": method.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Form Interaction Events
    
    func trackFormFieldFocus(field: String, page: String) {
        Analytics.logEvent("form_field_focus", parameters: [
            "field_name": field,
            "page_name": page,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackFormFieldBlur(field: String, page: String, hasValue: Bool) {
        Analytics.logEvent("form_field_blur", parameters: [
            "field_name": field,
            "page_name": page,
            "has_value": hasValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackFormValidation(field: String, page: String, isValid: Bool, errorType: String? = nil) {
        var parameters: [String: Any] = [
            "field_name": field,
            "page_name": page,
            "is_valid": isValid,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let errorType = errorType {
            parameters["error_type"] = errorType
        }
        
        Analytics.logEvent("form_validation", parameters: parameters)
    }
    
    // MARK: - Error Tracking
    
    func trackError(error: String, context: String, severity: ErrorSeverity) {
        Analytics.logEvent("app_error", parameters: [
            "error_message": error,
            "context": context,
            "severity": severity.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackDetailedError(error: String, context: String, severity: ErrorSeverity, additionalInfo: [String: Any] = [:]) {
        var parameters: [String: Any] = [
            "error_message": error,
            "context": context,
            "severity": severity.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Add any additional error information
        for (key, value) in additionalInfo {
            parameters[key] = value
        }
        
        Analytics.logEvent("app_error_detailed", parameters: parameters)
    }
    
    func trackNetworkError(error: String, endpoint: String, method: String, statusCode: Int? = nil, responseTime: TimeInterval? = nil) {
        var parameters: [String: Any] = [
            "error_message": error,
            "endpoint": endpoint,
            "method": method,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let statusCode = statusCode {
            parameters["status_code"] = statusCode
        }
        
        if let responseTime = responseTime {
            parameters["response_time"] = responseTime
        }
        
        Analytics.logEvent("network_error", parameters: parameters)
    }
    
    func trackValidationError(field: String, value: String, rule: String, page: String) {
        Analytics.logEvent("validation_error", parameters: [
            "field": field,
            "value": value,
            "rule": rule,
            "page": page,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackAuthenticationError(error: String, method: String, isRetry: Bool = false) {
        Analytics.logEvent("auth_error", parameters: [
            "error_message": error,
            "auth_method": method,
            "is_retry": isRetry,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackFirestoreError(operation: String, collection: String, document: String? = nil, error: String) {
        var parameters: [String: Any] = [
            "operation": operation,
            "collection": collection,
            "error_message": error,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let document = document {
            parameters["document"] = document
        }
        
        Analytics.logEvent("firestore_error", parameters: parameters)
    }
    
    // MARK: - Main App Events
    
    func trackTabSwitch(fromTab: String, toTab: String) {
        Analytics.logEvent("tab_switch", parameters: [
            "from_tab": fromTab,
            "to_tab": toTab,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackBetInteraction(action: BetAction, betId: String, betTitle: String, communityName: String? = nil) {
        var parameters: [String: Any] = [
            "action": action.rawValue,
            "bet_id": betId,
            "bet_title": betTitle,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let communityName = communityName {
            parameters["community_name"] = communityName
        }
        
        Analytics.logEvent("bet_interaction", parameters: parameters)
    }
    
    func trackBettingAction(betId: String, option: String, amount: Int, odds: String) {
        Analytics.logEvent("betting_action", parameters: [
            "bet_id": betId,
            "option": option,
            "amount": amount,
            "odds": odds,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackCommunityInteraction(action: CommunityAction, communityId: String, communityName: String) {
        Analytics.logEvent("community_interaction", parameters: [
            "action": action.rawValue,
            "community_id": communityId,
            "community_name": communityName,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackFilterUsage(filterType: String, filterValue: String, page: String) {
        Analytics.logEvent("filter_usage", parameters: [
            "filter_type": filterType,
            "filter_value": filterValue,
            "page": page,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackContentEngagement(contentType: String, contentId: String, action: String, duration: TimeInterval? = nil) {
        var parameters: [String: Any] = [
            "content_type": contentType,
            "content_id": contentId,
            "action": action,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let duration = duration {
            parameters["duration_seconds"] = duration
        }
        
        Analytics.logEvent("content_engagement", parameters: parameters)
    }
    
    func trackFeatureUsage(feature: String, context: String? = nil) {
        var parameters: [String: Any] = [
            "feature": feature,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let context = context {
            parameters["context"] = context
        }
        
        Analytics.logEvent("feature_usage", parameters: parameters)
    }
    
    func trackSearchQuery(query: String, resultsCount: Int, page: String) {
        Analytics.logEvent("search_query", parameters: [
            "query": query,
            "results_count": resultsCount,
            "page": page,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackShareAction(contentType: String, contentId: String, method: String) {
        Analytics.logEvent("share_action", parameters: [
            "content_type": contentType,
            "content_id": contentId,
            "share_method": method,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Notifications Events
    
    func trackNotificationInteraction(action: NotificationAction, notificationId: String, notificationType: String) {
        Analytics.logEvent("notification_interaction", parameters: [
            "action": action.rawValue,
            "notification_id": notificationId,
            "notification_type": notificationType,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackNotificationFilter(filter: String) {
        Analytics.logEvent("notification_filter", parameters: [
            "filter_type": filter,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackNotificationMarkAllRead(count: Int) {
        Analytics.logEvent("notification_mark_all_read", parameters: [
            "notifications_count": count,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Profile Events
    
    func trackProfileInteraction(action: ProfileAction, profileId: String, profileType: String) {
        Analytics.logEvent("profile_interaction", parameters: [
            "action": action.rawValue,
            "profile_id": profileId,
            "profile_type": profileType,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackProfileTabSwitch(fromTab: String, toTab: String, profileId: String) {
        Analytics.logEvent("profile_tab_switch", parameters: [
            "from_tab": fromTab,
            "to_tab": toTab,
            "profile_id": profileId,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackProfileEdit(field: String, profileId: String) {
        Analytics.logEvent("profile_edit", parameters: [
            "field": field,
            "profile_id": profileId,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackProfileImageAction(action: String, profileId: String) {
        Analytics.logEvent("profile_image_action", parameters: [
            "action": action,
            "profile_id": profileId,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackProfileStatsView(statType: String, profileId: String) {
        Analytics.logEvent("profile_stats_view", parameters: [
            "stat_type": statType,
            "profile_id": profileId,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Settings Events
    
    func trackSettingsInteraction(action: SettingsAction, settingType: String, settingValue: String? = nil) {
        var parameters: [String: Any] = [
            "action": action.rawValue,
            "setting_type": settingType,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let value = settingValue {
            parameters["setting_value"] = value
        }
        
        Analytics.logEvent("settings_interaction", parameters: parameters)
    }
    
    func trackSettingsSectionView(section: String) {
        Analytics.logEvent("settings_section_view", parameters: [
            "section": section,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackSettingsPreferenceChange(setting: String, oldValue: String, newValue: String) {
        Analytics.logEvent("settings_preference_change", parameters: [
            "setting": setting,
            "old_value": oldValue,
            "new_value": newValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Profile Edit Events
    
    func trackProfileEditAction(action: ProfileEditAction, field: String? = nil) {
        var parameters: [String: Any] = [
            "action": action.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let field = field {
            parameters["field"] = field
        }
        
        Analytics.logEvent("profile_edit_action", parameters: parameters)
    }
    
    func trackProfileImageUpload(method: String, success: Bool, error: String? = nil) {
        var parameters: [String: Any] = [
            "upload_method": method,
            "success": success,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let error = error {
            parameters["error"] = error
        }
        
        Analytics.logEvent("profile_image_upload", parameters: parameters)
    }
    
    func trackProfileFieldEdit(field: String, oldValue: String, newValue: String) {
        Analytics.logEvent("profile_field_edit", parameters: [
            "field": field,
            "old_value": oldValue,
            "new_value": newValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackProfileSave(success: Bool, fieldsChanged: [String], error: String? = nil) {
        var parameters: [String: Any] = [
            "success": success,
            "fields_changed": fieldsChanged.joined(separator: ","),
            "fields_count": fieldsChanged.count,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let error = error {
            parameters["error"] = error
        }
        
        Analytics.logEvent("profile_save", parameters: parameters)
    }
    
    // MARK: - Chat Events
    
    func trackChatInteraction(action: ChatAction, communityId: String, communityName: String, messageId: String? = nil) {
        var parameters: [String: Any] = [
            "action": action.rawValue,
            "community_id": communityId,
            "community_name": communityName,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let messageId = messageId {
            parameters["message_id"] = messageId
        }
        
        Analytics.logEvent("chat_interaction", parameters: parameters)
    }
    
    func trackMessageSend(communityId: String, communityName: String, messageLength: Int, success: Bool) {
        Analytics.logEvent("message_send", parameters: [
            "community_id": communityId,
            "community_name": communityName,
            "message_length": messageLength,
            "success": success,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackChatCommunitySelect(communityId: String, communityName: String, unreadCount: Int) {
        Analytics.logEvent("chat_community_select", parameters: [
            "community_id": communityId,
            "community_name": communityName,
            "unread_count": unreadCount,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackChatFilter(filterType: String, filterValue: String) {
        Analytics.logEvent("chat_filter", parameters: [
            "filter_type": filterType,
            "filter_value": filterValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - My Bets Events
    
    func trackMyBetsInteraction(action: MyBetsAction, betId: String, betTitle: String, betStatus: String? = nil) {
        var parameters: [String: Any] = [
            "action": action.rawValue,
            "bet_id": betId,
            "bet_title": betTitle,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let betStatus = betStatus {
            parameters["bet_status"] = betStatus
        }
        
        Analytics.logEvent("my_bets_interaction", parameters: parameters)
    }
    
    func trackBetFilter(filterType: String, filterValue: String, betCount: Int) {
        Analytics.logEvent("bet_filter", parameters: [
            "filter_type": filterType,
            "filter_value": filterValue,
            "bet_count": betCount,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackBetStatsView(statType: String, value: Int) {
        Analytics.logEvent("bet_stats_view", parameters: [
            "stat_type": statType,
            "value": value,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackBetManagement(action: String, betId: String, betTitle: String, details: [String: Any] = [:]) {
        var parameters: [String: Any] = [
            "action": action,
            "bet_id": betId,
            "bet_title": betTitle,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Add any additional details
        for (key, value) in details {
            parameters[key] = value
        }
        
        Analytics.logEvent("bet_management", parameters: parameters)
    }
    
    // MARK: - Communities Events
    
    func trackCommunitiesInteraction(action: CommunitiesAction, communityId: String? = nil, communityName: String? = nil, details: [String: Any] = [:]) {
        var parameters: [String: Any] = [
            "action": action.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let communityId = communityId {
            parameters["community_id"] = communityId
        }
        
        if let communityName = communityName {
            parameters["community_name"] = communityName
        }
        
        // Add any additional details
        for (key, value) in details {
            parameters[key] = value
        }
        
        Analytics.logEvent("communities_interaction", parameters: parameters)
    }
    
    func trackCommunityJoin(communityId: String, communityName: String, method: String, success: Bool) {
        Analytics.logEvent("community_join", parameters: [
            "community_id": communityId,
            "community_name": communityName,
            "join_method": method,
            "success": success,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackCommunityCreate(communityName: String, memberCount: Int, success: Bool, error: String? = nil) {
        var parameters: [String: Any] = [
            "community_name": communityName,
            "member_count": memberCount,
            "success": success,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let error = error {
            parameters["error"] = error
        }
        
        Analytics.logEvent("community_create", parameters: parameters)
    }
    
    func trackCommunityLeave(communityId: String, communityName: String, reason: String? = nil) {
        var parameters: [String: Any] = [
            "community_id": communityId,
            "community_name": communityName,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let reason = reason {
            parameters["reason"] = reason
        }
        
        Analytics.logEvent("community_leave", parameters: parameters)
    }
    
    func trackCommunityView(communityId: String, communityName: String, memberCount: Int, betCount: Int) {
        Analytics.logEvent("community_view", parameters: [
            "community_id": communityId,
            "community_name": communityName,
            "member_count": memberCount,
            "bet_count": betCount,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackCommunitySearch(query: String, resultsCount: Int) {
        Analytics.logEvent("community_search", parameters: [
            "search_query": query,
            "results_count": resultsCount,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackCommunityFilter(filterType: String, filterValue: String, resultsCount: Int) {
        Analytics.logEvent("community_filter", parameters: [
            "filter_type": filterType,
            "filter_value": filterValue,
            "results_count": resultsCount,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackCommunityBalanceView(communityId: String, communityName: String, balanceAmount: Double, balanceType: String) {
        Analytics.logEvent("community_balance_view", parameters: [
            "community_id": communityId,
            "community_name": communityName,
            "balance_amount": balanceAmount,
            "balance_type": balanceType,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Community Detail Events
    
    func trackCommunityDetailInteraction(action: CommunityDetailAction, communityId: String, communityName: String, details: [String: Any] = [:]) {
        var parameters: [String: Any] = [
            "action": action.rawValue,
            "community_id": communityId,
            "community_name": communityName,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Add any additional details
        for (key, value) in details {
            parameters[key] = value
        }
        
        Analytics.logEvent("community_detail_interaction", parameters: parameters)
    }
    
    func trackCommunityTabSwitch(communityId: String, communityName: String, fromTab: String, toTab: String) {
        Analytics.logEvent("community_tab_switch", parameters: [
            "community_id": communityId,
            "community_name": communityName,
            "from_tab": fromTab,
            "to_tab": toTab,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackCommunityMemberInteraction(action: String, communityId: String, communityName: String, memberEmail: String, memberName: String) {
        Analytics.logEvent("community_member_interaction", parameters: [
            "action": action,
            "community_id": communityId,
            "community_name": communityName,
            "member_email": memberEmail,
            "member_name": memberName,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackCommunityBetInteraction(action: String, communityId: String, communityName: String, betId: String, betTitle: String) {
        Analytics.logEvent("community_bet_interaction", parameters: [
            "action": action,
            "community_id": communityId,
            "community_name": communityName,
            "bet_id": betId,
            "bet_title": betTitle,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackCommunitySettingsAction(action: String, communityId: String, communityName: String, settingType: String) {
        Analytics.logEvent("community_settings_action", parameters: [
            "action": action,
            "community_id": communityId,
            "community_name": communityName,
            "setting_type": settingType,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackCommunityInviteAction(action: String, communityId: String, communityName: String, inviteMethod: String) {
        Analytics.logEvent("community_invite_action", parameters: [
            "action": action,
            "community_id": communityId,
            "community_name": communityName,
            "invite_method": inviteMethod,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackCommunityImageAction(action: String, communityId: String, communityName: String, imageSource: String) {
        Analytics.logEvent("community_image_action", parameters: [
            "action": action,
            "community_id": communityId,
            "community_name": communityName,
            "image_source": imageSource,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Performance Metrics
    
    func trackPerformanceMetric(metric: String, value: Double, unit: String, context: String? = nil) {
        var parameters: [String: Any] = [
            "metric": metric,
            "value": value,
            "unit": unit,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let context = context {
            parameters["context"] = context
        }
        
        Analytics.logEvent("performance_metric", parameters: parameters)
    }
    
    func trackEngagementMetric(action: String, duration: TimeInterval, context: String? = nil, additionalData: [String: Any] = [:]) {
        var parameters: [String: Any] = [
            "action": action,
            "duration_seconds": duration,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let context = context {
            parameters["context"] = context
        }
        
        // Add any additional engagement data
        for (key, value) in additionalData {
            parameters[key] = value
        }
        
        Analytics.logEvent("engagement_metric", parameters: parameters)
    }
    
    func trackAppPerformance(startTime: Date, endTime: Date, operation: String, success: Bool, additionalInfo: [String: Any] = [:]) {
        let duration = endTime.timeIntervalSince(startTime)
        
        var parameters: [String: Any] = [
            "operation": operation,
            "duration_seconds": duration,
            "success": success,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Add any additional performance info
        for (key, value) in additionalInfo {
            parameters[key] = value
        }
        
        Analytics.logEvent("app_performance", parameters: parameters)
    }
    
    func trackUserRetention(daysSinceFirstUse: Int, sessionsCount: Int, lastActiveDate: Date) {
        Analytics.logEvent("user_retention", parameters: [
            "days_since_first_use": daysSinceFirstUse,
            "sessions_count": sessionsCount,
            "last_active_date": lastActiveDate.timeIntervalSince1970,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    func trackFeatureAdoption(feature: String, isFirstTime: Bool, context: String? = nil) {
        var parameters: [String: Any] = [
            "feature": feature,
            "is_first_time": isFirstTime,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let context = context {
            parameters["context"] = context
        }
        
        Analytics.logEvent("feature_adoption", parameters: parameters)
    }
    
    // MARK: - Custom Events
    
    func trackCustomEvent(eventName: String, parameters: [String: Any] = [:]) {
        var eventParameters = parameters
        eventParameters["timestamp"] = Date().timeIntervalSince1970
        
        Analytics.logEvent(eventName, parameters: eventParameters)
    }
}

// MARK: - Analytics Enums

enum AuthPage: String, CaseIterable {
    case welcome = "welcome"
    case emailSignUp = "email_signup"
    case emailSignIn = "email_signin"
    case passwordStep = "password_step"
    case userDetailsStep = "user_details_step"
    case communityOnboarding = "community_onboarding"
}

enum AuthButton: String, CaseIterable {
    case googleSignIn = "google_signin"
    case appleSignIn = "apple_signin"
    case emailSignUp = "email_signup"
    case emailSignIn = "email_signin"
    case continueButton = "continue_button"
    case createAccount = "create_account"
    case signInButton = "signin_button"
    case toggleToSignIn = "toggle_to_signin"
    case toggleToSignUp = "toggle_to_signup"
    case joinCommunity = "join_community"
    case createCommunity = "create_community"
    case skipOnboarding = "skip_onboarding"
    case termsOfService = "terms_of_service"
}

enum AuthMethod: String, CaseIterable {
    case google = "google"
    case apple = "apple"
    case email = "email"
}

enum AuthStep: String, CaseIterable {
    case emailEntry = "email_entry"
    case passwordEntry = "password_entry"
    case userDetailsEntry = "user_details_entry"
    case accountCreation = "account_creation"
    case signIn = "signin"
}

enum UserFlowStep: String, CaseIterable {
    case appLaunch = "app_launch"
    case loadingScreen = "loading_screen"
    case welcomeScreen = "welcome_screen"
    case authentication = "authentication"
    case emailForm = "email_form"
    case communityOnboarding = "community_onboarding"
    case mainApp = "main_app"
    case homeTab = "home_tab"
    case chatTab = "chat_tab"
    case myBetsTab = "my_bets_tab"
    case communitiesTab = "communities_tab"
    case createBet = "create_bet"
    case joinBet = "join_bet"
    case viewBet = "view_bet"
    case shareBet = "share_bet"
    case notifications = "notifications"
    case profile = "profile"
    case profileEdit = "profile_edit"
    case settings = "settings"
}

enum NavigationMethod: String, CaseIterable {
    case buttonTap = "button_tap"
    case backButton = "back_button"
    case swipe = "swipe"
    case deepLink = "deep_link"
    case automatic = "automatic"
}

enum ErrorSeverity: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum BetAction: String, CaseIterable {
    case view = "view"
    case join = "join"
    case share = "share"
    case create = "create"
    case edit = "edit"
    case delete = "delete"
    case placeBet = "place_bet"
    case chooseWinner = "choose_winner"
}

enum CommunityAction: String, CaseIterable {
    case view = "view"
    case join = "join"
    case leave = "leave"
    case create = "create"
    case edit = "edit"
    case delete = "delete"
    case invite = "invite"
    case acceptInvite = "accept_invite"
    case declineInvite = "decline_invite"
}

enum NotificationAction: String, CaseIterable {
    case view = "view"
    case tap = "tap"
    case markRead = "mark_read"
    case markUnread = "mark_unread"
    case delete = "delete"
    case filter = "filter"
    case markAllRead = "mark_all_read"
}

enum ProfileAction: String, CaseIterable {
    case view = "view"
    case edit = "edit"
    case share = "share"
    case settings = "settings"
    case imageTap = "image_tap"
    case imageChange = "image_change"
    case statsView = "stats_view"
    case tabSwitch = "tab_switch"
    case betView = "bet_view"
    case activityView = "activity_view"
}

enum SettingsAction: String, CaseIterable {
    case view = "view"
    case tap = "tap"
    case toggle = "toggle"
    case change = "change"
    case save = "save"
    case cancel = "cancel"
    case reset = "reset"
    case delete = "delete"
    case export = "export"
    case importData = "import"
}

enum ProfileEditAction: String, CaseIterable {
    case open = "open"
    case close = "close"
    case save = "save"
    case cancel = "cancel"
    case fieldEdit = "field_edit"
    case imageSelect = "image_select"
    case imageUpload = "image_upload"
    case imageRemove = "image_remove"
    case validationError = "validation_error"
    case unsavedChanges = "unsaved_changes"
}

enum ChatAction: String, CaseIterable {
    case view = "view"
    case send = "send"
    case receive = "receive"
    case communitySelect = "community_select"
    case messageTap = "message_tap"
    case messageLongPress = "message_long_press"
    case filter = "filter"
    case search = "search"
    case markRead = "mark_read"
    case markUnread = "mark_unread"
    case delete = "delete"
    case edit = "edit"
    case reply = "reply"
    case share = "share"
}

enum MyBetsAction: String, CaseIterable {
    case view = "view"
    case filter = "filter"
    case sort = "sort"
    case betTap = "bet_tap"
    case betEdit = "bet_edit"
    case betDelete = "bet_delete"
    case betShare = "bet_share"
    case betSettle = "bet_settle"
    case betCancel = "bet_cancel"
    case statsView = "stats_view"
    case createBet = "create_bet"
    case joinBet = "join_bet"
    case leaveBet = "leave_bet"
    case viewDetails = "view_details"
    case viewHistory = "view_history"
}

enum CommunitiesAction: String, CaseIterable {
    case view = "view"
    case create = "create"
    case join = "join"
    case leave = "leave"
    case search = "search"
    case filter = "filter"
    case sort = "sort"
    case communityTap = "community_tap"
    case communityView = "community_view"
    case balanceView = "balance_view"
    case settings = "settings"
    case invite = "invite"
    case share = "share"
    case refresh = "refresh"
    case menuOpen = "menu_open"
    case menuClose = "menu_close"
}

enum CommunityDetailAction: String, CaseIterable {
    case view = "view"
    case back = "back"
    case tabSwitch = "tab_switch"
    case memberTap = "member_tap"
    case memberProfile = "member_profile"
    case betTap = "bet_tap"
    case betCreate = "bet_create"
    case betJoin = "bet_join"
    case betLeave = "bet_leave"
    case settings = "settings"
    case invite = "invite"
    case share = "share"
    case leave = "leave"
    case delete = "delete"
    case imageChange = "image_change"
    case imageView = "image_view"
    case filter = "filter"
    case sort = "sort"
    case refresh = "refresh"
    case menuOpen = "menu_open"
    case menuClose = "menu_close"
    case balanceView = "balance_view"
    case transactionHistory = "transaction_history"
}

// MARK: - Time Tracking Helper

class TimeTracker: ObservableObject {
    private var startTimes: [String: Date] = [:]
    
    func startTracking(for key: String) {
        startTimes[key] = Date()
    }
    
    func endTracking(for key: String) -> TimeInterval? {
        guard let startTime = startTimes[key] else { return nil }
        let duration = Date().timeIntervalSince(startTime)
        startTimes.removeValue(forKey: key)
        return duration
    }
    
    func getCurrentDuration(for key: String) -> TimeInterval? {
        guard let startTime = startTimes[key] else { return nil }
        return Date().timeIntervalSince(startTime)
    }
}
