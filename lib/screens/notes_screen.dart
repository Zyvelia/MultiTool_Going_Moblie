import 'dart:async';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/settings_service.dart';
import '../services/notes_api_service.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _settings = SettingsService();
  NotesApiService? _api;
  List<Note> _notes = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final base = await _settings.baseUrl('notes');
    if (base == null) return;
    setState(() => _api = NotesApiService(base));
    await _load();
  }

  Future<void> _load() async {
    if (_api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notes = await _api!.fetchNotes(query: _query);
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not reach Notes: ${e.toString().replaceFirst('Exception: ', '')}';
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = value;
      _load();
    });
  }

  Future<void> _openEditor({Note? note}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(api: _api!, note: note)),
    );
    if (saved == true) _load();
  }

  Future<void> _togglePin(Note note) async {
    try {
      await _api!.togglePin(note.id);
      _load();
    } catch (e) {
      _showToast(e.toString().replaceFirst('Exception: ', ''));
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_notes.isNotEmpty ? '${_notes.length} notes' : 'Notes'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search notes…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xFF1B2030),
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
                  : _error != null
                      ? ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(_error!,
                                  style: const TextStyle(color: Colors.redAccent),
                                  textAlign: TextAlign.center),
                            ),
                          ],
                        )
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
                                return ListTile(
                                  leading: Icon(
                                    note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                                    color: note.pinned
                                        ? const Color(0xFF4EA1FF)
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
  final NotesApiService api;
  final Note? note;

  const NoteEditorScreen({super.key, required this.api, this.note});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
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
        await widget.api.updateNote(widget.note!.id, title: title, body: body);
      } else {
        await widget.api.createNote(title: title, body: body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
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
      await widget.api.deleteNote(widget.note!.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _deleting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
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
