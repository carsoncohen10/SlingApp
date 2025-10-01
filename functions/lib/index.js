"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendReminderNotification = exports.sendBetVoidedNotification = exports.sendBetSettledNotification = exports.sendBetNotification = exports.sendChatNotification = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
// Initialize Firebase Admin SDK
if (!admin.apps.length) {
    admin.initializeApp({
        projectId: "sling-caff4"
    });
}
/**
 * Cloud Function triggered when a new chat message is created
 * Automatically sends push notifications to all chat members except the sender
 *
 * Note: Messages are stored in community.chat_history.{messageId} field,
 * so we listen to community document updates and check for new messages
 */
exports.sendChatNotification = (0, firestore_1.onDocumentUpdated)("community/{communityId}", async (event) => {
    var _a, _b, _c, _d;
    console.log("🔥 Community document updated, checking for new chat messages...");
    const beforeData = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before) === null || _b === void 0 ? void 0 : _b.data();
    const afterData = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.after) === null || _d === void 0 ? void 0 : _d.data();
    const communityId = event.params.communityId;
    if (!beforeData || !afterData) {
        console.log("❌ No document data found");
        return;
    }
    // Check if chat_history was updated
    const beforeChatHistory = beforeData.chat_history || {};
    const afterChatHistory = afterData.chat_history || {};
    // Find new messages by comparing before and after
    const newMessages = [];
    for (const [messageId, messageData] of Object.entries(afterChatHistory)) {
        if (!beforeChatHistory[messageId]) {
            newMessages.push(Object.assign({ id: messageId }, messageData));
        }
    }
    if (newMessages.length === 0) {
        console.log("📱 No new messages found in this update");
        return;
    }
    console.log(`📱 Found ${newMessages.length} new message(s)`);
    // Process the most recent message
    const latestMessage = newMessages[newMessages.length - 1];
    console.log(`📱 Processing message from ${latestMessage.sender_name} in community ${communityId}`);
    try {
        // 1. Get sender info
        const senderName = latestMessage.sender_name || "Someone";
        const senderEmail = latestMessage.sender_email || "";
        const messageText = latestMessage.message || "";
        console.log(`📤 Sender: ${senderName} (${senderEmail})`);
        console.log(`💬 Message: ${messageText}`);
        // 2. Get community members from CommunityMember collection
        const communityMembersRef = admin.firestore().collection("CommunityMember");
        const communityMembersQuery = communityMembersRef
            .where("community_id", "==", communityId)
            .where("is_active", "==", true);
        const communityMembersSnapshot = await communityMembersQuery.get();
        const memberEmails = [];
        communityMembersSnapshot.forEach((doc) => {
            const data = doc.data();
            const userEmail = data.user_email;
            if (userEmail) {
                memberEmails.push(userEmail);
            }
        });
        if (memberEmails.length === 0) {
            console.log("❌ No active community members found");
            return;
        }
        console.log(`👥 Community members: ${memberEmails.length} users`);
        // 2.5. Get community name
        const communityRef = admin.firestore().collection("community").doc(communityId);
        const communityDoc = await communityRef.get();
        const communityData = communityDoc.data();
        const communityName = (communityData === null || communityData === void 0 ? void 0 : communityData.name) || "Community";
        // 3. Fetch FCM tokens for all members except sender
        const tokens = [];
        const memberPromises = memberEmails
            .filter(memberEmail => memberEmail !== senderEmail)
            .map(async (memberEmail) => {
            try {
                const userSnap = await admin.firestore()
                    .collection("Users")
                    .doc(memberEmail)
                    .get();
                const userData = userSnap.data();
                if (userData === null || userData === void 0 ? void 0 : userData.fcm_token) {
                    console.log(`✅ Found FCM token for ${memberEmail}`);
                    return userData.fcm_token;
                }
                else {
                    console.log(`❌ No FCM token for ${memberEmail}`);
                    return null;
                }
            }
            catch (error) {
                console.log(`❌ Error fetching user ${memberEmail}:`, error);
                return null;
            }
        });
        const tokenResults = await Promise.all(memberPromises);
        tokens.push(...tokenResults.filter(token => token !== null));
        if (tokens.length === 0) {
            console.log("❌ No valid FCM tokens found");
            return;
        }
        console.log(`📱 Found ${tokens.length} FCM tokens to send notifications to`);
        // 4. Prepare notification payload
        const truncatedMessage = messageText.length > 50
            ? messageText.substring(0, 47) + "..."
            : messageText;
        const payload = {
            notification: {
                title: communityName,
                body: `${senderName}: ${truncatedMessage}`,
            },
            data: {
                community_id: communityId,
                message_id: latestMessage.id,
                sender_name: senderName,
                sender_email: senderEmail,
                type: "chat_message"
            },
            tokens: tokens,
        };
        console.log("📤 Sending push notifications...");
        console.log(`📱 Title: ${payload.notification.title}`);
        console.log(`📱 Body: ${payload.notification.body}`);
        // 5. Send push notifications via Firebase Admin SDK
        console.log("📤 Attempting to send FCM message via Firebase Admin SDK...");
        console.log(`📱 Project ID: ${admin.app().options.projectId}`);
        console.log(`📱 Number of tokens: ${tokens.length}`);
        try {
            // Try using Firebase Admin SDK sendMulticast first
            const response = await admin.messaging().sendMulticast(payload);
            console.log(`✅ Push notifications sent via Admin SDK!`);
            console.log(`📊 Success count: ${response.successCount}`);
            console.log(`📊 Failure count: ${response.failureCount}`);
            if (response.failureCount > 0) {
                console.log("❌ Some notifications failed:");
                response.responses.forEach((resp, idx) => {
                    var _a, _b;
                    if (!resp.success) {
                        console.log(`❌ Token ${idx}: ${(_a = resp.error) === null || _a === void 0 ? void 0 : _a.message}`);
                        console.log(`❌ Token ${idx}: ${(_b = resp.error) === null || _b === void 0 ? void 0 : _b.code}`);
                    }
                });
            }
        }
        catch (error) {
            console.log(`❌ Admin SDK sendMulticast failed: ${error}`);
            console.log("📤 This might be due to APNs configuration issues.");
        }
    }
    catch (error) {
        console.error("❌ Error sending chat notification:", error);
    }
});
/**
 * Cloud Function triggered when a new bet is created
 * Sends push notifications to community members about new betting opportunities
 */
