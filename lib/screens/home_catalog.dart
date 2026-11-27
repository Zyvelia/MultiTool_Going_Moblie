import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/home_tabs.dart';

enum HomeToolGroup { media, remote, productivity, utility }

class HomeTool {
  const HomeTool({
    required this.id,
    required this.tab,
    required this.name,
    required this.line,
    required this.icon,
    required this.group,
  });

  final String id;
  final int tab;
  final String name;
  final String line;
  final IconData icon;
  final HomeToolGroup group;
}

const homeTools = <HomeTool>[
  HomeTool(
    id: 'music',
    tab: HomeTabs.music,
    name: 'Music',
    line: 'Play your library on this phone.',
    icon: Icons.library_music_rounded,
    group: HomeToolGroup.media,
  ),
  HomeTool(
    id: 'vault',
    tab: HomeTabs.vault,
    name: 'Vault',
    line: 'Passwords, codes, and secure storage.',
    icon: Icons.lock_rounded,
    group: HomeToolGroup.utility,
  ),
  HomeTool(
    id: 'pc',
    tab: HomeTabs.pc,
    name: 'PC Remote',
    line: 'Reach the desktop, stream tools, and wake the PC.',
    icon: Icons.computer_rounded,
    group: HomeToolGroup.remote,
  ),
  HomeTool(
    id: 'notes',
    tab: HomeTabs.notes,
    name: 'Notes',
    line: 'Read, write, and sync notes.',
    icon: Icons.sticky_note_2_rounded,
    group: HomeToolGroup.productivity,
  ),
  HomeTool(
    id: 'chat',
    tab: HomeTabs.chat,
    name: 'Chat',
    line: 'Talk to the model on your PC.',
    icon: Icons.forum_rounded,
    group: HomeToolGroup.remote,
  ),
  HomeTool(
    id: 'games',
    tab: HomeTabs.games,
    name: 'Games',
    line: 'Launch and manage games.',
    icon: Icons.sports_esports_rounded,
    group: HomeToolGroup.media,
  ),
  HomeTool(
    id: 'yt',
    tab: HomeTabs.yt,
    name: 'YouTube',
    line: 'Send a video link to download.',
    icon: Icons.ondemand_video_rounded,
    group: HomeToolGroup.media,
  ),
  HomeTool(
    id: 'send',
    tab: HomeTabs.send,
    name: 'Quick Send',
    line: 'Move files between the phone and the PC.',
    icon: Icons.send_rounded,
    group: HomeToolGroup.remote,
  ),
  HomeTool(
    id: 'reminders',
    tab: HomeTabs.reminders,
    name: 'Reminders',
    line: 'Track deadlines and nudges.',
    icon: Icons.notifications_active_rounded,
    group: HomeToolGroup.productivity,
  ),
  HomeTool(
    id: 'clock',
    tab: HomeTabs.clock,
    name: 'Clock',
    line: 'Alarms, times, and schedules.',
    icon: Icons.alarm_rounded,
    group: HomeToolGroup.utility,
  ),
];

