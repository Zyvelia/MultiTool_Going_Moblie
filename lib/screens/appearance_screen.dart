import 'package:flutter/material.dart';

import '../theme/appearance.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late Appearance draft;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    draft = AppearanceController.instance.value;
  }

  Future<void> _apply() async {
    setState(() => saving = true);
    try {
      await AppearanceController.instance.apply(draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appearance saved')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save appearance. Please retry.')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = draft;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance Studio'),
        actions: [
          TextButton(onPressed: saving ? null : () => setState(() => draft = const Appearance()), child: const Text('Reset')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _Preview(palette: p),
          const SizedBox(height: 22),
          Text('Theme presets', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final preset in NeonPreset.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: preset.background,
                    child: Icon(Icons.bolt_rounded, color: preset.accent),
                  ),
                  title: Text(preset.label),
                  trailing: Icon(p.preset == preset ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: p.preset == preset ? p.accentGlow : p.muted),
                  onTap: saving ? null : () => setState(() => draft = draft.copyWith(preset: preset, clearAccent: true)),
                ),
              ),
            ),
          const SizedBox(height: 18),
          Text('Accent color', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 8, children: [
            for (final color in const [
              Color(0xFFB96BFF), Color(0xFFFF78D0), Color(0xFFFF718C),
              Color(0xFF51CCFF), Color(0xFF32E6A1), Color(0xFFFFB568),
            ])
              Tooltip(
                message: 'Accent #${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                child: Semantics(
                  selected: p.accent == color,
                  button: true,
                  child: InkResponse(
                    onTap: saving ? null : () => setState(() => draft = draft.copyWith(customAccent: color)),
                    child: Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      child: p.accent == color ? const Icon(Icons.check, color: Colors.black) : null,
                    ),
                  ),
                ),
              ),
          ]),
          TextButton(onPressed: saving ? null : () => setState(() => draft = draft.copyWith(clearAccent: true)), child: const Text('Use preset accent')),
          _slider('Neon intensity', p.glow, (v) => draft = draft.copyWith(glow: v)),
          _slider('Glass effect', p.glass, (v) => draft = draft.copyWith(glass: v)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Interface animations'),
            subtitle: const Text('Turn off for reduced motion.'),
            value: p.animations,
            onChanged: saving ? null : (v) => setState(() => draft = draft.copyWith(animations: v)),
          ),
          const SizedBox(height: 12),
          const Text('Preview changes instantly. Apply saves your choices on this phone. Some legacy module-specific artwork retains its original colors.'),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: saving ? null : _apply,
          icon: const Icon(Icons.check_rounded),
          label: Text(saving ? 'Saving…' : 'Apply appearance'),
        ),
      ),
    );
  }

  Widget _slider(String name, double value, ValueChanged<double> update) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(name)),
        Text('${(value * 100).round()}%'),
      ]),
      Slider(value: value, onChanged: saving ? null : (v) => setState(() => update(v))),
    ]);
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.palette});
  final Appearance palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight, radius: 1.1,
          colors: [Color.alphaBlend(p.accent.withValues(alpha: p.glow * 0.48), p.bg), p.bg],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bolt_rounded, color: p.accentGlow, size: 34),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Z's MultiTool", style: TextStyle(color: p.onSurface, fontSize: 21, fontWeight: FontWeight.w700)),
            Text(p.preset.label, style: TextStyle(color: p.muted)),
          ])),
        ]),
        const SizedBox(height: 16),
        for (final item in const [
          (Icons.computer_rounded, 'PC Remote'),
          (Icons.library_music_rounded, 'Music'),
          (Icons.send_rounded, 'Quick Send'),
        ])
          Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: p.accentMuted, borderRadius: BorderRadius.circular(10),
                  boxShadow: p.glow == 0 ? [] : [BoxShadow(color: p.accent.withValues(alpha: p.glow * 0.28), blurRadius: 12)],
                ),
                child: Icon(item.$1, color: p.accentGlow),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(item.$2, style: TextStyle(color: p.onSurface, fontWeight: FontWeight.w600))),
              Icon(Icons.chevron_right_rounded, color: p.accentGlow),
            ]),
          ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity, padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(12)),
          child: Text('LIVE PREVIEW', textAlign: TextAlign.center,
            style: TextStyle(color: p.onAccent, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ),
      ]),
    );
  }
}
