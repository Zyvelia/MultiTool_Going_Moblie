/// Which music server endpoint a request should prefer.
///
/// [auto] tries the private (Tailscale) address first — it's usually
/// lower-latency and doesn't leave the tailnet — and falls back to the
/// public HTTPS address if the private one doesn't answer quickly. Only
/// relevant when both are configured; if only one is set, that one is
/// used regardless of this setting.
enum PreferredServer { auto, private, public }

extension PreferredServerJson on PreferredServer {
  String toStorageString() => name;

  static PreferredServer fromStorageString(String? value) {
    switch (value) {
      case 'private':
        return PreferredServer.private;
      case 'public':
        return PreferredServer.public;
      default:
        return PreferredServer.auto;
    }
  }
}

/// Resolved base URL for a music request, plus which profile it came
/// from — callers use [label] in diagnostics/error messages so "can't
/// reach the server" says *which* server.
class ResolvedServer {
  final String baseUrl;
  final String label; // 'Private (Tailscale)' or 'Public'

  const ResolvedServer(this.baseUrl, this.label);
}
