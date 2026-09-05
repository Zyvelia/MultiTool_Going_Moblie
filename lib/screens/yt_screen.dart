import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/download_job.dart';
import '../services/settings_service.dart';
import '../services/user_facing_error.dart';
import '../services/yt_api_service.dart';

class YtScreen extends StatefulWidget {
  const YtScreen({super.key});

  @override
  State<YtScreen> createState() => _YtScreenState();
}

class _YtScreenState extends State<YtScreen> {
  final _settings = SettingsService();
  final _urlController = TextEditingController();
  YtApiService? _api;
  List<DownloadJob> _jobs = [];
  String _type = 'video';
  String _format = 'mp4';
  String? _error;
  bool _queuing = false;
  Timer? _pollTimer;

  // Keyed by "jobId:index" — null = not started, 0.0-1.0 = in progress,
  // 1.0 briefly before the share sheet opens.
  final Map<String, double> _saveProgress = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final base = await _settings.baseUrl('yt');
    final code = await _settings.getAccessCode('yt');
    if (base == null) return;
    setState(() => _api = YtApiService(base, accessCode: code));
    await _refreshJobs();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshJobs());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _refreshJobs() async {
    if (_api == null) return;
    try {
      final jobs = await _api!.fetchJobs();
      if (mounted) setState(() => _jobs = jobs.reversed.toList());
    } catch (_) {
      // transient — keep showing the last known jobs
    }
  }

  Future<void> _submit() async {
    if (_api == null) return;
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _queuing = true;
      _error = null;
    });
    try {
      await _api!.queueDownload(url: url, format: _format, type: _type);
      _urlController.clear();
      await _refreshJobs();
    } catch (e) {
      setState(() => _error = explainError(e, doing: 'queue that download'));
    } finally {
      if (mounted) setState(() => _queuing = false);
    }
  }

  Future<void> _saveToPhone(DownloadJob job, int index) async {
    if (_api == null) return;
    final file = job.files[index];
    final key = '${job.id}:$index';
    setState(() => _saveProgress[key] = 0.0);
    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/${file.name}';
      await _api!.downloadJobFile(
        jobId: job.id,
        index: index,
        savePath: savePath,
        onProgress: (p) {
          if (mounted) setState(() => _saveProgress[key] = p);
        },
      );
      if (!mounted) return;
      setState(() => _saveProgress.remove(key));
      // Hands off to the OS share sheet — "Save to Files"/"Save Video"
      // from there lands it in Files/Photos, same as sharing from Safari.
      await SharePlus.instance.share(
        ShareParams(files: [XFile(savePath)]),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveProgress.remove(key));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(explainError(e, doing: 'save that file to the phone'))),
      );
    }
  }

  Widget _buildFileRow(DownloadJob job, int index) {
    final file = job.files[index];
    final key = '${job.id}:$index';
    final progress = _saveProgress[key];
    final saving = progress != null;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          const SizedBox(width: 8),
          if (saving)
            SizedBox(
              width: 44,
              child: Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.ios_share, size: 18),
              tooltip: 'Save to phone',
              onPressed: () => _saveToPhone(job, index),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(6),
            ),
        ],
      ),
    );
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
      appBar: AppBar(title: const Text('YouTube Downloader')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    hintText: 'Paste a YouTube link',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _type,
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'video', child: Text('Video')),
                          DropdownMenuItem(value: 'playlist', child: Text('Playlist')),
                        ],
                        onChanged: (v) => setState(() => _type = v ?? 'video'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _format,
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'mp4', child: Text('mp4')),
                          DropdownMenuItem(value: 'mp3', child: Text('mp3')),
                        ],
                        onChanged: (v) => setState(() => _format = v ?? 'mp4'),
                      ),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _queuing ? null : _submit,
                  child: Text(_queuing ? 'Queuing…' : 'Queue Download'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _jobs.isEmpty
                ? const Center(
                    child: Text('No downloads yet.',
                        style: TextStyle(color: Colors.white38)),
                  )
                : ListView.builder(
                    itemCount: _jobs.length,
                    itemBuilder: (context, i) {
                      final j = _jobs[i];
                      final done = j.status == 'done';
                      final error = j.status == 'error';
                      return ListTile(
                        title: Text(
                          j.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              j.message.isNotEmpty ? j.message : j.status,
                              style: TextStyle(
                                fontSize: 12,
                                color: done
                                    ? Colors.greenAccent
                                    : error
                                        ? Colors.redAccent
                                        : Colors.white54,
                              ),
                            ),
                            if (!done && !error)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: LinearProgressIndicator(
                                  value: j.percent > 0 ? j.percent : null,
                                  minHeight: 3,
                                ),
                              ),
                            if (done && j.files.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (var idx = 0; idx < j.files.length; idx++)
                                      _buildFileRow(j, idx),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
