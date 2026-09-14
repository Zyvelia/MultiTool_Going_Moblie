# AI Remote Approvals / FCM Integration

The mobile app already uses Firebase Cloud Messaging for the existing Inbox/Cloudflare notification flow. AI approvals reuse that **same FCM token and Firebase configuration**; no second Firebase project is required.

## Mobile behavior

- The existing Inbox Worker registration remains unchanged.
- The same FCM token is optionally registered with the PC AI endpoint:
  `POST /api/ai/mobile/fcm-token`
- If that endpoint returns 404, the mobile app silently keeps working with the existing Inbox FCM registration. This preserves compatibility with older desktop AI builds.
- Foreground `ai_approval` messages become native local notifications.
- Background/terminated notification taps are routed through Firebase's `onMessageOpenedApp` / `getInitialMessage` path.
- Tapping an approval opens the AI Approvals screen.
- Accept/Deny sends only the approval decision; the phone never receives filesystem access.

## FCM data contract

Send a notification/data message containing:

```json
{
  "data": {
    "type": "ai_approval",
    "approval_id": "approval-id"
  },
  "notification": {
    "title": "AI approval required",
    "body": "The AI wants to modify 6 files."
  }
}
```

## PC AI approval API

The mobile client expects:

- `POST /api/ai/mobile/fcm-token`
- `GET /api/ai/approvals/pending`
- `GET /api/ai/approvals/{id}`
- `POST /api/ai/approvals/{id}/decision`

Decision body:

```json
{"approved": true, "ok": true}
```

The client also falls back to the existing `/api/pending_confirm` and `/api/confirm` endpoints for compatibility.
