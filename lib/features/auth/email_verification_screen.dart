import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/utils/user_facing_error.dart';
import 'auth_actions.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _isLoading = false;
  String? _error;

  Timer? _pollTimer;
  DateTime? _lastSentAt;

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();

    // Poll occasionally so the UI updates after the user verifies in email.
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      if (!mounted) return;
      final u = _user;
      if (u == null) return;
      if (u.emailVerified) return;
      try {
        await u.reload();
      } catch (_) {
        // Ignore; user might be offline.
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  bool get _canResend {
    final last = _lastSentAt;
    if (last == null) return true;
    return DateTime.now().difference(last) > const Duration(seconds: 30);
  }

  Future<void> _resend() async {
    final u = _user;
    if (u == null) return;

    if (!_canResend) {
      setState(() => _error = 'Please wait a moment before resending.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await u.sendEmailVerification();
      _lastSentAt = DateTime.now();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent.')),
      );
    } on FirebaseAuthException catch (e, st) {
      UserFacingError.log('EmailVerificationScreen._resend(FirebaseAuth)', e, st);
      setState(
        () => _error = UserFacingError.message(
          e.message ?? e.code,
          fallback: 'Could not resend email. Please try again.',
        ),
      );
    } catch (e, st) {
      UserFacingError.log('EmailVerificationScreen._resend', e, st);
      setState(
        () => _error = UserFacingError.message(
          e,
          fallback: 'Could not resend email. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkNow() async {
    final u = _user;
    if (u == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await u.reload();
    } catch (e, st) {
      UserFacingError.log('EmailVerificationScreen._checkNow', e, st);
      setState(
        () => _error = UserFacingError.message(
          e,
          fallback: 'Could not refresh verification status. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    // AuthGate (using userChanges) will swap to the app once verified.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final email = user?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify your email'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : () => AuthActions.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'One more step',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'We sent a verification link to:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              email.isEmpty ? '(no email on account)' : email,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              'Open your email and tap the verification link. Then come back and press “I verified”.\n\nTip: check Spam/Junk if you don\'t see it.',
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _resend,
                    child: Text(_canResend ? 'Resend email' : 'Resend (wait…)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isLoading ? null : _checkNow,
                    child: Text(_isLoading ? 'Checking…' : 'I verified'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (user != null) ...[
              Row(
                children: [
                  const Text('Status: '),
                  Text(
                    user.emailVerified ? 'Verified' : 'Not verified',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: user.emailVerified ? const Color(0xFF41D17B) : const Color(0xFFFFB020),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