const _orderKey = 'home_card_order';
const _pinnedKey = 'home_card_pinned';
const _recentKey = 'home_recent_tools';

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
  final _searchController = TextEditingController();

  List<String> _order = homeTools.map((tool) => tool.id).toList();
  Set<String> _pinned = {'music', 'pc', 'notes', 'send'};
  List<String> _recent = [];
  String? _lifted;
  bool _customize = false;
  String _query = '';
  HomeToolGroup? _group;
  int _destination = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getStringList(_orderKey);
    final savedPinned = prefs.getStringList(_pinnedKey);
    final savedRecent = prefs.getStringList(_recentKey);
    if (!mounted) return;
    setState(() {
      if (savedOrder != null) {
        _order = _normalize(savedOrder);
      }
      if (savedPinned != null) {
        _pinned = _knownIds(savedPinned).toSet();
      }
      if (savedRecent != null) {
        _recent = _knownIds(savedRecent).take(5).toList();
      }
    });
  }

  List<String> _knownIds(Iterable<String> saved) {
    final known = homeTools.map((tool) => tool.id).toSet();
    return saved.where(known.contains).toSet().toList();
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

  Future<void> _saveOrder(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, order);
  }

  Future<void> _savePinned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinnedKey, _pinned.toList());
  }

  Future<void> _saveRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentKey, _recent);
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
    _saveOrder(next);
  }

  void _togglePinned(String id) {
    final next = {..._pinned};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    setState(() => _pinned = next);
    _savePinned();
  }

  void _openTool(HomeTool tool) {
    final nextRecent = [tool.id, ..._recent.where((id) => id != tool.id)].take(5).toList();
    setState(() => _recent = nextRecent);
    _saveRecent();
    widget.onOpen(tool.tab);
  }

  List<HomeTool> get _orderedTools => [
    for (final id in _order) homeTools.firstWhere((tool) => tool.id == id),
  ];

  List<HomeTool> get _filteredTools {
    final lower = _query.trim().toLowerCase();
    return _orderedTools.where((tool) {
      final groupMatch = _group == null || tool.group == _group;
      if (!groupMatch) return false;
      if (lower.isEmpty) return true;
      final haystack = '${tool.name} ${tool.line}'.toLowerCase();
      return haystack.contains(lower);
    }).toList();
  }

  List<HomeTool> _fromIds(Iterable<String> ids) {
    final index = {for (final tool in homeTools) tool.id: tool};
    return [for (final id in ids) if (index[id] != null) index[id]!];
  }

  void _navigate(int index) {
    FocusScope.of(context).unfocus();
    if (index == 2) {
      _openTool(homeTools.firstWhere((tool) => tool.id == 'pc'));
      return;
    }
    setState(() {
      _destination = index;
      _customize = false;
      _lifted = null;
    });
  }

  void _toggleCustomize() {
    setState(() {
      _destination = 1;
      _customize = !_customize;
      _lifted = null;
      if (_customize) {
        _group = null;
        _query = '';
        _searchController.clear();
      }
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _group = null;
    });
  }

  Widget _toolRow(HomeTool tool, {bool editing = false}) {
    return _NeonToolRow(
      key: ValueKey(tool.id),
      tool: tool,
      pinned: _pinned.contains(tool.id),
      lifted: _lifted == tool.id,
      editing: editing,
      onOpen: () {
        if (editing && _lifted != null) {
          _dropOn(tool.id);
        } else {
          FocusScope.of(context).unfocus();
          _openTool(tool);
        }
      },
      onPin: () => _togglePinned(tool.id),
      onMove: () => _toggleGrip(tool.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTools;
    final pinned = _fromIds(_order.where(_pinned.contains));
    final recent = _fromIds(_recent);
    final title = switch (_destination) {
      0 => 'Home',
      3 => 'Activity',
      _ => 'Tools',
    };

    return Scaffold(
      backgroundColor: _CatalogPalette.background,
      body: SafeArea(
        bottom: false,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topRight,
              radius: 1.2,
              colors: [Color(0xFF21102D), _CatalogPalette.background],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: CustomScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _destination == 0 ? Icons.home_rounded
                                    : _destination == 3 ? Icons.history_rounded
                                    : Icons.grid_view_rounded,
                                size: 27,
                                color: _CatalogPalette.accent,
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Text(title, style: const TextStyle(
                                  fontSize: 25, fontWeight: FontWeight.w700,
                                  color: _CatalogPalette.text,
                                  letterSpacing: -0.5,
                                )),
                              ),
                              _CatalogIconButton(
                                tooltip: _customize ? 'Done customizing' : 'Customize tools',
                                icon: _customize ? Icons.check_rounded : Icons.tune_rounded,
                                onPressed: _toggleCustomize,
                                selected: _customize,
                              ),
                              const SizedBox(width: 6),
                              _CatalogIconButton(
                                tooltip: 'Settings',
                                icon: Icons.settings_outlined,
                                onPressed: widget.onSettings,
                              ),
                            ],
                          ),
                          if (_destination == 1) ...[
                            const SizedBox(height: 16),
                            TextField(
                              controller: _searchController,
                              onChanged: (value) => setState(() => _query = value),
                              textInputAction: TextInputAction.search,
                              style: const TextStyle(color: _CatalogPalette.text),
                              decoration: InputDecoration(
                                hintText: 'Search tools, modules, features…',
                                hintStyle: const TextStyle(color: _CatalogPalette.muted, fontSize: 13),
                                filled: true,
                                fillColor: _CatalogPalette.panel,
                                isDense: true,
                                prefixIcon: const Icon(Icons.search_rounded, color: _CatalogPalette.muted),
                                suffixIcon: _query.isEmpty ? null : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: _CatalogPalette.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: _CatalogPalette.accent),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _CatalogFilters(
                              selected: _group,
                              onChanged: (group) => setState(() => _group = group),
                            ),
                            const SizedBox(height: 12),
                            if (_customize)
                              _CatalogNotice(
                                icon: Icons.swap_vert_rounded,
                                text: _lifted == null
                                    ? 'Tap a grip to move a tool. Tap a star to pin it.'
                                    : 'Select the tool to place it before.',
                              )
                            else
                              Row(
                                children: [
                                  const Expanded(child: Text('TOOL CATALOG', style: _CatalogPalette.eyebrow)),
                                  Text('${filtered.length} tools', style: const TextStyle(
                                    color: _CatalogPalette.muted, fontSize: 12,
                                  )),
                                ],
                              ),
                          ] else ...[
                            const SizedBox(height: 14),
                            _CatalogNotice(
                              icon: _destination == 0 ? Icons.bolt_rounded : Icons.history_rounded,
                              text: _destination == 0
                                  ? 'Your pinned tools, ready to launch.'
                                  : 'Recently opened tools on this device.',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_destination == 1)
                    if (filtered.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const _CatalogNotice(icon: Icons.search_off_rounded, text: 'No matching tools.'),
                              TextButton(onPressed: _clearFilters, child: const Text('Reset filters')),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _toolRow(filtered[index], editing: _customize),
                            ),
                            childCount: filtered.length,
                          ),
                        ),
                      )
                  else ...[
                    if (_destination == 0)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('PINNED TOOLS', style: _CatalogPalette.eyebrow),
                              const SizedBox(height: 10),
                              if (pinned.isEmpty)
                                const _CatalogNotice(icon: Icons.star_border_rounded, text: 'Pin tools from the Tools tab.')
                              else
                                for (final tool in pinned)
                                  Padding(padding: const EdgeInsets.only(bottom: 8), child: _toolRow(tool)),
                            ],
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('RECENTLY OPENED', style: _CatalogPalette.eyebrow),
                            const SizedBox(height: 10),
                            if (recent.isEmpty)
                              const _CatalogNotice(icon: Icons.history_rounded, text: 'Open a tool to see it here.')
                            else
                              for (final tool in recent)
                                Padding(padding: const EdgeInsets.only(bottom: 8), child: _toolRow(tool)),
                            if (_destination == 0)
                              TextButton.icon(
                                onPressed: () => _navigate(1),
                                icon: const Icon(Icons.grid_view_rounded),
                                label: const Text('Browse all tools'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Container(
          decoration: BoxDecoration(
            color: _CatalogPalette.panel,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _CatalogPalette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              indicatorColor: const Color(0xFF49216D),
              labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                fontSize: 11,
                color: states.contains(WidgetState.selected) ? _CatalogPalette.accent : _CatalogPalette.muted,
                fontWeight: FontWeight.w600,
              )),
              iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                size: 23,
                color: states.contains(WidgetState.selected) ? _CatalogPalette.accent : _CatalogPalette.muted,
              )),
            ),
            child: NavigationBar(
              height: 66,
              elevation: 0,
              selectedIndex: _destination,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: _navigate,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Tools'),
                NavigationDestination(icon: Icon(Icons.devices_outlined), label: 'Devices'),
                NavigationDestination(icon: Icon(Icons.history_rounded), label: 'Activity'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogPalette {
  static const background = Color(0xFF090710);
  static const panel = Color(0xFF151020);
  static const border = Color(0xFF392749);
  static const accent = Color(0xFFD28AFF);
  static const text = Color(0xFFF8F2FF);
  static const muted = Color(0xFFB9AFCB);
  static const eyebrow = TextStyle(
    color: muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4,
  );

  static Color tool(HomeTool tool) => switch (tool.id) {
    'music' => const Color(0xFFF38BDB),
    'vault' => const Color(0xFFFFB568),
    'pc' => const Color(0xFF63D4FF),
    'notes' => const Color(0xFFB89AFF),
    'chat' => const Color(0xFF81C2FF),
    'games' => const Color(0xFFE09AFF),
    'yt' => const Color(0xFFFF819D),
    'send' => const Color(0xFF62E6CF),
    'reminders' => const Color(0xFFFFC46F),
    _ => const Color(0xFF96AEFF),
  };
}

class _CatalogIconButton extends StatelessWidget {
  const _CatalogIconButton({
    required this.tooltip, required this.icon, required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 21),
    style: IconButton.styleFrom(
      foregroundColor: selected ? _CatalogPalette.accent : _CatalogPalette.text,
      backgroundColor: _CatalogPalette.panel,
      minimumSize: const Size(44, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: selected ? _CatalogPalette.accent : _CatalogPalette.border),
      ),
    ),
  );
}

class _CatalogFilters extends StatelessWidget {
  const _CatalogFilters({required this.selected, required this.onChanged});
  final HomeToolGroup? selected;
  final ValueChanged<HomeToolGroup?> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = <(String, HomeToolGroup?)>[
      ('All', null),
      ('Media', HomeToolGroup.media),
      ('Remote', HomeToolGroup.remote),
      ('Productivity', HomeToolGroup.productivity),
      ('Utilities', HomeToolGroup.utility),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: ChoiceChip(
                label: Text(item.$1),
                selected: selected == item.$2,
                onSelected: (_) => onChanged(item.$2),
                showCheckmark: false,
                backgroundColor: _CatalogPalette.panel,
                selectedColor: const Color(0xFF6528A1),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected == item.$2 ? Colors.white : _CatalogPalette.muted,
                ),
                side: BorderSide(color: selected == item.$2 ? _CatalogPalette.accent : _CatalogPalette.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
        ],
      ),
    );
  }
}

