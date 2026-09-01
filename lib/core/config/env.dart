/// Where the app talks to, and nothing else.
///
/// Every request goes to one Go API gateway. Not to Supabase, not to the
/// individual services behind it -- the gateway is the only address the app
/// knows, which is what makes pointing a build at staging a one-flag change.
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8081
class Env {
  Env._();

  /// The gateway. Production serves the API from the same host as the web
  /// storefront.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://gtradea.com',
  );

  /// GoTrue lives beside the gateway rather than behind its prefix, so it needs
  /// its own base. Overridable on its own for the case where auth is pointed at
  /// production while the API is local.
  static const String _authBaseOverride = String.fromEnvironment(
    'GOTRUE_URL',
    defaultValue: '',
  );

  static String get authBaseUrl =>
      _authBaseOverride.isNotEmpty ? _authBaseOverride : '$apiBaseUrl/auth/v1';

  /// Everything the gateway serves sits under this.
  static const String apiPrefix = '/api/v1';

  static String get apiRoot => '$apiBaseUrl$apiPrefix';

  /// The host the payment gateways and the OAuth provider redirect back to.
  ///
  /// Its own define, deliberately. Payment returns are recognised by watching
  /// the WebView's URL, and OAuth by the same trick, so a build pointed at
  /// staging with this still reading `gtradea.com` would sit on the payment
  /// screen forever waiting for a redirect that never matches.
  static const String returnHost = String.fromEnvironment(
    'RETURN_HOST',
    defaultValue: 'gtradea.com',
  );

  /// Where GoTrue sends the browser back after Google sign-in. Must be
  /// allow-listed server-side: GoTrue quietly substitutes its own SITE_URL for
  /// any redirect it does not recognise, so a wrong value here fails as a
  /// redirect to the wrong place rather than as an error.
  static const String oauthRedirect = String.fromEnvironment(
    'OAUTH_REDIRECT',
    defaultValue: 'https://gtradea.com/auth/callback',
  );

  /// Long enough for a slow mobile network on a first connect, short enough
  /// that a dead server does not look like a hung app.
  static const Duration requestTimeout = Duration(seconds: 20);

  /// The realtime socket, derived rather than configured so it can never point
  /// somewhere the API does not.
  static String get realtimeUrl {
    final ws = apiBaseUrl.replaceFirst(RegExp('^http'), 'ws');
    return '$ws$apiPrefix/realtime';
  }
}
