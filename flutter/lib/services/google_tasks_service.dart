import 'dart:async';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/tasks/v1.dart' as google_tasks;
import 'package:googleapis_auth/googleapis_auth.dart' as google_auth;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'google_account_connection_service.dart';
import 'google_api_auth_service.dart';
import 'supabase_service.dart';

typedef TasksAuthChanged =
    FutureOr<void> Function(String? accountEmail, bool authorized);

class GoogleTasksService {
  GoogleTasksService();

  static const List<String> tasksScopes = [google_tasks.TasksApi.tasksScope];

  final GoogleSignIn _signIn = GoogleApiAuthService.signIn;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;
  GoogleSignInAccount? _currentUser;
  String? _accountEmail;
  google_auth.AuthClient? _authClient;
  google_tasks.TasksApi? _tasksApi;

  GoogleSignInAccount? get currentUser => _currentUser;

  String? get accountEmail => _accountEmail ?? _currentUser?.email;

  bool get isAuthorized => _tasksApi != null;

  void clearAuthorization() {
    _clearAuthClient();
  }

  bool isAuthorizationError(Object error) {
    if (error is google_tasks.DetailedApiRequestError) {
      if (error.status == 401) return true;
      final details = [
        error.message,
        for (final detail in error.errors) detail.reason,
        for (final detail in error.errors) detail.message,
        error.jsonResponse?.toString(),
      ].whereType<String>().join(' ').toLowerCase();
      return details.contains('insufficientpermissions') ||
          details.contains('access_token_scope_insufficient') ||
          (details.contains('insufficient') && details.contains('scope'));
    }
    return false;
  }

  Future<void> initialize({
    required TasksAuthChanged onAuthChanged,
    required void Function(Object error) onError,
  }) async {
    await GoogleApiAuthService.initialize();

    await _authSubscription?.cancel();
    _authSubscription = _signIn.authenticationEvents.listen((event) async {
      try {
        switch (event) {
          case GoogleSignInAuthenticationEventSignIn():
            await _setUser(event.user);
          case GoogleSignInAuthenticationEventSignOut():
            _clearAuthClient();
            _currentUser = null;
            _accountEmail = null;
        }
        await onAuthChanged(accountEmail, isAuthorized);
      } catch (error) {
        onError(error);
      }
    }, onError: onError);

    if (_setSupabaseSessionAuthorization()) {
      await onAuthChanged(accountEmail, isAuthorized);
      return;
    }

    final lightweight = _signIn.attemptLightweightAuthentication();
    if (lightweight != null) {
      final user = await lightweight;
      if (user != null) {
        await _setUser(user);
        await onAuthChanged(accountEmail, isAuthorized);
      }
    }

    final account = await GoogleAccountConnectionService().connectedAccount();
    final email = account?['account_email']?.toString().trim();
    if (email != null && email.isNotEmpty) {
      _accountEmail = email;
      await onAuthChanged(accountEmail, isAuthorized);
    }
  }

  Future<void> signInAndAuthorize() async {
    if (_setSupabaseSessionAuthorization()) return;

    if (kIsWeb) {
      await _connectWithSupabaseGoogleOAuth();
      return;
    }

    GoogleSignInAccount? user = _currentUser;
    if (user == null) {
      if (!_signIn.supportsAuthenticate()) {
        throw UnsupportedError(
          'Use the Google sign-in button before authorizing Tasks.',
        );
      }
      user = await _signIn.authenticate(scopeHint: tasksScopes);
      await _setUser(user);
    }
    await authorizeTasks();
  }

  Future<void> authorizeTasks() async {
    if (kIsWeb) {
      if (isAuthorized) return;
      await _connectWithSupabaseGoogleOAuth();
      return;
    }

    if (_setSupabaseSessionAuthorization()) return;

    final user = _currentUser;
    if (user == null) {
      throw StateError('Connect a Google account first.');
    }
    final authorization =
        await user.authorizationClient.authorizationForScopes(tasksScopes) ??
        await user.authorizationClient.authorizeScopes(tasksScopes);
    _setAuthorization(authorization);
  }

  Future<google_tasks.TaskList> getOrCreateSyncTaskList() async {
    final api = _requireApi();
    final lists = await api.tasklists.list(maxResults: 100);
    google_tasks.TaskList? existing;
    for (final list in lists.items ?? <google_tasks.TaskList>[]) {
      if (list.title == 'Project BluePill') {
        existing = list;
        break;
      }
    }
    if (existing != null && existing.id != null) return existing;
    return api.tasklists.insert(
      google_tasks.TaskList(title: 'Project BluePill'),
    );
  }

  Future<List<google_tasks.Task>> listTasks(
    String taskListId, {
    bool includeDeleted = false,
  }) async {
    final api = _requireApi();
    final tasks = <google_tasks.Task>[];
    String? pageToken;
    do {
      final page = await api.tasks.list(
        taskListId,
        maxResults: 100,
        pageToken: pageToken,
        showCompleted: true,
        showDeleted: includeDeleted,
        showHidden: true,
      );
      tasks.addAll(page.items ?? []);
      pageToken = page.nextPageToken;
    } while (pageToken != null);
    return includeDeleted
        ? tasks
        : tasks.where((task) => task.deleted != true).toList(growable: false);
  }

