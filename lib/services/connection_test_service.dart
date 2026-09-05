import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'trusted_http.dart';
import 'user_facing_error.dart';

enum StepStatus { pass, fail, skipped }

class ConnectionTestStep {
  final String name;
  final StepStatus status;
  final String detail;
  final int? latencyMs;

  const ConnectionTestStep(this.name, this.status, this.detail, {this.latencyMs});
}

/// Runs the four checks the upgrade spec calls for against a single
/// resolved base URL: DNS/reachability, API availability, auth, and the
/// music endpoint itself. Used by the diagnostics screen, and cheap
/// enough to also run ad-hoc from Settings' "Test connection" button.
///
/// Never surfaces a token/credential in [ConnectionTestStep.detail] —
/// only pass/fail and human-readable reasons (status code, timeout,
/// DNS failure, TLS failure), per the doc's diagnostics requirements.
class ConnectionTestService {
  /// [accessCode], if provided, is sent as `X-Access-Code` on the auth
  /// check — matches the header the other module servers
  /// (games/yt) already expect. Music has no auth wired up
  /// yet (see settings_screen), so that step reports itself as
  /// unconfigured rather than faking a pass.
  Future<List<ConnectionTestStep>> run(String baseUrl, {String? accessCode}) async {
    final steps = <ConnectionTestStep>[];

    final dnsStep = await _checkDns(baseUrl);
    steps.add(dnsStep);
    if (dnsStep.status != StepStatus.pass) {
      steps.add(const ConnectionTestStep(
        'API availability', StepStatus.skipped, 'Skipped — host unreachable',
      ));
      steps.add(const ConnectionTestStep(
        'Authentication', StepStatus.skipped, 'Skipped — host unreachable',
      ));
      steps.add(const ConnectionTestStep(
        'Music endpoint', StepStatus.skipped, 'Skipped — host unreachable',
      ));
      return steps;
    }

    final apiStep = await _checkApiStatus(baseUrl);
    steps.add(apiStep);

    if (accessCode == null || accessCode.isEmpty) {
      steps.add(const ConnectionTestStep(
        'Authentication', StepStatus.skipped, 'No access code configured for music',
      ));
    } else {
      steps.add(await _checkAuth(baseUrl, accessCode));
    }

    steps.add(await _checkMusicEndpoint(baseUrl));
    return steps;
  }

  Future<ConnectionTestStep> _checkDns(String baseUrl) async {
    final sw = Stopwatch()..start();
    try {
      final host = Uri.parse(baseUrl).host;
      final addresses = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 5));
      sw.stop();
      if (addresses.isEmpty) {
        return ConnectionTestStep(
          'DNS / reachability', StepStatus.fail, 'No addresses resolved for $host',
        );
      }
      return ConnectionTestStep(
        'DNS / reachability', StepStatus.pass, 'Resolved $host',
        latencyMs: sw.elapsedMilliseconds,
      );
    } on TimeoutException {
      return const ConnectionTestStep(
        'DNS / reachability', StepStatus.fail, 'DNS lookup timed out',
      );
    } on SocketException catch (e) {
      return ConnectionTestStep(
        'DNS / reachability', StepStatus.fail, explainError(e),
      );
    } catch (e) {
      return ConnectionTestStep('DNS / reachability', StepStatus.fail, explainError(e));
    }
  }

  Future<ConnectionTestStep> _checkApiStatus(String baseUrl) async {
    final sw = Stopwatch()..start();
    try {
      final res = await trustedHttp
          .get(Uri.parse('$baseUrl/api/status'))
          .timeout(const Duration(seconds: 8));
      sw.stop();
      if (res.statusCode == 200) {
        return ConnectionTestStep(
          'API availability', StepStatus.pass, 'Server reachable',
          latencyMs: sw.elapsedMilliseconds,
        );
      }
      return ConnectionTestStep(
        'API availability', StepStatus.fail, explainError(AppIssue.fromHttp(res.statusCode, res.body, doing: 'reach that API')),
        latencyMs: sw.elapsedMilliseconds,
      );
    } on TimeoutException {
      return const ConnectionTestStep(
        'API availability', StepStatus.fail, 'Connection timed out',
      );
    } on HandshakeException {
      return const ConnectionTestStep(
        'API availability', StepStatus.fail, explainError(HandshakeException('TLS handshake failed')),
      );
    } on SocketException catch (e) {
      return ConnectionTestStep('API availability', StepStatus.fail, explainError(e));
    } catch (e) {
      return ConnectionTestStep('API availability', StepStatus.fail, explainError(e));
    }
  }

  Future<ConnectionTestStep> _checkAuth(String baseUrl, String accessCode) async {
    try {
      final res = await trustedHttp.get(
        Uri.parse('$baseUrl/api/status'),
        headers: {'X-Access-Code': accessCode},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        return const ConnectionTestStep(
          'Authentication', StepStatus.pass, 'Authentication successful',
        );
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        return const ConnectionTestStep(
          'Authentication', StepStatus.fail, explainError(AppIssue.fromHttp(res.statusCode, res.body, doing: 'check the access code')),
        );
      }
      return ConnectionTestStep(
        'Authentication', StepStatus.fail, explainError(AppIssue.fromHttp(res.statusCode, res.body, doing: 'check the access code')),
      );
    } catch (e) {
      return ConnectionTestStep('Authentication', StepStatus.fail, explainError(e));
    }
  }

  Future<ConnectionTestStep> _checkMusicEndpoint(String baseUrl) async {
    final sw = Stopwatch()..start();
    try {
      final res = await trustedHttp
          .get(Uri.parse('$baseUrl/api/songs?offset=0&limit=1'))
          .timeout(const Duration(seconds: 8));
      sw.stop();
      if (res.statusCode == 200) {
        return ConnectionTestStep(
          'Music API available', StepStatus.pass, 'Music endpoint available',
          latencyMs: sw.elapsedMilliseconds,
        );
      }
      return ConnectionTestStep(
        'Music API available', StepStatus.fail, explainError(AppIssue.fromHttp(res.statusCode, res.body, doing: 'load a song from the library')),
      );
    } catch (e) {
      return ConnectionTestStep('Music API available', StepStatus.fail, explainError(e));
    }
  }
}