exports.sendBetNotification = (0, firestore_1.onDocumentCreated)("Communities/{communityId}/Bets/{betId}", async (event) => {
    console.log("🎯 New bet created, triggering push notification...");
    const snapshot = event.data;
    const bet = snapshot === null || snapshot === void 0 ? void 0 : snapshot.data();
    const communityId = event.params.communityId;
    const betId = event.params.betId;
    if (!bet) {
        console.log("❌ No bet data found");
        return;
    }
    try {
        // Get community data to find all members
        const communityRef = admin.firestore().collection("Communities").doc(communityId);
        const communityDoc = await communityRef.get();
        const communityData = communityDoc.data();
        if (!communityData || !communityData.members) {
            console.log("❌ No community data or members found");
            return;
        }
        const members = communityData.members;
        const communityName = communityData.name || "Community";
        const betTitle = bet.title || "New Bet";
        // Fetch FCM tokens for all members
        const tokens = [];
        const memberPromises = members.map(async (memberEmail) => {
            try {
                const userSnap = await admin.firestore()
                    .collection("Users")
                    .doc(memberEmail)
                    .get();
                const userData = userSnap.data();
                if (userData === null || userData === void 0 ? void 0 : userData.fcm_token) {
                    return userData.fcm_token;
                }
                return null;
            }
            catch (error) {
                console.log(`❌ Error fetching user ${memberEmail}:`, error);
                return null;
            }
        });
        const tokenResults = await Promise.all(memberPromises);
        tokens.push(...tokenResults.filter(token => token !== null));
        if (tokens.length === 0) {
            console.log("❌ No valid FCM tokens found");
            return;
        }
        // Send push notification about new bet
        const payload = {
            notification: {
                title: communityName,
                body: `New bet: ${betTitle}`,
            },
            data: {
                community_id: communityId,
                bet_id: betId,
                type: "new_bet"
            },
            tokens: tokens,
        };
        const response = await admin.messaging().sendMulticast(payload);
        console.log(`✅ Bet notification sent! Success: ${response.successCount}, Failures: ${response.failureCount}`);
    }
    catch (error) {
        console.error("❌ Error sending bet notification:", error);
    }
});
/**
 * Cloud Function triggered when a bet is settled
 * Sends push notifications to all participants about the settlement
 */
