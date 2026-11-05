import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../cloud/cloud_sync.dart';

/// The account: signed out, it offers to sign in; signed in, it shows the
/// sync state. [compact]: an icon only (navigation rail).
class AccountButton extends StatelessWidget {
  const AccountButton({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cloud = AppScope.of(context).cloud;
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) {
        if (!cloud.available) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final icon = !cloud.signedIn
            ? const Icon(Icons.account_circle_outlined)
            : cloud.syncing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : cloud.error != null
            ? Icon(Icons.cloud_off_outlined, color: scheme.error)
            : const Icon(Icons.cloud_done_outlined);
        final tip = !cloud.signedIn
            ? 'Sign in to sync your library between your devices'
            : cloud.error != null
            ? 'Sync failed: ${cloud.error}'
            : 'Signed in as ${cloud.user!.email}';
        if (compact) {
          return IconButton(
            tooltip: tip,
            onPressed: () => showAccount(context),
            icon: icon,
          );
        }
        return Tooltip(
          message: tip,
          child: OutlinedButton.icon(
            onPressed: () => showAccount(context),
            icon: icon,
            label: Text(cloud.signedIn ? 'Account' : 'Sign in'),
          ),
        );
      },
    );
  }
}

/// The account state as an icon: signed out, syncing, synced or failed.
class AccountIcon extends StatelessWidget {
  const AccountIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = AppScope.of(context).cloud;
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) {
        if (!cloud.signedIn) return const Icon(Icons.account_circle_outlined);
        if (cloud.syncing) {
          return const SizedBox(
            width: 22,
            height: 22,
            child: Padding(
              padding: EdgeInsets.all(2),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return cloud.error != null
            ? Icon(
                Icons.cloud_off_outlined,
                color: Theme.of(context).colorScheme.error,
              )
            : const Icon(Icons.cloud_done_outlined);
      },
    );
  }
}

