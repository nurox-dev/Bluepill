import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/model_helpers.dart';
import '../services/agent_gateway_service.dart';
import '../ui/bp_card.dart';
import '../ui/expressive_loading_indicator.dart';
import '../ui/responsive.dart';

class CronJobsPage extends StatefulWidget {
  const CronJobsPage({super.key});

  @override
  State<CronJobsPage> createState() => _CronJobsPageState();
}

class _CronJobsPageState extends State<CronJobsPage> {
  final _gateway = AgentGatewayService();
  final _dateTimeFormat = DateFormat('MMM d, h:mm a');
  late Future<_CronJobsData> _future;
  String? _selectedJobId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_CronJobsData> _load() async {
    final jobs = await _gateway.listCronJobs();
    final selectedJob = _selectedJob(jobs);
    final selectedId = selectedJob?['id']?.toString();
    if (_selectedJobId != selectedId) _selectedJobId = selectedId;

    final executions = selectedId == null
        ? <Map<String, dynamic>>[]
        : await _gateway.listCronJobExecutions(selectedId);
    return _CronJobsData(
      jobs: jobs,
      selectedJob: selectedJob,
      executions: executions,
    );
  }

  Map<String, dynamic>? _selectedJob(List<Map<String, dynamic>> jobs) {
    if (jobs.isEmpty) return null;
    if (_selectedJobId != null) {
      for (final job in jobs) {
        if (job['id']?.toString() == _selectedJobId) return job;
      }
    }
    return jobs.first;
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cron Jobs'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _saving ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : () => _openJobDialog(),
              icon: const Icon(Icons.add),
              label: const Text('New'),
            ),
          ),
        ],
      ),
      body: FutureBuilder<_CronJobsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: ExpressiveLoadingIndicator(
                semanticsLabel: 'Loading cron jobs',
              ),
            );
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final data = snapshot.data!;
          if (data.jobs.isEmpty) {
            return const EmptyState(
              icon: Icons.alarm_on_outlined,
              title: 'No cron jobs',
              message: 'Create a backend schedule for a recurring task.',
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 980;
              if (desktop) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _SummaryStrip(jobs: data.jobs),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 380,
                              child: _JobList(
                                jobs: data.jobs,
                                selectedJobId: _selectedJobId,
                                onSelect: _selectJob,
                                onEdit: _openJobDialog,
                                onToggle: _toggleJob,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SingleChildScrollView(
                                child: _JobDetail(
                                  job: data.selectedJob,
                                  executions: data.executions,
                                  formatDateTime: _formatDateTime,
                                  onEdit: _openJobDialog,
                                  onToggle: _toggleJob,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _SummaryStrip(jobs: data.jobs),
                    const SizedBox(height: 16),
                    _JobList(
                      jobs: data.jobs,
                      selectedJobId: _selectedJobId,
                      onSelect: _selectJob,
                      onEdit: _openJobDialog,
                      onToggle: _toggleJob,
                      shrinkWrap: true,
                    ),
                    const SizedBox(height: 16),
                    _JobDetail(
                      job: data.selectedJob,
                      executions: data.executions,
                      formatDateTime: _formatDateTime,
                      onEdit: _openJobDialog,
                      onToggle: _toggleJob,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _selectJob(Map<String, dynamic> job) {
    final id = job['id']?.toString();
    if (id == null || id == _selectedJobId) return;
    setState(() {
      _selectedJobId = id;
      _future = _load();
    });
  }

  Future<void> _toggleJob(Map<String, dynamic> job, bool enabled) async {
    final id = job['id'];
    if (id == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _gateway.updateCronJob(id, enabled: enabled);
      _refresh();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openJobDialog([Map<String, dynamic>? job]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: !_saving,
      builder: (dialogContext) => _CronJobDialog(
        job: job,
        saving: _saving,
        onSave: (draft) async {
          setState(() => _saving = true);
          try {
            if (job == null) {
              final created = await _gateway.createCronJob(
                name: draft.name,
                schedule: draft.schedule,
                task: draft.task,
                payload: draft.payload,
                enabled: draft.enabled,
                timezone: draft.timezone,
                maxRetries: draft.maxRetries,
                timeoutSeconds: draft.timeoutSeconds,
                retryDelaySeconds: draft.retryDelaySeconds,
              );
              _selectedJobId = created['id']?.toString();
            } else {
              await _gateway.updateCronJob(
                job['id'],
                name: draft.name,
                schedule: draft.schedule,
                task: draft.task,
                payload: draft.payload,
                enabled: draft.enabled,
                timezone: draft.timezone,
                maxRetries: draft.maxRetries,
                timeoutSeconds: draft.timeoutSeconds,
                retryDelaySeconds: draft.retryDelaySeconds,
              );
              _selectedJobId = job['id']?.toString();
            }
            if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
          } catch (error) {
            _showError(error);
          } finally {
            if (mounted) setState(() => _saving = false);
          }
        },
      ),
    );

    if (saved == true) _refresh();
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  String _formatDateTime(Object? value) {
    if (value == null) return 'Not set';
    final date = DateTime.tryParse(value.toString());
    if (date == null) return value.toString();
    return _dateTimeFormat.format(date.toLocal());
  }
}

class _CronJobsData {
  const _CronJobsData({
    required this.jobs,
    required this.selectedJob,
    required this.executions,
  });

  final List<Map<String, dynamic>> jobs;
  final Map<String, dynamic>? selectedJob;
  final List<Map<String, dynamic>> executions;
}

class _JobList extends StatelessWidget {
  const _JobList({
    required this.jobs,
    required this.selectedJobId,
    required this.onSelect,
    required this.onEdit,
    required this.onToggle,
    this.shrinkWrap = false,
  });

  final List<Map<String, dynamic>> jobs;
  final String? selectedJobId;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final void Function(Map<String, dynamic>, bool) onToggle;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final job in jobs)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _JobCard(
            job: job,
            selected: job['id']?.toString() == selectedJobId,
            onTap: () => onSelect(job),
            onEdit: () => onEdit(job),
            onToggle: (value) => onToggle(job, value),
          ),
        ),
    ];

    if (shrinkWrap) {
      return Column(children: children);
    }

    return ListView(children: children);
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onToggle,
  });

  final Map<String, dynamic> job;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = job['enabled'] == true;
    final status = job['last_status']?.toString() ?? 'scheduled';
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: selected ? colorScheme.primary : colorScheme.outlineVariant,
        width: selected ? 1.6 : 1,
      ),
    );

    return Material(
      color: selected ? colorScheme.primaryContainer : colorScheme.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      job['name']?.toString() ?? 'Untitled job',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: enabled ? status : 'disabled'),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniChip(
                    icon: Icons.schedule,
                    text: job['schedule']?.toString() ?? '-',
                  ),
                  _MiniChip(
                    icon: Icons.bolt_outlined,
                    text: _taskLabel(job['task']),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  const Spacer(),
                  Switch(value: enabled, onChanged: onToggle),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobDetail extends StatelessWidget {
  const _JobDetail({
    required this.job,
    required this.executions,
    required this.formatDateTime,
    required this.onEdit,
    required this.onToggle,
  });

  final Map<String, dynamic>? job;
  final List<Map<String, dynamic>> executions;
  final String Function(Object?) formatDateTime;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final void Function(Map<String, dynamic>, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    final selected = job;
    if (selected == null) {
      return const BpCard(
        child: EmptyState(
          icon: Icons.schedule_outlined,
          title: 'Select a job',
          message: 'Choose a job to view executions.',
        ),
      );
    }

    final enabled = selected['enabled'] == true;
    final payload = _prettyJson(selected['payload']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected['name']?.toString() ?? 'Untitled job',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _StatusChip(
                              status: enabled
                                  ? selected['last_status']?.toString() ??
                                        'scheduled'
                                  : 'disabled',
                            ),
                            _MiniChip(
                              icon: Icons.schedule,
                              text: selected['schedule']?.toString() ?? '-',
                            ),
                            _MiniChip(
                              icon: Icons.public,
                              text: selected['timezone']?.toString() ?? 'UTC',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit',
                    onPressed: () => onEdit(selected),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: (value) => onToggle(selected, value),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ResponsiveWrap(
                minItemWidth: 180,
                spacing: 10,
                runSpacing: 10,
                children: [
                  _DetailTile(
                    label: 'Task',
                    value: _taskLabel(selected['task']),
                  ),
                  _DetailTile(
                    label: 'Last run',
                    value: formatDateTime(selected['last_run_at']),
                  ),
                  _DetailTile(
                    label: 'Next run',
                    value: formatDateTime(selected['next_run_at']),
                  ),
                  _DetailTile(
                    label: 'Retries',
                    value: '${intValue(selected['max_retries'])}',
                  ),
                  _DetailTile(
                    label: 'Timeout',
                    value: '${intValue(selected['timeout_seconds'], 300)}s',
                  ),
                  _DetailTile(
                    label: 'Delay',
                    value: '${intValue(selected['retry_delay_seconds'], 30)}s',
                  ),
                ],
              ),
              if ((selected['last_error']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                _ErrorBanner(message: selected['last_error'].toString()),
              ],
              const SizedBox(height: 16),
              _CodeBlock(title: 'Payload', text: payload),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionTitle(
          title: 'Execution Logs',
          subtitle: '${executions.length} recent runs',
        ),
        const SizedBox(height: 12),
        if (executions.isEmpty)
          const BpCard(
            child: EmptyState(
              icon: Icons.history,
              title: 'No executions',
              message: 'This job has not run yet.',
            ),
          )
        else
          for (final execution in executions) ...[
            _ExecutionCard(
              execution: execution,
              formatDateTime: formatDateTime,
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.jobs});

  final List<Map<String, dynamic>> jobs;

  @override
  Widget build(BuildContext context) {
    final enabled = jobs.where((job) => job['enabled'] == true).length;
    final disabled = jobs.length - enabled;
    final failed = jobs
        .where(
          (job) =>
              job['last_status'] == 'failed' ||
              job['last_status'] == 'timed_out',
        )
        .length;
    final nextJobs =
        jobs
            .where((job) => job['next_run_at'] != null)
            .map((job) => DateTime.tryParse(job['next_run_at'].toString()))
            .whereType<DateTime>()
            .toList()
          ..sort();
    final next = nextJobs.isEmpty
        ? 'None'
        : DateFormat('MMM d, h:mm a').format(nextJobs.first.toLocal());

    return ResponsiveWrap(
      minItemWidth: 170,
      spacing: 10,
      runSpacing: 10,
      children: [
        _MetricTile(label: 'Total', value: '${jobs.length}'),
        _MetricTile(label: 'Enabled', value: '$enabled'),
        _MetricTile(label: 'Disabled', value: '$disabled'),
        _MetricTile(label: 'Needs attention', value: '$failed'),
        _MetricTile(label: 'Next run', value: next),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colorScheme.surfaceContainerLow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExecutionCard extends StatelessWidget {
  const _ExecutionCard({required this.execution, required this.formatDateTime});

  final Map<String, dynamic> execution;
  final String Function(Object?) formatDateTime;

  @override
  Widget build(BuildContext context) {
    final logs = _asList(execution['logs']);
    final error = execution['error']?.toString();
    return BpCard(
      padding: const EdgeInsets.all(14),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 10),
        leading: _StatusDot(status: execution['status']?.toString()),
        title: Row(
          children: [
            Expanded(
              child: Text(
                formatDateTime(execution['scheduled_for']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 8),
            _StatusChip(status: execution['status']?.toString() ?? 'running'),
          ],
        ),
        subtitle: Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            Text('Attempts ${intValue(execution['attempts'])}'),
            if (execution['duration_ms'] != null)
              Text('${intValue(execution['duration_ms'])}ms'),
            if (execution['agent_run_id'] != null)
              Text('Agent ${_shortId(execution['agent_run_id'])}'),
          ],
        ),
        children: [
          if (error != null && error.isNotEmpty) _ErrorBanner(message: error),
          if (logs.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CodeBlock(title: 'Logs', text: _prettyJson(logs)),
          ],
          if ((execution['result'] as Object?) != null) ...[
            const SizedBox(height: 10),
            _CodeBlock(title: 'Result', text: _prettyJson(execution['result'])),
          ],
        ],
      ),
    );
  }
}

class _CronJobDialog extends StatefulWidget {
  const _CronJobDialog({
    required this.job,
    required this.saving,
    required this.onSave,
  });

  final Map<String, dynamic>? job;
  final bool saving;
  final Future<void> Function(_CronJobDraft) onSave;

  @override
  State<_CronJobDialog> createState() => _CronJobDialogState();
}

class _CronJobDialogState extends State<_CronJobDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _schedule;
  late final TextEditingController _timezone;
  late final TextEditingController _payload;
  late final TextEditingController _maxRetries;
  late final TextEditingController _timeoutSeconds;
  late final TextEditingController _retryDelaySeconds;
  late String _task;
  late bool _enabled;
  late bool _saving;
  late _ScheduleInputMode _scheduleMode;
  late TimeOfDay _dailyTime;

  @override
  void initState() {
    super.initState();
    final job = widget.job;
    final initialSchedule = job?['schedule']?.toString() ?? '0 9 * * *';
    final initialDailyTime = _dailyTimeFromSchedule(initialSchedule);
    _name = TextEditingController(text: job?['name']?.toString() ?? '');
    _schedule = TextEditingController(text: initialSchedule);
    _timezone = TextEditingController(
      text: job?['timezone']?.toString() ?? 'UTC',
    );
    _payload = TextEditingController(
      text: _prettyJson(
        job?['payload'] ??
            {'message': 'Review my day and suggest the next best action.'},
      ),
    );
    _maxRetries = TextEditingController(
      text: '${intValue(job?['max_retries'])}',
    );
    _timeoutSeconds = TextEditingController(
      text: '${intValue(job?['timeout_seconds'], 300)}',
    );
    _retryDelaySeconds = TextEditingController(
      text: '${intValue(job?['retry_delay_seconds'], 30)}',
    );
    _task = job?['task']?.toString() ?? 'agent_prompt';
    _enabled = job?['enabled'] != false;
    _saving = widget.saving;
    _dailyTime = initialDailyTime ?? const TimeOfDay(hour: 9, minute: 0);
    _scheduleMode = initialDailyTime == null && job != null
        ? _ScheduleInputMode.cron
        : _ScheduleInputMode.daily;
  }

  @override
  void dispose() {
    _name.dispose();
    _schedule.dispose();
    _timezone.dispose();
    _payload.dispose();
    _maxRetries.dispose();
    _timeoutSeconds.dispose();
    _retryDelaySeconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.job == null ? 'New Cron Job' : 'Edit Cron Job'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<_ScheduleInputMode>(
                    segments: const [
                      ButtonSegment(
                        value: _ScheduleInputMode.daily,
                        icon: Icon(Icons.access_time),
                        label: Text('Daily time'),
                      ),
                      ButtonSegment(
                        value: _ScheduleInputMode.cron,
                        icon: Icon(Icons.code),
                        label: Text('Cron'),
                      ),
                    ],
                    selected: {_scheduleMode},
                    onSelectionChanged: _saving
                        ? null
                        : (selection) {
                            final mode = selection.first;
                            setState(() {
                              _scheduleMode = mode;
                              if (mode == _ScheduleInputMode.daily) {
                                _schedule.text = _dailyCron(_dailyTime);
                              }
                            });
                          },
                  ),
                ),
                const SizedBox(height: 12),
                _ResponsiveFieldRow(
                  flexes: const [2, 1],
                  children: [
                    if (_scheduleMode == _ScheduleInputMode.daily)
                      _TimePickerField(
                        time: _dailyTime,
                        cronText: _dailyCron(_dailyTime),
                        enabled: !_saving,
                        onTap: _pickDailyTime,
                      )
                    else
                      TextFormField(
                        controller: _schedule,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Cron expression',
                          prefixIcon: Icon(Icons.schedule),
                        ),
                        validator: _required,
                      ),
                    TextFormField(
                      controller: _timezone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Timezone',
                        prefixIcon: Icon(Icons.public),
                      ),
                      validator: _required,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _task,
                  decoration: const InputDecoration(
                    labelText: 'Task',
                    prefixIcon: Icon(Icons.bolt_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'agent_prompt',
                      child: Text('Agent prompt'),
                    ),
                    DropdownMenuItem(value: 'noop', child: Text('No-op')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _task = value ?? _task),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _payload,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Payload JSON',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.data_object),
                  ),
                  validator: _jsonObject,
                ),
                const SizedBox(height: 12),
                _ResponsiveFieldRow(
                  children: [
                    TextFormField(
                      controller: _maxRetries,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Retries',
                        prefixIcon: Icon(Icons.replay),
                      ),
                      validator: (value) => _integerRange(value, 0, 10),
                    ),
                    TextFormField(
                      controller: _timeoutSeconds,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Timeout',
                        prefixIcon: Icon(Icons.timer_outlined),
                      ),
                      validator: (value) => _integerRange(value, 1, 3600),
                    ),
                    TextFormField(
                      controller: _retryDelaySeconds,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Delay',
                        prefixIcon: Icon(Icons.more_time),
                      ),
                      validator: (value) => _integerRange(value, 0, 3600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _enabled,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _enabled = value),
                  title: const Text('Enabled'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const ExpressiveLoadingIndicator(size: 18, strokeWidth: 2)
              : const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final payload = jsonDecode(_payload.text) as Map<String, dynamic>;
    final schedule = _scheduleMode == _ScheduleInputMode.daily
        ? _dailyCron(_dailyTime)
        : _schedule.text.trim();
    setState(() => _saving = true);
    try {
      await widget.onSave(
        _CronJobDraft(
          name: _name.text.trim(),
          schedule: schedule,
          task: _task,
          payload: payload,
          enabled: _enabled,
          timezone: _timezone.text.trim(),
          maxRetries: int.parse(_maxRetries.text.trim()),
          timeoutSeconds: int.parse(_timeoutSeconds.text.trim()),
          retryDelaySeconds: int.parse(_retryDelaySeconds.text.trim()),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }

  String? _jsonObject(String? value) {
    try {
      final decoded = jsonDecode(value ?? '');
      return decoded is Map<String, dynamic> ? null : 'Use a JSON object';
    } catch (_) {
      return 'Invalid JSON';
    }
  }

  String? _integerRange(String? value, int min, int max) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'Number';
    if (parsed < min || parsed > max) return '$min-$max';
    return null;
  }

  Future<void> _pickDailyTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dailyTime,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _dailyTime = picked;
      _schedule.text = _dailyCron(picked);
    });
  }
}

enum _ScheduleInputMode { daily, cron }

class _TimePickerField extends StatelessWidget {
  const _TimePickerField({
    required this.time,
    required this.cronText,
    required this.enabled,
    required this.onTap,
  });

  final TimeOfDay time;
  final String cronText;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          enabled: enabled,
          labelText: 'Run time',
          prefixIcon: const Icon(Icons.access_time),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                time.format(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              cronText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponsiveFieldRow extends StatelessWidget {
  const _ResponsiveFieldRow({required this.children, this.flexes});

  final List<Widget> children;
  final List<int>? flexes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(height: 12),
                children[index],
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(width: 12),
              Expanded(
                flex: flexes == null ? 1 : flexes![index],
                child: children[index],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CronJobDraft {
  const _CronJobDraft({
    required this.name,
    required this.schedule,
    required this.task,
    required this.payload,
    required this.enabled,
    required this.timezone,
    required this.maxRetries,
    required this.timeoutSeconds,
    required this.retryDelaySeconds,
  });

  final String name;
  final String schedule;
  final String task;
  final Map<String, dynamic> payload;
  final bool enabled;
  final String timezone;
  final int maxRetries;
  final int timeoutSeconds;
  final int retryDelaySeconds;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors(context, status);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.$1,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          _statusLabel(status),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.$2,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors(context, status ?? 'running');
    return CircleAvatar(
      radius: 14,
      backgroundColor: colors.$1,
      child: Icon(Icons.circle, size: 9, color: colors.$2),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colorScheme.errorContainer,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: ShapeDecoration(
            color: colorScheme.surfaceContainerHighest,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: BpCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 36),
              const SizedBox(height: 12),
              Text(
                'Could not load cron jobs',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

(Color, Color) _statusColors(BuildContext context, String status) {
  final colorScheme = Theme.of(context).colorScheme;
  switch (status) {
    case 'succeeded':
    case 'completed':
      return (Colors.green.shade100, Colors.green.shade900);
    case 'failed':
    case 'timed_out':
      return (colorScheme.errorContainer, colorScheme.onErrorContainer);
    case 'disabled':
    case 'cancelled':
      return (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
      );
    case 'running':
      return (Colors.blue.shade100, Colors.blue.shade900);
    default:
      return (colorScheme.secondaryContainer, colorScheme.onSecondaryContainer);
  }
}

String _statusLabel(String status) {
  return status
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

String _taskLabel(Object? task) {
  switch (task?.toString()) {
    case 'agent_prompt':
      return 'Agent prompt';
    case 'noop':
      return 'No-op';
    default:
      return task?.toString() ?? 'Unknown';
  }
}

String _shortId(Object? value) {
  final text = value?.toString() ?? '';
  return text.length <= 8 ? text : text.substring(0, 8);
}

TimeOfDay? _dailyTimeFromSchedule(String schedule) {
  final parts = schedule.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return null;
  if (parts[2] != '*' || parts[3] != '*' || parts[4] != '*') return null;
  final minute = int.tryParse(parts[0]);
  final hour = int.tryParse(parts[1]);
  if (minute == null || hour == null) return null;
  if (minute < 0 || minute > 59 || hour < 0 || hour > 23) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

String _dailyCron(TimeOfDay time) => '${time.minute} ${time.hour} * * *';

String _prettyJson(Object? value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value ?? {});
  } catch (_) {
    return value?.toString() ?? '{}';
  }
}

List<dynamic> _asList(Object? value) {
  return value is List ? value : const [];
}
