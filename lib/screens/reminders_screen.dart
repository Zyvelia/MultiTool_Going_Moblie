import 'package:flutter/material.dart';

import '../models/reminder.dart';
import '../services/reminder_service.dart';
import '../theme/app_colors.dart';
import '../widgets/scheduling_help_dialog.dart';
import 'home_leading.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _service = ReminderService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: homeBackLeading(context),
        title: const Text('Reminders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Alarms & reminders help',
            onPressed: () => showSchedulingHelpDialog(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add_alarm),
        label: const Text('New'),
      ),
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.deferToChild,
        child: ValueListenableBuilder<List<Reminder>>(
        valueListenable: _service.reminders,
        builder: (context, items, _) {
          final active = items.where((r) => !r.completed).toList();
          final done = items.where((r) => r.completed).toList();
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Set a date, time, and note — you\'ll get a notification '
                  'when it\'s due (and a heads-up a few minutes before).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
            children: [
              if (active.isNotEmpty) ...[
                _sectionTitle('Upcoming'),
                ...active.map(
                  (r) => _ReminderTile(
                    reminder: r,
                    onEdit: () => _openEditor(context, existing: r),
                  ),
                ),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionTitle('Done'),
                ...done.map(
                  (r) => _ReminderTile(
                    reminder: r,
                    onEdit: () => _openEditor(context, existing: r),
                  ),
                ),
              ],
            ],
          );
        },
      ),
      ),
    );
  }

  Widget _sectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.accentGlow,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, {Reminder? existing}) async {
    final textCtrl = TextEditingController(text: existing?.text ?? '');
    var date = existing?.dueAt ?? DateTime.now().add(const Duration(hours: 1));
    var time = TimeOfDay.fromDateTime(date);
    var nudge = existing?.nudgeMinutesBefore ?? 5;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        void dismissKeyboard() {
          FocusManager.instance.primaryFocus?.unfocus();
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: MediaQuery.paddingOf(ctx).bottom +
                MediaQuery.viewInsetsOf(ctx).bottom +
                20,
          ),
          child: GestureDetector(
            onTap: dismissKeyboard,
            behavior: HitTestBehavior.opaque,
            child: StatefulBuilder(
            builder: (context, setLocal) {
              Future<void> pickDate() async {
                dismissKeyboard();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                );
                if (picked != null) {
                  setLocal(() {
                    date = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                      time.hour,
                      time.minute,
                    );
                  });
                }
              }

              Future<void> pickTime() async {
                dismissKeyboard();
                final picked = await showTimePicker(
                  context: context,
                  initialTime: time,
                );
                if (picked != null) {
                  setLocal(() {
                    time = picked;
                    date = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      picked.hour,
                      picked.minute,
                    );
                  });
                }
              }

              final loc = MaterialLocalizations.of(context);
              final dateLabel = loc.formatMediumDate(date);
              final timeLabel = loc.formatTimeOfDay(time);

              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    existing == null ? 'New reminder' : 'Edit reminder',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: textCtrl,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.done,
                    onTapOutside: (_) => dismissKeyboard(),
                    onSubmitted: (_) => dismissKeyboard(),
                    onEditingComplete: dismissKeyboard,
                    decoration: const InputDecoration(
                      labelText: 'What to remember',
                      hintText: 'Take meds, call mom, raid night…',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month),
                    title: const Text('Date'),
                    subtitle: Text(dateLabel),
                    onTap: pickDate,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: const Text('Time'),
                    subtitle: Text(timeLabel),
                    onTap: pickTime,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Heads-up before'),
                    subtitle: Text('Notify $nudge minutes early'),
                    value: nudge > 0,
                    onChanged: (on) => setLocal(() => nudge = on ? 5 : 0),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      final due = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                      try {
                        if (existing != null) {
                          await _service.update(
                            id: existing.id,
                            text: textCtrl.text,
                            dueAt: due,
                            nudgeMinutesBefore: nudge,
                          );
                        } else {
                          await _service.add(
                            text: textCtrl.text,
                            dueAt: due,
                            nudgeMinutesBefore: nudge,
                          );
                        }
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString())),
                        );
                      }
                    },
                    child: Text(existing == null ? 'Save reminder' : 'Update'),
                  ),
                ],
              ),
              );
            },
          ),
          ),
        );
      },
    );
    textCtrl.dispose();
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder, required this.onEdit});

  final Reminder reminder;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final when =
        '${loc.formatMediumDate(reminder.dueAt)} · ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(reminder.dueAt))}';
    final service = ReminderService.instance;

    return Dismissible(
      key: ValueKey(reminder.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.accentMuted,
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => service.delete(reminder.id),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: CheckboxListTile(
          value: reminder.completed,
          onChanged: (v) => service.toggleCompleted(reminder.id, v ?? false),
          title: InkWell(
            onTap: onEdit,
            child: Text(
              reminder.text,
              style: TextStyle(
                decoration: reminder.completed ? TextDecoration.lineThrough : null,
                color: reminder.completed ? AppColors.muted : null,
              ),
            ),
          ),
          subtitle: InkWell(onTap: onEdit, child: Text(when)),
          secondary: reminder.isPast && !reminder.completed
              ? const Icon(Icons.warning_amber_rounded, color: AppColors.accent)
              : const Icon(Icons.notifications_active_outlined),
        ),
      ),
    );
  }
}
