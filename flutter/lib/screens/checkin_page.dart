import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/model_helpers.dart';
import '../services/ai_service.dart';
import '../services/mcp_context_service.dart';
import '../services/progress_engine.dart';
import '../services/supabase_service.dart';
import '../ui/bp_card.dart';
import '../ui/expressive_loading_indicator.dart';

class CheckinPage extends StatefulWidget {
  const CheckinPage({super.key});

  @override
  State<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends State<CheckinPage> {
  final _answer = TextEditingController();
  final _mcp = McpContextService();
  final _ai = AiService();
  String _type = 'morning';
  bool _saving = false;
  Map<String, dynamic>? _extracted;
  late Future<Map<String, dynamic>?> _streakFuture;

  static const _questions = {
    'morning': [
      'What are your top 3 priorities today?',
      'How do you feel today?',
      'What could block you today?',
    ],
    'afternoon': [
      'Are you still on track?',
      'What have you completed so far?',
      'Do you need to adjust your plan?',
    ],
    'night': [
      'What did you complete today?',
      'What did you miss?',
      'Why did you miss it?',
      'How focused were you from 1 to 10?',
      'What is one lesson from today?',
    ],
    'weekly': [
      'What worked this week?',
      'What failed this week?',
      'What should change next week?',
    ],
  };

  @override
  void initState() {
    super.initState();
    _streakFuture = _loadStreak();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _loadStreak() {
    return _mcp.getAiCheckinStreak(SupabaseService.currentUserId);
  }

  @override
  Widget build(BuildContext context) {
    final question = _questions[_type]!.join('\n');

    return Scaffold(
      appBar: AppBar(title: const Text('AI Check-In')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FutureBuilder<Map<String, dynamic>?>(
            future: _streakFuture,
            builder: (context, snapshot) {
              return _DailyCheckinStreakCard(streak: snapshot.data);
            },
          ),
          const SizedBox(height: 16),
          BpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Check-in type',
                    prefixIcon: Icon(Icons.schedule),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'morning', child: Text('Morning')),
                    DropdownMenuItem(
                      value: 'afternoon',
                      child: Text('Afternoon'),
                    ),
                    DropdownMenuItem(value: 'night', child: Text('Night')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                  ],
                  onChanged: (value) => setState(() {
                    _type = value ?? _type;
                    _extracted = null;
                  }),
                ),
                const SizedBox(height: 18),
                Text(
                  question,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800, height: 1.45),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _answer,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Answer naturally',
                    alignLabelWithHint: true,
                    hintText:
                        'I studied Java for 45 minutes but skipped gym because I was tired. Focus was 6.',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: ExpressiveLoadingIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: const Text('Extract Progress'),
                ),
              ],
            ),
          ),
          if (_extracted != null) ...[
            const SizedBox(height: 16),
            BpCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Structured Progress Saved',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(_extracted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_answer.text.trim().isEmpty) return;
    setState(() => _saving = true);

    try {
      final userId = SupabaseService.currentUserId;
      final userContext = await _mcp.getUserContext(userId);
      final extracted = await _ai.extractProgressFromCheckin(
        _answer.text.trim(),
        userContext,
      );

      await SupabaseService.client.from('checkins').insert({
        'user_id': userId,
        'type': _type,
        'question': _questions[_type]!.join('\n'),
        'user_answer': _answer.text.trim(),
        'ai_extracted_data': extracted,
      });
      final streak = await _mcp.recordAiCheckinStreak(userId);

      final progressLog = ProgressEngine.buildDailyProgressLog(
        userId: userId,
        todayTasks: await _mcp.getTodayTasks(userId),
        todayHabitLogs: await _mcp.getTodayHabitLogs(userId),
        todayCheckins: await _mcp.getRecentCheckins(userId, limit: 4),
        extracted: extracted,
      );
      await _mcp.saveProgressLog(userId, progressLog);

      if (!mounted) return;
      setState(() {
        _extracted = extracted;
        _streakFuture = Future.value(streak);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Check-in saved. Current streak: ${streak['current_streak']} days.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DailyCheckinStreakCard extends StatelessWidget {
  const _DailyCheckinStreakCard({required this.streak});

  final Map<String, dynamic>? streak;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final current = intValue(streak?['current_streak']);
    final best = intValue(streak?['best_streak']);
    final last = streak?['last_checkin_date'];
    final hasStarted = current > 0;

    return BpCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.local_fire_department_outlined,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily AI check-in streak',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  hasStarted
                      ? '$current day${current == 1 ? '' : 's'} current, best $best'
                      : 'Start your streak with today\'s check-in.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                if (last != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Last check-in: ${compactDate(last)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
