import 'dart:async';

import 'package:flutter/material.dart';
import 'package:googleapis/tasks/v1.dart' as google_tasks;

import '../config/app_config.dart';
import '../models/model_helpers.dart';
import '../services/ai_service.dart';
import '../services/google_tasks_service.dart';
import '../services/mcp_context_service.dart';
import '../services/supabase_service.dart';
import '../ui/bp_card.dart';
import '../ui/expressive_loading_indicator.dart';

class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> with WidgetsBindingObserver {
  static const _googleTasksAutoSyncInterval = Duration(minutes: 5);

  final _mcp = McpContextService();
  final _ai = AiService();
  final _googleTasks = GoogleTasksService();
  late Future<List<Map<String, dynamic>>> _future;
  List<Map<String, dynamic>>? _orderedTasks;
  bool _ordering = false;
  bool _googleTasksAuthorized = false;
  bool _syncingGoogleTasks = false;
  bool _pendingGoogleTasksSync = false;
  Timer? _googleTasksAutoSyncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _load();
    unawaited(_initializeGoogleTasksAutoSync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _googleTasksAutoSyncTimer?.cancel();
    _googleTasks.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _refresh();
    unawaited(_autoSyncGoogleTasks());
  }

  Future<List<Map<String, dynamic>>> _load() {
    return _mcp.getAllTasks(SupabaseService.currentUserId);
  }

