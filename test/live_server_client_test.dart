import 'package:flutter_test/flutter_test.dart';
import '../lib/services/live_server_client.dart';

void main() {
  test('accepts only explicit Tailscale IPv4 HTTP or HTTPS endpoints', () {
    expect(LiveServerClient.parseAddress('http://100.64.1.23:8790').host, '100.64.1.23');
    expect(LiveServerClient.parseAddress('https://100.64.1.23:8790').scheme, 'https');
    expect(LiveServerClient.validTrackId(List.filled(64, 'a').join()), isTrue);
    expect(LiveServerClient.validTrackId('../secret'), isFalse);
    for (final url in [
      'http://127.0.0.1:8790', 'http://192.168.1.2:8790',
      'http://100.128.0.1:8790', 'http://100.63.1.2:8790',
      'http://example.com:8790', 'http://100.64.1.23:8790/api',
      'http://user@100.64.1.23:8790', 'http://100.64.1.23:8790?token=x',
      'http://100.64.1.23:8790/#x', 'https://example.com:8790',
      'http://100.64.1.23', 'http://100.64.1.23:80',
    ]) {
      expect(() => LiveServerClient.parseAddress(url), throwsFormatException, reason: url);
    }
  });
  test('rejects malformed session codes', () {
    expect(() => LiveServerClient('http://100.64.1.23:8790', 'abc'), throwsFormatException);
    expect(() => LiveServerClient('http://100.64.1.23:8790', List.filled(64, 'a').join()), returnsNormally);
  });
}
