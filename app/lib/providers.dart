import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:future_todo/core/hlc.dart';
import 'package:future_todo/data/db/database.dart';
import 'package:future_todo/data/remote/http_remote_api.dart';
import 'package:future_todo/data/remote/remote_api.dart';
import 'package:future_todo/data/repository.dart';
import 'package:future_todo/data/sync/realtime_listener.dart';
import 'package:future_todo/data/sync/sync_service.dart';
import 'package:future_todo/domain/smart_lists.dart';
import 'package:future_todo/domain/sorting.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ------------------------------------------------------------ infrastructure

/// Overridden in `main()` and in tests.
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider must be overridden'),
);

/// Overridden in `main()` and in tests.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden'),
);

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

final remoteApiProvider = Provider<RemoteApi>((ref) {
  final prefs = ref.watch(prefsProvider);
  return HttpRemoteApi(baseUrl: apiBaseUrl)
    ..deviceId = ref.watch(hlcClockProvider).node
    ..accessToken = prefs.getString('auth.access')
    ..refreshToken = prefs.getString('auth.refresh')
    ..onTokens = (access, refresh) {
      unawaited(prefs.setString('auth.access', access));
      unawaited(prefs.setString('auth.refresh', refresh));
    };
});

final hlcClockProvider = Provider<HlcClock>((ref) {
  final prefs = ref.watch(prefsProvider);
  var node = prefs.getString('deviceId');
  if (node == null) {
    node = const Uuid().v4();
    unawaited(prefs.setString('deviceId', node));
  }
  return HlcClock(node);
});

final repositoryProvider = Provider<TodoRepository>(
  (ref) => TodoRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(hlcClockProvider),
  ),
);

// --------------------------------------------------------------- data streams

final groupsProvider = StreamProvider<List<ListGroup>>(
  (ref) => ref.watch(repositoryProvider).watchGroups(),
);
final listsProvider = StreamProvider<List<TaskList>>(
  (ref) => ref.watch(repositoryProvider).watchLists(),
);
final tasksProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(repositoryProvider).watchTasks(),
);
final stepsProvider = StreamProvider<List<TaskStep>>(
  (ref) => ref.watch(repositoryProvider).watchSteps(),
);
final dirtyCountProvider = StreamProvider<int>(
  (ref) => ref.watch(repositoryProvider).watchDirtyCount(),
);

/// Current local time, updated at every local midnight so that "My Day"
/// and the planned buckets refresh by themselves (FR-4.1).
final todayProvider = StreamProvider<DateTime>((ref) {
  final controller = StreamController<DateTime>()..add(DateTime.now());
  Timer? timer;
  void schedule() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    timer = Timer(midnight.difference(now) + const Duration(seconds: 1), () {
      controller.add(DateTime.now());
      schedule();
    });
  }

  schedule();
  ref.onDispose(() {
    timer?.cancel();
    unawaited(controller.close());
  });
  return controller.stream;
});

// ------------------------------------------------------------------ selection

/// What the task area shows: a regular list or a smart list.
@immutable
class ViewSelection {
  const ViewSelection.list(String this.listId) : smart = null;
  const ViewSelection.smart(SmartList this.smart) : listId = null;

  final String? listId;
  final SmartList? smart;

  @override
  bool operator ==(Object other) =>
      other is ViewSelection && other.listId == listId && other.smart == smart;

  @override
  int get hashCode => Object.hash(listId, smart);
}

final selectedViewProvider = StateProvider<ViewSelection>(
  (ref) => const ViewSelection.smart(SmartList.myDay),
);
final selectedTaskIdProvider = StateProvider<String?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');
final searchIncludeCompletedProvider = StateProvider<bool>((ref) => true);

