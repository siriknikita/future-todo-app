/// Keys under which the app stores values in `SharedPreferences`.
///
/// The string values are persisted on users' devices, so they must never
/// change.
abstract final class PrefKeys {
  // Auth session.
  static const accessToken = 'auth.access';
  static const refreshToken = 'auth.refresh';
  static const userId = 'auth.userId';
  static const userEmail = 'auth.email';
  static const userName = 'auth.name';

  /// Everything removed on sign-out.
  static const authKeys = [
    accessToken,
    refreshToken,
    userId,
    userEmail,
    userName,
  ];

  // Device and sync.
  static const deviceId = 'deviceId';
  static const syncCursor = 'sync.cursor';

  // Settings.
  static const themeMode = 'themeMode';
  static const language = 'language';
  static const hideCompleted = 'hideCompleted';
  static const sortMode = 'sortMode';
}