class _NeonToolRow extends StatelessWidget {
  const _NeonToolRow({
    super.key, required this.tool, required this.pinned, required this.lifted,
    required this.editing, required this.onOpen, required this.onPin,
    required this.onMove,
  });

  final HomeTool tool;
  final bool pinned, lifted, editing;
  final VoidCallback onOpen, onPin, onMove;

  @override
  Widget build(BuildContext context) {
    final tint = _CatalogPalette.tool(tool);
    final radius = BorderRadius.circular(16);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: lifted ? tint : _CatalogPalette.border),
          gradient: LinearGradient(
            colors: [Color.alphaBlend(tint.withValues(alpha: 0.09), _CatalogPalette.panel), _CatalogPalette.panel],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onOpen,
                onLongPress: onPin,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 43, height: 43,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(colors: [
                            tint.withValues(alpha: 0.25),
                            tint.withValues(alpha: 0.07),
                          ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          border: Border.all(color: tint.withValues(alpha: 0.28)),
                          boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.12), blurRadius: 12)],
                        ),
                        child: Icon(tool.icon, color: tint, size: 23),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(child: Text(tool.name, style: const TextStyle(
                                color: _CatalogPalette.text, fontSize: 15, fontWeight: FontWeight.w700,
                              ))),
                              if (pinned) ...[
                                const SizedBox(width: 5),
                                Icon(Icons.push_pin_rounded, color: tint, size: 12, semanticLabel: 'Pinned'),
                              ],
                            ]),
                            const SizedBox(height: 3),
                            Text(tool.line, style: const TextStyle(
                              color: _CatalogPalette.muted, fontSize: 12, height: 1.25,
                            )),
                          ],
                        ),
                      ),
                      if (!editing) ...[
                        const SizedBox(width: 5),
                        Icon(Icons.chevron_right_rounded, size: 21, color: tint),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (editing) ...[
              IconButton(
                tooltip: pinned ? 'Unpin ${tool.name}' : 'Pin ${tool.name}',
                onPressed: onPin,
                icon: Icon(pinned ? Icons.star_rounded : Icons.star_border_rounded, color: tint),
              ),
              IconButton(
                tooltip: 'Move ${tool.name}',
                onPressed: onMove,
                icon: Icon(Icons.drag_indicator_rounded, color: lifted ? tint : _CatalogPalette.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CatalogNotice extends StatelessWidget {
  const _CatalogNotice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: _CatalogPalette.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _CatalogPalette.border),
    ),
    child: Row(children: [
      Icon(icon, color: _CatalogPalette.accent),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(color: _CatalogPalette.muted, fontSize: 13))),
    ]),
  );
}
