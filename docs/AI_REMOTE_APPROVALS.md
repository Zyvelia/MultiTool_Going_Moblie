# AI Remote Approvals

The AI approval notification system is intentionally separate from the Inbox.

## Flow

```text
PC AI -> FCM -> Android/iOS OS notification -> Accept/Deny -> PC AI approval API
```

The Inbox WebView, Inbox message database, and Inbox push registration are not
required for AI approvals.

## Phone behavior

1. The app initializes Firebase Messaging.
2. `AiPushService` gets the device FCM token.
3. The token is registered directly with the PC AI `/api/ai/mobile/fcm-token`
   endpoint using the existing Chat connection/access code.
4. The PC AI sends an FCM notification with:
   - `type=ai_approval`
   - `approval_id=<pending approval id>`
5. If the app is in the foreground, the app creates a normal OS local
   notification so it appears in the notification tray.
6. If the app is backgrounded/terminated, an FCM notification payload is shown
   by Android/iOS normally.
7. Tapping the notification opens the AI approval screen.
8. Accept/Deny calls the PC AI approval endpoint for that exact approval ID.

## Important

The PC still needs an FCM sending credential. Keep that credential on the PC,
never in the mobile app. The PC AI supports either a Firebase Admin service
account or an authenticated relay.

The mobile app does not contain a Firebase private key.