exports.sendBetSettledNotification = (0, firestore_1.onDocumentUpdated)("Bet/{betId}", async (event) => {
    var _a, _b, _c, _d, _e, _f;
    console.log("🎯 Bet settlement notification triggered...");
    const beforeData = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before) === null || _b === void 0 ? void 0 : _b.data();
    const afterData = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.after) === null || _d === void 0 ? void 0 : _d.data();
    const betId = event.params.betId;
    if (!beforeData || !afterData) {
        console.log("❌ No document data found");
        return;
    }
    // Check if bet status changed to settled
    const beforeStatus = beforeData.status;
    const afterStatus = afterData.status;
    if (beforeStatus === afterStatus || afterStatus !== "settled") {
        console.log("📱 Bet status not changed to settled, skipping notification");
        return;
    }
    try {
        const betTitle = afterData.title;
        const communityName = afterData.community_name;
        const winnerOption = afterData.winner_option;
        console.log(`📱 Bet "${betTitle}" settled with winner: ${winnerOption}`);
        // Get all participants for this bet
        const participantsSnapshot = await admin.firestore()
            .collection("BetParticipant")
            .where("bet_id", "==", betId)
            .get();
        if (participantsSnapshot.empty) {
            console.log("❌ No participants found for bet");
            return;
        }
        console.log(`📱 Found ${participantsSnapshot.size} participants to notify`);
        // Get FCM tokens for all participants
        const userEmails = participantsSnapshot.docs.map(doc => doc.data().user_email);
        const userDocs = await Promise.all(userEmails.map(email => admin.firestore().collection("Users").doc(email).get()));
        const tokens = [];
        userDocs.forEach(doc => {
            var _a, _b;
            if (doc.exists && ((_a = doc.data()) === null || _a === void 0 ? void 0 : _a.fcm_token)) {
                tokens.push((_b = doc.data()) === null || _b === void 0 ? void 0 : _b.fcm_token);
            }
        });
        if (tokens.length === 0) {
            console.log("❌ No valid FCM tokens found");
            return;
        }
        // Send notifications to each participant
        for (const participantDoc of participantsSnapshot.docs) {
            const participantData = participantDoc.data();
            const userEmail = participantData.user_email;
            const chosenOption = participantData.chosen_option;
            const stakeAmount = participantData.stake_amount;
            const finalPayout = participantData.final_payout;
            const isWinner = chosenOption === winnerOption;
            const formattedAmount = finalPayout ? finalPayout.toLocaleString() : stakeAmount.toLocaleString();
            const payload = {
                notification: {
                    title: communityName,
                    body: isWinner
                        ? `You won ${formattedAmount} on '${betTitle}'`
                        : `Your bet on '${betTitle}' has been settled`,
                },
                data: {
                    bet_id: betId,
                    type: "bet_settled",
                    is_winner: isWinner.toString(),
                },
                token: (_f = (_e = userDocs.find(doc => doc.id === userEmail)) === null || _e === void 0 ? void 0 : _e.data()) === null || _f === void 0 ? void 0 : _f.fcm_token,
            };
            if (payload.token) {
                await admin.messaging().send(payload);
                console.log(`✅ Settlement notification sent to ${userEmail}`);
            }
        }
        console.log(`✅ All settlement notifications sent for bet "${betTitle}"`);
    }
    catch (error) {
        console.error("❌ Error sending bet settlement notification:", error);
    }
});
/**
 * Cloud Function triggered when a bet is voided
 * Sends push notifications to all participants about the void
 */
