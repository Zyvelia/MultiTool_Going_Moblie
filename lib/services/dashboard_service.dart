import 'package:flutter/foundation.dart';

import 'connectivity_service.dart';
import 'device_trust_service.dart';
import 'library_index_service.dart';
import 'offline_cache_service.dart';
import 'settings_service.dart';
import 'trusted_http.dart';

enum DashboardReachability { notConfigured, offline, reachable, denied, unavailable, unknown }

@immutable
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.reachability,
    required this.checkedAt,
    this.network,
    this.paired,
    this.indexed,
    this.downloaded,
    this.downloadBytes,
    this.latencyMs,
  });

  final DashboardReachability reachability;
  final DateTime checkedAt;
  final NetworkType? network;
  final bool? paired;
  final int? indexed, downloaded, downloadBytes, latencyMs;

  String get connectionLabel => switch (reachability) {
    DashboardReachability.notConfigured => 'Music server not configured',
    DashboardReachability.offline => 'Phone network offline',
    DashboardReachability.reachable => 'PC music endpoint reachable',
    DashboardReachability.denied => 'Music endpoint denied access',
    DashboardReachability.unavailable => 'Music endpoint unavailable',
    DashboardReachability.unknown => 'Connection not verified',
  };

  String get networkLabel => switch (network) {
    NetworkType.wifi => 'Wi-Fi',
    NetworkType.cellular => 'Cellular',
    NetworkType.ethernet => 'Ethernet',
    NetworkType.other => 'Other network',
    NetworkType.offline => 'Offline',
    null => 'Network unknown',
  };
}

class DashboardService {
  Future<DashboardSnapshot> load() async {
    final settings = SettingsService();
    final index = LibraryIndexService.instance;
    final cache = OfflineCacheService.instance;
    NetworkType? network;
    bool? paired;
    int? indexed, downloaded, bytes, latency;
    var reachability = DashboardReachability.unknown;

    Future<void> getNetwork() async {
      try {
        network = await ConnectivityService.instance.current().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    Future<void> getPairing() async {
      try {
        paired = await deviceTrust.isPaired().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    Future<void> getIndex() async {
      try {
        await index.ensureReady().timeout(const Duration(seconds: 4));
        indexed = index.count;
      } catch (_) {}
    }

    Future<void> getCache() async {
      try {
        await cache.ensureReady().timeout(const Duration(seconds: 4));
        downloaded = cache.count;
        bytes = cache.totalBytes;
      } catch (_) {}
    }

    await Future.wait([getNetwork(), getPairing(), getIndex(), getCache()]);
    if (network == NetworkType.offline) {
      reachability = DashboardReachability.offline;
    } else {
      try {
        final server = await settings.resolveMusicServer().timeout(const Duration(seconds: 4));
        if (server == null) {
          reachability = DashboardReachability.notConfigured;
        } else {
          final watch = Stopwatch()..start();
          final response = await trustedHttp.get(Uri.parse('${server.baseUrl}/api/status'))
              .timeout(const Duration(seconds: 5));
          watch.stop();
          latency = watch.elapsedMilliseconds;
          reachability = switch (response.statusCode) {
            200 => DashboardReachability.reachable,
            401 || 403 => DashboardReachability.denied,
            _ => DashboardReachability.unavailable,
          };
        }
      } catch (_) {
        reachability = DashboardReachability.unavailable;
      }
    }
    return DashboardSnapshot(
      reachability: reachability, checkedAt: DateTime.now(), network: network,
      paired: paired, indexed: indexed, downloaded: downloaded, downloadBytes: bytes,
      latencyMs: latency,
    );
  }
}
