import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/model_helpers.dart';
import 'google_api_auth_service.dart';
import 'supabase_service.dart';

class GoogleAccountConnectionService {
  GoogleAccountConnectionService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  static const apiScopes = GoogleApiAuthService.googleApiScopes;
  static const _autoRenewCooldown = Duration(minutes: 10);
  static const _autoRenewKeyPrefix = 'google_auto_renew_attempt';

  Future<GoogleAccountConnectionState> load() async {
    await recordCurrentSessionIfPossible(source: 'settings_load');
    final account = await connectedAccount();
    final user = SupabaseService.currentUser;
    final session = SupabaseService.client.auth.currentSession;
    return GoogleAccountConnectionState(
      account: account,
      userHasGoogleIdentity: hasGoogleIdentity(user),
      sessionHasProviderToken: _hasProviderToken(session),
      sessionGoogleEmail: googleIdentityEmail(user) ?? user?.email,
    );
  }

  Future<Map<String, dynamic>?> connectedAccount() async {
    final user = SupabaseService.currentUser;
    if (user == null) return null;

    final data = await _client
        .from('connected_accounts')
        .select('account_email, scopes, status, metadata, updated_at')
        .eq('user_id', user.id)
        .eq('provider', 'google')
        .eq('status', 'connected')
        .contains('scopes', [GoogleApiAuthService.tasksScope])
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return maybeRow(data);
  }

  Future<void> connect() async {
    if (!AppConfig.googleApisConfigured) {
      throw StateError('Missing GOOGLE_OAUTH_CLIENT_ID for Google APIs.');
    }

    if (kIsWeb) {
      await _connectWithSupabaseGoogleOAuth();
      return;
    }

    await _connectWithGoogleSignIn();
  }

  Future<bool> autoRenewConnectedSessionIfNeeded() async {
    if (!kIsWeb || !AppConfig.googleApisConfigured) return false;
    final user = SupabaseService.currentUser;
    if (user == null) return false;
    if (_hasProviderToken(SupabaseService.client.auth.currentSession)) {
      return false;
    }

    final account = await connectedAccount();
    if (account == null) return false;
    if (!hasGoogleIdentity(user)) return false;

    final prefs = await SharedPreferences.getInstance();
    final key = '$_autoRenewKeyPrefix:${user.id}';
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastAttempt = prefs.getInt(key);
    if (lastAttempt != null &&
        now - lastAttempt < _autoRenewCooldown.inMilliseconds) {
      return false;
    }

    await prefs.setInt(key, now);
    await renewLiveAccess();
    return true;
  }

  Future<void> renewLiveAccess() async {
    if (!AppConfig.googleApisConfigured) {
      throw StateError('Missing GOOGLE_OAUTH_CLIENT_ID for Google APIs.');
    }

    if (kIsWeb) {
      await _connectWithSupabaseGoogleOAuth(requireLinkedIdentity: true);
      return;
    }

    await _connectWithGoogleSignIn();
  }

  Future<void> recordCurrentSessionIfPossible({
    String source = 'session',
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null || !hasGoogleIdentity(user)) return;

    final session = SupabaseService.client.auth.currentSession;
    final hasProviderToken = _hasProviderToken(session);
    if (!hasProviderToken) return;

    final email = googleIdentityEmail(user) ?? user.email;
    if (email == null || email.trim().isEmpty) return;

    final latest = await _latestGoogleAccount(email: email);
    if (_isExplicitlyRevoked(latest)) return;

    await saveConnectedAccount(
      email: email,
      source: source,
      hasProviderToken: hasProviderToken,
    );
    await _clearAutoRenewAttempt(user.id);
  }

  Future<void> saveConnectedAccount({
    required String email,
    required String source,
    required bool hasProviderToken,
  }) async {
    final userId = SupabaseService.currentUserId;
    final now = DateTime.now().toUtc().toIso8601String();
    final previous = await _latestGoogleAccount(email: email);
    final previousMetadata = previous?['metadata'];
    await _client.from('connected_accounts').upsert({
      'user_id': userId,
      'provider': 'google',
      'account_label': 'Google Account',
      'account_email': email,
      'scopes': apiScopes,
      'status': 'connected',
      'metadata': {
        if (previousMetadata is Map) ...previousMetadata,
        'source': source,
        'tasks_authorized': true,
        'calendar_authorized': true,
        'provider_token_available': hasProviderToken,
        'connected_at': now,
        'synced_at': now,
      },
      'updated_at': now,
    }, onConflict: 'user_id,provider,account_email');
  }