  void _refresh() {
    setState(() {
      _future = _load();
      _orderedTasks = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Todo List'),
        actions: [
          IconButton(
            tooltip: 'AI task order',
            onPressed: _ordering ? null : _orderWithAi,
            icon: _ordering
                ? const SizedBox.square(
                    dimension: 18,
                    child: ExpressiveLoadingIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
          ),
          IconButton(
            tooltip: 'Add task',
            onPressed: () => _editTask(),
            icon: const Icon(Icons.add),
          ),
          if (_syncingGoogleTasks)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox.square(
                dimension: 18,
                child: ExpressiveLoadingIndicator(strokeWidth: 2),
              ),
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
          final tasks = _orderedTasks ?? snapshot.data ?? [];

          if (tasks.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'No tasks yet',
              message:
                  'Add a task and connect your day to your long-term mission.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return BpCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Checkbox(
                    value: task['status'] == 'completed',
                    onChanged: (value) => _toggleTask(task, value ?? false),
                  ),
                  title: Text(
                    task['title'].toString(),
                    style: TextStyle(
                      decoration: task['status'] == 'completed'
                          ? TextDecoration.lineThrough
                          : null,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _Chip(text: '${task['priority']} priority'),
                        _Chip(text: task['category'].toString()),
                        _Chip(text: compactDate(task['due_date'])),
                        if (task['estimated_minutes'] != null)
                          _Chip(text: '${task['estimated_minutes']} min'),
                        _Chip(text: task['status'].toString()),
                      ],
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _editTask(task);
                      if (value == 'delete') _deleteTask(task);
                      if (value == 'tomorrow') _moveToTomorrow(task);
                      if (value == 'missed') _markMissed(task);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'missed',
                        child: Text('Mark missed'),
                      ),
                      PopupMenuItem(
                        value: 'tomorrow',
                        child: Text('Move to tomorrow'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: tasks.length,
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editTask(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _initializeGoogleTasksAutoSync() async {
    if (!AppConfig.googleApisConfigured) return;
    try {
      await _googleTasks.initialize(
        onAuthChanged: (accountEmail, authorized) {
          if (!mounted) return;
          setState(() => _googleTasksAuthorized = authorized);
          if (authorized) {
            _startGoogleTasksAutoSyncTimer();
            unawaited(_autoSyncGoogleTasks());
          } else {
            _stopGoogleTasksAutoSyncTimer();
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _googleTasksAuthorized = false);
          _stopGoogleTasksAutoSyncTimer();
        },
      );
      if (!mounted) return;
      setState(() => _googleTasksAuthorized = _googleTasks.isAuthorized);
      if (_googleTasks.isAuthorized) {
        _startGoogleTasksAutoSyncTimer();
        unawaited(_autoSyncGoogleTasks());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _googleTasksAuthorized = false);
      _stopGoogleTasksAutoSyncTimer();
    }
  }

  void _startGoogleTasksAutoSyncTimer() {
    _googleTasksAutoSyncTimer ??= Timer.periodic(
      _googleTasksAutoSyncInterval,
      (_) => unawaited(_autoSyncGoogleTasks()),
    );
  }

  void _stopGoogleTasksAutoSyncTimer() {
    _googleTasksAutoSyncTimer?.cancel();
    _googleTasksAutoSyncTimer = null;
  }

  Future<void> _autoSyncGoogleTasks() async {
    if (!mounted || !_googleTasksAuthorized || !_googleTasks.isAuthorized) {
      return;
    }
    if (_syncingGoogleTasks) {
      _pendingGoogleTasksSync = true;
      return;
    }

    setState(() => _syncingGoogleTasks = true);
    try {
      final tasks = await _load();
      await _syncGoogleTasks(tasks);
      if (!mounted) return;
      setState(() {
        _future = _load();
        _orderedTasks = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (_googleTasks.isAuthorizationError(error)) {
        _googleTasks.clearAuthorization();
        _stopGoogleTasksAutoSyncTimer();
        setState(() => _googleTasksAuthorized = false);
      } else {
        _showError('Could not sync Google Tasks: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _syncingGoogleTasks = false);
        if (_pendingGoogleTasksSync) {
          _pendingGoogleTasksSync = false;
          unawaited(_autoSyncGoogleTasks());
        }
      }
    }
  }

  Future<GoogleTasksSyncResult> _syncGoogleTasks(
    List<Map<String, dynamic>> localTasks,
  ) async {
    final userId = SupabaseService.currentUserId;
    final taskList = await _googleTasks.getOrCreateSyncTaskList();
    final taskListId = taskList.id;
    if (taskListId == null) {
      throw StateError('Google Tasks did not return a task list id.');
    }

    final googleTasks = await _googleTasks.listTasks(
      taskListId,
      includeDeleted: true,
    );
    final activeGoogleTasks = googleTasks
        .where((task) => task.deleted != true)
        .toList(growable: false);
    final googleById = <String, google_tasks.Task>{
      for (final task in googleTasks)
        if (task.id != null) task.id!: task,
    };
    final linkedGoogleIds = <String>{};
    var createdGoogle = 0;
    var updatedGoogle = 0;
    var importedLocal = 0;
    var updatedLocal = 0;
    var removedLocal = 0;

    for (final localTask in localTasks) {
      final googleTaskId = _stringValue(localTask['google_task_id']);
      if (googleTaskId == null) {
        final created = await _googleTasks.createTask(
          taskListId,
          _draftFromLocalTask(localTask),
        );
        await _saveGoogleTaskLink(localTask['id'], taskListId, created);
        final createdId = created.id;
        if (createdId != null) linkedGoogleIds.add(createdId);
        createdGoogle++;
        continue;
      }

      linkedGoogleIds.add(googleTaskId);
      final remoteTask = googleById[googleTaskId];
      if (remoteTask?.deleted == true) {
        await _deleteLocalTaskFromGoogle(localTask['id']);
        removedLocal++;
        continue;
      }

      if (remoteTask == null) {
        final created = await _googleTasks.createTask(
          taskListId,
          _draftFromLocalTask(localTask),
        );
        await _saveGoogleTaskLink(localTask['id'], taskListId, created);
        final createdId = created.id;
        if (createdId != null) linkedGoogleIds.add(createdId);
        createdGoogle++;
        continue;
      }

      if (_googleTaskChangedSinceLastSync(localTask, remoteTask)) {
        await _updateLocalTaskFromGoogle(
          localTask['id'],
          userId,
          taskListId,
          remoteTask,
        );
        updatedLocal++;
      } else {
        final updated = await _googleTasks.updateTask(
          taskListId,
          googleTaskId,
          _draftFromLocalTask(localTask),
        );
        await _saveGoogleTaskLink(localTask['id'], taskListId, updated);
        updatedGoogle++;
      }
    }

    for (final googleTask in activeGoogleTasks) {
      final googleTaskId = googleTask.id;
      if (googleTaskId == null || linkedGoogleIds.contains(googleTaskId)) {
        continue;
      }
      await _insertLocalTaskFromGoogle(userId, taskListId, googleTask);
      importedLocal++;
    }

    return GoogleTasksSyncResult(
      createdGoogle: createdGoogle,
      updatedGoogle: updatedGoogle,
      importedLocal: importedLocal,
      updatedLocal: updatedLocal,
      removedLocal: removedLocal,
    );
  }

  GoogleTaskDraft _draftFromLocalTask(Map<String, dynamic> task) {
    return GoogleTaskDraft(
      title: task['title']?.toString().trim().isEmpty ?? true
          ? 'Untitled task'
          : task['title'].toString(),
      notes: task['description']?.toString() ?? '',
      dueDate: DateTime.tryParse(task['due_date']?.toString() ?? ''),
      completed: task['status'] == 'completed',
      completedAt: DateTime.tryParse(task['completed_at']?.toString() ?? ''),
    );
  }

  bool _googleTaskChangedSinceLastSync(
    Map<String, dynamic> localTask,
    google_tasks.Task googleTask,
  ) {
    final lastSynced = DateTime.tryParse(
      localTask['google_task_updated_at']?.toString() ?? '',
    );
    final googleUpdated = DateTime.tryParse(googleTask.updated ?? '');
    if (lastSynced == null || googleUpdated == null) return false;
    return googleUpdated.isAfter(lastSynced.add(const Duration(seconds: 1)));
  }

  Future<void> _saveGoogleTaskLink(
    Object? localTaskId,
    String taskListId,
    google_tasks.Task googleTask,
  ) async {
    final taskId = googleTask.id;
    if (localTaskId == null || taskId == null) return;
    try {
      await SupabaseService.client
          .from('tasks')
          .update({
            'google_task_id': taskId,
            'google_task_list_id': taskListId,
            'google_task_updated_at': _googleUpdatedAt(googleTask),
          })
          .eq('id', localTaskId);
    } catch (error) {
      _throwGoogleTaskSchemaError(error);
    }
  }

  Future<void> _updateLocalTaskFromGoogle(
    Object? localTaskId,
    String userId,
    String taskListId,
    google_tasks.Task googleTask,
  ) async {
    if (localTaskId == null) return;
    try {
      await SupabaseService.client
          .from('tasks')
          .update(
            _localDataFromGoogleTask(userId, taskListId, googleTask)
              ..remove('user_id'),
          )
          .eq('id', localTaskId);
    } catch (error) {
      _throwGoogleTaskSchemaError(error);
    }
  }

  Future<void> _insertLocalTaskFromGoogle(
    String userId,
    String taskListId,
    google_tasks.Task googleTask,
  ) async {
    try {
      await SupabaseService.client
          .from('tasks')
          .insert(_localDataFromGoogleTask(userId, taskListId, googleTask));
    } catch (error) {
      _throwGoogleTaskSchemaError(error);
    }
  }

  Future<void> _deleteLocalTaskFromGoogle(Object? localTaskId) async {
    if (localTaskId == null) return;
    await SupabaseService.client.from('tasks').delete().eq('id', localTaskId);
  }

  Map<String, dynamic> _localDataFromGoogleTask(
    String userId,
    String taskListId,
    google_tasks.Task googleTask,
  ) {
    final completed = googleTask.status == 'completed';
    return {
      'user_id': userId,
      'title': googleTask.title?.trim().isEmpty ?? true
          ? 'Untitled task'
          : googleTask.title,
      'description': googleTask.notes ?? '',
      'priority': 'medium',
      'category': 'personal',
      'status': completed ? 'completed' : 'pending',
      'completed_at': completed
          ? DateTime.tryParse(googleTask.completed ?? '')?.toIso8601String()
          : null,
      'due_date': _googleDueDateKey(googleTask.due),
      'google_task_id': googleTask.id,
      'google_task_list_id': taskListId,
      'google_task_updated_at': _googleUpdatedAt(googleTask),
    };
  }

  String? _googleDueDateKey(String? value) {
    if (value == null || value.length < 10) return null;
    return value.substring(0, 10);
  }

  String? _googleUpdatedAt(google_tasks.Task task) {
    return DateTime.tryParse(task.updated ?? '')?.toIso8601String();
  }

  String? _stringValue(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  Never _throwGoogleTaskSchemaError(Object error) {
    final text = error.toString();
    if (text.contains('PGRST204') &&
        (text.contains('google_task_id') ||
            text.contains('google_task_list_id') ||
            text.contains('google_task_updated_at'))) {
      throw StateError(
        'Run the latest supabase/schema.sql so tasks can store Google Tasks sync IDs.',
      );
    }
    throw error;
  }

  Future<void> _orderWithAi() async {
    setState(() => _ordering = true);
    try {
      final userId = SupabaseService.currentUserId;
      final tasks = await _future;
      final context = await _mcp.getUserContext(userId);
      final ordered = await _ai.generateTaskPriorityOrder(tasks, context);
      final orderedIds = ordered.map((task) => task['id']).toSet();
      final remaining = tasks
          .where((task) => !orderedIds.contains(task['id']))
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _orderedTasks = [...ordered, ...remaining]);
    } catch (error) {
      _showError('Could not order tasks: $error');
    } finally {
      if (mounted) setState(() => _ordering = false);
    }
  }

  Future<void> _toggleTask(Map<String, dynamic> task, bool completed) async {
    await _runTaskMutation(() async {
      await SupabaseService.client
          .from('tasks')
          .update({
            'status': completed ? 'completed' : 'pending',
            'completed_at': completed ? DateTime.now().toIso8601String() : null,
          })
          .eq('id', task['id']);
    });
  }

  Future<void> _markMissed(Map<String, dynamic> task) async {
    await _runTaskMutation(() async {
      await SupabaseService.client
          .from('tasks')
          .update({'status': 'missed', 'completed_at': null})
          .eq('id', task['id']);
    });
  }

  Future<void> _moveToTomorrow(Map<String, dynamic> task) async {
    final tomorrow = dateKey(DateTime.now().add(const Duration(days: 1)));
    await _runTaskMutation(() async {
      await SupabaseService.client
          .from('tasks')
          .update({
            'status': 'pending',
            'due_date': tomorrow,
            'completed_at': null,
          })
          .eq('id', task['id']);
    });
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    await _runTaskMutation(() async {
      await _deleteLinkedGoogleTask(task);
      await SupabaseService.client.from('tasks').delete().eq('id', task['id']);
    });
  }

  Future<void> _runTaskMutation(Future<void> Function() mutation) async {
    try {
      await mutation();
      if (mounted) {
        _refresh();
        unawaited(_autoSyncGoogleTasks());
      }
    } catch (error) {
      _showError('Could not update task: $error');
    }
  }

  Future<void> _deleteLinkedGoogleTask(Map<String, dynamic> task) async {
    if (!_googleTasksAuthorized || !_googleTasks.isAuthorized) return;
    final taskListId = _stringValue(task['google_task_list_id']);
    final taskId = _stringValue(task['google_task_id']);
    if (taskListId == null || taskId == null) return;

    try {
      await _googleTasks.deleteTask(taskListId, taskId);
    } catch (error) {
      if (_googleTasks.isAuthorizationError(error)) {
        _googleTasks.clearAuthorization();
        _stopGoogleTasksAutoSyncTimer();
        if (mounted) setState(() => _googleTasksAuthorized = false);
        return;
      }
      _showError('Could not delete Google Tasks copy: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editTask([Map<String, dynamic>? task]) async {
    List<Map<String, dynamic>> goals;
    try {
      goals = await _mcp.getUserGoals(SupabaseService.currentUserId);
    } catch (error) {
      goals = [];
      _showError('Could not load goals: $error');
    }
    if (!mounted) return;
    final goalIds = goals.map((goal) => goal['id'].toString()).toSet();
    final title = TextEditingController(text: task?['title']?.toString());
    final description = TextEditingController(
      text: task?['description']?.toString(),
    );
    final estimate = TextEditingController(
      text: task?['estimated_minutes']?.toString() ?? '',
    );
    var priority = task?['priority']?.toString() ?? 'medium';
    var category = task?['category']?.toString() ?? 'personal';
    final linkedGoalId = task?['goal_id']?.toString();
    var goalId = linkedGoalId != null && goalIds.contains(linkedGoalId)
        ? linkedGoalId
        : 'none';
    var dueDate = DateTime.tryParse(task?['due_date']?.toString() ?? '');
    var saving = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(task == null ? 'Add task' : 'Edit task'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (errorText != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
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
                      initialValue: priority,
                      decoration: const InputDecoration(labelText: 'Priority'),
                      items: const [
                        DropdownMenuItem(value: 'high', child: Text('High')),
                        DropdownMenuItem(
                          value: 'medium',
                          child: Text('Medium'),
                        ),
                        DropdownMenuItem(value: 'low', child: Text('Low')),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => priority = value ?? priority),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: const [
                        DropdownMenuItem(value: 'study', child: Text('Study')),
                        DropdownMenuItem(value: 'work', child: Text('Work')),
                        DropdownMenuItem(
                          value: 'health',
                          child: Text('Health'),
                        ),
                        DropdownMenuItem(
                          value: 'finance',
                          child: Text('Finance'),
                        ),
                        DropdownMenuItem(
                          value: 'personal',
                          child: Text('Personal'),
                        ),
                        DropdownMenuItem(
                          value: 'career',
                          child: Text('Career'),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => category = value ?? category),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: goalId,
                      decoration: const InputDecoration(
                        labelText: 'Linked goal',
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: 'none',
                          child: Text('None'),
                        ),
                        for (final goal in goals)
                          DropdownMenuItem<String>(
                            value: goal['id'].toString(),
                            child: Text(goal['title'].toString()),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => goalId = value ?? 'none'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: estimate,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Estimated minutes',
                      ),
                    ),
                    const SizedBox(height: 12),
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
                          initialDate: dueDate ?? DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => dueDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        dueDate == null
                            ? 'Set due date'
                            : 'Due ${compactDate(dueDate!.toIso8601String())}',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final trimmedTitle = title.text.trim();
                          final trimmedEstimate = estimate.text.trim();
                          final estimatedMinutes = trimmedEstimate.isEmpty
                              ? null
                              : int.tryParse(trimmedEstimate);
                          if (trimmedTitle.isEmpty) {
                            setDialogState(
                              () => errorText = 'Task title is required.',
                            );
                            return;
                          }
                          if (trimmedEstimate.isNotEmpty &&
                              (estimatedMinutes == null ||
                                  estimatedMinutes <= 0)) {
                            setDialogState(
                              () => errorText =
                                  'Estimated minutes must be a positive number.',
                            );
                            return;
                          }

                          setDialogState(() {
                            saving = true;
                            errorText = null;
                          });

                          try {
                            final data = {
                              'user_id': SupabaseService.currentUserId,
                              'title': trimmedTitle,
                              'description': description.text.trim(),
                              'priority': priority,
                              'category': category,
                              'due_date': dueDate == null
                                  ? null
                                  : dateKey(dueDate!),
                              'estimated_minutes': estimatedMinutes,
                            };
                            if (goalId != 'none' ||
                                task?.containsKey('goal_id') == true) {
                              data['goal_id'] = goalId == 'none'
                                  ? null
                                  : goalId;
                            }
                            if (task == null) {
                              await _saveNewTask(data);
                            } else {
                              final updateData = Map<String, dynamic>.from(data)
                                ..remove('user_id');
                              await _updateTask(task['id'], updateData);
                            }
                            if (context.mounted) Navigator.pop(context);
                            if (mounted) {
                              _refresh();
                              unawaited(_autoSyncGoogleTasks());
                            }
                          } catch (error) {
                            setDialogState(() {
                              saving = false;
                              errorText = 'Could not save task: $error';
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: ExpressiveLoadingIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    title.dispose();
    description.dispose();
    estimate.dispose();
  }

  Future<void> _saveNewTask(Map<String, dynamic> data) async {
    try {
      await SupabaseService.client.from('tasks').insert(data);
    } catch (error) {
      if (!_isMissingGoalIdError(error) || !data.containsKey('goal_id')) {
        rethrow;
      }
      final fallbackData = Map<String, dynamic>.from(data)..remove('goal_id');
      await SupabaseService.client.from('tasks').insert(fallbackData);
    }
  }

  Future<void> _updateTask(Object taskId, Map<String, dynamic> data) async {
    try {
      await SupabaseService.client.from('tasks').update(data).eq('id', taskId);
    } catch (error) {
      if (!_isMissingGoalIdError(error) || !data.containsKey('goal_id')) {
        rethrow;
      }
      final fallbackData = Map<String, dynamic>.from(data)..remove('goal_id');
      await SupabaseService.client
          .from('tasks')
          .update(fallbackData)
          .eq('id', taskId);
    }
  }

  bool _isMissingGoalIdError(Object error) {
    final text = error.toString();
    return text.contains('PGRST204') && text.contains('goal_id');
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class GoogleTasksSyncResult {
  const GoogleTasksSyncResult({
    required this.createdGoogle,
    required this.updatedGoogle,
    required this.importedLocal,
    required this.updatedLocal,
    required this.removedLocal,
  });

  final int createdGoogle;
  final int updatedGoogle;
  final int importedLocal;
  final int updatedLocal;
  final int removedLocal;

  int get total =>
      createdGoogle +
      updatedGoogle +
      importedLocal +
      updatedLocal +
      removedLocal;

  String get message {
    if (total == 0) return 'Everything is already in sync.';
    return [
      if (createdGoogle > 0) '$createdGoogle pushed to Google',
      if (updatedGoogle > 0) '$updatedGoogle updated in Google',
      if (importedLocal > 0) '$importedLocal imported',
      if (updatedLocal > 0) '$updatedLocal updated locally',
      if (removedLocal > 0) '$removedLocal removed locally',
    ].join(', ');
  }
}
