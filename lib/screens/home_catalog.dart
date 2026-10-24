import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/home_tabs.dart';
import '../theme/app_colors.dart';

class HomeTool {
  const HomeTool({
    required this.id,
    required this.tab,
    required this.name,
    required this.line,
  });

  final String id;
  final int tab;
  final String name;
  final String line;
}

const homeTools = <HomeTool>[
  HomeTool(id: 'music', tab: HomeTabs.music, name: 'Music', line: 'Play the library on this phone.'),
  HomeTool(id: 'vault', tab: HomeTabs.vault, name: 'Vault', line: 'Passwords and codes.'),
  HomeTool(id: 'pc', tab: HomeTabs.pc, name: 'PC', line: 'The desktop, from here.'),
  HomeTool(id: 'notes', tab: HomeTabs.notes, name: 'Notes', line: 'Read and write notes.'),
  HomeTool(id: 'chat', tab: HomeTabs.chat, name: 'Chat', line: 'Talk to the model on the PC.'),
  HomeTool(id: 'games', tab: HomeTabs.games, name: 'Games', line: 'Launch a game on the PC.'),
  HomeTool(id: 'yt', tab: HomeTabs.yt, name: 'YT', line: 'Send a link to download.'),
  HomeTool(id: 'send', tab: HomeTabs.send, name: 'Send', line: 'Files between the phone and the PC.'),
  HomeTool(id: 'reminders', tab: HomeTabs.reminders, name: 'Reminders', line: 'What is due.'),
  HomeTool(id: 'clock', tab: HomeTabs.clock, name: 'Clock', line: 'Alarms and the time.'),
];

const _orderKey = 'home_card_order';

class HomeCatalog extends StatefulWidget {
  const HomeCatalog({
    super.key,
    required this.onOpen,
    required this.onSettings,
  });

  final ValueChanged<int> onOpen;
  final VoidCallback onSettings;

  @override
  State<HomeCatalog> createState() => _HomeCatalogState();
}

class _HomeCatalogState extends State<HomeCatalog> {
  List<String> _order = homeTools.map((tool) => tool.id).toList();
  String? _lifted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_orderKey);
    if (!mounted || saved == null) return;
    setState(() => _order = _normalize(saved));
  }

  List<String> _normalize(List<String> saved) {
    final known = {for (final tool in homeTools) tool.id};
    final next = <String>[];
    for (final id in saved) {
      if (known.contains(id) && !next.contains(id)) next.add(id);
    }
    for (final tool in homeTools) {
      if (!next.contains(tool.id)) next.add(tool.id);
    }
    return next;
  }

  Future<void> _save(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, order);
  }

  void _toggleGrip(String id) {
    setState(() => _lifted = _lifted == id ? null : id);
  }

  void _dropOn(String targetId) {
    final lifted = _lifted;
    if (lifted == null || lifted == targetId) {
      setState(() => _lifted = null);
      return;
    }
    final next = _order.where((id) => id != lifted).toList();
    final index = next.indexOf(targetId);
    next.insert(index < 0 ? next.length : index, lifted);
    setState(() {
      _order = next;
      _lifted = null;
    });
    _save(next);
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final id in _order)
        homeTools.firstWhere((tool) => tool.id == id),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 14, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Home',
                          style: TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _lifted == null
                              ? 'Most used at the top.'
                              : 'Tap the card that should sit below.',
                          style: const TextStyle(color: AppColors.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: widget.onSettings,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.card,
                      foregroundColor: AppColors.onSurface,
                      fixedSize: const Size(40, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    icon: const Icon(Icons.settings, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                itemCount: cards.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final tool = cards[index];
                  return _ToolCard(
                    tool: tool,
                    lifted: _lifted == tool.id,
                    onOpen: () {
                      if (_lifted != null) {
                        _dropOn(tool.id);
                      } else {
                        widget.onOpen(tool.tab);
                      }
                    },
                    onGrip: () => _toggleGrip(tool.id),
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

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.tool,
    required this.lifted,
    required this.onOpen,
    required this.onGrip,
  });

  final HomeTool tool;
  final bool lifted;
  final VoidCallback onOpen;
  final VoidCallback onGrip;

  @override
  Widget build(BuildContext context) {
    final markColor = lifted ? AppColors.accent : AppColors.accentMuted;
    final markInk = lifted ? AppColors.bg : AppColors.onSurface;

    return Material(
      color: lifted ? AppColors.accentMuted : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: lifted ? AppColors.accent : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: markColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          tool.name.characters.first,
                          style: TextStyle(
                            color: markInk,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              tool.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tool.line,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                tooltip: 'Move ${tool.name}',
                onPressed: onGrip,
                style: IconButton.styleFrom(
                  backgroundColor: lifted ? AppColors.accent : Colors.transparent,
                  foregroundColor: lifted ? AppColors.bg : AppColors.muted,
                  fixedSize: const Size(32, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const _GripDots(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GripDots extends StatelessWidget {
  const _GripDots();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? AppColors.muted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < 3; row++) ...[
          if (row > 0) const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dot(color),
              const SizedBox(width: 3),
              _dot(color),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
