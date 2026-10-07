import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:future_todo/features/common/widgets.dart';
import 'package:future_todo/l10n/app_localizations.dart';
import 'package:future_todo/providers.dart';
import 'package:go_router/go_router.dart';

String? _validateEmail(AppLocalizations l, String? v) {
  final value = v?.trim() ?? '';
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)
      ? null
      : l.invalidEmail;
}

String? _validatePassword(AppLocalizations l, String? v) =>
    (v ?? '').length >= 8 ? null : l.passwordTooShort;

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: BackButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      );
}

/// Sign-in screen (FR-1.1 login half, FR-1.3 link).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authProvider.notifier)
          .login(_email.text.trim(), _password.text);
      if (mounted) context.go('/');
    } on Object catch (e) {
      if (mounted) {
        showMessage(
          context,
          '${AppLocalizations.of(context).errorGeneric}: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _AuthScaffold(
      title: l.signIn,
      child: Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              key: const Key('login-email'),
              controller: _email,
              decoration: InputDecoration(labelText: l.email),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => _validateEmail(l, v),
            ),
            TextFormField(
              key: const Key('login-password'),
              controller: _password,
              decoration: InputDecoration(labelText: l.password),
              obscureText: true,
              validator: (v) => (v ?? '').isEmpty ? l.passwordTooShort : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('login-submit'),
              onPressed: _busy ? null : _submit,
              child: Text(l.signIn),
            ),
            TextButton(
              onPressed: () => context.push('/forgot-password'),
              child: Text(l.forgotPassword),
            ),
            TextButton(
              onPressed: () => context.push('/register'),
              child: Text(l.createAccount),
            ),
          ],
        ),
      ),
    );
  }
}

/// Registration (FR-1.1). The server sends a confirmation email.
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).register(
            email: _email.text.trim(),
            password: _password.text,
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
          );
      if (mounted) setState(() => _sent = true);
    } on Object catch (e) {
      if (mounted) {
        showMessage(
          context,
          '${AppLocalizations.of(context).errorGeneric}: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_sent) {
      return _AuthScaffold(
        title: l.createAccount,
        child: Column(
          children: [
            Text(l.confirmEmailSent, key: const Key('register-sent')),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/login'),
              child: Text(l.signIn),
            ),
          ],
        ),
      );
    }
    return _AuthScaffold(
      title: l.createAccount,
      child: Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: l.name),
            ),
            TextFormField(
              key: const Key('register-email'),
              controller: _email,
              decoration: InputDecoration(labelText: l.email),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => _validateEmail(l, v),
            ),
            TextFormField(
              key: const Key('register-password'),
              controller: _password,
              decoration: InputDecoration(labelText: l.password),
              obscureText: true,
              validator: (v) => _validatePassword(l, v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('register-submit'),
              onPressed: _busy ? null : _submit,
              child: Text(l.createAccount),
            ),
          ],
        ),
      ),
    );
  }
}

