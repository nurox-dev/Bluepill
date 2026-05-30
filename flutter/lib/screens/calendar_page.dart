import 'dart:async';

import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis/tasks/v1.dart' as google_tasks;
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../models/model_helpers.dart';
import '../services/ai_service.dart';
import '../services/google_calendar_service.dart';
import '../services/google_tasks_service.dart';
import '../services/mcp_context_service.dart';
import '../services/supabase_service.dart';
import '../ui/bp_card.dart';
import '../ui/expressive_loading_indicator.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage>
    with WidgetsBindingObserver {
  static const _calendarAutoRefreshInterval = Duration(minutes: 5);
  static const _googleTasksAutoSyncInterval = Duration(minutes: 5);

  final _calendar = GoogleCalendarService();
  final _mcp = McpContextService();
  final _ai = AiService();
  final _googleTasks = GoogleTasksService();
  final _dateFormat = DateFormat('EEE, MMM d');
  final _timeFormat = DateFormat('h:mm a');
  final _dateTimeFormat = DateFormat('MMM d, h:mm a');
  final _monthFormat = DateFormat('MMMM yyyy');
  final _selectedDateFormat = DateFormat('EEEE, MMMM d');

  String? _accountEmail;
  List<calendar.Event> _events = [];
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>>? _orderedTasks;
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  bool _authorized = false;
  bool _initializing = true;
  bool _loadingEvents = false;
  bool _loadingTasks = false;
  bool _ordering = false;
  bool _busy = false;
  bool _googleTasksAuthorized = false;
  bool _syncingGoogleTasks = false;
  bool _pendingGoogleTasksSync = false;
  String? _error;
  String? _taskError;
  Timer? _calendarAutoRefreshTimer;
  Timer? _googleTasksAutoSyncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCalendar());
    unawaited(_loadTasks());
    unawaited(_initializeGoogleTasksAutoSync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _calendarAutoRefreshTimer?.cancel();
    _googleTasksAutoSyncTimer?.cancel();
    _calendar.dispose();
    _googleTasks.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_calendar.isAuthorized) unawaited(_loadEvents());
    unawaited(_loadTasks());
    unawaited(_autoSyncGoogleTasks());
  }

  Future<void> _initializeCalendar() async {
    try {
      await _calendar.initialize(
        onAuthChanged: (accountEmail, authorized) async {
          if (!mounted) return;
          setState(() {
            _accountEmail = accountEmail;
            _authorized = authorized;
            _error = null;
          });
          if (authorized) {
            _startCalendarAutoRefreshTimer();
            await _loadEvents();
          } else {
            _stopCalendarAutoRefreshTimer();
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _error = error.toString());
        },
      );
      if (!mounted) return;
      setState(() {
        _accountEmail = _calendar.accountEmail;
        _authorized = _calendar.isAuthorized;
        _initializing = false;
      });
      if (_calendar.isAuthorized) {
        _startCalendarAutoRefreshTimer();
        await _loadEvents();
      } else {
        _stopCalendarAutoRefreshTimer();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _initializing = false;
      });
    }
  }

  void _startCalendarAutoRefreshTimer() {
    _calendarAutoRefreshTimer ??= Timer.periodic(
      _calendarAutoRefreshInterval,
      (_) => unawaited(_loadEvents()),
    );
  }

  void _stopCalendarAutoRefreshTimer() {
    _calendarAutoRefreshTimer?.cancel();
    _calendarAutoRefreshTimer = null;
  }

  Future<void> _loadEvents() async {
    if (!_calendar.isAuthorized || _loadingEvents) return;
    setState(() => _loadingEvents = true);
    try {
      final events = await _calendar.listUpcomingEvents();
      await _saveCalendarContext(events);
      if (!mounted) return;
      setState(() {
        _events = events;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (_calendar.isAuthorizationError(error)) {
        _calendar.clearAuthorization();
        _stopCalendarAutoRefreshTimer();
        setState(() {
          _authorized = false;
          _events = [];
          _error =
              'Google Calendar needs permission. Refresh Google access from Settings > Account.';
        });
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loadingEvents = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadTasksFromStore() {
    return _mcp.getAllTasks(SupabaseService.currentUserId);
  }

  Future<void> _loadTasks() async {
    if (_loadingTasks) return;
    setState(() => _loadingTasks = true);
    try {
      final tasks = await _loadTasksFromStore();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _orderedTasks = null;
        _taskError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _taskError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingTasks = false);
    }
  }

  Future<void> _refreshPlanner() async {
    if (_calendar.isAuthorized) {
      await _loadEvents();
    }
    if (_googleTasksAuthorized && _googleTasks.isAuthorized) {
      await _autoSyncGoogleTasks();
    } else {
      await _loadTasks();
    }
  }

  Future<void> _runBusyAction(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _orderedTasks ?? _tasks;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planner'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadingEvents || _loadingTasks || _syncingGoogleTasks
                ? null
                : _refreshPlanner,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'AI task order',
            onPressed: _ordering || tasks.isEmpty ? null : _orderWithAi,
            icon: _ordering
                ? const SizedBox.square(
                    dimension: 18,
                    child: ExpressiveLoadingIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
          ),
          IconButton(
            tooltip: 'Add task',
            onPressed: _busy ? null : () => _editTask(),
            icon: const Icon(Icons.check_circle_outline),
          ),
          if (_authorized)
            IconButton(
              tooltip: 'Add event',
              onPressed: _busy ? null : () => _editEvent(),
              icon: const Icon(Icons.event_available_outlined),
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
      body: _initializing
          ? const Center(child: ExpressiveLoadingIndicator())
          : RefreshIndicator(
              onRefresh: _refreshPlanner,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  SectionTitle(
                    title: 'Planner',
                    subtitle: _plannerSubtitle(tasks.length),
                    trailing: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : () => _editTask(),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Task'),
                        ),
                        if (_authorized)
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _editEvent(),
                            icon: const Icon(Icons.event_outlined),
                            label: const Text('Event'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    _ErrorCard(message: _error!),
                    const SizedBox(height: 16),
                  ],
                  if (_taskError != null) ...[
                    _ErrorCard(message: _taskError!),
                    const SizedBox(height: 16),
                  ],
                  if (!AppConfig.googleCalendarConfigured) const _SetupCard(),
                  if (AppConfig.googleCalendarConfigured && !_authorized)
                    _CalendarAccountCard(email: _accountEmail),
                  if (!AppConfig.googleCalendarConfigured ||
                      (AppConfig.googleCalendarConfigured && !_authorized))
                    const SizedBox(height: 16),
                  if (_loadingEvents || _loadingTasks || _syncingGoogleTasks)
                    const LinearProgressIndicator(),
                  if (_loadingEvents || _loadingTasks || _syncingGoogleTasks)
                    const SizedBox(height: 16),
                  _CalendarWorkspace(
                    focusedMonth: _focusedMonth,
                    selectedDate: _selectedDate,
                    monthLabel: _monthFormat.format(_focusedMonth),
                    selectedDateLabel: _selectedDateFormat.format(
                      _selectedDate,
                    ),
                    events: _events,
                    tasks: tasks,
                    eventStart: _eventStart,
                    eventTimeText: _formatEventTime,
                    taskDueDate: _taskDueDate,
                    onPreviousMonth: () => _moveMonth(-1),
                    onNextMonth: () => _moveMonth(1),
                    onToday: _goToToday,
                    onSelectDate: _selectDate,
                    onCreateEvent: () => _editEvent(),
                    onCreateTask: () => _editTask(),
                    onEditEvent: _editEvent,
                    onDeleteEvent: _deleteEvent,
                    onToggleTask: _toggleTask,
                    onEditTask: _editTask,
                    onDeleteTask: _deleteTask,
                    onMoveTaskToTomorrow: _moveToTomorrow,
                    onMarkTaskMissed: _markMissed,
                  ),
                  if (tasks.isEmpty && !_loadingTasks) ...[
                    const SizedBox(height: 16),
                    const EmptyState(
                      icon: Icons.check_circle_outline,
                      title: 'No tasks yet',
                      message:
                          'Add a task and connect your day to your calendar.',
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  String _plannerSubtitle(int taskCount) {
    final calendarLabel = _accountEmail?.trim().isNotEmpty == true
        ? _accountEmail!.trim()
        : _authorized
        ? 'Primary calendar'
        : 'Calendar not connected';
    final taskLabel = taskCount == 1 ? '1 task' : '$taskCount tasks';
    return '$calendarLabel • $taskLabel';
  }

  Future<void> _editEvent([calendar.Event? event]) async {
    final title = TextEditingController(text: event?.summary ?? '');
    final description = TextEditingController(
      text: event?.description?.toString() ?? '',
    );
    final location = TextEditingController(
      text: event?.location?.toString() ?? '',
    );
    final attendees = TextEditingController(
      text:
          event?.attendees
              ?.map((attendee) => attendee.email)
              .whereType<String>()
              .join(', ') ??
          '',
    );

    final defaultStart = _defaultEventStart();
    var start = _eventStart(event) ?? defaultStart;
    var end = _eventEnd(event) ?? defaultStart.add(const Duration(hours: 1));
    if (!end.isAfter(start)) {
      end = start.add(const Duration(hours: 1));
    }
    var saving = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> pickDateTime(bool pickingStart) async {
              final current = pickingStart ? start : end;
              final pickedDate = await showDatePicker(
                context: dialogContext,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
                initialDate: current,
              );
              if (pickedDate == null || !dialogContext.mounted) return;
              final pickedTime = await showTimePicker(
                context: dialogContext,
                initialTime: TimeOfDay.fromDateTime(current),
              );
              if (pickedTime == null) return;
              final picked = DateTime(
                pickedDate.year,
                pickedDate.month,
                pickedDate.day,
                pickedTime.hour,
                pickedTime.minute,
              );
              setDialogState(() {
                if (pickingStart) {
                  final duration = end.difference(start);
                  start = picked;
                  end = start.add(
                    duration.isNegative || duration == Duration.zero
                        ? const Duration(hours: 1)
                        : duration,
                  );
                } else {
                  end = picked;
                }
              });
            }

            return AlertDialog(
              title: Text(event == null ? 'Add event' : 'Edit event'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
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
                              fontWeight: FontWeight.w700,
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
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: saving
                                  ? null
                                  : () => pickDateTime(true),
                              icon: const Icon(Icons.play_arrow_outlined),
                              label: Text(_formatDraftDateTime(start)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: saving
                                  ? null
                                  : () => pickDateTime(false),
                              icon: const Icon(Icons.stop_outlined),
                              label: Text(_formatDraftDateTime(end)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: location,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: attendees,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Attendees',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: description,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final parsedAttendees = _parseAttendees(
                            attendees.text,
                          );
                          if (title.text.trim().isEmpty) {
                            setDialogState(
                              () => errorText = 'Event title is required.',
                            );
                            return;
                          }
                          if (!end.isAfter(start)) {
                            setDialogState(
                              () => errorText =
                                  'End time must be after start time.',
                            );
                            return;
                          }
                          if (parsedAttendees.any(
                            (email) => !email.contains('@'),
                          )) {
                            setDialogState(
                              () => errorText =
                                  'Attendees must be valid email addresses.',
                            );
                            return;
                          }

                          setDialogState(() {
                            saving = true;
                            errorText = null;
                          });

                          final draft = CalendarEventDraft(
                            title: title.text.trim(),
                            description: description.text.trim(),
                            location: location.text.trim(),
                            attendees: parsedAttendees,
                            start: start,
                            end: end,
                          );

                          try {
                            final eventId = event?.id;
                            if (eventId == null) {
                              await _calendar.createEvent(draft);
                            } else {
                              await _calendar.updateEvent(eventId, draft);
                            }
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            await _loadEvents();
                          } catch (error) {
                            setDialogState(() {
                              saving = false;
                              errorText = error.toString();
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
    location.dispose();
    attendees.dispose();
  }

  Future<void> _deleteEvent(calendar.Event event) async {
    final eventId = event.id;
    if (eventId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete event'),
        content: Text(event.summary ?? 'Untitled event'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runBusyAction(() async {
      await _calendar.deleteEvent(eventId);
      await _loadEvents();
    });
  }

  String _formatEventTime(calendar.Event event) {
    final start = _eventStart(event);
    final end = _eventEnd(event);
    if (start == null) return 'No time';
    if (end == null) return _dateTimeFormat.format(start);
    if (_sameDate(start, end)) {
      return '${_dateFormat.format(start)} • ${_timeFormat.format(start)} - ${_timeFormat.format(end)}';
    }
    return '${_dateTimeFormat.format(start)} - ${_dateTimeFormat.format(end)}';
  }

  String _formatDraftDateTime(DateTime value) {
    return _dateTimeFormat.format(value);
  }

  void _moveMonth(int offset) {
    setState(() {
      _focusedMonth = DateTime(
        _focusedMonth.year,
        _focusedMonth.month + offset,
      );
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _selectedDate = DateTime(now.year, now.month, now.day);
      _focusedMonth = DateTime(now.year, now.month);
    });
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
      _focusedMonth = DateTime(date.year, date.month);
    });
  }

  DateTime? _eventStart(calendar.Event? event) {
    final start = event?.start;
    return start?.dateTime?.toLocal() ?? start?.date?.toLocal();
  }

  DateTime? _eventEnd(calendar.Event? event) {
    final end = event?.end;
    return end?.dateTime?.toLocal() ?? end?.date?.toLocal();
  }

  DateTime _nextWholeHour() {
    final next = DateTime.now().add(const Duration(hours: 1));
    return DateTime(next.year, next.month, next.day, next.hour);
  }

  DateTime _defaultEventStart() {
    final today = DateTime.now();
    if (_sameDate(_selectedDate, today)) {
      return _nextWholeHour();
    }
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      9,
    );
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<String> _parseAttendees(String value) {
    return value
        .split(RegExp(r'[,;\n]'))
        .map((email) => email.trim())
        .where((email) => email.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Future<void> _saveCalendarContext(List<calendar.Event> events) async {
    final email = _calendar.accountEmail?.trim();
    if (email == null || email.isEmpty || !_calendar.isAuthorized) return;

    await _mcp.saveGoogleCalendarConnection(
      userId: SupabaseService.currentUserId,
      email: email,
      scopes: GoogleCalendarService.calendarScopes,
      upcomingEvents: events.map(_eventSummary).toList(growable: false),
    );
  }

  Map<String, dynamic> _eventSummary(calendar.Event event) {
    final start = _eventStart(event);
    final end = _eventEnd(event);
    return {
      'id': event.id,
      'title': event.summary ?? 'Untitled event',
      'start': start?.toIso8601String(),
      'end': end?.toIso8601String(),
      'time_text': _formatEventTime(event),
      if ((event.location ?? '').trim().isNotEmpty) 'location': event.location,
      if ((event.description ?? '').trim().isNotEmpty)
        'description': event.description,
      if ((event.attendees ?? []).isNotEmpty)
        'attendees': event.attendees
            ?.map((attendee) => attendee.email)
            .whereType<String>()
            .toList(growable: false),
    };
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
      final tasks = await _loadTasksFromStore();
      await _syncGoogleTasks(tasks);
      final freshTasks = await _loadTasksFromStore();
      if (!mounted) return;
      setState(() {
        _tasks = freshTasks;
        _orderedTasks = null;
        _taskError = null;
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

  Future<_GoogleTasksSyncResult> _syncGoogleTasks(
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

    return _GoogleTasksSyncResult(
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
      final tasks = _tasks.isEmpty ? await _loadTasksFromStore() : _tasks;
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
        await _loadTasks();
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
    if (task == null) {
      dueDate = _selectedDate;
    }
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
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: saving
                                ? null
                                : () async {
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
                        ),
                        if (dueDate != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Clear due date',
                            onPressed: saving
                                ? null
                                : () => setDialogState(() => dueDate = null),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ],
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
                              await _loadTasks();
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

  DateTime? _taskDueDate(Map<String, dynamic> task) {
    return DateTime.tryParse(task['due_date']?.toString() ?? '');
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard();

  @override
  Widget build(BuildContext context) {
    return const BpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings_outlined),
              SizedBox(width: 8),
              Text(
                'Calendar setup needed',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text('Add GOOGLE_OAUTH_CLIENT_ID to .env and enable Calendar API.'),
        ],
      ),
    );
  }
}

class _CalendarAccountCard extends StatelessWidget {
  const _CalendarAccountCard({required this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    final linkedEmail = email?.trim();
    return BpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.event_available_outlined),
              SizedBox(width: 8),
              Text(
                'Calendar account',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (linkedEmail != null && linkedEmail.isNotEmpty) ...[
            Text(
              linkedEmail,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
          ],
          const Text('Manage Google connection from Settings > Account.'),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return BpCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarWorkspace extends StatelessWidget {
  const _CalendarWorkspace({
    required this.focusedMonth,
    required this.selectedDate,
    required this.monthLabel,
    required this.selectedDateLabel,
    required this.events,
    required this.tasks,
    required this.eventStart,
    required this.eventTimeText,
    required this.taskDueDate,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToday,
    required this.onSelectDate,
    required this.onCreateEvent,
    required this.onCreateTask,
    required this.onEditEvent,
    required this.onDeleteEvent,
    required this.onToggleTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onMoveTaskToTomorrow,
    required this.onMarkTaskMissed,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final String monthLabel;
  final String selectedDateLabel;
  final List<calendar.Event> events;
  final List<Map<String, dynamic>> tasks;
  final DateTime? Function(calendar.Event event) eventStart;
  final String Function(calendar.Event event) eventTimeText;
  final DateTime? Function(Map<String, dynamic> task) taskDueDate;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onSelectDate;
  final VoidCallback onCreateEvent;
  final VoidCallback onCreateTask;
  final ValueChanged<calendar.Event> onEditEvent;
  final ValueChanged<calendar.Event> onDeleteEvent;
  final void Function(Map<String, dynamic> task, bool completed) onToggleTask;
  final ValueChanged<Map<String, dynamic>> onEditTask;
  final ValueChanged<Map<String, dynamic>> onDeleteTask;
  final ValueChanged<Map<String, dynamic>> onMoveTaskToTomorrow;
  final ValueChanged<Map<String, dynamic>> onMarkTaskMissed;

  @override
  Widget build(BuildContext context) {
    final selectedEvents =
        events.where((event) {
          final start = eventStart(event);
          return start != null && _sameDay(start, selectedDate);
        }).toList()..sort((a, b) {
          final aStart = eventStart(a);
          final bStart = eventStart(b);
          if (aStart == null || bStart == null) return 0;
          return aStart.compareTo(bStart);
        });
    final selectedTasks = tasks.where((task) {
      final dueDate = taskDueDate(task);
      return dueDate != null && _sameDay(dueDate, selectedDate);
    }).toList()..sort(_compareTasks);
    final unscheduledTasks =
        tasks.where((task) => taskDueDate(task) == null).toList()
          ..sort(_compareTasks);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final calendarView = _CalendarMonthView(
          focusedMonth: focusedMonth,
          selectedDate: selectedDate,
          monthLabel: monthLabel,
          events: events,
          tasks: tasks,
          eventStart: eventStart,
          taskDueDate: taskDueDate,
          onPreviousMonth: onPreviousMonth,
          onNextMonth: onNextMonth,
          onToday: onToday,
          onSelectDate: onSelectDate,
        );
        final agenda = _SelectedDayAgenda(
          selectedDateLabel: selectedDateLabel,
          events: selectedEvents,
          tasks: selectedTasks,
          unscheduledTasks: unscheduledTasks,
          eventTimeText: eventTimeText,
          onCreateEvent: onCreateEvent,
          onCreateTask: onCreateTask,
          onEditEvent: onEditEvent,
          onDeleteEvent: onDeleteEvent,
          onToggleTask: onToggleTask,
          onEditTask: onEditTask,
          onDeleteTask: onDeleteTask,
          onMoveTaskToTomorrow: onMoveTaskToTomorrow,
          onMarkTaskMissed: onMarkTaskMissed,
        );

        if (!wide) {
          return Column(
            children: [calendarView, const SizedBox(height: 16), agenda],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: calendarView),
            const SizedBox(width: 16),
            SizedBox(width: 360, child: agenda),
          ],
        );
      },
    );
  }

  int _compareTasks(Map<String, dynamic> a, Map<String, dynamic> b) {
    final statusComparison = _statusRank(
      a['status'],
    ).compareTo(_statusRank(b['status']));
    if (statusComparison != 0) return statusComparison;
    final priorityComparison = _priorityRank(
      a['priority'],
    ).compareTo(_priorityRank(b['priority']));
    if (priorityComparison != 0) return priorityComparison;
    final aCreated = DateTime.tryParse(a['created_at']?.toString() ?? '');
    final bCreated = DateTime.tryParse(b['created_at']?.toString() ?? '');
    if (aCreated == null || bCreated == null) return 0;
    return aCreated.compareTo(bCreated);
  }

  int _statusRank(Object? status) {
    return switch (status?.toString()) {
      'pending' => 0,
      'missed' => 1,
      'completed' => 2,
      _ => 3,
    };
  }

  int _priorityRank(Object? priority) {
    return switch (priority?.toString()) {
      'high' => 0,
      'medium' => 1,
      'low' => 2,
      _ => 3,
    };
  }
}

class _CalendarMonthView extends StatelessWidget {
  const _CalendarMonthView({
    required this.focusedMonth,
    required this.selectedDate,
    required this.monthLabel,
    required this.events,
    required this.tasks,
    required this.eventStart,
    required this.taskDueDate,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToday,
    required this.onSelectDate,
  });

  static const _weekdayLabels = [
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final String monthLabel;
  final List<calendar.Event> events;
  final List<Map<String, dynamic>> tasks;
  final DateTime? Function(calendar.Event event) eventStart;
  final DateTime? Function(Map<String, dynamic> task) taskDueDate;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final days = _visibleDaysForMonth(focusedMonth);

    return BpCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: onPreviousMonth,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  monthLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              OutlinedButton(onPressed: onToday, child: const Text('Today')),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 7,
            childAspectRatio: 3.4,
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            children: [
              for (final day in _weekdayLabels)
                Center(
                  child: Text(
                    day,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          GridView.builder(
            itemCount: days.length,
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.98,
            ),
            itemBuilder: (context, index) {
              final day = days[index];
              final dayEvents = events.where((event) {
                final start = eventStart(event);
                return start != null && _sameDay(start, day);
              }).toList();
              final dayTasks = tasks.where((task) {
                final dueDate = taskDueDate(task);
                return dueDate != null && _sameDay(dueDate, day);
              }).toList();
              return _CalendarDayCell(
                date: day,
                inFocusedMonth: day.month == focusedMonth.month,
                selected: _sameDay(day, selectedDate),
                today: _sameDay(day, DateTime.now()),
                events: dayEvents,
                tasks: dayTasks,
                onTap: () => onSelectDate(day),
              );
            },
          ),
        ],
      ),
    );
  }

  List<DateTime> _visibleDaysForMonth(DateTime month) {
    final first = DateTime(month.year, month.month);
    final firstVisible = first.subtract(Duration(days: first.weekday % 7));
    return [
      for (var index = 0; index < 42; index++)
        DateTime(
          firstVisible.year,
          firstVisible.month,
          firstVisible.day + index,
        ),
    ];
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.inFocusedMonth,
    required this.selected,
    required this.today,
    required this.events,
    required this.tasks,
    required this.onTap,
  });

  final DateTime date;
  final bool inFocusedMonth;
  final bool selected;
  final bool today;
  final List<calendar.Event> events;
  final List<Map<String, dynamic>> tasks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleEvents = events.take(2).toList(growable: false);
    final visibleTasks = tasks
        .take((2 - visibleEvents.length).clamp(0, 2))
        .toList(growable: false);
    final hiddenCount =
        events.length +
        tasks.length -
        visibleEvents.length -
        visibleTasks.length;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.78)
                : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : Theme.of(context).dividerColor.withValues(alpha: 0.55),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: today ? colorScheme.primary : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        color: today
                            ? colorScheme.onPrimary
                            : inFocusedMonth
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.58,
                              ),
                        fontWeight: today || selected
                            ? FontWeight.w900
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                for (final event in visibleEvents)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: _EventPill(title: event.summary ?? 'Untitled event'),
                  ),
                for (final task in visibleTasks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: _TaskPill(title: task['title'].toString()),
                  ),
                if (hiddenCount > 0)
                  Text(
                    '+$hiddenCount more',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w800,
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

class _EventPill extends StatelessWidget {
  const _EventPill({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        title.trim().isEmpty ? 'Untitled event' : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TaskPill extends StatelessWidget {
  const _TaskPill({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.tertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        title.trim().isEmpty ? 'Untitled task' : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.tertiary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SelectedDayAgenda extends StatelessWidget {
  const _SelectedDayAgenda({
    required this.selectedDateLabel,
    required this.events,
    required this.tasks,
    required this.unscheduledTasks,
    required this.eventTimeText,
    required this.onCreateEvent,
    required this.onCreateTask,
    required this.onEditEvent,
    required this.onDeleteEvent,
    required this.onToggleTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onMoveTaskToTomorrow,
    required this.onMarkTaskMissed,
  });

  final String selectedDateLabel;
  final List<calendar.Event> events;
  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> unscheduledTasks;
  final String Function(calendar.Event event) eventTimeText;
  final VoidCallback onCreateEvent;
  final VoidCallback onCreateTask;
  final ValueChanged<calendar.Event> onEditEvent;
  final ValueChanged<calendar.Event> onDeleteEvent;
  final void Function(Map<String, dynamic> task, bool completed) onToggleTask;
  final ValueChanged<Map<String, dynamic>> onEditTask;
  final ValueChanged<Map<String, dynamic>> onDeleteTask;
  final ValueChanged<Map<String, dynamic>> onMoveTaskToTomorrow;
  final ValueChanged<Map<String, dynamic>> onMarkTaskMissed;

  @override
  Widget build(BuildContext context) {
    return BpCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  selectedDateLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Add task',
                onPressed: onCreateTask,
                icon: const Icon(Icons.check_circle_outline),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Add event',
                onPressed: onCreateEvent,
                icon: const Icon(Icons.event_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AgendaSectionHeader(
            icon: Icons.event_outlined,
            title: 'Events',
            count: events.length,
          ),
          const SizedBox(height: 8),
          if (events.isEmpty)
            Text(
              'No events for this date.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final event in events) ...[
              _EventCard(
                event: event,
                timeText: eventTimeText(event),
                onEdit: event.id == null ? null : () => onEditEvent(event),
                onDelete: event.id == null ? null : () => onDeleteEvent(event),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 8),
          const Divider(height: 24),
          _AgendaSectionHeader(
            icon: Icons.check_circle_outline,
            title: 'Tasks',
            count: tasks.length,
          ),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            Text(
              'No tasks due on this date.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final task in tasks) ...[
              _TaskCard(
                task: task,
                onToggle: (completed) => onToggleTask(task, completed),
                onEdit: () => onEditTask(task),
                onDelete: () => onDeleteTask(task),
                onMoveToTomorrow: () => onMoveTaskToTomorrow(task),
                onMarkMissed: () => onMarkTaskMissed(task),
              ),
              const SizedBox(height: 10),
            ],
          if (unscheduledTasks.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 24),
            _AgendaSectionHeader(
              icon: Icons.inbox_outlined,
              title: 'Inbox',
              count: unscheduledTasks.length,
            ),
            const SizedBox(height: 8),
            for (final task in unscheduledTasks) ...[
              _TaskCard(
                task: task,
                onToggle: (completed) => onToggleTask(task, completed),
                onEdit: () => onEditTask(task),
                onDelete: () => onDeleteTask(task),
                onMoveToTomorrow: () => onMoveTaskToTomorrow(task),
                onMarkMissed: () => onMarkTaskMissed(task),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _AgendaSectionHeader extends StatelessWidget {
  const _AgendaSectionHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        Text(
          count.toString(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.timeText,
    required this.onEdit,
    required this.onDelete,
  });

  final calendar.Event event;
  final String timeText;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final attendeeCount = event.attendees?.length ?? 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.65),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: const Icon(Icons.event_outlined),
        title: Text(
          event.summary?.trim().isEmpty ?? true
              ? 'Untitled event'
              : event.summary!,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _EventChip(text: timeText),
              if (event.location?.trim().isNotEmpty == true)
                _EventChip(text: event.location!),
              if (attendeeCount > 0)
                _EventChip(text: '$attendeeCount attendees'),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') onEdit?.call();
            if (value == 'delete') onDelete?.call();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'edit',
              enabled: onEdit != null,
              child: const Text('Edit'),
            ),
            PopupMenuItem(
              value: 'delete',
              enabled: onDelete != null,
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveToTomorrow,
    required this.onMarkMissed,
  });

  final Map<String, dynamic> task;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMoveToTomorrow;
  final VoidCallback onMarkMissed;

  @override
  Widget build(BuildContext context) {
    final completed = task['status'] == 'completed';
    final estimatedMinutes = task['estimated_minutes'];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.65),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: Checkbox(
          value: completed,
          onChanged: (value) => onToggle(value ?? false),
        ),
        title: Text(
          task['title']?.toString().trim().isEmpty ?? true
              ? 'Untitled task'
              : task['title'].toString(),
          style: TextStyle(
            decoration: completed ? TextDecoration.lineThrough : null,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _TaskChip(text: '${task['priority']} priority'),
              _TaskChip(text: task['category'].toString()),
              _TaskChip(text: compactDate(task['due_date'])),
              if (estimatedMinutes != null)
                _TaskChip(text: '$estimatedMinutes min'),
              _TaskChip(text: task['status'].toString()),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'delete') onDelete();
            if (value == 'tomorrow') onMoveToTomorrow();
            if (value == 'missed') onMarkMissed();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'missed', child: Text('Mark missed')),
            PopupMenuItem(value: 'tomorrow', child: Text('Move to tomorrow')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class _EventChip extends StatelessWidget {
  const _EventChip({required this.text});

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

class _TaskChip extends StatelessWidget {
  const _TaskChip({required this.text});

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

class _GoogleTasksSyncResult {
  const _GoogleTasksSyncResult({
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
}
