
## Project IDs

These Firebase client files are registered for this app:

- Android package: `com.zsmultitool.multi_tool_remote`
- iOS bundle ID: `com.zsmultitool.multiToolRemote`
- Firebase project: `inbox-worker`

The GitHub Actions workflow validates both files before building. If either
file belongs to a different Firebase app, the build stops instead of silently
shipping an app without working Firebase Messaging.
