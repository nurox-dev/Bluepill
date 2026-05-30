import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../data/profile_options.dart';
import '../models/model_helpers.dart';
import '../services/google_account_connection_service.dart';
import '../services/supabase_service.dart';
import '../theme/theme_controller.dart';
import '../ui/bp_card.dart';
import '../ui/expressive_loading_indicator.dart';
import '../ui/profile_fields.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _name = TextEditingController();
  final _locationCity = TextEditingController();
  final _dreamGoal = TextEditingController();
  final _role = TextEditingController();
  final _yearlyGoal = TextEditingController();
  final _struggle = TextEditingController();
  final _futureVision = TextEditingController();
  final _successDefinition = TextEditingController();
  List<String> _goalCategories = [];
  List<String> _barriers = [];
  List<String> _strengths = [];
  List<String> _skillsToLearn = [];
  final _googleConnection = GoogleAccountConnectionService();
  DateTime? _dob;
  String _educationStatus = 'student';
  List<String> _skills = [];
  List<String> _interests = [];
  String _motivationStyle = 'friendly';
  late Future<Map<String, dynamic>?> _future;
  late Future<GoogleAccountConnectionState> _googleFuture;
  bool _saving = false;
  bool _googleBusy = false;
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _googleFuture = _googleConnection.load();
  }

  @override
  void dispose() {
    _name.dispose();
    _locationCity.dispose();
    _dreamGoal.dispose();
    _role.dispose();
    _yearlyGoal.dispose();
    _struggle.dispose();
    _futureVision.dispose();
    _successDefinition.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _load() async {
    final data = await SupabaseService.client
        .from('users_profile')
        .select()
        .eq('user_id', SupabaseService.currentUserId)
        .maybeSingle();
    return maybeRow(data);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.tune_outlined), child: _TabLabel('App')),
              Tab(
                icon: Icon(Icons.account_circle_outlined),
                child: _TabLabel('Account'),
              ),
              Tab(
                icon: Icon(Icons.person_pin_outlined),
                child: _TabLabel('Personalization'),
              ),
            ],
          ),
        ),
        body: FutureBuilder<Map<String, dynamic>?>(
          future: _future,
          builder: (context, snapshot) {
            final profileLoading =
                snapshot.connectionState == ConnectionState.waiting;
            final profileError = snapshot.error;
            if (!profileLoading && profileError == null) {
              _hydrate(snapshot.data);
            }

            return TabBarView(
              children: [
                _buildAppSettings(context),
                _buildAccountSettings(context),
                if (profileLoading)
                  const Center(child: ExpressiveLoadingIndicator())
                else if (profileError != null)
                  _settingsList([_ErrorCard(message: profileError.toString())])
                else
                  _buildPersonalizationSettings(context),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppSettings(BuildContext context) {
    return _settingsList([
      BpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              icon: Icons.palette_outlined,
              title: 'App Settings',
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<BluePillThemeChoice>(
              valueListenable: ThemeController.instance,
              builder: (context, selectedTheme, _) {
                return SegmentedButton<BluePillThemeChoice>(
                  segments: const [
                    ButtonSegment(
                      value: BluePillThemeChoice.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Dark'),
                    ),
                    ButtonSegment(
                      value: BluePillThemeChoice.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Light'),
                    ),
                  ],
                  selected: {selectedTheme},
                  onSelectionChanged: (selection) {
                    ThemeController.instance.setTheme(selection.single);
                  },
                );
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      BpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              icon: Icons.hub_outlined,
              title: 'Services',
            ),
            const SizedBox(height: 14),
            _StatusRow(
              label: 'Supabase',
              enabled: AppConfig.supabaseConfigured,
            ),
            _StatusRow(
              label: 'Agent backend',
              enabled: AppConfig.fastApiConfigured,
            ),
            _StatusRow(
              label: 'Google APIs',
              enabled: AppConfig.googleApisConfigured,
            ),
            const SizedBox(height: 8),
            _AccountRow(
              label: 'FastAPI',
              value: AppConfig.fastApiConfigured
                  ? AppConfig.fastApiBaseUrl
                  : 'Not configured',
              mono: AppConfig.fastApiConfigured,
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildAccountSettings(BuildContext context) {
    return _settingsList([
      BpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              icon: Icons.account_circle_outlined,
              title: 'Account Settings',
            ),
            const SizedBox(height: 14),
            _AccountRow(
              label: 'Email',
              value: SupabaseService.currentUser?.email ?? 'Unknown',
            ),
            _AccountRow(
              label: 'User ID',
              value: SupabaseService.currentUserId,
              mono: true,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      FutureBuilder<GoogleAccountConnectionState>(
        future: _googleFuture,
        builder: (context, snapshot) {
          return _GoogleAccountCard(
            loading: snapshot.connectionState == ConnectionState.waiting,
            busy: _googleBusy,
            error: snapshot.error,
            state: snapshot.data,
            onConnect: _connectGoogle,
            onDisconnect: snapshot.data?.email == null
                ? null
                : () => _disconnectGoogle(snapshot.data!.email),
            onRefresh: _refreshGoogleConnection,
          );
        },
      ),
      const SizedBox(height: 16),
      BpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(context, icon: Icons.logout, title: 'Session'),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => SupabaseService.client.auth.signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildPersonalizationSettings(BuildContext context) {
    return _settingsList([
      BpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              icon: Icons.badge_outlined,
              title: 'Profile',
            ),
            const SizedBox(height: 14),
            _field(_name, 'Name'),
            CityAutocompleteField(controller: _locationCity),
            const SizedBox(height: 12),
            DatePickerField(
              label: 'Date of birth',
              value: _dob,
              onChanged: (value) => setState(() => _dob = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _educationStatus,
              decoration: const InputDecoration(
                labelText: 'Education',
                prefixIcon: Icon(Icons.school_outlined),
              ),
              items: [
                for (final status in educationStatuses)
                  DropdownMenuItem(
                    value: status,
                    child: Text(educationLabel(status)),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _educationStatus = value ?? _educationStatus),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      BpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(context, icon: Icons.flag_outlined, title: 'Goals'),
            const SizedBox(height: 14),
            _field(_dreamGoal, 'Main goal', lines: 3),
            _field(_role, 'Current role'),
            _field(_yearlyGoal, 'Main goal this year'),
            _field(_struggle, 'Main struggle', lines: 2),
            DropdownButtonFormField<String>(
              initialValue: _motivationStyle,
              decoration: const InputDecoration(
                labelText: 'Motivation style',
                prefixIcon: Icon(Icons.psychology_alt_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'soft', child: Text('Soft')),
                DropdownMenuItem(value: 'strict', child: Text('Strict')),
                DropdownMenuItem(value: 'friendly', child: Text('Friendly')),
                DropdownMenuItem(
                  value: 'business mentor',
                  child: Text('Business mentor'),
                ),
                DropdownMenuItem(
                  value: 'military discipline',
                  child: Text('Military discipline'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _motivationStyle = value ?? _motivationStyle),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      BpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              icon: Icons.auto_awesome_outlined,
              title: 'Personalization',
            ),
            const SizedBox(height: 14),
            MultiSelectChipsField(
              label: 'Skills',
              icon: Icons.construction_outlined,
              options: skillOptions,
              selectedValues: _skills,
              onChanged: (values) => setState(() => _skills = values),
            ),
            const SizedBox(height: 16),
            MultiSelectChipsField(
              label: 'Interests',
              icon: Icons.interests_outlined,
              options: interestOptions,
              selectedValues: _interests,
              onChanged: (values) => setState(() => _interests = values),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: ExpressiveLoadingIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Save settings'),
        ),
      ),
    ]);
  }

  Widget _settingsList(List<Widget> children) {
    return ListView(padding: const EdgeInsets.all(20), children: children);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        minLines: lines,
        maxLines: lines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  void _hydrate(Map<String, dynamic>? profile) {
    if (_hydrated || profile == null) return;
    _name.text = profile['name']?.toString() ?? '';
    _locationCity.text = profile['location_city']?.toString() ?? '';
    _dreamGoal.text = profile['dream_goal']?.toString() ?? '';
    _dob = DateTime.tryParse(profile['dob']?.toString() ?? '');
    final education = profile['education_status']?.toString();
    if (education != null && educationStatuses.contains(education)) {
      _educationStatus = education;
    }
    _skills = _stringList(profile['skills']);
    _interests = _stringList(profile['interests']);
    _role.text = profile['current_role']?.toString() ?? '';
    _yearlyGoal.text = profile['yearly_goal']?.toString() ?? '';
    _struggle.text = profile['main_struggle']?.toString() ?? '';
    _motivationStyle = profile['motivation_style']?.toString() ?? 'friendly';
    _futureVision.text = profile['future_vision']?.toString() ?? '';
    _successDefinition.text = profile['success_definition']?.toString() ?? '';
    _goalCategories = _stringList(profile['goal_categories']);
    _barriers = _stringList(profile['barriers']);
    _strengths = _stringList(profile['strengths']);
    _skillsToLearn = _stringList(profile['skills_to_learn']);
    _hydrated = true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final dreamGoal = _dreamGoal.text.trim();
      await SupabaseService.client
          .from('users_profile')
          .update({
            'name': _name.text.trim(),
            'location_city': _locationCity.text.trim(),
            'dob': _dob == null ? null : dateKey(_dob!),
            'education_status': _educationStatus,
            'dream_goal': dreamGoal,
            'skills': _skills,
            'interests': _interests,
            'current_role': _role.text.trim(),
            'yearly_goal': _yearlyGoal.text.trim(),
            'main_struggle': _struggle.text.trim(),
            'motivation_style': _motivationStyle,
            'future_vision': _futureVision.text.trim(),
            'success_definition': _successDefinition.text.trim(),
            'goal_categories': _goalCategories,
            'barriers': _barriers,
            'strengths': _strengths,
            'skills_to_learn': _skillsToLearn,
          })
          .eq('user_id', SupabaseService.currentUserId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _connectGoogle() async {
    setState(() => _googleBusy = true);
    try {
      await _googleConnection.connect();
      if (!mounted) return;
      setState(() => _googleFuture = _googleConnection.load());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Google connected.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _disconnectGoogle(String? email) async {
    setState(() => _googleBusy = true);
    try {
      await _googleConnection.disconnect(email: email);
      if (!mounted) return;
      setState(() => _googleFuture = _googleConnection.load());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Google disconnected.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  void _refreshGoogleConnection() {
    setState(() => _googleFuture = _googleConnection.load());
  }
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontFamily: mono ? 'monospace' : null,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1)),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle : Icons.error_outline,
            color: enabled ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Text('$label: ${enabled ? 'configured' : 'not configured'}'),
        ],
      ),
    );
  }
}

class _GoogleAccountCard extends StatelessWidget {
  const _GoogleAccountCard({
    required this.loading,
    required this.busy,
    required this.error,
    required this.state,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRefresh,
  });

  final bool loading;
  final bool busy;
  final Object? error;
  final GoogleAccountConnectionState? state;
  final VoidCallback onConnect;
  final VoidCallback? onDisconnect;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final connected = state?.connected ?? false;
    final email = state?.email;
    return BpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_tree_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Google Account',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: busy ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!AppConfig.googleApisConfigured)
            const Text('Add GOOGLE_OAUTH_CLIENT_ID to enable Google sync.')
          else if (loading)
            const Center(child: ExpressiveLoadingIndicator())
          else if (error != null)
            Text(
              error.toString(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            )
          else ...[
            _AccountRow(
              label: 'Status',
              value: state?.statusLabel ?? 'Unknown',
            ),
            _AccountRow(label: 'Google', value: email ?? 'Not connected'),
            _StatusRow(label: 'Tasks sync', enabled: connected),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onConnect,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: ExpressiveLoadingIndicator(strokeWidth: 2),
                        )
                      : Icon(connected ? Icons.sync_outlined : Icons.link),
                  label: Text(connected ? 'Refresh access' : 'Connect Google'),
                ),
                if (connected)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onDisconnect,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect'),
                  ),
              ],
            ),
          ],
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
