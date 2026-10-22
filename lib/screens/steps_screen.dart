import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/steps_activity_permission.dart';
import '../services/steps_health_capabilities.dart';
import '../services/steps_health_service.dart';
import '../theme/app_colors.dart';
import '../widgets/steps_celebration_overlay.dart';

enum _StepsPeriod { today, week, month }

Color _monthHeatFill(int level) {
  switch (level) {
    case 3:
      return AppColors.accent.withValues(alpha: 0.9);
    case 2:
      return AppColors.accentMuted;
    case 1:
      return AppColors.wine;
    default:
      return _StepsChrome.progressTrack;
  }
}

/// Steps “D” chrome — wine track, magenta arc, soft bloom (no flat gray-blue).
abstract final class _StepsChrome {
  static const arcTrack = Color(0xFF2E1220);
  static const arcTrackEdge = Color(0xFF4A1A30);
  static const progressTrack = Color(0xFF1E0C14);
  static const chartFill = Color(0x33FF4DA8);
  static const chartLine = Color(0xFFFF4DA8);
  static const chartDot = Color(0xFFFF2D95);
  static const chipFill = Color(0xFF2A0C1A);
}

/// StepsApp-style counter — phone pedometer first; Health optional for history.
class StepsScreen extends StatefulWidget {
  const StepsScreen({super.key});

  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> with WidgetsBindingObserver {
  final _steps = StepsHealthService.instance;
  Timer? _liveTimer;
  _StepsPeriod _period = _StepsPeriod.today;
  StepsCelebrationKind? _celebration;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _steps.addListener(_onSteps);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _steps.startTracking();
    });
    _liveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _steps.syncWithHealth) _steps.refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveTimer?.cancel();
    _steps.detachPedometer();
    _steps.removeListener(_onSteps);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _steps.startTracking();
      if (_steps.syncWithHealth) _steps.refresh();
    }
  }

  void _onSteps() {
    if (!mounted) return;
    StepsCelebrationKind? burst;
    if (_steps.goalCelebrationPending) {
      burst = StepsCelebrationKind.goal;
      _steps.goalCelebrationPending = false;
      _steps.streakCelebrationPending = false;
    } else if (_steps.streakCelebrationPending) {
      burst = StepsCelebrationKind.streak;
      _steps.streakCelebrationPending = false;
    }
    setState(() => _celebration = burst ?? _celebration);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Steps'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Daily goal',
            onPressed: () => _editGoal(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_celebration != null)
            Positioned.fill(
              child: StepsCelebrationOverlay(
                kind: _celebration!,
                streakDays: _steps.streakDays,
                onDone: () => setState(() => _celebration = null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_steps.isSupported) {
      return _message('Steps need a physical iPhone or Android phone.');
    }

    final goal = _steps.dailyGoal;
    final now = DateTime.now();
    final monthLabel = DateFormat.yMMMM().format(now);

    return RefreshIndicator(
      onRefresh: () async {
        await _steps.startTracking();
        if (_steps.syncWithHealth) {
          await _steps.refresh(requestHealthPermission: true);
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _StepsDateHeader(goal: goal),
          const SizedBox(height: 16),
          _UnderlinePeriodTabs(
            period: _period,
            onChanged: (p) => setState(() => _period = p),
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: switch (_period) {
              _StepsPeriod.today => _TodayPanel(
                  key: const ValueKey('today'),
                  steps: _steps,
                  goal: goal,
                  weekDays: _steps.calendarWeek,
                ),
              _StepsPeriod.week => _WeekPanel(
                  key: const ValueKey('week'),
                  days: _steps.calendarWeek,
                  goal: goal,
                  weekTotal: _steps.sumSteps(_steps.calendarWeek),
                  weekAvg: _steps.averageSteps(_steps.calendarWeek),
                ),
              _StepsPeriod.month => _MonthPanel(
                  key: const ValueKey('month'),
                  monthLabel: monthLabel,
                  grid: _steps.calendarMonthGrid,
                  days: _steps.calendarMonth,
                  goal: goal,
                  monthTotal: _steps.sumSteps(_steps.calendarMonth),
                  monthAvg: _steps.averageSteps(_steps.calendarMonth),
                ),
            },
          ),
          const SizedBox(height: 24),
          _TrackingToggles(steps: _steps),
        ],
      ),
    );
  }

  Widget _message(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, height: 1.45),
        ),
      ),
    );
  }

  Future<void> _editGoal(BuildContext context) async {
    final ctrl = TextEditingController(text: '${_steps.dailyGoal}');
    final next = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily goal'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '10000'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (next != null && next > 0) {
      await _steps.setDailyGoal(next);
    }
  }

  static String _formatCount(int? n) =>
      n == null ? '—' : NumberFormat.decimalPattern().format(n);
}