/// Password recovery by email (FR-1.3).
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    try {
      await ref
          .read(authProvider.notifier)
          .requestPasswordReset(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on Object catch (e) {
      if (mounted) {
        showMessage(
          context,
          '${AppLocalizations.of(context).errorGeneric}: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _AuthScaffold(
      title: l.forgotPassword,
      child: _sent
          ? Text(l.resetLinkSent, key: const Key('reset-sent'))
          : Form(
              key: _form,
              child: Column(
                children: [
                  TextFormField(
                    key: const Key('reset-email'),
                    controller: _email,
                    decoration: InputDecoration(labelText: l.email),
                    validator: (v) => _validateEmail(l, v),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('reset-submit'),
                    onPressed: _submit,
                    child: Text(l.sendResetLink),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Opened from the reset link in the email: choose a new password (FR-1.3).
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({required this.token, super.key});

  final String? token;

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _done = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    try {
      await ref
          .read(authProvider.notifier)
          .resetPassword(widget.token ?? '', _password.text);
      if (mounted) setState(() => _done = true);
    } on Object catch (e) {
      if (mounted) {
        showMessage(
          context,
          '${AppLocalizations.of(context).errorGeneric}: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _AuthScaffold(
      title: l.newPassword,
      child: _done
          ? Column(
              children: [
                Text(l.passwordChanged, key: const Key('reset-done')),
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: Text(l.signIn),
                ),
              ],
            )
          : Form(
              key: _form,
              child: Column(
                children: [
                  TextFormField(
                    key: const Key('new-password'),
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(labelText: l.newPassword),
                    validator: (v) => _validatePassword(l, v),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('new-password-submit'),
                    onPressed: _submit,
                    child: Text(l.save),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Opened from the confirmation link in the email (FR-1.1).
class VerifyEmailPage extends ConsumerStatefulWidget {
  const VerifyEmailPage({required this.token, super.key});

  final String? token;

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        await ref.read(authProvider.notifier).verifyEmail(widget.token ?? '');
        if (mounted) setState(() => _done = true);
      } on Object catch (e) {
        if (mounted) setState(() => _error = e.toString());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _AuthScaffold(
      title: l.createAccount,
      child: _error != null
          ? Text('${l.errorGeneric}: $_error')
          : _done
              ? Column(
                  children: [
                    Text(l.emailConfirmed, key: const Key('verify-done')),
                    FilledButton(
                      onPressed: () => context.go('/login'),
                      child: Text(l.signIn),
                    ),
                  ],
                )
              : const Center(child: CircularProgressIndicator()),
    );
  }
}

/// Profile: change name and password (FR-1.4); sign out. Photo upload is
/// not implemented.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late final TextEditingController _name;
  final _current = TextEditingController();
  final _new = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name =
        TextEditingController(text: ref.read(authProvider).user?.name ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _current.dispose();
    _new.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (_new.text.isNotEmpty && _new.text.length < 8) {
      showMessage(context, l.passwordTooShort);
      return;
    }
    try {
      await ref.read(authProvider.notifier).updateProfile(
            name: _name.text.trim(),
            currentPassword: _new.text.isEmpty ? null : _current.text,
            newPassword: _new.text.isEmpty ? null : _new.text,
          );
      if (mounted) showMessage(context, l.profileSaved);
    } on Object catch (e) {
      if (mounted) showMessage(context, '${l.errorGeneric}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final user = ref.watch(authProvider).user;
    return _AuthScaffold(
      title: l.profile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            user?.email ?? '',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          TextField(
            key: const Key('profile-name'),
            controller: _name,
            decoration: InputDecoration(labelText: l.name),
          ),
          TextField(
            controller: _current,
            obscureText: true,
            decoration: InputDecoration(labelText: l.currentPassword),
          ),
          TextField(
            controller: _new,
            obscureText: true,
            decoration: InputDecoration(labelText: l.newPassword),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('profile-save'),
            onPressed: _save,
            child: Text(l.save),
          ),
          TextButton(
            key: const Key('sign-out'),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/');
            },
            child: Text(l.signOut),
          ),
        ],
      ),
    );
  }
}

/// Opened from an invitation link (FR-5.1, joining side).
class InvitePage extends ConsumerStatefulWidget {
  const InvitePage({required this.token, super.key});

  final String token;

  @override
  ConsumerState<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends ConsumerState<InvitePage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_join);
  }

  Future<void> _join() async {
    if (!ref.read(authProvider).signedIn) {
      if (mounted) context.go('/login');
      return;
    }
    try {
      await ref.read(remoteApiProvider).joinByInvite(widget.token);
      await ref.read(syncServiceProvider).syncNow();
      if (mounted) context.go('/');
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _AuthScaffold(
      title: l.joinList,
      child: _error == null
          ? const Center(child: CircularProgressIndicator())
          : Text('${l.errorGeneric}: $_error'),
    );
  }
}
