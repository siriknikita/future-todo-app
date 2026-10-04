import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:future_todo/features/auth/auth_pages.dart';
import 'package:future_todo/features/home/home_page.dart';
import 'package:future_todo/l10n/app_localizations.dart';
import 'package:future_todo/providers.dart';
import 'package:go_router/go_router.dart';

GoRouter buildRouter() => GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomePage()),
        GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
        GoRoute(path: '/register', builder: (_, __) => const RegisterPage()),
        GoRoute(
          path: '/forgot-password',
          builder: (_, __) => const ForgotPasswordPage(),
        ),
        GoRoute(
          path: '/reset-password',
          builder: (_, state) =>
              ResetPasswordPage(token: state.uri.queryParameters['token']),
        ),
        GoRoute(
          path: '/verify-email',
          builder: (_, state) =>
              VerifyEmailPage(token: state.uri.queryParameters['token']),
        ),
        GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
        GoRoute(
          path: '/join/:token',
          builder: (_, state) =>
              InvitePage(token: state.pathParameters['token']!),
        ),
      ],
    );

ThemeData _theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2564CF),
        brightness: brightness,
      ),
    );

class FutureTodoApp extends ConsumerStatefulWidget {
  const FutureTodoApp({super.key});

  @override
  ConsumerState<FutureTodoApp> createState() => _FutureTodoAppState();
}

class _FutureTodoAppState extends ConsumerState<FutureTodoApp> {
  final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    ref.watch(autoSyncProvider);
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      routerConfig: _router,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: settings.themeMode,
      locale: settings.languageCode == null
          ? null
          : Locale(settings.languageCode!),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
