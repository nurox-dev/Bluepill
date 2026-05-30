import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/model_helpers.dart';
import '../services/ai_service.dart';
import '../services/mcp_context_service.dart';
import '../services/supabase_service.dart';
import '../ui/bp_card.dart';
import '../ui/responsive.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  final _mcp = McpContextService();
  final _ai = AiService();
  late Future<Map<String, dynamic>> _future;
  bool _summarizing = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final userId = SupabaseService.currentUserId;
    return {
      'progress': await _mcp.getRecentProgress(userId, limit: 30),
      'tasks': await _mcp.getAllTasks(userId),
      'habits': await _mcp.getUserHabits(userId),
      'ai_checkin_streak': await _mcp.getAiCheckinStreak(userId),
      'feedback': await _mcp.getRecentFeedback(userId, limit: 20),
    };
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress'),
        actions: [
          IconButton(
            tooltip: 'AI weekly summary',
            onPressed: _summarizing ? null : _generateWeeklySummary,
            icon: _summarizing
                ? const _ProgressPageSpinner.compact()
                : const Icon(Icons.auto_awesome),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: _ProgressPageSpinner());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final data = snapshot.data!;
          final progress = data['progress'] as List<Map<String, dynamic>>;
          final tasks = data['tasks'] as List<Map<String, dynamic>>;
          final habits = data['habits'] as List<Map<String, dynamic>>;
          final aiCheckinStreak = data['ai_checkin_streak'] is Map
              ? Map<String, dynamic>.from(data['ai_checkin_streak'] as Map)
              : null;
          final feedback = data['feedback'] as List<Map<String, dynamic>>;
          final checkinStreakDays = intValue(
            aiCheckinStreak?['current_streak'],
          );
          final bestCheckinStreak = intValue(aiCheckinStreak?['best_streak']);
          final latestScore = progress.isEmpty
              ? 0
              : intValue(progress.last['life_score']);
          final recent = progress.length > 7
              ? progress.sublist(progress.length - 7)
              : progress;
          final weeklyScore = recent.isEmpty
              ? 0
              : (recent
                            .map((item) => intValue(item['life_score']))
                            .reduce((a, b) => a + b) /
                        recent.length)
                    .round();
          final taskRate = tasks.isEmpty
              ? 0
              : (tasks.where((task) => task['status'] == 'completed').length /
                        tasks.length *
                        100)
                    .round();
          final habitRate = habits.isEmpty
              ? 0
              : (habits
                            .map(
                              (habit) => doubleValue(habit['completion_rate']),
                            )
                            .reduce((a, b) => a + b) /
                        habits.length)
                    .round();
          final focusAvg = recent.isEmpty
              ? 0
              : (recent
                            .map((item) => intValue(item['focus_score']))
                            .reduce((a, b) => a + b) /
                        recent.length)
                    .round();
          final best = progress.isEmpty
              ? null
              : progress.reduce(
                  (a, b) =>
                      intValue(a['life_score']) > intValue(b['life_score'])
                      ? a
                      : b,
                );
          final blocker = _commonBlocker(progress);
          final weeklySummaries = feedback
              .where((item) => item['feedback_type'] == 'weekly_summary')
              .map((item) => item['message'].toString())
              .toList();
          final weeklySummary = weeklySummaries.isEmpty
              ? null
              : weeklySummaries.first;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ResponsiveWrap(
                minItemWidth: 240,
                children: [
                  _MetricCard(title: 'Daily Life Score', value: '$latestScore'),
                  _MetricCard(
                    title: 'Weekly Life Score',
                    value: '$weeklyScore',
                  ),
                  _MetricCard(
                    title: 'Check-in Streak',
                    value:
                        '$checkinStreakDays day${checkinStreakDays == 1 ? '' : 's'}',
                  ),
                  _MetricCard(
                    title: 'Best Check-in Run',
                    value:
                        '$bestCheckinStreak day${bestCheckinStreak == 1 ? '' : 's'}',
                  ),
                  _MetricCard(title: 'Task Completion', value: '$taskRate%'),
                  _MetricCard(title: 'Habit Completion', value: '$habitRate%'),
                  _MetricCard(title: 'Focus Trend', value: '$focusAvg/10'),
                  _MetricCard(
                    title: 'Best Productive Day',
                    value: best == null ? 'No data' : compactDate(best['date']),
                  ),
                  _MetricCard(
                    title: 'Weakest Area',
                    value: _weakestArea(taskRate, habitRate, focusAvg),
                  ),
                  _MetricCard(
                    title: 'Common Blocker',
                    value: blocker ?? 'No blocker yet',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              BpCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mood and Focus',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(height: 240, child: _FocusChart(progress)),
                    const SizedBox(height: 12),
                    Text('Recent moods: ${_moodTrend(progress)}'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              BpCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.summarize_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AI Weekly Summary',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _summarizing
                              ? null
                              : _generateWeeklySummary,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Generate'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      weeklySummary ??
                          'Generate a weekly review after you have check-ins and progress logs.',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _generateWeeklySummary() async {
    setState(() => _summarizing = true);
    try {
      final userId = SupabaseService.currentUserId;
      final context = await _mcp.getUserContext(userId);
      final summary = await _ai.generateWeeklyReview(context);
      await _mcp.saveAIFeedback(userId, {
        'feedback_type': 'weekly_summary',
        'message': summary,
        'related_data': {'source': 'progress_page'},
      });
      _refresh();
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  String? _commonBlocker(List<Map<String, dynamic>> progress) {
    final counts = <String, int>{};
    for (final log in progress) {
      final blocker = log['blocker']?.toString();
      if (blocker == null || blocker.trim().isEmpty) continue;
      for (final item in blocker.split(',')) {
        final key = item.trim();
        if (key.isEmpty) continue;
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }

  String _weakestArea(int taskRate, int habitRate, int focusAvg) {
    final focusPercent = focusAvg * 10;
    if (taskRate <= habitRate && taskRate <= focusPercent) return 'Tasks';
    if (habitRate <= taskRate && habitRate <= focusPercent) return 'Habits';
    return 'Focus';
  }

  String _moodTrend(List<Map<String, dynamic>> progress) {
    final moods = progress
        .map((log) => log['mood']?.toString())
        .where((mood) => mood != null && mood.isNotEmpty)
        .cast<String>()
        .toList();
    if (moods.isEmpty) return 'No mood logs yet';
    return moods.take(6).join(', ');
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return BpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _ProgressPageSpinner extends StatelessWidget {
  const _ProgressPageSpinner() : compact = false;

  const _ProgressPageSpinner.compact() : compact = true;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = IconTheme.of(context).color ?? colorScheme.primary;
    final activeColor = compact ? iconColor : colorScheme.primary;
    final trackColor = activeColor.withValues(alpha: compact ? 0.24 : 0.18);

    final Widget child = CircularProgressIndicator(
      valueColor: AlwaysStoppedAnimation<Color>(activeColor),
      strokeAlign: -1,
      backgroundColor: trackColor,
      strokeWidth: compact ? 3 : 4,
    );

    return Semantics(
      label: compact ? 'Generating summary' : 'Loading progress',
      child: ExcludeSemantics(child: child),
    );
  }
}

class _FocusChart extends StatelessWidget {
  const _FocusChart(this.progress);

  final List<Map<String, dynamic>> progress;

  @override
  Widget build(BuildContext context) {
    if (progress.isEmpty) {
      return const EmptyState(
        icon: Icons.show_chart,
        title: 'No focus trend yet',
        message: 'Night check-ins will populate your focus trend.',
      );
    }

    final spots = progress.asMap().entries.map((entry) {
      return FlSpot(
        entry.key.toDouble(),
        doubleValue(entry.value['focus_score']),
      );
    }).toList();

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 10,
        gridData: const FlGridData(show: true),
        titlesData: const FlTitlesData(
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 3,
            color: Theme.of(context).colorScheme.primary,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}