class _StepsDateHeader extends StatelessWidget {
  const _StepsDateHeader({required this.goal});

  final int goal;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateLabel = DateFormat('EEE, MMM d').format(now);
    final goalLabel = goal >= 1000
        ? 'Goal ${(goal / 1000).toStringAsFixed(goal % 1000 == 0 ? 0 : 1)}k'
        : 'Goal $goal';

    return Row(
      children: [
        Text(
          dateLabel,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _StepsChrome.chipFill,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.45),
            ),
          ),
          child: Text(
            goalLabel,
            style: const TextStyle(
              color: AppColors.accentGlow,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _UnderlinePeriodTabs extends StatelessWidget {
  const _UnderlinePeriodTabs({
    required this.period,
    required this.onChanged,
  });

  final _StepsPeriod period;
  final ValueChanged<_StepsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _tab('Today', _StepsPeriod.today),
        const SizedBox(width: 28),
        _tab('Week', _StepsPeriod.week),
        const SizedBox(width: 28),
        _tab('Month', _StepsPeriod.month),
      ],
    );
  }

  Widget _tab(String label, _StepsPeriod value) {
    final selected = period == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.onSurface : AppColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 2,
              width: selected ? 28 : 0,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(1),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.55),
                          blurRadius: 6,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayPanel extends StatelessWidget {
  const _TodayPanel({
    super.key,
    required this.steps,
    required this.goal,
    required this.weekDays,
  });

  final StepsHealthService steps;
  final int goal;
  final List<DaySteps> weekDays;

  @override
  Widget build(BuildContext context) {
    final progress =
        goal > 0 ? (steps.todaySteps / goal).clamp(0.0, 1.0) : 0.0;
    final pct = (progress * 100).round();
    final left = (goal - steps.todaySteps).clamp(0, goal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ArcHero(progress: progress, steps: steps.todaySteps),
        const SizedBox(height: 4),
        Text(
          '$pct% of daily goal · ~${steps.todayDistanceKm.toStringAsFixed(2)} km',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        if (steps.pedestrianStatus == 'walking')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Walking',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.accentGlow,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        const SizedBox(height: 16),
        _GoalProgressBar(
          progress: progress,
          leftLabel: 'Progress',
          rightLabel:
              '${NumberFormat.decimalPattern().format(left)} left',
        ),
        if (steps.streakDays > 0) ...[
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _StepsChrome.chipFill,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_fire_department,
                    size: 18,
                    color: AppColors.accentGlow,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${steps.streakDays}-day streak',
                    style: const TextStyle(
                      color: AppColors.accentGlow,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 28),
        Divider(color: AppColors.border.withValues(alpha: 0.65), height: 1),
        const SizedBox(height: 20),
        Text(
          'This week',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 12),
        _WeekTrendChart(days: weekDays, goal: goal),
      ],
    );
  }
}

class _WeekPanel extends StatelessWidget {
  const _WeekPanel({
    super.key,
    required this.days,
    required this.goal,
    required this.weekTotal,
    required this.weekAvg,
  });

  final List<DaySteps> days;
  final int goal;
  final int? weekTotal;
  final int? weekAvg;

  @override
  Widget build(BuildContext context) {
    final range = _weekRangeLabel(days);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          range,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.onSurface,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Monday – Sunday',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _StatTile(
              label: 'Week total',
              value: _StepsScreenState._formatCount(weekTotal),
            ),
            _StatTile(
              label: 'Daily avg',
              value: _StepsScreenState._formatCount(weekAvg),
            ),
            _StatTile(
              label: 'Best day',
              value: _StepsScreenState._formatCount(_bestDay(days)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _WeekTrendChart(days: days, goal: goal),
      ],
    );
  }

  static String _weekRangeLabel(List<DaySteps> days) {
    if (days.isEmpty) return 'This week';
    final start = days.first.date;
    final end = days.last.date;
    final f = DateFormat.MMMd();
    return '${f.format(start)} – ${f.format(end)}';
  }

  static int? _bestDay(List<DaySteps> days) {
    int? best;
    for (final d in days) {
      if (d.steps == null) continue;
      best = best == null ? d.steps : math.max(best, d.steps!);
    }
    return best;
  }
}

class _MonthPanel extends StatelessWidget {
  const _MonthPanel({
    super.key,
    required this.monthLabel,
    required this.grid,
    required this.days,
    required this.goal,
    required this.monthTotal,
    required this.monthAvg,
  });

