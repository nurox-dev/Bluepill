import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/model_helpers.dart';
import '../services/mcp_context_service.dart';
import '../services/supabase_service.dart';
import '../ui/bp_card.dart';
import '../ui/expressive_loading_indicator.dart';

class HabitsPage extends StatefulWidget {
  const HabitsPage({super.key});

  @override
  State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> {
  final _mcp = McpContextService();
  late Future<Map<String, dynamic>> _future;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSearch = false;
  final Set<String> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final userId = SupabaseService.currentUserId;
    final today = dateKey(DateTime.now());
    final monthAgo = dateKey(DateTime.now().subtract(const Duration(days: 30)));

    final habits = await _mcp.getUserHabits(userId);
    final recentLogs = rows(await SupabaseService.client
        .from('habit_logs')
        .select()
        .eq('user_id', userId)
        .gte('date', monthAgo)
        .lte('date', today)
        .order('date', ascending: false));

    for (final h in habits) {
      _expandedCategories.add(h['category']?.toString() ?? 'personal');
    }

    final todayLogs = recentLogs.where((l) => l['date'] == today).toList();

    return {
      'habits': habits,
      'recent_logs': recentLogs,
      'today_logs': todayLogs,
    };
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Color _statusColor(String? status, {bool muted = false}) {
    final cs = Theme.of(context).colorScheme;
    if (status == 'completed') return muted ? cs.primary : Colors.green;
    if (status == 'partial') return Colors.orange;
    if (status == 'missed') return Colors.red;
    return cs.onSurfaceVariant;
  }

  Future<void> _logHabit(Map<String, dynamic> habit, String status) async {
    final userId = SupabaseService.currentUserId;
    final today = dateKey(DateTime.now());
    final existing = await SupabaseService.client
        .from('habit_logs')
        .select()
        .eq('habit_id', habit['id'])
        .eq('date', today)
        .maybeSingle();
    final previousLog = maybeRow(existing);
    final wasCompleted = previousLog?['status'] == 'completed';

    await SupabaseService.client.from('habit_logs').upsert(
      {
        'habit_id': habit['id'],
        'user_id': userId,
        'date': today,
        'status': status,
      },
      onConflict: 'habit_id,date',
    );

    final logs30 = rows(await SupabaseService.client
        .from('habit_logs')
        .select()
        .eq('habit_id', habit['id'])
        .order('date', ascending: false)
        .limit(30));
    final completed = logs30.where((l) => l['status'] == 'completed');
    final completionRate =
        logs30.isEmpty ? 0 : (completed.length / logs30.length * 100).round();
    final streak = status == 'completed'
        ? intValue(habit['current_streak']) + (wasCompleted ? 0 : 1)
        : 0;

    await SupabaseService.client.from('habits').update({
      'current_streak': streak,
      'completion_rate': completionRate,
    }).eq('id', habit['id']);

    _refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_capitalize(status)} — ${habit['title']}'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              if (previousLog != null) {
                await SupabaseService.client
                    .from('habit_logs')
                    .upsert(previousLog, onConflict: 'habit_id,date');
              } else {
                await SupabaseService.client
                    .from('habit_logs')
                    .delete()
                    .eq('habit_id', habit['id'])
                    .eq('date', today);
              }
              _refresh();
            },
          ),
        ),
      );
    }
  }

  Future<void> _deleteHabit(Map<String, dynamic> habit) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete habit'),
        content: Text('Delete "${habit['title']}" and all its logs?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SupabaseService.client
          .from('habits')
          .delete()
          .eq('id', habit['id']);
      _refresh();
    }
  }

  Future<void> _editHabit([Map<String, dynamic>? habit]) async {
    final title = TextEditingController(text: habit?['title']?.toString());
    final target = TextEditingController(text: habit?['target']?.toString());
    var category = habit?['category']?.toString() ?? 'personal';
    var frequency = habit?['frequency']?.toString() ?? 'daily';
    final isNew = habit == null;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(isNew ? 'Add habit' : 'Edit habit'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'e.g. Morning workout',
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: const [
                      DropdownMenuItem(value: 'health', child: Text('Health')),
                      DropdownMenuItem(
                          value: 'fitness', child: Text('Fitness')),
                      DropdownMenuItem(
                          value: 'productivity',
                          child: Text('Productivity')),
                      DropdownMenuItem(
                          value: 'learning', child: Text('Learning')),
                      DropdownMenuItem(
                          value: 'mindfulness', child: Text('Mindfulness')),
                      DropdownMenuItem(
                          value: 'social', child: Text('Social')),
                      DropdownMenuItem(
                          value: 'finance', child: Text('Finance')),
                      DropdownMenuItem(
                          value: 'personal', child: Text('Personal')),
                      DropdownMenuItem(
                          value: 'custom', child: Text('Custom...')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => category = value ?? category),
                  ),
                  if (category == 'custom') ...[
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Custom category',
                        hintText: 'e.g. Creative',
                      ),
                      onChanged: (v) => category = v.trim(),
                    ),
                  ],
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: frequency,
                    decoration: const InputDecoration(labelText: 'Frequency'),
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(
                          value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(
                          value: 'custom', child: Text('Custom')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => frequency = value ?? frequency),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: target,
                    decoration: const InputDecoration(
                      labelText: 'Target (optional)',
                      hintText: 'e.g. 30 min, 10 pages, 2L water',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (title.text.trim().isEmpty) return;
                  final data = {
                    'user_id': SupabaseService.currentUserId,
                    'title': title.text.trim(),
                    'category': category,
                    'frequency': frequency,
                    'target': target.text.trim(),
                  };
                  if (isNew) {
                    await SupabaseService.client.from('habits').insert(data);
                  } else {
                    await SupabaseService.client
                        .from('habits')
                        .update(data)
                        .eq('id', habit['id']);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _refresh();
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );

    title.dispose();
    target.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search habits...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('Habits'),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.search_off : Icons.search),
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchQuery = '';
                _searchController.clear();
              }
            }),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: ExpressiveLoadingIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          return _buildCombinedView(snapshot.data!);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editHabit(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildStatsBanner(
      List<Map<String, dynamic>> habits, List<Map<String, dynamic>> recentLogs) {
    final cs = Theme.of(context).colorScheme;
    final total = habits.length;
    final completed =
        recentLogs.where((l) => l['status'] == 'completed').length;
    final missed = recentLogs.where((l) => l['status'] == 'missed').length;
    final rate = recentLogs.isEmpty
        ? 0
        : (completed / recentLogs.length * 100).round();
    final bestStreak = habits.fold<int>(
        0,
        (max, h) =>
            intValue(h['best_streak'] ?? h['current_streak']) > max
                ? intValue(h['best_streak'] ?? h['current_streak'])
                : max);

    return BpCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _buildStatCircle(rate, 'Rate', cs.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatColumn('Habits', '$total'),
                _buildStatColumn('Best', '${bestStreak}d'),
                _buildStatColumn('Done', '$completed'),
                _buildStatColumn('Missed', '$missed'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCircle(int value, String label, Color color) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              value: value / 100,
              strokeWidth: 5,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text(
            '$value%',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildCategorySection(
    String category,
    List<Map<String, dynamic>> habits,
    List<Map<String, dynamic>> recentLogs,
    List<Map<String, dynamic>> todayLogs,
  ) {
    final cs = Theme.of(context).colorScheme;
    final expanded = _expandedCategories.contains(category);
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() {
            if (expanded) {
              _expandedCategories.remove(category);
            } else {
              _expandedCategories.add(category);
            }
          }),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  _capitalize(category),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${habits.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          ...habits.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildHabitCard(h, recentLogs, todayLogs),
              )),
      ],
    );
  }

  Widget _buildHabitCard(
    Map<String, dynamic> habit,
    List<Map<String, dynamic>> recentLogs,
    List<Map<String, dynamic>> todayLogs,
  ) {
    final cs = Theme.of(context).colorScheme;
    final habitLogs = recentLogs.where((l) => l['habit_id'] == habit['id']);
    final todayLog =
        todayLogs.where((l) => l['habit_id'] == habit['id']).toList();
    final status = todayLog.isEmpty ? null : todayLog.first['status'];
    final rate = intValue(habit['completion_rate']);
    final streak = intValue(habit['current_streak']);

    return BpCard(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showHabitDetail(habit, habitLogs.toList()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _logHabit(
                      habit, status == 'completed' ? 'missed' : 'completed'),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      status == 'completed'
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      key: ValueKey(status),
                      color: _statusColor(status),
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit['title'].toString(),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (habit['target'] != null &&
                          habit['target'].toString().isNotEmpty)
                        Text(
                          habit['target'].toString(),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') _editHabit(habit);
                    if (value == 'delete') _deleteHabit(habit);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMiniHeatmap(habitLogs.toList()),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (streak > 0) ...[
                          Text('🔥',
                              style: Theme.of(context).textTheme.bodyLarge),
                          const SizedBox(width: 2),
                        ],
                        Text(
                          '${streak}d',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: streak > 0 ? Colors.orange : null,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$rate%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: rate >= 70
                            ? Colors.green
                            : rate >= 40
                                ? Colors.orange
                                : Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildLogButton(
                  label: 'Done',
                  icon: Icons.done,
                  isActive: status == 'completed',
                  onTap: () => _logHabit(habit, 'completed'),
                ),
                const SizedBox(width: 6),
                _buildLogButton(
                  label: 'Half',
                  icon: Icons.timelapse,
                  isActive: status == 'partial',
                  onTap: () => _logHabit(habit, 'partial'),
                ),
                const SizedBox(width: 6),
                _buildLogButton(
                  label: 'Miss',
                  icon: Icons.close,
                  isActive: status == 'missed',
                  onTap: () => _logHabit(habit, 'missed'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = isActive ? _statusColor(label == 'Done'
        ? 'completed'
        : label == 'Half'
            ? 'partial'
            : 'missed') : cs.onSurfaceVariant;
    return Expanded(
      child: isActive
          ? FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 16),
              label: Text(label),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                minimumSize: Size.zero,
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 16),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                minimumSize: Size.zero,
              ),
            ),
    );
  }

  Widget _buildMiniHeatmap(List<Map<String, dynamic>> logs) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final logMap = <String, String>{};
    for (final l in logs) {
      final d = l['date'].toString();
      if (!logMap.containsKey(d)) {
        logMap[d] = l['status'].toString();
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(7, (i) {
        final day = today.subtract(Duration(days: 6 - i));
        final key = dateKey(day);
        final status = logMap[key];
        final Color color;
        if (status == 'completed') {
          color = Colors.green;
        } else if (status == 'partial') {
          color = Colors.orange;
        } else if (status == 'missed') {
          color = Colors.red.shade300;
        } else {
          color = cs.surfaceContainerHighest;
        }
        final isToday = i == 6;
        return Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Container(
            width: isToday ? 18 : 14,
            height: isToday ? 18 : 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }

  void _showHabitDetail(
    Map<String, dynamic> habit,
    List<Map<String, dynamic>> logs,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _HabitDetailPage(
          habit: habit,
          logs: logs,
          onChanged: _refresh,
        ),
      ),
    );
  }

  // --- Combined view ---

  Widget _buildCombinedView(Map<String, dynamic> data) {
    final habits = data['habits'] as List<Map<String, dynamic>>;
    final recentLogs = data['recent_logs'] as List<Map<String, dynamic>>;
    final todayLogs = data['today_logs'] as List<Map<String, dynamic>>;

    if (habits.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.repeat,
          title: 'No habits yet',
          message: 'Add habits like coding, workout, reading, or stretching.',
        ),
      );
    }

    var filtered = habits;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = habits.where((h) {
        return h['title']?.toString().toLowerCase().contains(q) == true ||
            h['category']?.toString().toLowerCase().contains(q) == true;
      }).toList();
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final h in filtered) {
      final cat = h['category']?.toString() ?? 'personal';
      grouped.putIfAbsent(cat, () => []).add(h);
    }
    final sortedCategories = grouped.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        _buildHeatmapStrip(recentLogs),
        const SizedBox(height: 12),
        _buildStatsSection(habits, recentLogs),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const EmptyState(
            icon: Icons.search_off,
            title: 'No results',
            message: 'Try a different search term.',
          )
        else ...[
          _buildStatsBanner(filtered, recentLogs),
          const SizedBox(height: 16),
          for (final cat in sortedCategories) ...[
            _buildCategorySection(cat, grouped[cat]!, recentLogs, todayLogs),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildHeatmapStrip(List<Map<String, dynamic>> recentLogs) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    const days = 30;

    final dayStats = <String, int>{}; // date -> 0=none, 1=mixed/partial, 2=all done, 3=all missed
    for (int i = 0; i < days; i++) {
      final d = today.subtract(Duration(days: days - 1 - i));
      final key = dateKey(d);
      final logs = recentLogs.where((l) => l['date'] == key).toList();
      if (logs.isEmpty) {
        dayStats[key] = 0;
      } else {
        final completed = logs.where((l) => l['status'] == 'completed').length;
        final missed = logs.where((l) => l['status'] == 'missed').length;
        if (completed == logs.length) {
          dayStats[key] = 2;
        } else if (missed == logs.length) {
          dayStats[key] = 3;
        } else {
          dayStats[key] = 1;
        }
      }
    }

    return BpCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('30-day heatmap',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 3,
            runSpacing: 3,
            children: List.generate(days, (i) {
              final d = today.subtract(Duration(days: days - 1 - i));
              final key = dateKey(d);
              final stat = dayStats[key] ?? 0;
              final color = stat == 2
                  ? cs.primary
                  : stat == 1
                      ? Colors.orange
                      : stat == 3
                          ? cs.error
                          : cs.surfaceContainerHighest;
              final isToday = i == days - 1;
              return Container(
                width: isToday ? 20 : 15,
                height: isToday ? 20 : 15,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                  border: isToday
                      ? Border.all(color: cs.onSurface, width: 1.2)
                      : null,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _legendDot(cs.primary, 'Done'),
              const SizedBox(width: 12),
              _legendDot(Colors.orange, 'Partial'),
              const SizedBox(width: 12),
              _legendDot(cs.error, 'Missed'),
              const SizedBox(width: 12),
              _legendDot(cs.surfaceContainerHighest, 'None'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 3),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontWeight: FontWeight.w600, fontSize: 10)),
      ],
    );
  }

  // --- Stats section (within overview tab) ---

  Widget _buildStatsSection(
    List<Map<String, dynamic>> habits,
    List<Map<String, dynamic>> recentLogs,
  ) {
    final cs = Theme.of(context).colorScheme;
    return _buildStreaksCard(habits, cs);
  }

  Widget _buildStreaksCard(List<Map<String, dynamic>> habits, ColorScheme cs) {
    return BpCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Streaks',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final h in habits) ...[
            Row(
              children: [
                Text(h['title'].toString(),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (intValue(h['current_streak']) > 0)
                  Text('🔥 ',
                      style: Theme.of(context).textTheme.labelSmall),
                Text(
                  '${intValue(h['current_streak'])}d',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: intValue(h['current_streak']) > 0
                        ? Colors.orange
                        : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

// ────────────────────────────────────────────────────────────
// Habit Detail Page
// ────────────────────────────────────────────────────────────

class _HabitDetailPage extends StatefulWidget {
  final Map<String, dynamic> habit;
  final List<Map<String, dynamic>> logs;
  final VoidCallback onChanged;

  const _HabitDetailPage({
    required this.habit,
    required this.logs,
    required this.onChanged,
  });

  @override
  State<_HabitDetailPage> createState() => _HabitDetailPageState();
}

class _HabitDetailPageState extends State<_HabitDetailPage> {
  int _selectedMonthOffset = 0;

  DateTime get _viewMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month + _selectedMonthOffset);
  }

  Color _statusColor(String? status) {
    if (status == 'completed') return Colors.green;
    if (status == 'partial') return Colors.orange;
    if (status == 'missed') return Colors.red;
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.habit;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rate = intValue(h['completion_rate']);
    final streak = intValue(h['current_streak']);

    return Scaffold(
      appBar: AppBar(title: Text(h['title'].toString())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          BpCard(
            child: Column(
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: CircularProgressIndicator(
                          value: rate / 100,
                          strokeWidth: 8,
                          backgroundColor: cs.primary.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation(cs.primary),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$rate%',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              color: cs.primary,
                            ),
                          ),
                          Text('rate',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _detailStat('Category',
                        _capitalize(h['category']?.toString() ?? 'personal')),
                    _detailStat('Frequency',
                        _capitalize(h['frequency']?.toString() ?? 'daily')),
                    _detailStat(
                        'Streak', streak > 0 ? '$streak 🔥' : '$streak'),
                  ],
                ),
                if (h['target'] != null &&
                    h['target'].toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Target: ${h['target']}',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          BpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Monthly Log',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 18),
                          onPressed: () =>
                              setState(() => _selectedMonthOffset--),
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                          padding: EdgeInsets.zero,
                        ),
                        Text(
                          DateFormat('MMM yyyy').format(_viewMonth),
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 18),
                          onPressed: () =>
                              setState(() => _selectedMonthOffset++),
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildMonthGrid(h, cs),
              ],
            ),
          ),
          const SizedBox(height: 16),
          BpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recent Activity',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                ...widget.logs.take(20).map((l) {
                  final status = l['status'].toString();
                  final date = l['date'].toString();
                  final dt = DateTime.tryParse(date);
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                        status == 'completed'
                            ? Icons.check_circle
                            : status == 'partial'
                                ? Icons.timelapse
                                : Icons.cancel,
                        color: _statusColor(status),
                        size: 18),
                    title: Text(
                        dt != null
                            ? DateFormat('MMM d, yyyy').format(dt)
                            : date,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    trailing: Text(
                      _capitalize(status),
                      style: TextStyle(
                        color: _statusColor(status),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  );
                }),
                if (widget.logs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                        child: Text('No logs yet',
                            style: Theme.of(context).textTheme.bodySmall)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _detailStat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildMonthGrid(Map<String, dynamic> habit, ColorScheme cs) {
    final daysInMonth =
        DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;
    final firstWeekday =
        DateTime(_viewMonth.year, _viewMonth.month, 1).weekday % 7;
    final today = DateTime.now();
    final isCurrentMonth =
        _viewMonth.month == today.month && _viewMonth.year == today.year;

    final logMap = <int, String>{};
    for (final l in widget.logs) {
      final dt = DateTime.tryParse(l['date'].toString());
      if (dt != null &&
          dt.month == _viewMonth.month &&
          dt.year == _viewMonth.year) {
        final d = dt.day;
        if (!logMap.containsKey(d)) {
          logMap[d] = l['status'].toString();
        }
      }
    }

    final children = <Widget>[];
    for (final d in ['S', 'M', 'T', 'W', 'T', 'F', 'S']) {
      children.add(Center(
        child: Text(d,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
            )),
      ));
    }
    for (int i = 0; i < firstWeekday; i++) {
      children.add(const SizedBox.shrink());
    }
    for (int day = 1; day <= daysInMonth; day++) {
      final status = logMap[day];
      Color? color;
      if (status == 'completed') {
        color = cs.primary;
      } else if (status == 'partial') {
        color = Colors.orange;
      } else if (status == 'missed') {
        color = cs.error;
      }

      final isToday = isCurrentMonth && day == today.day;

      children.add(
        Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: color?.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(6),
            border: isToday
                ? Border.all(color: cs.primary, width: 2)
                : null,
          ),
          child: Center(
            child: Text(
              '$day',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 350),
        child: GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.0,
          ),
          children: children,
        ),
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