  Future<void> disconnect({String? email}) async {
    var query = _client
        .from('connected_accounts')
        .update({
          'status': 'revoked',
          'metadata': {
            'tasks_authorized': false,
            'calendar_authorized': false,
            'pending_reconnect': false,
            'revoked_at': DateTime.now().toUtc().toIso8601String(),
          },
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', SupabaseService.currentUserId)
        .eq('provider', 'google');

    if (email != null && email.trim().isNotEmpty) {
      query = query.eq('account_email', email);
    }

    await query;
  }

  Future<void> _connectWithSupabaseGoogleOAuth({
    bool requireLinkedIdentity = false,
  }) async {
    final auth = SupabaseService.client.auth;
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before connecting Google.');
    }

    final redirectTo = AppConfig.authRedirectUrl(Uri.base);
    if (hasGoogleIdentity(user)) {
      await _markReconnectPending(googleIdentityEmail(user) ?? user.email);
      await auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        scopes: GoogleApiAuthService.supabaseGoogleApiScopes,
        queryParams: GoogleApiAuthService.googleOAuthQueryParams,
      );
    } else if (requireLinkedIdentity) {
      throw StateError('Connect Google from Account Settings first.');
    } else {
      await auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: redirectTo,
        scopes: GoogleApiAuthService.supabaseGoogleApiScopes,
        queryParams: GoogleApiAuthService.googleOAuthQueryParams,
      );
    }
  }

  Future<Map<String, dynamic>?> _latestGoogleAccount({
    required String email,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null || email.trim().isEmpty) return null;
    final data = await _client
        .from('connected_accounts')
        .select('account_email, scopes, status, metadata, updated_at')
        .eq('user_id', user.id)
        .eq('provider', 'google')
        .eq('account_email', email)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return maybeRow(data);
  }

  Future<void> _markReconnectPending(String? email) async {
    final trimmed = email?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    final latest = await _latestGoogleAccount(email: trimmed);
    if (latest?['status'] != 'revoked') return;

    await _client
        .from('connected_accounts')
        .update({
          'metadata': {
            'pending_reconnect': true,
            'reconnect_started_at': DateTime.now().toUtc().toIso8601String(),
          },
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', SupabaseService.currentUserId)
        .eq('provider', 'google')
        .eq('account_email', trimmed);
  }

  bool _isExplicitlyRevoked(Map<String, dynamic>? account) {
    if (account?['status'] != 'revoked') return false;
    final metadata = account?['metadata'];
    return metadata is! Map || metadata['pending_reconnect'] != true;
  }

  Future<void> _connectWithGoogleSignIn() async {
    await GoogleApiAuthService.initialize();
    final signIn = GoogleApiAuthService.signIn;
    if (!signIn.supportsAuthenticate()) {
      throw UnsupportedError(
        'Google account connection is not available here.',
      );
    }

    final user = await signIn.authenticate(scopeHint: apiScopes);
    await user.authorizationClient.authorizationForScopes(apiScopes) ??
        await user.authorizationClient.authorizeScopes(apiScopes);
    await saveConnectedAccount(
      email: user.email,
      source: 'google_sign_in',
      hasProviderToken: true,
    );
  }

  static bool hasGoogleIdentity(User? user) {
    if (user == null) return false;
    final providers = user.appMetadata['providers'];
    if (providers is List && providers.contains('google')) return true;
    if (user.appMetadata['provider'] == 'google') return true;
    return user.identities?.any((identity) => identity.provider == 'google') ??
        false;
  }

  static String? googleIdentityEmail(User? user) {
    final identities = user?.identities;
    if (identities == null) return null;
    for (final identity in identities) {
      if (identity.provider != 'google') continue;
      final email = identity.identityData?['email']?.toString().trim();
      if (email != null && email.isNotEmpty) return email;
    }
    return null;
  }

  static bool _hasProviderToken(Session? session) {
    final token = session?.providerToken?.trim();
    return token != null && token.isNotEmpty;
  }

  Future<void> _clearAutoRenewAttempt(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_autoRenewKeyPrefix:$userId');
  }
}

class GoogleAccountConnectionState {
  const GoogleAccountConnectionState({
    required this.account,
    required this.userHasGoogleIdentity,
    required this.sessionHasProviderToken,
    required this.sessionGoogleEmail,
  });

  final Map<String, dynamic>? account;
  final bool userHasGoogleIdentity;
  final bool sessionHasProviderToken;
  final String? sessionGoogleEmail;

  bool get connected => account != null;

  bool get readyNow => connected;

  bool get hasLiveAccess => connected && sessionHasProviderToken;

  String? get email {
    final stored = account?['account_email']?.toString().trim();
    if (stored != null && stored.isNotEmpty) return stored;
    final session = sessionGoogleEmail?.trim();
    if (session != null && session.isNotEmpty) return session;
    return null;
  }

  String get statusLabel {
    if (!connected) return 'Not connected';
    if (hasLiveAccess) return 'Connected';
    return 'Connected';
  }
}
