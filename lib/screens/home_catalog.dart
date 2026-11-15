import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/home_tabs.dart';
import '../theme/app_colors.dart';

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
        _pinned = _normalize(savedPinned).toSet();
      }
      if (savedRecent != null) {
        _recent = _normalize(savedRecent);
      }
    });
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
    await prefs.setStringList(_pinnedKey, _normalize(_pinned.toList()));
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTools;
    final pinned = _fromIds(_order.where(_pinned.contains));
    final recent = _fromIds(_recent);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 700;
            final toolColumns = constraints.maxWidth >= 960
                ? 3
                : constraints.maxWidth >= 620
                    ? 2
                    : 1;

            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(wide ? 24 : 18, 16, wide ? 24 : 18, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _HeaderRow(
                            customize: _customize,
                            lifted: _lifted,
                            onSettings: widget.onSettings,
                            onCustomize: () {
                              setState(() {
                                _customize = !_customize;
                                _lifted = null;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          _HeroCard(
                            toolCount: homeTools.length,
                            pinnedCount: _pinned.length,
                            recentCount: _recent.length,
                            onOpenMain: () => _openTool(homeTools.firstWhere((t) => t.id == 'music')),
                            onOpenRemote: () => _openTool(homeTools.firstWhere((t) => t.id == 'pc')),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _searchController,
                            onChanged: (value) => setState(() => _query = value),
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Search tools, music, notes, remote…',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _query = '');
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _GroupChips(
                            selected: _group,
                            onChanged: (group) => setState(() => _group = group),
                          ),
                          if (_customize) ...[
                            const SizedBox(height: 14),
                            _CustomizeBanner(lifted: _lifted),
                          ],
                          if (!_customize && pinned.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            _SectionHeader(
                              title: 'Quick access',
                              subtitle: 'Your pinned tools stay here.',
                            ),
                            const SizedBox(height: 10),
                            _QuickAccessWrap(
                              tools: pinned,
                              onOpen: _openTool,
                            ),
                          ],
                          if (!_customize && recent.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            _SectionHeader(
                              title: 'Continue',
                              subtitle: 'Jump back into what you used last.',
                            ),
                            const SizedBox(height: 10),
                            _RecentStrip(tools: recent, onOpen: _openTool),
                          ],
                          const SizedBox(height: 18),
                          _SectionHeader(
                            title: _customize ? 'Reorder tools' : 'All tools',
                            subtitle: _customize
                                ? 'Tap the dot button on a card, then tap where it should land.'
                                : 'Everything stays here — nothing removed.',
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                  if (_customize)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(wide ? 24 : 18, 0, wide ? 24 : 18, 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final tool = filtered[index];
                            return Padding(
                              padding: EdgeInsets.only(bottom: index == filtered.length - 1 ? 0 : 10),
                              child: _ReorderToolCard(
                                tool: tool,
                                lifted: _lifted == tool.id,
                                pinned: _pinned.contains(tool.id),
                                onOpen: () {
                                  if (_lifted != null) {
                                    _dropOn(tool.id);
                                  } else {
                                    _openTool(tool);
                                  }
                                },
                                onGrip: () => _toggleGrip(tool.id),
                                onPinToggle: () => _togglePinned(tool.id),
                              ),
                            );
                          },
                          childCount: filtered.length,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(wide ? 24 : 18, 0, wide ? 24 : 18, 24),
                      sliver: filtered.isEmpty
                          ? SliverToBoxAdapter(
                              child: _EmptyState(
                                onReset: () {
                                  _searchController.clear();
                                  setState(() {
                                    _query = '';
                                    _group = null;
                                  });
                                },
                              ),
                            )
                          : SliverGrid.builder(
                              itemCount: filtered.length,
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: toolColumns,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: 160,
                              ),
                              itemBuilder: (context, index) {
                                final tool = filtered[index];
                                return _DashboardToolCard(
                                  tool: tool,
                                  pinned: _pinned.contains(tool.id),
                                  onOpen: () => _openTool(tool),
                                  onPinToggle: () => _togglePinned(tool.id),
                                );
                              },
                            ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.customize,
    required this.lifted,
    required this.onSettings,
    required this.onCustomize,
  });

  final bool customize;
  final String? lifted;
  final VoidCallback onSettings;
  final VoidCallback onCustomize;

  @override
  Widget build(BuildContext context) {
    final subtitle = customize
        ? (lifted == null ? 'Reordering is on. Pick a card to move.' : 'Now tap the card that should sit below.')
        : 'Your tools, cleaner and easier to reach.';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome back',
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _HeaderIconButton(
          tooltip: customize ? 'Done customizing' : 'Customize home',
          icon: customize ? Icons.check_rounded : Icons.tune_rounded,
          active: customize,
          onTap: onCustomize,
        ),
        const SizedBox(width: 8),
        _HeaderIconButton(
          tooltip: 'Settings',
          icon: Icons.settings_rounded,
          onTap: onSettings,
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: active ? AppColors.accentMuted : AppColors.card,
        foregroundColor: active ? AppColors.accent : AppColors.onSurface,
        fixedSize: const Size(44, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: active ? AppColors.accent : AppColors.border),
        ),
      ),
      icon: Icon(icon, size: 21),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.toolCount,
    required this.pinnedCount,
    required this.recentCount,
    required this.onOpenMain,
    required this.onOpenRemote,
  });

  final int toolCount;
  final int pinnedCount;
  final int recentCount;
  final VoidCallback onOpenMain;
  final VoidCallback onOpenRemote;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        gradient: const LinearGradient(
          colors: [Color(0xFF201022), Color(0xFF130812), Color(0xFF0B0610)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.accentMuted,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.dashboard_customize_rounded, color: AppColors.accent, size: 26),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Z Multi Tool Mobile',
                        style: TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'A cleaner mobile dashboard for your music, remote tools, notes, games, and utilities.',
                        style: TextStyle(color: AppColors.muted, fontSize: 13.2, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatPill(label: 'Tools', value: '$toolCount'),
                _StatPill(label: 'Pinned', value: '$pinnedCount'),
                _StatPill(label: 'Recent', value: '$recentCount'),
                const _StatPill(label: 'Platforms', value: 'iOS + Android'),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onOpenMain,
                  icon: const Icon(Icons.play_circle_fill_rounded),
                  label: const Text('Open Music'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenRemote,
                  icon: const Icon(Icons.computer_rounded),
                  label: const Text('Open PC Remote'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.onSurface,
                    side: const BorderSide(color: AppColors.border),
                    backgroundColor: AppColors.card,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xAA120913),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12.2),
          ),
        ],
      ),
    );
  }
}

