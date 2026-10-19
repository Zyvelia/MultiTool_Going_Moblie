import 'package:flutter_test/flutter_test.dart';
import 'package:multi_tool_remote/services/wol_service.dart';

void main() {
  group('parseMacAddress', () {
    test('accepts colon format', () {
      expect(
        WolService.parseMacAddress('aa:bb:cc:dd:ee:ff'),
        [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff],
      );
    });

    test('accepts hyphen format', () {
      expect(
        WolService.parseMacAddress('AA-BB-CC-DD-EE-FF'),
        [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff],
      );
    });

    test('rejects short mac', () {
      expect(
        () => WolService.parseMacAddress('aa:bb:cc'),
        throwsA(isA<WolException>()),
      );
    });
  });

  group('buildMagicPacket', () {
    test('length and structure', () {
      final mac = WolService.parseMacAddress('01:02:03:04:05:06');
      final packet = WolService.buildMagicPacket(mac);
      expect(packet.length, WolService.magicPacketLength);
      expect(packet.sublist(0, 6), List.filled(6, 0xFF));
      for (var i = 0; i < 16; i++) {
        expect(packet.sublist(6 + i * 6, 6 + (i + 1) * 6), mac);
      }
    });
  });

  group('parsePort', () {
    test('defaults empty to 9', () {
      expect(WolService.parsePort(''), 9);
    });
    test('rejects invalid', () {
      expect(() => WolService.parsePort('0'), throwsA(isA<WolException>()));
    });
  });

  group('validateConfiguration', () {
    test('does not require network', () {
      final r = WolService.validateConfiguration(
        macAddress: 'de:ad:be:ef:00:01',
        broadcast: '192.168.4.255',
        port: 9,
      );
      expect(r.bytesSent, 102);
      expect(r.destination, '192.168.4.255');
      expect(r.port, 9);
    });
  });
}
