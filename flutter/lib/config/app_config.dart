import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static const _supabaseUrlDefine = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKeyDefine = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const _googleOAuthClientIdDefine = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID',
  );
  static const _authRedirectOriginDefine = String.fromEnvironment(
    'AUTH_REDIRECT_ORIGIN',
  );
  static const _fastApiBaseUrlDefine = String.fromEnvironment(
    'FASTAPI_BASE_URL',
  );
  static const _mcpServerUrlDefine = String.fromEnvironment(
    'MCP_SERVER_URL',
  );

  static String get supabaseUrl => _firstNonEmpty([
    _supabaseUrlDefine,
    dotenv.env['SUPABASE_URL'],
    dotenv.env['NEXT_PUBLIC_SUPABASE_URL'],
  ]);
  static String get supabaseAnonKey => _firstNonEmpty([
    _supabaseAnonKeyDefine,
    dotenv.env['SUPABASE_ANON_KEY'],
    dotenv.env['NEXT_PUBLIC_SUPABASE_ANON_KEY'],
  ]);

  static String get googleOAuthClientId => _firstNonEmpty([
    _googleOAuthClientIdDefine,
    dotenv.env['GOOGLE_OAUTH_CLIENT_ID'],
    dotenv.env['GOOGLE_CLIENT_ID'],
  ]);

  static String get authRedirectOrigin => _firstNonEmpty([
    _authRedirectOriginDefine,
    dotenv.env['AUTH_REDIRECT_ORIGIN'],
    dotenv.env['APP_ORIGIN'],
  ]);

  static String get fastApiBaseUrl => _firstNonEmpty([
    _fastApiBaseUrlDefine,
    dotenv.env['FASTAPI_BASE_URL'],
    dotenv.env['WORKER_BASE_URL'],
  ]);

  static String get mcpServerUrl => _firstNonEmpty([
    _mcpServerUrlDefine,
    dotenv.env['MCP_SERVER_URL'],
  ]);

  static String authRedirectUrl(Uri currentUri) {
    final configured = _normalizedOrigin(authRedirectOrigin);
    if (configured.isNotEmpty) return configured;
    return _withTrailingSlash(currentUri.origin);
  }

  static bool get supabaseConfigured =>
      supabaseUrl.startsWith('https://') &&
      supabaseAnonKey.isNotEmpty &&
      !supabaseUrl.contains('your-project') &&
      !supabaseAnonKey.contains('your-supabase');

  static bool get googleCalendarConfigured =>
      googleOAuthClientId.endsWith('.apps.googleusercontent.com');
  static bool get googleApisConfigured => googleCalendarConfigured;
  static bool get fastApiConfigured =>
      fastApiBaseUrl.startsWith('http://') ||
      fastApiBaseUrl.startsWith('https://');

  static String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  static String _normalizedOrigin(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      return _withTrailingSlash(trimmed);
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/',
    ).toString();
  }

  static String _withTrailingSlash(String value) =>
      value.endsWith('/') ? value : '$value/';
}