class _GroupChips extends StatelessWidget {
  const _GroupChips({
    required this.selected,
    required this.onChanged,
  });

  final HomeToolGroup? selected;
  final ValueChanged<HomeToolGroup?> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <(String, HomeToolGroup?)>[
      ('All', null),
      ('Media', HomeToolGroup.media),
      ('Remote', HomeToolGroup.remote),
      ('Productivity', HomeToolGroup.productivity),
      ('Utilities', HomeToolGroup.utility),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final active = item.$2 == selected;
          return FilterChip(
            selected: active,
            onSelected: (_) => onChanged(item.$2),
            showCheckmark: false,
            label: Text(item.$1),
            labelStyle: TextStyle(
              color: active ? AppColors.accent : AppColors.onSurface,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
            selectedColor: AppColors.accentMuted,
            backgroundColor: AppColors.card,
            side: BorderSide(color: active ? AppColors.accent : AppColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.muted, fontSize: 12.8),
        ),
      ],
    );
  }
}

class _QuickAccessWrap extends StatelessWidget {
  const _QuickAccessWrap({required this.tools, required this.onOpen});

  final List<HomeTool> tools;
  final ValueChanged<HomeTool> onOpen;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final tool in tools)
          _MiniActionCard(tool: tool, onTap: () => onOpen(tool)),
      ],
    );
  }
}

class _MiniActionCard extends StatelessWidget {
  const _MiniActionCard({required this.tool, required this.onTap});

