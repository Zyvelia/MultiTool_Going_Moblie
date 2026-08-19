import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_colors.dart';
import 'package:share_plus/share_plus.dart';
import '../models/shared_file.dart';
import '../services/quick_send_api_service.dart';
import '../services/settings_service.dart';

class QuickSendScreen extends StatefulWidget {
  const QuickSendScreen({super.key});

  @override
  State<QuickSendScreen> createState() => _QuickSendScreenState();
}

class _QuickSendScreenState extends State<QuickSendScreen> {
  final _settings = SettingsService();
  QuickSendApiService? _api;

  List<SharedFile> _outbox = [];
  bool _loading = false;
  String? _error;

  bool _sending = false;
  String? _sendStatus;

  final Map<String, double> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final base = await _settings.baseUrl('send');
    if (base == null) return;
    setState(() => _api = QuickSendApiService(base));
    await _loadOutbox();
  }

  Future<void> _loadOutbox() async {
    if (_api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await _api!.fetchOutbox();
      setState(() {
        _outbox = files;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not reach PC: $e';
        _loading = false;
      });
    }
  }

  Future<void> _pickAndSend() async {
    if (_api == null) return;
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    setState(() {
      _sending = true;
      _sendStatus = 'Sending...';
    });
    try {
      await _api!.sendFile(path);
      setState(() => _sendStatus = 'Sent to PC ✓');
    } catch (e) {
      setState(() =>
          _sendStatus = 'Failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      setState(() => _sending = false);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _sendStatus = null);
      });
    }
  }

  Future<void> _downloadAndShare(SharedFile file) async {
    if (_api == null) return;
    setState(() => _downloadProgress[file.name] = 0.0);
    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/${file.name}';
      await _api!.downloadOutboxFile(
        name: file.name,
        savePath: savePath,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress[file.name] = p);
        },
      );
      if (!mounted) return;
      setState(() => _downloadProgress.remove(file.name));
      await SharePlus.instance.share(ShareParams(files: [XFile(savePath)]));
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloadProgress.remove(file.name));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Download failed: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    if (_api == null) {
      return const Scaffold(
        body: Center(
          child: Text('Set your PC hostname in Settings first.',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Send'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOutbox,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadOutbox,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('SEND TO PC',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _sending ? null : _pickAndSend,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Icon(
                      _sending ? Icons.hourglass_top : Icons.upload_file,
                      color: AppColors.accent,
                      size: 28,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _sendStatus ?? 'Tap to choose a file to send',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text('GET FROM PC',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              )
            else if (_loading && _outbox.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_outbox.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Nothing shared yet — drop a file in the Shared folder on your PC.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              )
            else
              ..._outbox.map((f) {
                final progress = _downloadProgress[f.name];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file,
                          color: Colors.white38, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14)),
                            Text(_formatSize(f.size),
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11)),
                          ],
                        ),
                      ),
                      if (progress != null)
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            value: progress > 0 ? progress : null,
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.download,
                              color: AppColors.accent),
                          onPressed: () => _downloadAndShare(f),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
