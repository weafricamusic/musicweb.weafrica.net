import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../app/theme.dart';
import '../../app/utils/user_facing_error.dart';
import '../../app/widgets/gradient_button.dart';
import '../../app/widgets/weafrica_brand_mark.dart';
import 'creator_profile_provisioner.dart';
import 'user_profile_provisioner.dart';
import 'user_role.dart';
import 'user_role_intent_store.dart';
import 'web_auth_session.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscure = true;
  String? _error;

  UserRole _roleIntent = UserRole.consumer;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // Load the last selected intent so the user doesn't have to re-pick each time.
    UserRoleIntentStore.getRole().then((value) {
      if (!mounted) return;
      setState(() => _roleIntent = value);
    });
  }

  Future<void> _setRoleIntent(UserRole role) async {
    setState(() => _roleIntent = role);
    await UserRoleIntentStore.setRole(role);
  }

  Future<void> _provisionCreatorProfileIfNeeded() async {
    if (_roleIntent == UserRole.consumer) return;

    try {
      await CreatorProfileProvisioner.ensureForCurrentUser(intent: _roleIntent);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not enable ${_roleIntent.label} mode yet. Please try again.')),
      );
    }
  }

  Future<void> _completePostSignInSetup() async {
    await UserProfileProvisioner.ensureForCurrentUser(intent: _roleIntent);
    await _provisionCreatorProfileIfNeeded();
  }

  bool _shouldFallbackToRedirect(FirebaseAuthException error) {
    if (!kIsWeb) return false;
    return const <String>{
      'popup-blocked',
      'operation-not-supported-in-this-environment',
    }.contains(error.code);
  }

  Widget _roleIntentSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign in as',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<UserRole>(
          segments: const [
            ButtonSegment<UserRole>(
              value: UserRole.consumer,
              icon: Icon(Icons.headphones),
              label: Text('Listener'),
            ),
            ButtonSegment<UserRole>(
              value: UserRole.artist,
              icon: Icon(Icons.mic),
              label: Text('Artist'),
            ),
            ButtonSegment<UserRole>(
              value: UserRole.dj,
              icon: Icon(Icons.graphic_eq),
              label: Text('DJ'),
            ),
          ],
          selected: <UserRole>{_roleIntent},
          onSelectionChanged: (set) {
            final role = set.isEmpty ? UserRole.consumer : set.first;
            _setRoleIntent(role);
          },
          showSelectedIcon: false,
          style: ButtonStyle(
            side: WidgetStateProperty.all(const BorderSide(color: AppColors.border)),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return AppColors.surface2;
              return AppColors.surface;
            }),
            foregroundColor: WidgetStateProperty.all(AppColors.text),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Ensure intent is persisted before auth state changes.
      await UserRoleIntentStore.setRole(_roleIntent);
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _identifierController.text.trim(),
        password: _passwordController.text,
      );

      await _completePostSignInSetup();
    } on FirebaseAuthException catch (e, st) {
      UserFacingError.log('LoginScreen._signInWithEmail(FirebaseAuth)', e, st);
      if (!mounted) return;
      setState(
        () => _error = UserFacingError.message(
          e.message ?? e.code,
          fallback: 'Sign in failed. Please try again.',
        ),
      );
    } catch (e, st) {
      UserFacingError.log('LoginScreen._signInWithEmail', e, st);
      if (!mounted) return;
      setState(
        () => _error = UserFacingError.message(
          e,
          fallback: 'Sign in failed. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Ensure intent is persisted before auth state changes.
      await UserRoleIntentStore.setRole(_roleIntent);
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _identifierController.text.trim(),
        password: _passwordController.text,
      );

      await UserProfileProvisioner.ensureForCurrentUser(intent: _roleIntent);

      // If the user is creating an Artist/DJ account, try to provision a basic
      // creator profile immediately. (Non-fatal if blocked by Supabase grants.)
      await _provisionCreatorProfileIfNeeded();

      // Force email verification for email/password accounts.
      await cred.user?.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent. Please verify to continue.')),
      );
    } on FirebaseAuthException catch (e, st) {
      UserFacingError.log('LoginScreen._createAccount(FirebaseAuth)', e, st);
      if (!mounted) return;
      setState(
        () => _error = UserFacingError.message(
          e.message ?? e.code,
          fallback: 'Could not create account. Please try again.',
        ),
      );
    } catch (e, st) {
      UserFacingError.log('LoginScreen._createAccount', e, st);
      if (!mounted) return;
      setState(
        () => _error = UserFacingError.message(
          e,
          fallback: 'Could not create account. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _identifierController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent')),
      );
    } on FirebaseAuthException catch (e, st) {
      UserFacingError.log('LoginScreen._forgotPassword(FirebaseAuth)', e, st);
      if (!mounted) return;
      setState(
        () => _error = UserFacingError.message(
          e.message ?? e.code,
          fallback: 'Could not send reset email. Please try again.',
        ),
      );
    } catch (e, st) {
      UserFacingError.log('LoginScreen._forgotPassword', e, st);
      if (!mounted) return;
      setState(
        () => _error = UserFacingError.message(
          e,
          fallback: 'Could not send reset email. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Ensure intent is persisted before auth state changes.
      await UserRoleIntentStore.setRole(_roleIntent);
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        await WebAuthSession.ensurePersistence();

        try {
          await FirebaseAuth.instance.signInWithPopup(provider);
          await _completePostSignInSetup();
        } on FirebaseAuthException catch (e) {
          if (_shouldFallbackToRedirect(e)) {
            await FirebaseAuth.instance.signInWithRedirect(provider);
            return;
          }
          rethrow;
        }
        return;
      }

      await GoogleSignIn.instance.initialize();
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      await _completePostSignInSetup();
    } on FirebaseAuthException catch (e, st) {
      UserFacingError.log('LoginScreen._signInWithGoogle(FirebaseAuth)', e, st);
      if (!mounted) return;
      setState(
        () => _error = UserFacingError.message(
          e.message ?? e.code,
          fallback: 'Sign in failed. Please try again.',
        ),
      );
    } catch (e, st) {
      UserFacingError.log('LoginScreen._signInWithGoogle', e, st);
      if (!mounted) return;
      setState(
        () => _error = UserFacingError.message(
          e,
          fallback: 'Sign in failed. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _socialButton({
    Key? key,
    required Widget icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: OutlinedButton.icon(
          key: key,
        onPressed: onPressed,
        icon: icon,
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.border),
          backgroundColor: AppColors.surface2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    minHeight: (constraints.maxHeight - 40).clamp(0, double.infinity),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: const WeAfricaBrandMark(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'WeAfrica\nMusic',
                        textAlign: TextAlign.left,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              height: 0.95,
                            ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Discover Africa\'s sound',
                        style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 28),
                      const SizedBox(height: 16),

                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _roleIntentSelector(),
                                const SizedBox(height: 16),

                                _socialButton(
                                  key: const Key('login_google'),
                                  icon: const Icon(Icons.g_mobiledata, size: 24),
                                  label: 'Continue with Google',
                                  onPressed: _isLoading ? null : _signInWithGoogle,
                                ),
                                const SizedBox(height: 12),

                                Row(
                                  children: [
                                    const Expanded(child: Divider(color: AppColors.border)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      child: Text(
                                        'or',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(color: AppColors.textMuted),
                                      ),
                                    ),
                                    const Expanded(child: Divider(color: AppColors.border)),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                TextFormField(
                                  key: const Key('login_email'),
                                  controller: _identifierController,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email, AutofillHints.username],
                                  decoration: const InputDecoration(
                                    labelText: 'Email / Phone',
                                    hintText: 'you@example.com',
                                  ),
                                  validator: (v) {
                                    final value = (v ?? '').trim();
                                    if (value.isEmpty) return 'Email or phone is required';
                                    // Current auth backend uses Firebase email/password.
                                    // Keep validation friendly while still allowing the "Email / Phone" field.
                                    if (!value.contains('@')) return 'Enter a valid email address';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  key: const Key('login_password'),
                                  controller: _passwordController,
                                  autofillHints: const [AutofillHints.password],
                                  obscureText: _obscure,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(() => _obscure = !_obscure),
                                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                    ),
                                  ),
                                  validator: (v) {
                                    final value = v ?? '';
                                    if (value.isEmpty) return 'Password is required';
                                    if (value.length < 6) return 'Use at least 6 characters';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    key: const Key('login_forgot_password'),
                                    onPressed: _isLoading ? null : _forgotPassword,
                                    child: const Text('Forgot password?'),
                                  ),
                                ),

                                if (_error != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFFF6B6B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),

                                GradientButton(
                                  key: const Key('login_submit'),
                                  isLoading: _isLoading,
                                  onPressed: _isLoading ? null : _signInWithEmail,
                                  child: Text(
                                    'Login',
                                    style: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 52,
                                  child: OutlinedButton(
                                    key: const Key('login_create_account'),
                                    onPressed: _isLoading ? null : _createAccount,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.text,
                                      side: const BorderSide(color: AppColors.border),
                                      backgroundColor: AppColors.surface2,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    child: const Text('Create account', style: TextStyle(fontWeight: FontWeight.w900)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