  final HomeTool tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        width: 160,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.accentMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(tool.icon, color: AppColors.accent, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tool.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentStrip extends StatelessWidget {
  const _RecentStrip({required this.tools, required this.onOpen});

  final List<HomeTool> tools;
  final ValueChanged<HomeTool> onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tools.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final tool = tools[index];
          return InkWell(
            onTap: () => onOpen(tool),
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              width: 220,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.accentMuted,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(tool.icon, color: AppColors.accent, size: 20),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_rounded, color: AppColors.muted, size: 18),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    tool.name,
                    style: const TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tool.line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.2),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DashboardToolCard extends StatelessWidget {
  const _DashboardToolCard({
    required this.tool,
    required this.pinned,
    required this.onOpen,
    required this.onPinToggle,
  });

  final HomeTool tool;
  final bool pinned;
  final VoidCallback onOpen;
  final VoidCallback onPinToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.accentMuted,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(tool.icon, color: AppColors.accent, size: 22),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: pinned ? 'Unpin ${tool.name}' : 'Pin ${tool.name}',
                    onPressed: onPinToggle,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                      color: pinned ? AppColors.accent : AppColors.muted,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                tool.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tool.line,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 12.7, height: 1.35),
              ),
              const Spacer(),
              Row(
                children: [
                  _ToolGroupBadge(group: tool.group),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_rounded, color: AppColors.muted, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReorderToolCard extends StatelessWidget {
  const _ReorderToolCard({
    required this.tool,
    required this.lifted,
    required this.pinned,
    required this.onOpen,
    required this.onGrip,
    required this.onPinToggle,
  });

  final HomeTool tool;
  final bool lifted;
  final bool pinned;
  final VoidCallback onOpen;
  final VoidCallback onGrip;
  final VoidCallback onPinToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: lifted ? AppColors.accentMuted : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: lifted ? AppColors.accent : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 82),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: lifted ? AppColors.accent : AppColors.accentMuted,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          tool.icon,
                          color: lifted ? AppColors.bg : AppColors.accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    tool.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.onSurface,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (pinned) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.push_pin_rounded, color: AppColors.accent, size: 15),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              tool.line,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.muted, fontSize: 12.2),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: pinned ? 'Unpin ${tool.name}' : 'Pin ${tool.name}',
                        onPressed: onPinToggle,
                        icon: Icon(
                          pinned ? Icons.star_rounded : Icons.star_border_rounded,
                          color: pinned ? AppColors.accent : AppColors.muted,
                          size: 21,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Move ${tool.name}',
                onPressed: onGrip,
                style: IconButton.styleFrom(
                  backgroundColor: lifted ? AppColors.accent : Colors.transparent,
                  foregroundColor: lifted ? AppColors.bg : AppColors.muted,
                  fixedSize: const Size(36, 42),
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

class _ToolGroupBadge extends StatelessWidget {
  const _ToolGroupBadge({required this.group});

  final HomeToolGroup group;

  @override
  Widget build(BuildContext context) {
    final label = switch (group) {
      HomeToolGroup.media => 'Media',
      HomeToolGroup.remote => 'Remote',
      HomeToolGroup.productivity => 'Productivity',
      HomeToolGroup.utility => 'Utility',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accentMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.accentGlow,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CustomizeBanner extends StatelessWidget {
  const _CustomizeBanner({required this.lifted});

  final String? lifted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accentMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.swap_vert_rounded, color: AppColors.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              lifted == null
                  ? 'Customization mode is on. Use the grip button to choose a card, then tap another card to drop it there.'
                  : 'Card selected. Tap the card that should sit below it.',
              style: const TextStyle(color: AppColors.onSurface, fontSize: 12.8, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, color: AppColors.muted, size: 34),
          const SizedBox(height: 12),
          const Text(
            'No tools match that search.',
            style: TextStyle(
              color: AppColors.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try a different keyword or clear the current category filter.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12.8),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reset filters'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.onSurface,
              side: const BorderSide(color: AppColors.border),
            ),
          ),
        ],
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
