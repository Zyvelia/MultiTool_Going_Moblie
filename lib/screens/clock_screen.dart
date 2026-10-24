import 'dart:async';

import 'package:flutter/material.dart';

import '../models/alarm.dart';
import '../services/alarm_service.dart';
import '../services/alarm_sound_catalog.dart';
import '../services/alarm_sound_player.dart';
import '../theme/app_colors.dart';
import '../widgets/scheduling_help_dialog.dart';
import 'home_leading.dart';

class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key});

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen> {
  final _alarms = AlarmService.instance;
  final _sounds = AlarmSoundCatalog.instance;
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(_now);
    final date = MaterialLocalizations.of(context).formatFullDate(_now);
    return Scaffold(
      appBar: AppBar(
        leading: homeBackLeading(context),
        title: const Text('Clock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Alarms & reminders help',
            onPressed: () => showSchedulingHelpDialog(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editAlarm(context),
        icon: const Icon(Icons.add_alarm),
        label: const Text('Alarm'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Column(
              children: [
                Text(
                  time.format(context),
                  style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 2,
                    color: AppColors.accentGlow,
                  ),
                ),
                Text(date, style: TextStyle(color: AppColors.muted, fontSize: 16)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ValueListenableBuilder<List<Alarm>>(
              valueListenable: _alarms.alarms,
              builder: (context, items, _) {
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No alarms yet. Pick a time, choose an annoying sound '
                        '(or import your own), and optional repeat days.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, height: 1.4),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final alarm = items[i];
                    return _AlarmTile(
                      alarm: alarm,
                      soundName: _sounds.nameFor(alarm.soundRef),
                      onToggle: (v) => _alarms.toggle(alarm.id, v),
                      onTap: () => _editAlarm(context, existing: alarm),
                      onDelete: () => _alarms.delete(alarm.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editAlarm(BuildContext context, {Alarm? existing}) async {
    var hour = existing?.hour ?? TimeOfDay.fromDateTime(_now).hour;
    var minute = existing?.minute ?? TimeOfDay.fromDateTime(_now).minute;
    var label = existing?.label ?? 'Alarm';
    var soundRef = existing?.soundRef ?? 'builtin:klaxon';
    var days = Set<int>.from(existing?.repeatWeekdays ?? {});
    final labelCtrl = TextEditingController(text: label);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: MediaQuery.paddingOf(ctx).bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (context, setLocal) {
              Future<void> pickTime() async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: hour, minute: minute),
                );
                if (picked != null) {
                  setLocal(() {
                    hour = picked.hour;
                    minute = picked.minute;
                  });
                }
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      existing == null ? 'New alarm' : 'Edit alarm',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: const Text('Time'),
                      subtitle: Text(TimeOfDay(hour: hour, minute: minute).format(context)),
                      onTap: pickTime,
                    ),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Label'),
                      controller: labelCtrl,
                      onChanged: (v) => label = v,
                    ),
                    const SizedBox(height: 12),
                    Text('Repeat', style: TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final entry in _weekdayChips)
                          FilterChip(
                            label: Text(entry.label),
                            selected: days.contains(entry.weekday),
                            onSelected: (on) {
                              setLocal(() {
                                if (on) {
                                  days.add(entry.weekday);
                                } else {
                                  days.remove(entry.weekday);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Sound'),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _pickSound(context, soundRef, (ref) {
                            setLocal(() => soundRef = ref);
                          }),
                          child: Text(_sounds.nameFor(soundRef)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        final trimmedLabel = labelCtrl.text.trim().isEmpty
                            ? 'Alarm'
                            : labelCtrl.text.trim();
                        final alarm = Alarm(
                          id: existing?.id ?? '',
                          hour: hour,
                          minute: minute,
                          label: trimmedLabel,
                          soundRef: soundRef,
                          repeatWeekdays: days,
                          enabled: existing?.enabled ?? true,
                        );
                        if (existing == null) {
                          await _alarms.add(
                            hour: hour,
                            minute: minute,
                            label: trimmedLabel,
                            soundRef: soundRef,
                            repeatWeekdays: days,
                          );
                        } else {
                          await _alarms.update(alarm);
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text(existing == null ? 'Save alarm' : 'Update'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    labelCtrl.dispose();
  }

  Future<void> _pickSound(
    BuildContext context,
    String current,
    void Function(String ref) onPick,
  ) async {
    await _sounds.load();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final options = _sounds.all();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Alarm sounds'),
                subtitle: const Text('Preview plays for a few seconds'),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final opt in options)
                      ListTile(
                        leading: Icon(
                          opt.isCustom ? Icons.audio_file : Icons.graphic_eq,
                        ),
                        title: Text(opt.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () => AlarmSoundPlayer.instance.preview(opt.ref),
                            ),
                            if (current == opt.ref)
                              const Icon(Icons.check, color: AppColors.accent),
                            if (opt.isCustom)
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  await _sounds.deleteCustom(opt);
                                  if (context.mounted) Navigator.pop(ctx);
                                  _pickSound(context, current, onPick);
                                },
                              ),
                          ],
                        ),
                        onTap: () {
                          onPick(opt.ref);
                          Navigator.pop(ctx);
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.upload_file),
                      title: const Text('Add your own sound…'),
                      subtitle: const Text('mp3, wav, m4a, ogg'),
                      onTap: () async {
                        final added = await _sounds.importCustom();
                        if (added != null) {
                          onPick(added.ref);
                          if (ctx.mounted) Navigator.pop(ctx);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

const _weekdayChips = [
  (label: 'Mon', weekday: DateTime.monday),
  (label: 'Tue', weekday: DateTime.tuesday),
  (label: 'Wed', weekday: DateTime.wednesday),
  (label: 'Thu', weekday: DateTime.thursday),
  (label: 'Fri', weekday: DateTime.friday),
  (label: 'Sat', weekday: DateTime.saturday),
  (label: 'Sun', weekday: DateTime.sunday),
];

class _AlarmTile extends StatelessWidget {
  const _AlarmTile({
    required this.alarm,
    required this.soundName,
    required this.onToggle,
    required this.onTap,
    required this.onDelete,
  });

  final Alarm alarm;
  final String soundName;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: alarm.hour, minute: alarm.minute);
    final repeat = alarm.repeatWeekdays.isEmpty
        ? 'Once'
        : alarm.repeatWeekdays.map((d) => _weekdayChips.firstWhere((c) => c.weekday == d).label).join(' ');
    return Dismissible(
      key: ValueKey(alarm.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.accentMuted,
        child: const Icon(Icons.delete_outline),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          onTap: onTap,
          title: Text(
            time.format(context),
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w300,
              color: alarm.enabled ? AppColors.onSurface : AppColors.muted,
            ),
          ),
          subtitle: Text('${alarm.label} · $soundName · $repeat'),
          trailing: Switch(value: alarm.enabled, onChanged: onToggle),
        ),
      ),
    );
  }
}