  Future<google_tasks.Task> createTask(
    String taskListId,
    GoogleTaskDraft draft,
  ) async {
    final api = _requireApi();
    return api.tasks.insert(_taskFromDraft(draft), taskListId);
  }

  Future<google_tasks.Task> updateTask(
    String taskListId,
    String taskId,
    GoogleTaskDraft draft,
  ) async {
    final api = _requireApi();
    return api.tasks.patch(_taskFromDraft(draft), taskListId, taskId);
  }

  Future<void> deleteTask(String taskListId, String taskId) async {
    final api = _requireApi();
    await api.tasks.delete(taskListId, taskId);
  }

  Future<void> disconnect() async {
    if (_currentUser != null) {
      await _signIn.disconnect();
    }
    _clearAuthClient();
    _currentUser = null;
    _accountEmail = null;
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _clearAuthClient();
  }

  Future<void> _setUser(GoogleSignInAccount user) async {
    _currentUser = user;
    _accountEmail = user.email;
    final authorization = await user.authorizationClient.authorizationForScopes(
      tasksScopes,
    );
    if (authorization == null) {
      _clearAuthClient();
      return;
    }
    _setAuthorization(authorization);
  }

  void _setAuthorization(GoogleSignInClientAuthorization authorization) {
    _clearAuthClient();
    _authClient = authorization.authClient(scopes: tasksScopes);
    _tasksApi = google_tasks.TasksApi(_authClient!);
  }

  bool _setSupabaseSessionAuthorization() {
    final session = SupabaseService.client.auth.currentSession;
    final providerToken = session?.providerToken?.trim();
    if (providerToken == null || providerToken.isEmpty) return false;

    final user = session?.user ?? SupabaseService.currentUser;
    final email = _googleIdentityEmail(user) ?? user?.email;
    final expiresAt = session?.expiresAt == null
        ? DateTime.now().toUtc().add(const Duration(minutes: 55))
        : DateTime.fromMillisecondsSinceEpoch(
            session!.expiresAt! * 1000,
            isUtc: true,
          );
    if (!expiresAt.isAfter(DateTime.now().toUtc())) return false;

    _setProviderTokenAuthorization(
      providerToken: providerToken,
      email: email,
      expiresAt: expiresAt,
    );
    return true;
  }

  Future<void> _connectWithSupabaseGoogleOAuth() async {
    final auth = SupabaseService.client.auth;
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before connecting Google Tasks.');
    }

    final redirectTo = AppConfig.authRedirectUrl(Uri.base);
    if (_hasGoogleIdentity(user)) {
      await auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        scopes: GoogleApiAuthService.supabaseGoogleApiScopes,
        queryParams: GoogleApiAuthService.googleOAuthQueryParams,
      );
    } else {
      await auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: redirectTo,
        scopes: GoogleApiAuthService.supabaseGoogleApiScopes,
        queryParams: GoogleApiAuthService.googleOAuthQueryParams,
      );
    }
  }

  void _setProviderTokenAuthorization({
    required String providerToken,
    required String? email,
    required DateTime expiresAt,
  }) {
    _clearAuthClient();
    _currentUser = null;
    _accountEmail = email;
    final credentials = google_auth.AccessCredentials(
      google_auth.AccessToken('Bearer', providerToken, expiresAt),
      null,
      tasksScopes,
    );
    _authClient = google_auth.authenticatedClient(
      http.Client(),
      credentials,
      closeUnderlyingClient: true,
    );
    _tasksApi = google_tasks.TasksApi(_authClient!);
  }

  bool _hasGoogleIdentity(User user) {
    final providers = user.appMetadata['providers'];
    if (providers is List && providers.contains('google')) return true;
    if (user.appMetadata['provider'] == 'google') return true;
    return user.identities?.any((identity) => identity.provider == 'google') ??
        false;
  }

  String? _googleIdentityEmail(User? user) {
    final identities = user?.identities;
    if (identities == null) return null;
    for (final identity in identities) {
      if (identity.provider != 'google') continue;
      final email = identity.identityData?['email']?.toString().trim();
      if (email != null && email.isNotEmpty) return email;
    }
    return null;
  }

  void _clearAuthClient() {
    _authClient?.close();
    _authClient = null;
    _tasksApi = null;
  }

  google_tasks.TasksApi _requireApi() {
    final api = _tasksApi;
    if (api == null) {
      throw StateError('Authorize Google Tasks access first.');
    }
    return api;
  }

  google_tasks.Task _taskFromDraft(GoogleTaskDraft draft) {
    return google_tasks.Task(
      title: draft.title,
      notes: draft.notes,
      due: draft.dueDate == null ? null : _googleDueDate(draft.dueDate!),
      status: draft.completed ? 'completed' : 'needsAction',
      completed: draft.completed
          ? (draft.completedAt ?? DateTime.now()).toUtc().toIso8601String()
          : null,
    );
  }

  String _googleDueDate(DateTime date) {
    final utcDate = DateTime.utc(date.year, date.month, date.day);
    return utcDate.toIso8601String();
  }
}

class GoogleTaskDraft {
  const GoogleTaskDraft({
    required this.title,
    required this.notes,
    required this.dueDate,
    required this.completed,
    required this.completedAt,
  });

  final String title;
  final String notes;
  final DateTime? dueDate;
  final bool completed;
  final DateTime? completedAt;
}
