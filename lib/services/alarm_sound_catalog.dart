import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_tone_wav.dart';

class AlarmSoundOption {
  const AlarmSoundOption({
    required this.ref,
    required this.name,
    this.isCustom = false,
  });

  final String ref;
  final String name;
  final bool isCustom;
}

class AlarmSoundCatalog {
  AlarmSoundCatalog._();
  static final instance = AlarmSoundCatalog._();

  static const _customKey = 'alarm_custom_sounds_v1';

  static const builtIns = [
    AlarmSoundOption(ref: 'builtin:klaxon', name: 'Klaxon (alternating)'),
    AlarmSoundOption(ref: 'builtin:siren', name: 'Siren sweep'),
    AlarmSoundOption(ref: 'builtin:brain_melt', name: 'Brain melt'),
    AlarmSoundOption(ref: 'builtin:foghorn', name: 'Foghorn'),
    AlarmSoundOption(ref: 'builtin:chaos', name: 'Chaos beeps'),
  ];

  List<AlarmSoundOption> _custom = [];

  List<AlarmSoundOption> all() => [...builtIns, ..._custom];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customKey);
    _custom = [];
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        if (item is! Map) continue;
        final ref = item['ref'] as String?;
        if (ref != null) {
          _custom.add(
            AlarmSoundOption(
              ref: ref,
              name: item['name'] as String? ?? 'Custom',
              isCustom: true,
            ),
          );
        }
      }
    } catch (_) {}
    _custom = _custom.where((o) => resolvePath(o.ref) != null).toList();
  }

  Future<void> _saveCustom() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _custom.map((o) => {'ref': o.ref, 'name': o.name}).toList(),
    );
    await prefs.setString(_customKey, encoded);
  }

  Future<Directory> customDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/alarm_sounds');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<String?> resolvePlayablePath(String soundRef) async {
    final path = await resolvePath(soundRef);
    return path;
  }

  Future<String?> resolvePath(String soundRef) async {
    if (soundRef.startsWith('builtin:')) {
      final id = soundRef.substring('builtin:'.length);
      final file = await AlarmToneWav.fileForBuiltin(id);
      return file.path;
    }
    if (soundRef.startsWith('custom:')) {
      final name = soundRef.substring('custom:'.length);
      final dir = await customDir();
      final file = File('${dir.path}/$name');
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  Future<AlarmSoundOption?> importCustom() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;
    final srcPath = picked.path;
    if (srcPath == null) return null;

    final dir = await customDir();
    final ext = picked.extension?.isNotEmpty == true ? '.${picked.extension}' : '';
    final safeName = '${DateTime.now().microsecondsSinceEpoch}$ext';
    final dest = File('${dir.path}/$safeName');
    await File(srcPath).copy(dest.path);

    final display = picked.name.isNotEmpty ? picked.name : 'Custom sound';
    final option = AlarmSoundOption(
      ref: 'custom:$safeName',
      name: display,
      isCustom: true,
    );
    _custom.add(option);
    await _saveCustom();
    return option;
  }

  Future<void> deleteCustom(AlarmSoundOption option) async {
    if (!option.isCustom) return;
    _custom.removeWhere((o) => o.ref == option.ref);
    final path = await resolvePath(option.ref);
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    await _saveCustom();
  }

  String nameFor(String soundRef) {
    for (final o in all()) {
      if (o.ref == soundRef) return o.name;
    }
    return 'Alarm sound';
  }
}