exports.sendBetVoidedNotification = (0, firestore_1.onDocumentUpdated)("Bet/{betId}", async (event) => {
    var _a, _b, _c, _d, _e, _f;
    console.log("🚫 Bet void notification triggered...");
    const beforeData = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before) === null || _b === void 0 ? void 0 : _b.data();
    const afterData = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.after) === null || _d === void 0 ? void 0 : _d.data();
    const betId = event.params.betId;
    if (!beforeData || !afterData) {
        console.log("❌ No document data found");
        return;
    }
    // Check if bet status changed to voided
    const beforeStatus = beforeData.status;
    const afterStatus = afterData.status;
    if (beforeStatus === afterStatus || afterStatus !== "voided") {
        console.log("📱 Bet status not changed to voided, skipping notification");
        return;
    }
    try {
        const betTitle = afterData.title;
        const communityName = afterData.community_name;
        console.log(`📱 Bet "${betTitle}" voided`);
        // Get all participants for this bet
        const participantsSnapshot = await admin.firestore()
            .collection("BetParticipant")
            .where("bet_id", "==", betId)
            .get();
        if (participantsSnapshot.empty) {
            console.log("❌ No participants found for bet");
            return;
        }
        // Get FCM tokens for all participants
        const userEmails = participantsSnapshot.docs.map(doc => doc.data().user_email);
        const userDocs = await Promise.all(userEmails.map(email => admin.firestore().collection("Users").doc(email).get()));
        // Send notifications to each participant
        for (const participantDoc of participantsSnapshot.docs) {
            const participantData = participantDoc.data();
            const userEmail = participantData.user_email;
            const stakeAmount = participantData.stake_amount;
            const payload = {
                notification: {
                    title: communityName,
                    body: `Your bet on '${betTitle}' was voided due to lack of opposing wagers. You've been refunded ${stakeAmount.toLocaleString()} points.`,
                },
                data: {
                    bet_id: betId,
                    type: "bet_voided",
                },
                token: (_f = (_e = userDocs.find(doc => doc.id === userEmail)) === null || _e === void 0 ? void 0 : _e.data()) === null || _f === void 0 ? void 0 : _f.fcm_token,
            };
            if (payload.token) {
                await admin.messaging().send(payload);
                console.log(`✅ Void notification sent to ${userEmail}`);
            }
        }
        console.log(`✅ All void notifications sent for bet "${betTitle}"`);
    }
    catch (error) {
        console.error("❌ Error sending bet void notification:", error);
    }
});
/**
 * Cloud Function triggered when a reminder is sent
 * Sends push notifications to bet creators about settlement reminders
 */
exports.sendReminderNotification = (0, firestore_1.onDocumentCreated)("Notification/{notificationId}", async (event) => {
    var _a, _b, _c;
    console.log("🔔 Reminder notification triggered...");
    const notificationData = (_a = event.data) === null || _a === void 0 ? void 0 : _a.data();
    const notificationId = event.params.notificationId;
    if (!notificationData || notificationData.type !== "remind_settle") {
        console.log("📱 Not a settlement reminder notification, skipping");
        return;
    }
    try {
        const userEmail = notificationData.user_email;
        const communityName = notificationData.community_name || "Community";
        const message = notificationData.message;
        console.log(`📱 Settlement reminder for ${userEmail}: ${message}`);
        // Get user's FCM token
        const userDoc = await admin.firestore()
            .collection("Users")
            .doc(userEmail)
            .get();
        if (!userDoc.exists || !((_b = userDoc.data()) === null || _b === void 0 ? void 0 : _b.fcm_token)) {
            console.log(`❌ No FCM token found for user: ${userEmail}`);
            return;
        }
        const payload = {
            notification: {
                title: communityName,
                body: message,
            },
            data: {
                notification_id: notificationId,
                type: "remind_settle",
            },
            token: (_c = userDoc.data()) === null || _c === void 0 ? void 0 : _c.fcm_token,
        };
        await admin.messaging().send(payload);
        console.log(`✅ Reminder notification sent to ${userEmail}`);
    }
    catch (error) {
        console.error("❌ Error sending reminder notification:", error);
    }
});
//# sourceMappingURL=index.js.map