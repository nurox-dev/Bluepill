import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/app_config.dart';

class GoogleApiAuthService {
  GoogleApiAuthService._();

  static const calendarEventsScope =
      'https://www.googleapis.com/auth/calendar.events';
  static const tasksScope = 'https://www.googleapis.com/auth/tasks';
  static const googleApiScopes = [calendarEventsScope, tasksScope];
  static const supabaseGoogleApiScopes =
      'openid email profile $calendarEventsScope $tasksScope';
  static const supabaseGoogleCalendarScopes = supabaseGoogleApiScopes;
  static const googleOAuthQueryParams = {
    'access_type': 'offline',
    'include_granted_scopes': 'true',
  };

  static final GoogleSignIn signIn = GoogleSignIn.instance;
  static Future<void>? _initializeFuture;

  static Future<void> initialize() async {
    if (kIsWeb && !AppConfig.googleCalendarConfigured) {
      throw StateError('Missing GOOGLE_OAUTH_CLIENT_ID for Google APIs.');
    }

    _initializeFuture ??= signIn.initialize(
      clientId: AppConfig.googleOAuthClientId.isEmpty
          ? null
          : AppConfig.googleOAuthClientId,
    );
    await _initializeFuture;
  }
}
