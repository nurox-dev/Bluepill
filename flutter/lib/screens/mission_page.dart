import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/model_helpers.dart';
import '../services/agent_gateway_service.dart';
import '../services/ai_service.dart';
import '../services/mcp_context_service.dart';
import '../services/supabase_service.dart';
import '../ui/bp_card.dart';
import '../ui/expressive_loading_indicator.dart';
import '../ui/responsive.dart';

const _checkpointRunPollInterval = Duration(milliseconds: 1500);
const _checkpointRunTimeout = Duration(seconds: 75);

class MissionPage extends StatefulWidget {
  const MissionPage({super.key});

  @override
  State<MissionPage> createState() => _MissionPageState();
}

class _MissionPageState extends State<MissionPage> {
  final _mcp = McpContextService();
  final _ai = AiService();
  final _gateway = AgentGatewayService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return _mcp.getUserGoals(SupabaseService.currentUserId);
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mission'),
        actions: [
          IconButton(
            tooltip: 'Add mission',
            onPressed: () => _editMission(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: ExpressiveLoadingIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final goals = snapshot.data ?? [];
          final missions = _missionTiles(goals);

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width < 640 ? 14 : 24,
                vertical: MediaQuery.sizeOf(context).width < 640 ? 14 : 24,
              ),
              children: [
                if (missions.isEmpty)
                  const EmptyState(
                    icon: Icons.flag_outlined,
                    title: 'No missions yet',
                    message: 'Add a mission to create AI checkpoints.',
                  )
                else
                  ResponsiveWrap(
                    minItemWidth: 320,
                    children: [
                      for (final mission in missions)
                        _MissionTile(
                          key: PageStorageKey('mission-${mission['id']}'),
                          mission: mission,
                          checkpoints: _childGoals(mission, goals),
                          onOpen: () => _openMission(mission, goals),
                          onEdit: () => _editMission(mission),
                          onDelete: () => _deleteMission(mission),
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editMission(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _openMission(
    Map<String, dynamic> mission,
    List<Map<String, dynamic>> goals,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _MissionDetailPage(
          mission: mission,
          initialGoals: goals,
          generateCheckpoints: _generateCheckpointsWithModelApi,
          setCheckpointProgress: _setCheckpointProgress,
          editMission: _editMission,
          deleteMission: _deleteMission,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<List<String>> _generateCheckpointsWithModelApi(
    Map<String, dynamic> mission,
  ) async {
    final prompt =
        '''
Break this mission into 5 to 7 concrete checkpoints for tracking progress.
Return only valid JSON in this shape:
{"checkpoints":["checkpoint one","checkpoint two"]}

Mission title: ${mission['title']}
Mission description: ${mission['description'] ?? ''}
Mission type: ${mission['goal_type'] ?? 'life'}
Deadline: ${mission['deadline'] ?? 'none'}
''';

    try {
      final response = await _gateway.createAgentRun(
        message: prompt,
        idempotencyKey: 'mission-checkpoints-${mission['id']}',
      );
      final status = response['status']?.toString();
      final run = status == 'completed'
          ? response
          : await _waitForCheckpointRun(response['agent_run_id']);
      final text = _replyTextFromRun(run);
      final parsed = _parseCheckpointText(text);
      if (parsed.isNotEmpty) return parsed;
    } catch (_) {
      // If the model API is unavailable, keep the page usable with local AI.
    }

    final context = await _mcp.getUserContext(SupabaseService.currentUserId);
    return _ai.generateMissionCheckpoints(mission, context);
  }

  Future<Map<String, dynamic>> _waitForCheckpointRun(Object? runId) async {
    if (runId == null) return const {};
    final timeoutAt = DateTime.now().add(_checkpointRunTimeout);
    var run = await _gateway.getAgentRun(runId);

    while (mounted && DateTime.now().isBefore(timeoutAt)) {
      final status = run['status']?.toString();
      if (status == 'completed' ||
          status == 'failed' ||
          status == 'cancelled') {
        return run;
      }

      await Future<void>.delayed(_checkpointRunPollInterval);
      run = await _gateway.getAgentRun(runId);
    }

    return run;
  }

  String _replyTextFromRun(Map<String, dynamic> run) {
    final result = run['result'];
    if (result is Map && result['text'] != null) {
      return result['text'].toString().trim();
    }
    return '';
  }

  List<String> _parseCheckpointText(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return const [];

    for (final candidate in [
      clean,
      _jsonSlice(clean, '{', '}'),
      _jsonSlice(clean, '[', ']'),
    ]) {
      if (candidate == null || candidate.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map && decoded['checkpoints'] is List) {
          return _cleanCheckpointList(decoded['checkpoints'] as List);
        }
        if (decoded is List) return _cleanCheckpointList(decoded);
      } catch (_) {
        continue;
      }
    }

    final bulletLines = clean
        .split('\n')
        .where((line) => RegExp(r'^\s*([-*]|\d+[.)])\s+').hasMatch(line))
        .map((line) => line.replaceFirst(RegExp(r'^\s*[-*\d.)]+\s*'), ''))
        .toList();
    final parsedBullets = _cleanCheckpointList(bulletLines);
    return parsedBullets.length >= 3 ? parsedBullets : const [];
  }

  String? _jsonSlice(String text, String open, String close) {
    final start = text.indexOf(open);
    final end = text.lastIndexOf(close);
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  List<String> _cleanCheckpointList(List items) {
    return items
        .map((item) => item.toString().replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((item) => item.isNotEmpty)
        .take(7)
        .toList(growable: false);
  }

  Future<void> _setCheckpointProgress(
    Map<String, dynamic> mission,
    Map<String, dynamic> checkpoint,
    double progress,
  ) async {
    final missionId = mission['id']?.toString();
    if (missionId == null || missionId.isEmpty) return;
    await _updateGoalProgress(
      checkpoint['id'],
      progress,
      status: progress >= 100 ? 'completed' : 'active',
    );
    await _syncGoalProgress(missionId);
    _refresh();
  }

  Future<void> _updateGoalProgress(
    Object? goalId,
    double progress, {
    String? status,
  }) async {
    if (goalId == null) return;
    await SupabaseService.client
        .from('goals')
        .update({
          'progress_percent': progress.round().clamp(0, 100),
          if (status != null) 'status': status,
        })
        .eq('id', goalId);
  }

  Future<void> _syncGoalProgress(String? goalId) async {
    if (goalId == null || goalId.isEmpty) return;
    final userId = SupabaseService.currentUserId;
    final children = rows(
      await SupabaseService.client
          .from('goals')
          .select()
          .eq('user_id', userId)
          .eq('parent_goal_id', goalId),
    );
    if (children.isEmpty) return;

    final progress =
        (children
                    .map((item) => doubleValue(item['progress_percent']))
                    .reduce((a, b) => a + b) /
                children.length)
            .round()
            .clamp(0, 100);
    final current = maybeRow(
      await SupabaseService.client
          .from('goals')
          .select('parent_goal_id, status')
          .eq('id', goalId)
          .maybeSingle(),
    );
    final currentStatus = current?['status']?.toString();
    final nextStatus = progress >= 100
        ? 'completed'
        : currentStatus == 'completed'
        ? 'active'
        : currentStatus;
    await SupabaseService.client
        .from('goals')
        .update({
          'progress_percent': progress,
          if (nextStatus != null) 'status': nextStatus,
        })
        .eq('id', goalId);
    await _syncGoalProgress(current?['parent_goal_id']?.toString());
  }

  Future<void> _deleteMission(Map<String, dynamic> mission) async {
    await SupabaseService.client.from('goals').delete().eq('id', mission['id']);
    _refresh();
  }

  Future<void> _editMission([Map<String, dynamic>? mission]) async {
    if (!mounted) return;
    final title = TextEditingController(text: mission?['title']?.toString());
    final description = TextEditingController(
      text: mission?['description']?.toString(),
    );
    var type = mission?['goal_type']?.toString() ?? 'life';
    var status = mission?['status']?.toString() ?? 'active';
    var progress = doubleValue(mission?['progress_percent']);
    var deadline = DateTime.tryParse(mission?['deadline']?.toString() ?? '');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(mission == null ? 'Add mission' : 'Edit mission'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: description,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(value: 'life', child: Text('Life')),
                        DropdownMenuItem(
                          value: 'yearly',
                          child: Text('Yearly'),
                        ),
                        DropdownMenuItem(
                          value: 'monthly',
                          child: Text('Monthly'),
                        ),
                        DropdownMenuItem(
                          value: 'weekly',
                          child: Text('Weekly'),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => type = value ?? type),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(
                          value: 'active',
                          child: Text('Active'),
                        ),
                        DropdownMenuItem(
                          value: 'paused',
                          child: Text('Paused'),
                        ),
                        DropdownMenuItem(
                          value: 'completed',
                          child: Text('Completed'),
                        ),
                        DropdownMenuItem(
                          value: 'archived',
                          child: Text('Archived'),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => status = value ?? status),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Progress'),
                        Expanded(
                          child: Slider(
                            value: progress,
                            min: 0,
                            max: 100,
                            divisions: 20,
                            label: '${progress.round()}%',
                            onChanged: (value) =>
                                setDialogState(() => progress = value),
                          ),
                        ),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 365),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                          initialDate: deadline ?? DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => deadline = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        deadline == null
                            ? 'Set deadline'
                            : 'Deadline ${compactDate(deadline!.toIso8601String())}',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (title.text.trim().isEmpty) return;
                    final data = {
                      'user_id': SupabaseService.currentUserId,
                      'title': title.text.trim(),
                      'description': description.text.trim(),
                      'goal_type': type,
                      'parent_goal_id': null,
                      'deadline': deadline == null ? null : dateKey(deadline!),
                      'progress_percent': progress.round(),
                      'status': status,
                    };
                    if (mission == null) {
                      await SupabaseService.client.from('goals').insert(data);
                    } else {
                      await SupabaseService.client
                          .from('goals')
                          .update(data)
                          .eq('id', mission['id']);
                    }
                    if (context.mounted) Navigator.pop(context);
                    _refresh();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    title.dispose();
    description.dispose();
  }

  List<Map<String, dynamic>> _missionTiles(List<Map<String, dynamic>> goals) {
    final active = goals
        .where((goal) => goal['status'] != 'archived')
        .toList(growable: false);
    final topLevel = active
        .where((goal) => goal['parent_goal_id'] == null)
        .toList(growable: false);
    return topLevel.isEmpty ? active : topLevel;
  }

  List<Map<String, dynamic>> _childGoals(
    Map<String, dynamic> goal,
    List<Map<String, dynamic>> goals,
  ) {
    final id = goal['id']?.toString();
    if (id == null) return const [];
    return goals
        .where((item) => item['parent_goal_id']?.toString() == id)
        .toList(growable: false);
  }
}

class _MissionTile extends StatelessWidget {
  const _MissionTile({
    super.key,
    required this.mission,
    required this.checkpoints,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> mission;
  final List<Map<String, dynamic>> checkpoints;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = _progress;

    return BpCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.flag_outlined, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      mission['title'].toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              if (mission['description'] != null &&
                  mission['description'].toString().trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  mission['description'].toString(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: progress / 100),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${progress.round()}% complete',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    '${checkpoints.length} checkpoint${checkpoints.length == 1 ? '' : 's'}',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_ios, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  double get _progress {
    if (checkpoints.isEmpty) return doubleValue(mission['progress_percent']);
    return checkpoints
            .map((item) => doubleValue(item['progress_percent']))
            .reduce((a, b) => a + b) /
        checkpoints.length;
  }
}

class _MissionDetailPage extends StatefulWidget {
  const _MissionDetailPage({
    required this.mission,
    required this.initialGoals,
    required this.generateCheckpoints,
    required this.setCheckpointProgress,
    required this.editMission,
    required this.deleteMission,
  });

  final Map<String, dynamic> mission;
  final List<Map<String, dynamic>> initialGoals;
  final Future<List<String>> Function(Map<String, dynamic>) generateCheckpoints;
  final Future<void> Function(
    Map<String, dynamic>,
    Map<String, dynamic>,
    double,
  )
  setCheckpointProgress;
  final Future<void> Function([Map<String, dynamic>?]) editMission;
  final Future<void> Function(Map<String, dynamic>) deleteMission;

  @override
  State<_MissionDetailPage> createState() => _MissionDetailPageState();
}

class _MissionDetailPageState extends State<_MissionDetailPage> {
  late Map<String, dynamic> _mission;
  late List<Map<String, dynamic>> _goals;
  bool _checkpointing = false;

  @override
  void initState() {
    super.initState();
    _mission = Map<String, dynamic>.from(widget.mission);
    _goals = [...widget.initialGoals];
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCheckpoints());
  }

  @override
  Widget build(BuildContext context) {
    final checkpoints = _childGoals;
    final progress = _progress(checkpoints);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_mission['title']?.toString() ?? 'Mission'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () async {
              await widget.editMission(_mission);
              await _reload();
            },
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () async {
              await widget.deleteMission(_mission);
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width < 640 ? 14 : 24,
            vertical: MediaQuery.sizeOf(context).width < 640 ? 14 : 24,
          ),
          children: [
            if (_mission['description'] != null &&
                _mission['description'].toString().trim().isNotEmpty)
              BpCard(child: Text(_mission['description'].toString())),
            if (_mission['description'] != null &&
                _mission['description'].toString().trim().isNotEmpty)
              const SizedBox(height: 14),
            BpCard(child: _MissionProgress(value: progress)),
            const SizedBox(height: 14),
            BpCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Checkpoints',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (_checkpointing)
                        const SizedBox.square(
                          dimension: 18,
                          child: ExpressiveLoadingIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_checkpointing)
                    Text(
                      'AI is breaking down this mission...',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    )
                  else if (checkpoints.isEmpty)
                    Text(
                      'No checkpoints yet.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    )
                  else
                    for (final checkpoint in checkpoints)
                      _CheckpointRow(
                        checkpoint: checkpoint,
                        onChanged: (value) async {
                          await widget.setCheckpointProgress(
                            _mission,
                            checkpoint,
                            value,
                          );
                          await _reload();
                        },
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _ensureCheckpoints() async {
    if (_childGoals.isNotEmpty || _checkpointing) return;
    final missionId = _mission['id']?.toString();
    if (missionId == null || missionId.isEmpty) return;

    setState(() => _checkpointing = true);
    try {
      final checkpoints = await widget.generateCheckpoints(_mission);
      if (checkpoints.isEmpty) return;
      final childType = _childGoalType(_mission['goal_type']?.toString());
      await SupabaseService.client.from('goals').insert([
        for (final checkpoint in checkpoints)
          {
            'user_id': SupabaseService.currentUserId,
            'title': checkpoint,
            'description': 'AI checkpoint for ${_mission['title']}',
            'goal_type': childType,
            'parent_goal_id': missionId,
            'progress_percent': 0,
            'status': 'active',
          },
      ]);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create checkpoints: $error')),
      );
    } finally {
      if (mounted) setState(() => _checkpointing = false);
    }
  }

  Future<void> _reload() async {
    final goals = await McpContextService().getUserGoals(
      SupabaseService.currentUserId,
    );
    if (!mounted) return;
    setState(() {
      _goals = goals;
      _mission = goals.firstWhere(
        (goal) => goal['id']?.toString() == _mission['id']?.toString(),
        orElse: () => _mission,
      );
    });
  }

  List<Map<String, dynamic>> get _childGoals {
    final id = _mission['id']?.toString();
    if (id == null) return const [];
    return _goals
        .where((item) => item['parent_goal_id']?.toString() == id)
        .toList(growable: false);
  }

  double _progress(List<Map<String, dynamic>> checkpoints) {
    if (checkpoints.isEmpty) return doubleValue(_mission['progress_percent']);
    return checkpoints
            .map((item) => doubleValue(item['progress_percent']))
            .reduce((a, b) => a + b) /
        checkpoints.length;
  }

  String _childGoalType(String? type) {
    if (type == 'life') return 'yearly';
    if (type == 'yearly') return 'monthly';
    return 'weekly';
  }
}

class _MissionProgress extends StatelessWidget {
  const _MissionProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final progress = value.clamp(0, 100);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${progress.round()}%',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                'progress',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: progress / 100),
        ),
      ],
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  const _CheckpointRow({required this.checkpoint, required this.onChanged});

  final Map<String, dynamic> checkpoint;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final progress = doubleValue(checkpoint['progress_percent']);
    final complete = progress >= 100;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: complete,
            onChanged: (value) => onChanged(value == true ? 100 : 0),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  checkpoint['title'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Slider(
                  value: progress.clamp(0, 100),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${progress.round()}%',
                  onChanged: onChanged,
                ),
                Text(
                  '${progress.round()}% complete',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
