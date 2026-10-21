import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'quick_send_api_service.dart';

class QueuedSendItem {
  QueuedSendItem({
    required this.id,
    required this.localPath,
    required this.filename,
    required this.queuedAt,
  });

  final String id;
  final String localPath;
  final String filename;
  final DateTime queuedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'localPath': localPath,
        'filename': filename,
        'queuedAt': queuedAt.toIso8601String(),
      };

  factory QueuedSendItem.fromJson(Map<String, dynamic> j) => QueuedSendItem(
        id: j['id'] as String,
        localPath: j['localPath'] as String,
        filename: j['filename'] as String,
        queuedAt: DateTime.tryParse(j['queuedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Phone-side upload queue when Quick Send / Tailscale is unreachable.
class QuickSendOutboxService {
  QuickSendOutboxService._();
  static final instance = QuickSendOutboxService._();

  Directory? _dir;
  final List<QueuedSendItem> _items = [];
  bool _ready = false;
  Future<void>? _initFuture;

  Future<void> ensureReady() => _initFuture ??= _init();

  Future<void> _init() async {
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/quick_send_outbox');
    await _dir!.create(recursive: true);
    await _load();
    _ready = true;
  }

  File get _index => File('${_dir!.path}/queue.json');

  Future<void> _load() async {
    _items.clear();
    try {
      if (!await _index.exists()) return;
      final raw = jsonDecode(await _index.readAsString()) as List;
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          _items.add(QueuedSendItem.fromJson(e));
        }
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    await _index.writeAsString(
      jsonEncode(_items.map((e) => e.toJson()).toList()),
    );
  }

  List<QueuedSendItem> get items => List.unmodifiable(_items);
  int get count => _items.length;
  bool get isReady => _ready;

  Future<void> enqueue(String sourcePath, {String? filename}) async {
    await ensureReady();
    final name = filename ?? sourcePath.split(Platform.pathSeparator).last;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final dest = File('${_dir!.path}/${id}_$name');
    await File(sourcePath).copy(dest.path);
    _items.add(QueuedSendItem(
      id: id,
      localPath: dest.path,
      filename: name,
      queuedAt: DateTime.now(),
    ));
    await _save();
  }

  Future<void> remove(String id) async {
    final item = _items.cast<QueuedSendItem?>().firstWhere(
          (e) => e?.id == id,
          orElse: () => null,
        );
    if (item == null) return;
    _items.removeWhere((e) => e.id == id);
    try {
      final f = File(item.localPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await _save();
  }

  /// Upload everything queued; returns how many succeeded.
  Future<int> flush(QuickSendApiService api) async {
    await ensureReady();
    var ok = 0;
    for (final item in List<QueuedSendItem>.from(_items)) {
      try {
        if (!await File(item.localPath).exists()) {
          await remove(item.id);
          continue;
        }
        await api.sendFile(item.localPath, filenameOverride: item.filename);
        await remove(item.id);
        ok++;
      } catch (_) {
        // Leave in queue for next attempt.
      }
    }
    return ok;
  }
}