// ------------------------------------------------------------------- settings

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.languageCode,
    this.hideCompleted = false,
    this.sortMode = SortMode.manual,
  });

  final ThemeMode themeMode;

  /// `null` follows the system language.
  final String? languageCode;
  final bool hideCompleted;
  final SortMode sortMode;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? languageCode,
    bool clearLanguage = false,
    bool? hideCompleted,
    SortMode? sortMode,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        languageCode: clearLanguage ? null : languageCode ?? this.languageCode,
        hideCompleted: hideCompleted ?? this.hideCompleted,
        sortMode: sortMode ?? this.sortMode,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(prefsProvider);
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == prefs.getString('themeMode'),
        orElse: () => ThemeMode.system,
      ),
      languageCode: prefs.getString('language'),
      hideCompleted: prefs.getBool('hideCompleted') ?? false,
      sortMode: SortMode.values.firstWhere(
        (m) => m.name == prefs.getString('sortMode'),
        orElse: () => SortMode.manual,
      ),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString('themeMode', mode.name);
  }

  /// Pass `null` to follow the system language (FR-9.2).
  Future<void> setLanguage(String? code) async {
    state = code == null
        ? state.copyWith(clearLanguage: true)
        : state.copyWith(languageCode: code);
    if (code == null) {
      await _prefs.remove('language');
    } else {
      await _prefs.setString('language', code);
    }
  }

  Future<void> setHideCompleted({required bool hide}) async {
    state = state.copyWith(hideCompleted: hide);
    await _prefs.setBool('hideCompleted', hide);
  }

  Future<void> setSortMode(SortMode mode) async {
    state = state.copyWith(sortMode: mode);
    await _prefs.setString('sortMode', mode.name);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ----------------------------------------------------------------------- auth

class AuthState {
  const AuthState({this.user});

  final AuthUser? user;
  bool get signedIn => user != null;
}

class AuthController extends Notifier<AuthState> {
  RemoteApi get _api => ref.read(remoteApiProvider);
  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  AuthState build() {
    final prefs = ref.watch(prefsProvider);
    final token = prefs.getString('auth.access');
    final id = prefs.getString('auth.userId');
    final email = prefs.getString('auth.email');
    if (token == null || id == null || email == null) {
      return const AuthState();
    }
    return AuthState(
      user: AuthUser(id: id, email: email, name: prefs.getString('auth.name')),
    );
  }

  Future<void> register({
    required String email,
    required String password,
    String? name,
  }) =>
      _api.register(email: email, password: password, name: name);

  Future<void> login(String email, String password) async {
    final session = await _api.login(email: email, password: password);
    _api
      ..accessToken = session.accessToken
      ..refreshToken = session.refreshToken;
    await _prefs.setString('auth.access', session.accessToken);
    await _prefs.setString('auth.refresh', session.refreshToken);
    await _saveUser(session.user);
    state = AuthState(user: session.user);
  }

  Future<void> requestPasswordReset(String email) =>
      _api.requestPasswordReset(email);

  Future<void> verifyEmail(String token) => _api.verifyEmail(token);

  Future<void> resetPassword(String token, String newPassword) =>
      _api.resetPassword(token: token, newPassword: newPassword);

  /// FR-1.4: name and/or password. (Photo upload is not implemented.)
  Future<void> updateProfile({
    String? name,
    String? currentPassword,
    String? newPassword,
  }) async {
    if (newPassword != null && currentPassword != null) {
      await _api.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
    }
    final user = await _api.updateProfile(name: name);
    await _saveUser(user);
    state = AuthState(user: user);
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } on Object {
      // Signing out locally must work offline.
    }
    _api
      ..accessToken = null
      ..refreshToken = null;
    for (final k in [
      'auth.access',
      'auth.refresh',
      'auth.userId',
      'auth.email',
      'auth.name',
    ]) {
      await _prefs.remove(k);
    }
    state = const AuthState();
  }

  Future<void> _saveUser(AuthUser user) async {
    await _prefs.setString('auth.userId', user.id);
    await _prefs.setString('auth.email', user.email);
    if (user.name != null) await _prefs.setString('auth.name', user.name!);
  }
}

final authProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

// ----------------------------------------------------------------------- sync

final syncServiceProvider = Provider<SyncService>((ref) {
  final prefs = ref.watch(prefsProvider);
  final service = SyncService(
    repository: ref.watch(repositoryProvider),
    remote: ref.watch(remoteApiProvider),
    loadCursor: () => prefs.getInt('sync.cursor') ?? 0,
    saveCursor: (c) => prefs.setInt('sync.cursor', c),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Keeps the local database in sync while a user is signed in: once at
/// start, 1 s after local changes, when the server's WebSocket reports
/// changes (FR-5.6, PR-3), and every 30 s as a fallback.
final autoSyncProvider = Provider<void>((ref) {
  final signedIn = ref.watch(authProvider).signedIn;
  if (!signedIn) return;
  final service = ref.watch(syncServiceProvider);
  final api = ref.watch(remoteApiProvider);
  unawaited(service.syncNow());

  final poll = Timer.periodic(
    const Duration(seconds: 30),
    (_) => unawaited(service.syncNow()),
  );
  Timer? debounce;
  ref.listen<AsyncValue<int>>(dirtyCountProvider, (_, next) {
    if ((next.valueOrNull ?? 0) > 0) {
      debounce?.cancel();
      debounce = Timer(
        const Duration(seconds: 1),
        () => unawaited(service.syncNow()),
      );
    }
  });
  final realtime = RealtimeListener(
    uriProvider: api.realtimeUri,
    onChanges: () => unawaited(service.syncNow()),
  )..start();
  ref.onDispose(() {
    poll.cancel();
    debounce?.cancel();
    realtime.stop();
  });
});

enum SyncIndicator { guest, synced, pending, error }

final syncStatusStreamProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(syncServiceProvider).statuses,
);

final syncIndicatorProvider = Provider<SyncIndicator>((ref) {
  if (!ref.watch(authProvider).signedIn) return SyncIndicator.guest;
  final status = ref.watch(syncStatusStreamProvider).valueOrNull;
  if (status == SyncStatus.error) return SyncIndicator.error;
  final dirty = ref.watch(dirtyCountProvider).valueOrNull ?? 0;
  return dirty > 0 ? SyncIndicator.pending : SyncIndicator.synced;
});
