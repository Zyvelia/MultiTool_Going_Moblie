import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Coarse network classification the rest of the app reasons about.
/// connectivity_plus tells us the *interface* (wifi/cellular/etc.) but
/// not whether it actually has internet — [NetworkType.offline] here
/// means "no interface at all", not "interface up but unreachable".
/// Actual reachability is a job for [ConnectionTestService] / the
/// per-request retry logic, not this class.
enum NetworkType { wifi, cellular, ethernet, other, offline }

class ConnectivityService {
  ConnectivityService._internal() {
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final mapped = _map(results);
      if (mapped != _last) {
        _last = mapped;
        _controller.add(mapped);
      }
    });
  }

  static final ConnectivityService instance = ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final StreamController<NetworkType> _controller =
      StreamController<NetworkType>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  NetworkType? _last;

  /// Fires whenever the network type changes (not on every OS callback —
  /// de-duped against the last known value). Good for "connection
  /// restored, resume requests/downloads" and "gone metered, pause
  /// large transfers" hooks.
  Stream<NetworkType> get onChange => _controller.stream;

  Future<NetworkType> current() async {
    final results = await _connectivity.checkConnectivity();
    _last = _map(results);
    return _last!;
  }

  NetworkType _map(List<ConnectivityResult> results) {
    // A device can report multiple simultaneous interfaces (e.g. wifi +
    // vpn). Prefer the one that actually matters for "should I treat
    // this as metered / unmetered".
    if (results.contains(ConnectivityResult.wifi)) return NetworkType.wifi;
    if (results.contains(ConnectivityResult.ethernet)) {
      return NetworkType.ethernet;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return NetworkType.cellular;
    }
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return NetworkType.offline;
    }
    return NetworkType.other;
  }

  /// Best-effort "is this a connection the user probably doesn't want
  /// big automatic transfers on" check. Wi-Fi/ethernet are treated as
  /// unmetered; cellular and anything unrecognized are treated as
  /// metered (fail toward *not* burning someone's data plan). This is
  /// an interface-type heuristic — the OS-reported "metered" flag some
  /// platforms expose (e.g. a hotspot marked metered on Wi-Fi) isn't
  /// available through connectivity_plus, so it isn't checked here.
  bool isLikelyMetered(NetworkType type) {
    switch (type) {
      case NetworkType.wifi:
      case NetworkType.ethernet:
        return false;
      case NetworkType.cellular:
      case NetworkType.other:
      case NetworkType.offline:
        return true;
    }
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
