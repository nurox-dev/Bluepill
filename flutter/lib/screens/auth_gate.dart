import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/model_helpers.dart';
import '../services/google_account_connection_service.dart';
import '../services/supabase_service.dart';
import '../ui/bp_card.dart';
import '../ui/expressive_loading_indicator.dart';
import '../ui/project_logo.dart';
import 'auth_page.dart';
import 'main_shell.dart';
import 'onboarding_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const _profileLoadTimeout = Duration(seconds: 12);

  int _profileReload = 0;
  Future<Map<String, dynamic>?>? _profileFuture;
  String? _profileUserId;
  String? _recordedGoogleConnectionKey;
  String? _googleRenewalAttemptKey;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.supabaseConfigured) {
      return const SetupRequiredPage();
    }

    return StreamBuilder<AuthState>(
      stream: SupabaseService.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final user = SupabaseService.currentUser;
        if (user == null) return const AuthPage();
        _syncGoogleConnection(user);

        return FutureBuilder<Map<String, dynamic>?>(
          key: ValueKey(_profileReload),
          future: _profileFutureFor(user.id),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: ExpressiveLoadingIndicator()),
              );
            }
            if (profileSnapshot.hasError) {
              return _ProfileLoadError(
                error: profileSnapshot.error!,
                onRetry: () => _reloadProfile(user.id),
                onSignOut: _signOut,
              );
            }
            final profile = profileSnapshot.data;
            if (_needsOnboarding(profile)) {
              return OnboardingPage(
                initialProfile: profile,
                onCompleted: () => _reloadProfile(user.id),
              );
            }
            return const MainShell();
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _profileFutureFor(String userId) {
    if (_profileUserId != userId || _profileFuture == null) {
      _profileUserId = userId;
      _profileFuture = _loadProfile(userId).timeout(_profileLoadTimeout);
    }
    return _profileFuture!;
  }

  void _reloadProfile(String userId) {
    setState(() {
      _profileReload++;
      _profileUserId = userId;
      _profileFuture = _loadProfile(userId).timeout(_profileLoadTimeout);
    });
  }

  Future<void> _signOut() async {
    await SupabaseService.client.auth.signOut();
    if (!mounted) return;
    setState(() {
      _profileUserId = null;
      _profileFuture = null;
    });
  }

  Future<Map<String, dynamic>?> _loadProfile(String userId) async {
    final response = await SupabaseService.client
        .from('users_profile')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return maybeRow(response);
  }

  void _syncGoogleConnection(User user) {
    final session = SupabaseService.client.auth.currentSession;
    final key = '${user.id}:${session?.providerToken ?? ''}';
    final service = GoogleAccountConnectionService();
    if (_recordedGoogleConnectionKey != key) {
      _recordedGoogleConnectionKey = key;
      unawaited(service.recordCurrentSessionIfPossible(source: 'auth_session'));
    }

    final renewalKey = '${user.id}:${session?.accessToken ?? ''}';
    if (_googleRenewalAttemptKey == renewalKey) return;
    _googleRenewalAttemptKey = renewalKey;
    unawaited(service.autoRenewConnectedSessionIfNeeded());
  }

  bool _needsOnboarding(Map<String, dynamic>? profile) {
    if (profile == null) return true;
    final newFieldsMissing = (profile['identity_stage']?.toString() ?? '').isEmpty;
    final requiredText = [
      profile['name'],
      profile['location_city'],
      profile['dob'],
      profile['dream_goal'],
    ];
    if (newFieldsMissing) return true;
    if (requiredText.any(
      (value) => value == null || value.toString().trim().isEmpty,
    )) {
      return true;
    }
    return _stringList(profile['skills']).isEmpty ||
        _stringList(profile['interests']).isEmpty;
  }
}

class _ProfileLoadError extends StatelessWidget {
  const _ProfileLoadError({
    required this.error,
    required this.onRetry,
    required this.onSignOut,
  });

  final Object error;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final detail = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: BpCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    color: colorScheme.error,
                    size: 36,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Could not load your profile',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    detail.isEmpty
                        ? 'The profile request did not finish.'
                        : detail,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onSignOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

class SetupRequiredPage extends StatelessWidget {
  const SetupRequiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: BpCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ProjectLogo(size: 72),
                  const SizedBox(height: 18),
                  Text(
                    'Project BluePill needs Supabase credentials',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Edit flutter/.env with SUPABASE_URL and SUPABASE_ANON_KEY, run the SQL in supabase/schema.sql, then restart the app.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.38,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: const SelectableText(
                      'cd flutter\ncp .env.example .env\nflutter pub get\nflutter run -d chrome',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