  final String monthLabel;
  final List<DaySteps?> grid;
  final List<DaySteps> days;
  final int goal;
  final int? monthTotal;
  final int? monthAvg;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          monthLabel,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.onSurface,
              ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _StatTile(
              label: 'Month total',
              value: _StepsScreenState._formatCount(monthTotal),
            ),
            _StatTile(
              label: 'Daily avg',
              value: _StepsScreenState._formatCount(monthAvg),
            ),
            _StatTile(
              label: 'Active days',
              value: '${_activeDays(days)}',
            ),
          ],
        ),
        const SizedBox(height: 20),
        _MonthHeatCalendar(grid: grid, goal: goal),
        const SizedBox(height: 12),
        _MonthHeatLegend(goal: goal),
      ],
    );
  }

  static int _activeDays(List<DaySteps> days) {
    var n = 0;
    for (final d in days) {
      if (d.steps != null && d.steps! > 0) n++;
    }
    return n;
  }
}

class _TrackingToggles extends StatelessWidget {
  const _TrackingToggles({required this.steps});

  final StepsHealthService steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (steps.activityPermissionDenied)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  steps.errorMessage ?? 'Physical activity permission needed.',
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () => StepsActivityPermission.openSettings(),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          ),
        if (!steps.allowTracking)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Turn on Allow tracking to count steps.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        if (steps.errorMessage != null && !steps.pedometerListening)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              steps.errorMessage!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
            ),
          ),
        SwitchListTile(
          title: const Text('Allow tracking'),
          subtitle: const Text(
            'Phone motion sensor (like StepsApp).',
          ),
          value: steps.allowTracking,
          onChanged: (v) => steps.setAllowTracking(v),
        ),
        if (Platform.isAndroid)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Tip: add the Steps home-screen widget from the Android widget picker.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        if (steps.healthSyncAvailable)
          SwitchListTile(
            title: const Text('Sync with Health Connect'),
            subtitle: const Text(
              'Optional: full history from Health Connect (Android).',
            ),
            value: steps.syncWithHealth,
            onChanged: (v) => steps.setSyncWithHealth(v),
          )
        else if (StepsHealthCapabilities.isIosMotionOnly)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              StepsHealthCapabilities.iosMotionOnlyMessage,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        if (steps.healthSyncAvailable &&
            steps.syncWithHealth &&
            !steps.healthAuthorized &&
            steps.loading)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (steps.healthSyncAvailable &&
            steps.syncWithHealth &&
            !steps.healthAuthorized &&
            !steps.loading &&
            !steps.healthConnectAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                Text(
                  'Install Health Connect for full month history.',
                  style: TextStyle(color: AppColors.muted),
                ),
                TextButton(
                  onPressed: () => steps.installHealthConnect(),
                  child: const Text('Get Health Connect'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ArcHero extends StatelessWidget {
  const _ArcHero({required this.progress, required this.steps});

  final double progress;
  final int steps;

  @override
  Widget build(BuildContext context) {
    const w = 280.0;
    const h = 148.0;
    return SizedBox(
      width: w,
      height: h + 36,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          CustomPaint(
            size: const Size(w, h),
            painter: _ArcPainter(progress: progress),
          ),
          Positioned(
            top: h - 52,
            child: Text(
              NumberFormat.decimalPattern().format(steps),
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w300,
                color: AppColors.onSurface,
                letterSpacing: 0.5,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final cx = size.width / 2;
    final cy = size.height - 6;
    final r = size.width / 2 - stroke - 4;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    const start = math.pi;
    const sweepFull = math.pi;
    final sweep = sweepFull * progress.clamp(0.0, 1.0);

    final track = Paint()
      ..color = _StepsChrome.arcTrack
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweepFull, false, track);

    final trackRim = Paint()
      ..color = _StepsChrome.arcTrackEdge.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawArc(rect, start, sweepFull, false, trackRim);

    if (sweep > 0.02) {
      final glow = Paint()
        ..color = AppColors.accent.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawArc(rect, start, sweep, false, glow);

      final arc = Paint()
        ..color = _StepsChrome.chartLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep, false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) => old.progress != progress;
}

class _GoalProgressBar extends StatelessWidget {
  const _GoalProgressBar({
    required this.progress,
    required this.leftLabel,
    required this.rightLabel,
  });

  final double progress;
  final String leftLabel;
  final String rightLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              leftLabel,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const Spacer(),
            Text(
              rightLabel,
              style: TextStyle(
                color: AppColors.accentGlow,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 8,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: _StepsChrome.progressTrack),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accent,
                          AppColors.accentGlow,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekTrendChart extends StatelessWidget {
  const _WeekTrendChart({required this.days, required this.goal});

  final List<DaySteps> days;
  final int goal;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.85),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 108,
            width: double.infinity,
            child: CustomPaint(
              painter: _WeekTrendPainter(days: days, goal: goal),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final day in days)
                Expanded(
                  child: Text(
                    DateFormat.E().format(day.date).substring(0, 1),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: _isToday(day.date)
                          ? AppColors.accentGlow
                          : AppColors.muted,
                      fontWeight: _isToday(day.date)
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }
}

class _WeekTrendPainter extends CustomPainter {
  _WeekTrendPainter({required this.days, required this.goal});

  final List<DaySteps> days;
  final int goal;

  @override
  void paint(Canvas canvas, Size size) {
    final padH = 8.0;
    final padT = 8.0;
    final padB = 12.0;
    final plotW = size.width - padH * 2;
    final plotH = size.height - padT - padB;

    var maxY = goal.toDouble();
    for (final d in days) {
      if (d.steps != null) maxY = math.max(maxY, d.steps!.toDouble());
    }
    if (maxY < 1) maxY = 1;

    final goalY = padT + plotH * (1 - goal / maxY);
    final goalPaint = Paint()
      ..color = AppColors.wine.withValues(alpha: 0.9)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(padH, goalY),
      Offset(size.width - padH, goalY),
      goalPaint,
    );

    final n = days.length;
    if (n < 2) return;

    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final steps = days[i].steps;
      if (steps == null) continue;
      final x = padH + plotW * (i / (n - 1));
      final y = padT + plotH * (1 - steps / maxY);
      points.add(Offset(x, y));
    }
    if (points.isEmpty) return;

    if (points.length >= 2) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      final fillPath = Path.from(path)
        ..lineTo(points.last.dx, padT + plotH)
        ..lineTo(points.first.dx, padT + plotH)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()..color = _StepsChrome.chartFill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = _StepsChrome.chartLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (final p in points) {
      canvas.drawCircle(p, 4, Paint()..color = _StepsChrome.chartDot);
      canvas.drawCircle(
        p,
        7,
        Paint()..color = AppColors.accent.withValues(alpha: 0.25),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WeekTrendPainter old) => old.days != days;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _MonthHeatCalendar extends StatelessWidget {
  const _MonthHeatCalendar({required this.grid, required this.goal});

  final List<DaySteps?> grid;
  final int goal;

  @override
  Widget build(BuildContext context) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.85)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final l in labels)
                Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 4,
              childAspectRatio: 1,
            ),
            itemCount: grid.length,
            itemBuilder: (context, i) {
              final cell = grid[i];
              if (cell == null) return const SizedBox.shrink();
              return _HeatDayCell(day: cell, goal: goal);
            },
          ),
        ],
      ),
    );
  }
}

class _HeatDayCell extends StatelessWidget {
  const _HeatDayCell({required this.day, required this.goal});

  final DaySteps day;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final today = _isToday(day.date);
    final level = _heatLevel(day.steps, goal);
    final fill = _monthHeatFill(level);

    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: today
              ? AppColors.accentGlow
              : AppColors.border.withValues(alpha: 0.5),
          width: today ? 1.5 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.date.day}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: today ? FontWeight.bold : FontWeight.w500,
          color: level >= 2 ? AppColors.onSurface : AppColors.muted,
        ),
      ),
    );
  }

  static int _heatLevel(int? steps, int goal) {
    if (steps == null) return -1;
    if (steps <= 0) return 0;
    final r = steps / goal;
    if (r >= 1) return 3;
    if (r >= 0.55) return 2;
    return 1;
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }
}

class _MonthHeatLegend extends StatelessWidget {
  const _MonthHeatLegend({required this.goal});

  final int goal;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Less', style: TextStyle(fontSize: 10, color: AppColors.muted)),
        const SizedBox(width: 6),
        for (final level in [0, 1, 2, 3])
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _monthHeatFill(level),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border),
            ),
          ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Goal ${NumberFormat.compact().format(goal)}+',
            style: TextStyle(fontSize: 10, color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}
