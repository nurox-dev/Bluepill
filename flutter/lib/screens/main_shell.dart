import 'package:flutter/material.dart';

import 'agent_page.dart';
import 'calendar_page.dart';
import 'cron_jobs_page.dart';
import 'dashboard_page.dart';
import 'habits_page.dart';
import 'mcp_connect_page.dart';
import 'mission_page.dart';
import 'settings_page.dart';
import '../ui/project_logo.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _items = [
    _NavItem('Agent', Icons.support_agent_outlined, AgentPage()),
    _NavItem('Dashboard', Icons.space_dashboard_outlined, DashboardPage()),
    _NavItem('Mission', Icons.flag_outlined, MissionPage()),
    _NavItem('Planner', Icons.calendar_month_outlined, CalendarPage()),
    _NavItem('Habits', Icons.repeat, HabitsPage()),
    _NavItem('Cron Jobs', Icons.alarm_on_outlined, CronJobsPage()),
    _NavItem('Connect', Icons.cable, McpConnectPage()),
    _NavItem('Settings', Icons.settings_outlined, SettingsPage()),
  ];
  static const _mobilePrimaryIndexes = [0, 1, 2, 3];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        if (desktop) {
          return Scaffold(
            body: Row(
              children: [
                _DesktopSidebar(
                  items: _items,
                  selectedIndex: _index,
                  onSelected: (value) => setState(() => _index = value),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _AnimatedPage(
                    index: _index,
                    child: _items[_index].page,
                  ),
                ),
              ],
            ),
          );
        }

        final primarySlot = _mobilePrimaryIndexes.indexOf(_index);
        return Scaffold(
          body: _AnimatedPage(index: _index, child: _items[_index].page),
          bottomNavigationBar: NavigationBar(
            selectedIndex: primarySlot == -1 ? 4 : primarySlot,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (value) {
              if (value == 4) {
                _showMoreDestinations();
                return;
              }
              setState(() => _index = _mobilePrimaryIndexes[value]);
            },
            destinations: [
              for (final index in _mobilePrimaryIndexes)
                NavigationDestination(
                  icon: Icon(_items[index].icon),
                  selectedIcon: Icon(_items[index].icon),
                  label: _items[index].label,
                  tooltip: '',
                ),
              const NavigationDestination(
                icon: Icon(Icons.more_horiz),
                selectedIcon: Icon(Icons.more_horiz),
                label: 'More',
                tooltip: '',
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMoreDestinations() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final secondaryIndexes = [
          for (var index = 0; index < _items.length; index++)
            if (!_mobilePrimaryIndexes.contains(index)) index,
        ];
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                'More',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              for (final index in secondaryIndexes)
                _MoreDestinationTile(
                  item: _items[index],
                  selected: index == _index,
                  onTap: () {
                    Navigator.of(context).pop();
                    setState(() => _index = index);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 236,
      color: colorScheme.surfaceContainerLow,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Row(
                children: [
                  const ProjectLogo(size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BluePill',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Command center',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (var index = 0; index < items.length; index++)
                    _DesktopNavButton(
                      item: items[index],
                      selected: index == selectedIndex,
                      onTap: () => onSelected(index),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopNavButton extends StatelessWidget {
  const _DesktopNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: selected
            ? colorScheme.secondary.withValues(alpha: 0.30)
            : Colors.transparent,
      ),
    );
    final background = selected
        ? colorScheme.secondaryContainer
        : Colors.transparent;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(
        message: item.label,
        waitDuration: const Duration(milliseconds: 700),
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Easing.emphasizedDecelerate,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: ShapeDecoration(color: background, shape: shape),
            child: Row(
              children: [
                Icon(item.icon, color: foreground, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreDestinationTile extends StatelessWidget {
  const _MoreDestinationTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ListTile(
        selected: selected,
        selectedTileColor: colorScheme.secondaryContainer,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        leading: Icon(
          item.icon,
          color: selected ? colorScheme.onSecondaryContainer : null,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _AnimatedPage extends StatelessWidget {
  const _AnimatedPage({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220),
      switchInCurve: Easing.emphasizedDecelerate,
      switchOutCurve: Easing.emphasizedAccelerate,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0.025, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey(index), child: child),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.page);

  final String label;
  final IconData icon;
  final Widget page;
}
