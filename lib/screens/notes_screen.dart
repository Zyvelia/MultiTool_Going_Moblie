import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/note.dart';
import '../services/settings_service.dart';
import '../services/notes_api_service.dart';
import '../services/notes_sync_service.dart';
import '../services/connectivity_service.dart';
import '../services/user_facing_error.dart';
import '../theme/app_colors.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _settings = SettingsService();
  final _sync = NotesSyncService.instance;
  NotesApiService? _api;
  List<Note> _notes = [];
  bool _loading = true;
  String _query = '';

  StreamSubscription<NetworkType>? _connectivitySub;
  StreamSubscription<NotesSyncEvent>? _syncSub;
  NetworkType _networkType = NetworkType.other;
  // True once a live fetch has actually failed — distinct from
  // _networkType == offline, which only means "no interface at all"
  // and misses the more common case here (interface up, Tailscale
  // hostname unreachable).
  bool _unreachable = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _syncSub = _sync.events.listen((evt) {
      if (!mounted) return;
      if (evt.type == NotesSyncEventType.syncStarted) {
        setState(() => _syncing = true);
      } else if (evt.type == NotesSyncEventType.syncFinished) {
        setState(() => _syncing = false);
        _refreshLocal();
        final synced = evt.synced ?? 0;
        final failed = evt.failed ?? 0;
        if (synced > 0) {
          _showToast(
            'Synced $synced note${synced == 1 ? '' : 's'} to desktop'
            '${failed > 0 ? ' ($failed failed, will retry)' : ''}',
          );
        }
      }
    });
    _init();
    _initConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await _sync.ensureReady();
    _refreshLocal();
    final base = await _settings.baseUrl('notes');
    if (base == null) return;
    setState(() => _api = NotesApiService(base));
    await _load();
  }

  void _initConnectivity() {
    ConnectivityService.instance.current().then((t) {
      if (mounted) setState(() => _networkType = t);
    });
    _connectivitySub = ConnectivityService.instance.onChange.listen((type) async {
      final wasOffline = _networkType == NetworkType.offline;
      if (mounted) setState(() => _networkType = type);
      if (type == NetworkType.offline) return;
      if (!wasOffline) return; // only act on offline -> back-online edges
      await _load();
    });
  }

  void _refreshLocal() {
    setState(() {
      _notes = _sync.localNotes(query: _query);
      _loading = false;
    });
  }

  /// Shows the local cache immediately (works with no connection at
  /// all), then — if a server is configured — tries to pull the latest
  /// from the desktop and push any queued local changes.
  Future<void> _load() async {
    _refreshLocal();
    if (_api == null) return;
    try {
      final serverNotes = await _api!.fetchNotes();
      await _sync.replaceFromServer(serverNotes);
      if (mounted) setState(() => _unreachable = false);
      await _sync.sync(_api!);
      _refreshLocal();
    } catch (_) {
      // Desktop unreachable — local cache (already shown) is the
      // fallback, and whatever's queued just waits for the next
      // successful _load().
      if (mounted) setState(() => _unreachable = true);
    }
  }

  void _onSearchChanged(String value) {
    // Purely a local-cache filter now (see NotesSyncService.localNotes),
    // so no debounce/network round trip needed — it also means search
    // works the same online or off.
    setState(() {
      _query = value;
      _notes = _sync.localNotes(query: _query);
    });
  }

  Future<void> _openEditor({Note? note}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
    );
    if (saved == true) {
      _refreshLocal();
      _maybeSync();
    }
  }

  /// Fire-and-forget sync attempt after a local edit — only actually
  /// does anything if a server's configured and reachable; otherwise
  /// the change just stays queued.
  void _maybeSync() {
    if (_api == null || _networkType == NetworkType.offline) return;
    _sync.sync(_api!);
  }

  Future<void> _togglePin(Note note) async {
    if (_api == null || _networkType == NetworkType.offline) {
      _showToast('Connect to the desktop to toggle pin');
      return;
    }
    try {
      final updated = await _api!.togglePin(note.id);
      await _sync.upsertFromServer(updated);
      _refreshLocal();
    } catch (e) {
      _showToast(explainError(e));
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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

    final showOfflineBanner =
        _networkType == NetworkType.offline || _unreachable;
    final pending = _sync.pendingCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(_notes.isNotEmpty ? '${_notes.length} notes' : 'Notes'),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (pending > 0)
            IconButton(
              icon: Badge(
                label: Text('$pending'),
                child: const Icon(Icons.cloud_upload_outlined),
              ),
              tooltip: '$pending note${pending == 1 ? '' : 's'} waiting to sync — tap to retry',
              onPressed: _maybeSync,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            if (showOfflineBanner)
              Container(
                width: double.infinity,
                color: Colors.amber.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const Text(
                  'Offline — showing notes saved on this phone. '
                  'Changes will sync once reconnected.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.amber),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search notes…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _notes.isEmpty
                      ? ListView(
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'No notes yet. Tap + to write one.',
                                style: TextStyle(color: Colors.white54),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: _notes.length,
                          itemBuilder: (context, i) {
                            final note = _notes[i];
                            final isPending = _sync.isPending(note.id);
                            return ListTile(
                              leading: Icon(
                                note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                                color: note.pinned
                                    ? AppColors.accent
                                    : Colors.white38,
                              ),
                              title: Text(note.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                note.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54),
                              ),
                              trailing: isPending
                                  ? const Icon(Icons.cloud_off,
                                      size: 18, color: Colors.white38)
                                  : null,
                              onTap: () => _openEditor(note: note),
                              onLongPress: () => _togglePin(note),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class NoteEditorScreen extends StatefulWidget {
  final Note? note;

  const NoteEditorScreen({super.key, this.note});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final _sync = NotesSyncService.instance;
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _bodyController = TextEditingController(text: widget.note?.body ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final title = _titleController.text.trim();
      final body = _bodyController.text;
      if (widget.note != null) {
        await _sync.updateNote(widget.note!.id, title: title, body: body);
      } else {
        await _sync.createNote(title: title, body: body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(explainError(e))),
        );
      }
    }
  }

  /// Renders the note (whatever's currently in the text fields, saved or
  /// not) to a simple PDF and hands it to the OS print flow — AirPrint on
  /// iOS, the Android print framework (which covers most wireless/network
  /// printers) on Android. Fully offline: the PDF is built on-device, no
  /// server round trip involved.
  Future<void> _print() async {
    final title = _titleController.text.trim().isEmpty
        ? 'Untitled'
        : _titleController.text.trim();
    final body = _bodyController.text;

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(title,
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Paragraph(text: body, style: const pw.TextStyle(fontSize: 12)),
        ],
      ),
    );

    await Printing.layoutPdf(
      name: title,
      onLayout: (format) async => doc.save(),
    );
  }

  Future<void> _delete() async {
    if (widget.note == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await _sync.deleteNote(widget.note!.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _deleting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(explainError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _deleting;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note != null ? 'Edit note' : 'New note'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print',
            onPressed: busy ? null : _print,
          ),
          if (widget.note != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: busy ? null : _delete,
            ),
          IconButton(
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: busy ? null : _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: 'Title',
                border: InputBorder.none,
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: TextField(
                controller: _bodyController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'Write something…',
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