Future<void> showAccount(BuildContext context) => showDialog(
  context: context,
  builder: (c) => _AccountDialog(cloud: AppScope.read(context).cloud),
);

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.cloud});
  final CloudSync cloud;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;
  bool _showPassword = false;
  late bool _keep = cloud.sessionStore.keep;

  CloudSync get cloud => widget.cloud;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  bool _check({bool password = true}) {
    final email = _email.text.trim();
    String? error;
    if (!email.contains('@')) {
      error = 'Enter your e-mail address.';
    } else if (password && _password.text.length < 6) {
      error = 'The password needs at least 6 characters.';
    }
    setState(() => _error = error);
    return error == null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) => AlertDialog(
        title: Text(
          cloud.recovering
              ? (cloud.signedIn ? 'Change your password' : 'New password')
              : cloud.signedIn
              ? 'Account'
              : 'Sign in',
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...cloud.recovering
                  ? _recovery()
                  : cloud.signedIn
                  ? _signedIn(context)
                  : _signedOut(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_info != null) ...[const SizedBox(height: 12), Text(_info!)],
            ],
          ),
        ),
        actions: _actions(context),
      ),
    );
  }

  Widget _emailField() => TextField(
    controller: _email,
    autofocus: true,
    keyboardType: TextInputType.emailAddress,
    autofillHints: const [AutofillHints.email],
    decoration: const InputDecoration(
      labelText: 'E-mail',
      border: OutlineInputBorder(),
    ),
  );

  Widget _passwordField({String label = 'Password'}) => TextField(
    controller: _password,
    obscureText: !_showPassword,
    autofillHints: const [AutofillHints.password],
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: _showPassword ? 'Hide the password' : 'Show the password',
        onPressed: () => setState(() => _showPassword = !_showPassword),
        icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
      ),
    ),
    onSubmitted: (_) => cloud.recovering ? _setPassword() : _signIn(),
  );

  List<Widget> _signedOut() => [
    const Text(
      'With an account, your library and your training progress are the '
      'same on the PC and on the web. Without one, everything stays on '
      'this device.',
    ),
    const SizedBox(height: 16),
    AutofillGroup(
      child: Column(
        children: [_emailField(), const SizedBox(height: 10), _passwordField()],
      ),
    ),
    const SizedBox(height: 4),
    CheckboxListTile(
      value: _keep,
      onChanged: (v) => setState(() => _keep = v!),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: const Text('Keep me signed in'),
      subtitle: const Text(
        'Untick it on a shared device: closing Go Dojo signs you out.',
      ),
    ),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: _busy ? null : _forgot,
        child: const Text('Forgot your password?'),
      ),
    ),
  ];

  List<Widget> _signedIn(BuildContext context) {
    final theme = Theme.of(context);
    final last = cloud.lastSync;
    return [
      Text('Signed in as', style: theme.textTheme.bodySmall),
      Text(cloud.user?.email ?? '', style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      Row(
        children: [
          if (cloud.syncing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              cloud.error == null
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              size: 18,
              color: cloud.error == null ? null : theme.colorScheme.error,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              cloud.syncing
                  ? 'Syncing…'
                  : cloud.error != null
                  ? 'Sync failed: ${cloud.error}'
                  : last == null
                  ? 'Not synced yet.'
                  : 'Synced at ${_time(last)}.',
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'Your files and progress sync by themselves: when you sign in, '
        'when you change a file, and every minute and a half.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Icon(
            cloud.sessionStore.keep ? Icons.lock_open : Icons.timer_outlined,
            size: 16,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              cloud.sessionStore.keep
                  ? 'You stay signed in on this device.'
                  : 'You are signed out when Go Dojo is closed.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy
              ? null
              : () {
                  _password.clear();
                  cloud.startPasswordChange();
                },
          icon: const Icon(Icons.password, size: 18),
          label: const Text('Change the password'),
        ),
      ),
    ];
  }

  List<Widget> _recovery() => [
    const Text('Choose a new password for your account.'),
    const SizedBox(height: 16),
    _passwordField(label: 'New password'),
  ];

  List<Widget> _actions(BuildContext context) {
    final close = TextButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Close'),
    );
    if (cloud.recovering) {
      return [
        if (cloud.signedIn)
          TextButton(
            onPressed: cloud.cancelPasswordChange,
            child: const Text('Cancel'),
          )
        else
          close,
        FilledButton(
          onPressed: _busy ? null : _setPassword,
          child: const Text('Save the password'),
        ),
      ];
    }
    if (cloud.signedIn) {
      return [
        TextButton(
          onPressed: _busy ? null : () => _run(cloud.signOut),
          child: const Text('Sign out'),
        ),
        OutlinedButton.icon(
          onPressed: cloud.syncing ? null : cloud.sync,
          icon: const Icon(Icons.sync),
          label: const Text('Sync now'),
        ),
        close,
      ];
    }
    return [
      close,
      TextButton(
        onPressed: _busy ? null : _signUp,
        child: const Text('Create an account'),
      ),
      FilledButton(
        onPressed: _busy ? null : _signIn,
        child: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Sign in'),
      ),
    ];
  }

  void _signIn() {
    if (!_check()) return;
    _run(() => cloud.signIn(_email.text, _password.text, keepSignedIn: _keep));
  }

  void _signUp() {
    if (!_check()) return;
    _run(() async {
      final ready = await cloud.signUp(
        _email.text,
        _password.text,
        keepSignedIn: _keep,
      );
      if (!ready) {
        _info =
            'Account created. Open the e-mail we sent you to confirm it, '
            'then sign in here.';
      }
    });
  }

  void _forgot() {
    if (!_check(password: false)) return;
    _run(() async {
      await cloud.sendPasswordReset(_email.text);
      _info =
          'E-mail sent. Its link opens Go Dojo on the web, where you choose '
          'a new password.';
    });
  }

  void _setPassword() {
    if (_password.text.length < 6) {
      setState(() => _error = 'The password needs at least 6 characters.');
      return;
    }
    _run(() async {
      await cloud.setNewPassword(_password.text);
      _info = 'Password saved.';
    });
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
