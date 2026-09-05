import 'package:http/http.dart' as http;

import 'device_trust_service.dart';

/// Same as [http.Client], plus device HMAC headers when this phone is paired.
final trustedHttp = SigningClient();

class SigningClient extends http.BaseClient {
  SigningClient({http.Client? inner}) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final signed = await deviceTrust.signHeaders(request.method, request.url.path);
    signed.forEach((key, value) {
      request.headers.putIfAbsent(key, () => value);
    });
    return _inner.send(request);
  }
}
