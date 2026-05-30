import 'dart:async';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as google_auth;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'google_api_auth_service.dart';
import 'supabase_service.dart';

typedef CalendarAuthChanged =
    FutureOr<void> Function(String? accountEmail, bool authorized);

class GoogleCalendarService {
  GoogleCalendarService();

  static const List<String> calendarScopes = [CalendarApi.calendarEventsScope];

  final GoogleSignIn _signIn = GoogleApiAuthService.signIn;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;
  GoogleSignInAccount? _currentUser;
  String? _accountEmail;
  google_auth.AuthClient? _authClient;
  CalendarApi? _calendarApi;

  String? get accountEmail => _accountEmail ?? _currentUser?.email;

  bool get isAuthorized => _calendarApi != null;

  void clearAuthorization() {
    _clearAuthClient();
  }

  bool isAuthorizationError(Object error) {
    if (error is DetailedApiRequestError) {
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
    required CalendarAuthChanged onAuthChanged,
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
  }

  Future<void> connectCalendar() async {
    if (_setSupabaseSessionAuthorization()) return;

    if (kIsWeb) {
      await _connectWithSupabaseGoogleOAuth();
      return;
    }

    await _signInAndAuthorizeWithGoogleSignIn();
  }

  Future<void> _signInAndAuthorizeWithGoogleSignIn() async {
    GoogleSignInAccount? user = _currentUser;
    if (user == null) {
      if (!_signIn.supportsAuthenticate()) {
        throw UnsupportedError(
          'Use Google OAuth in the browser before authorizing Calendar.',
        );
      }
      user = await _signIn.authenticate(scopeHint: calendarScopes);
      await _setUser(user);
    }
    final authorization =
        await user.authorizationClient.authorizationForScopes(calendarScopes) ??
        await user.authorizationClient.authorizeScopes(calendarScopes);
    _setAuthorization(authorization);
  }

  Future<void> _connectWithSupabaseGoogleOAuth() async {
    final auth = SupabaseService.client.auth;
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before connecting Google Calendar.');
    }

    final redirectTo = AppConfig.authRedirectUrl(Uri.base);
    if (_hasGoogleIdentity(user)) {
      await auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        scopes: GoogleApiAuthService.supabaseGoogleCalendarScopes,
        queryParams: GoogleApiAuthService.googleOAuthQueryParams,
      );
    } else {
      await auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: redirectTo,
        scopes: GoogleApiAuthService.supabaseGoogleCalendarScopes,
        queryParams: GoogleApiAuthService.googleOAuthQueryParams,
      );
    }
  }

  Future<List<Event>> listUpcomingEvents({
    int days = 30,
    int maxResults = 50,
  }) async {
    final api = _requireApi();
    final now = DateTime.now();
    final timeMin = DateTime(now.year, now.month, now.day);
    final timeMax = timeMin.add(Duration(days: days));
    final result = await api.events.list(
      'primary',
      maxResults: maxResults,
      orderBy: 'startTime',
      showDeleted: false,
      singleEvents: true,
      timeMin: timeMin,
      timeMax: timeMax,
    );
    return (result.items ?? [])
        .where((event) => event.status != 'cancelled')
        .toList(growable: false);
  }

  Future<Event> createEvent(CalendarEventDraft draft) async {
    final api = _requireApi();
    return api.events.insert(
      _eventFromDraft(draft),
      'primary',
      sendUpdates: draft.attendees.isEmpty ? 'none' : 'all',
    );
  }

  Future<Event> updateEvent(String eventId, CalendarEventDraft draft) async {
    final api = _requireApi();
    return api.events.patch(
      _eventFromDraft(draft),
      'primary',
      eventId,
      sendUpdates: draft.attendees.isEmpty ? 'none' : 'all',
    );
  }

  Future<void> deleteEvent(String eventId) async {
    final api = _requireApi();
    await api.events.delete('primary', eventId, sendUpdates: 'all');
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
      calendarScopes,
    );
    if (authorization == null) {
      _clearAuthClient();
      return;
    }
    _setAuthorization(authorization);
  }

  void _setAuthorization(GoogleSignInClientAuthorization authorization) {
    _clearAuthClient();
    _authClient = authorization.authClient(scopes: calendarScopes);
    _calendarApi = CalendarApi(_authClient!);
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
      calendarScopes,
    );
    _authClient = google_auth.authenticatedClient(
      http.Client(),
      credentials,
      closeUnderlyingClient: true,
    );
    _calendarApi = CalendarApi(_authClient!);
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
    _calendarApi = null;
  }

  CalendarApi _requireApi() {
    final api = _calendarApi;
    if (api == null) {
      throw StateError('Authorize Google Calendar access first.');
    }
    return api;
  }

  Event _eventFromDraft(CalendarEventDraft draft) {
    return Event(
      summary: draft.title,
      description: draft.description.isEmpty ? null : draft.description,
      location: draft.location.isEmpty ? null : draft.location,
      start: EventDateTime(dateTime: draft.start),
      end: EventDateTime(dateTime: draft.end),
      attendees: draft.attendees
          .map((email) => EventAttendee(email: email))
          .toList(growable: false),
    );
  }
}

class CalendarEventDraft {
  const CalendarEventDraft({
    required this.title,
    required this.description,
    required this.location,
    required this.attendees,
    required this.start,
    required this.end,
  });

  final String title;
  final String description;
  final String location;
  final List<String> attendees;
  final DateTime start;
  final DateTime end;
}
