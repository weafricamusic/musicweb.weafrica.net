import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../app/utils/user_facing_error.dart';
import 'creator_profile_provisioner.dart';
import 'user_profile_provisioner.dart';
import 'user_role.dart';
import 'user_role_intent_store.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  static const Color _primary = Color(0xFFFF6B2C);
  static const Color _primaryDark = Color(0xFFE55A1F);
  static const Color _gold = Color(0xFFFFB347);
  static const Color _purple = Color(0xFF7B2D8E);
  static const Color _teal = Color(0xFF00C9A7);
  static const Color _blue = Color(0xFF4F46E5);
  static const Color _pink = Color(0xFFEC4899);
  static const Color _dark = Color(0xFF0A0A0F);
  static const Color _card = Color(0xFF12121A);
  static const Color _input = Color(0xFF1A1A28);
  static const Color _border = Color(0xFF2A2A3E);
  static const Color _textSecondary = Color(0xFFA0A0B8);
  static const Color _textMuted = Color(0xFF6B6B80);
  static const Color _facebook = Color(0xFF1877F2);

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscure = true;
  bool _rememberMe = false;
  bool _isCreateMode = false;
  String? _error;

  UserRole _roleIntent = UserRole.artist;

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();

    UserRoleIntentStore.getRole().then((value) {
      if (!mounted) return;
      setState(() {
        _roleIntent = value == UserRole.consumer ? UserRole.artist : value;
      });
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
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
        SnackBar(
          content: Text(
            'Could not enable ${_roleIntent.label} mode yet. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _primaryDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
  }

  Future<void> _completePostSignInSetup() async {
    await UserProfileProvisioner.ensureForCurrentUser(intent: _roleIntent);
    await _provisionCreatorProfileIfNeeded();
  }

  String get _roleName {
    switch (_roleIntent) {
      case UserRole.artist:
        return 'Artist';
      case UserRole.dj:
        return 'DJ';
      case UserRole.consumer:
        return 'Fan';
    }
  }

  Color get _roleColor {
    switch (_roleIntent) {
      case UserRole.artist:
        return _primary;
      case UserRole.dj:
        return _purple;
      case UserRole.consumer:
        return _teal;
    }
  }

  List<Color> get _buttonGradient {
    switch (_roleIntent) {
      case UserRole.artist:
        return const [_primary, _primaryDark];
      case UserRole.dj:
        return const [_purple, _blue];
      case UserRole.consumer:
        return const [_teal, Color(0xFF0891B2)];
    }
  }

  String get _roleInfo {
    switch (_roleIntent) {
      case UserRole.artist:
        return 'Artist: Upload tracks, host live sessions, earn from streams & fan gifts';
      case UserRole.dj:
        return 'DJ: Stream live mixes, battle other DJs, build your fanbase with tips';
      case UserRole.consumer:
        return 'Fan: Get personalized playlists, watch live battles, support artists';
    }
  }

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await UserRoleIntentStore.setRole(_roleIntent);

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      await _completePostSignInSetup();
    } on FirebaseAuthException catch (e, st) {
      UserFacingError.log('LoginScreen._signInWithEmail(FirebaseAuth)', e, st);
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.message(
          e.message ?? e.code,
          fallback: 'Sign in failed. Please try again.',
        );
      });
    } catch (e, st) {
      UserFacingError.log('LoginScreen._signInWithEmail', e, st);
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.message(
          e,
          fallback: 'Sign in failed. Please try again.',
        );
      });
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
      await UserRoleIntentStore.setRole(_roleIntent);

      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      await _completePostSignInSetup();
      await cred.user?.sendEmailVerification();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Account created. Verification email sent.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green.shade700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    } on FirebaseAuthException catch (e, st) {
      UserFacingError.log('LoginScreen._createAccount(FirebaseAuth)', e, st);
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.message(
          e.message ?? e.code,
          fallback: 'Could not create account. Please try again.',
        );
      });
    } catch (e, st) {
      UserFacingError.log('LoginScreen._createAccount', e, st);
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.message(
          e,
          fallback: 'Could not create account. Please try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email address first.');
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
        SnackBar(
          content: const Text('Password reset link sent. Check your email.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green.shade700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    } on FirebaseAuthException catch (e, st) {
      UserFacingError.log('LoginScreen._forgotPassword(FirebaseAuth)', e, st);
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.message(
          e.message ?? e.code,
          fallback: 'Could not send reset email. Please try again.',
        );
      });
    } catch (e, st) {
      UserFacingError.log('LoginScreen._forgotPassword', e, st);
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.message(
          e,
          fallback: 'Could not send reset email. Please try again.',
        );
      });
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
      await UserRoleIntentStore.setRole(_roleIntent);

      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        provider.setCustomParameters({'prompt': 'select_account'});
        try {
          await FirebaseAuth.instance.signInWithPopup(provider);
        } catch (popupError) {
          // Fallback to redirect if popup is blocked
          debugPrint('Popup failed, trying redirect: $popupError');
          await FirebaseAuth.instance.signInWithRedirect(provider);
        }
      } else {
        await GoogleSignIn.instance.initialize();
        final googleUser = await GoogleSignIn.instance.authenticate();
        final googleAuth = googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );

        await FirebaseAuth.instance.signInWithCredential(credential);
      }

      await _completePostSignInSetup();
    } on FirebaseAuthException catch (e, st) {
      UserFacingError.log('LoginScreen._signInWithGoogle(FirebaseAuth)', e, st);
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.message(
          e.message ?? e.code,
          fallback: 'Google sign in failed. Please try again.',
        );
      });
    } catch (e, st) {
      UserFacingError.log('LoginScreen._signInWithGoogle', e, st);
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.message(
          e,
          fallback: 'Google sign in failed. Please try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithFacebook() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Facebook login will be enabled after Facebook app setup.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _facebook,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<void> _submit() async {
    if (_isCreateMode) {
      await _createAccount();
    } else {
      await _signInWithEmail();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Container(
                      width: double.infinity,
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      color: _card,
                      child: isWide
                          ? Row(
                              children: [
                                Expanded(
                                  child: _buildVisualPanel(isWide: true),
                                ),
                                SizedBox(width: 460, child: _buildFormPanel()),
                              ],
                            )
                          : SingleChildScrollView(
                              child: Column(
                                children: [
                                  _buildVisualPanel(isWide: false),
                                  _buildFormPanel(),
                                ],
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisualPanel({required bool isWide}) {
    return Container(
      constraints: BoxConstraints(minHeight: isWide ? double.infinity : 280),
      padding: EdgeInsets.fromLTRB(
        isWide ? 50 : 24,
        isWide ? 40 : 28,
        isWide ? 50 : 24,
        isWide ? 50 : 36,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0x1FFF6B2C), Color(0x147B2D8E), Color(0x1000C9A7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: -80,
            right: -60,
            child: _GlowOrb(color: _primary, size: 280),
          ),
          const Positioned(
            bottom: -80,
            left: -70,
            child: _GlowOrb(color: _purple, size: 250),
          ),
          const Positioned(
            top: 160,
            left: 180,
            child: _GlowOrb(color: _teal, size: 190),
          ),
          Positioned(
            top: isWide ? 130 : 65,
            left: isWide ? 40 : null,
            right: isWide ? null : 42,
            child: const _FloatingBubble(
              emoji: '🎤',
              size: 78,
              colors: [_primary, _gold],
            ),
          ),
          Positioned(
            top: isWide ? 240 : 145,
            right: isWide ? 90 : null,
            left: isWide ? null : 28,
            child: const _FloatingBubble(
              emoji: '🎧',
              size: 68,
              colors: [_purple, _blue],
              delay: 300,
            ),
          ),
          Positioned(
            bottom: isWide ? 175 : 35,
            left: isWide ? 125 : null,
            right: isWide ? null : 90,
            child: const _FloatingBubble(
              emoji: '🎶',
              size: 62,
              colors: [_teal, _gold],
              delay: 600,
            ),
          ),
          Positioned(
            top: isWide ? 210 : 115,
            right: isWide ? 35 : 145,
            child: const _FloatingBubble(
              emoji: '❤️',
              size: 54,
              colors: [_pink, _primary],
              delay: 900,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLogo(),
                SizedBox(height: isWide ? 120 : 70),
              Text(
                'Listeners, Artists\n& DJs Together',
                style: TextStyle(
                  color: Colors.white,
                  height: 1.12,
                  fontSize: isWide ? 42 : 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: isWide ? 390 : double.infinity,
                child: const Text(
                  'Login to discover music, upload songs, stream live, battle DJs, and support African talent.',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 15,
                    height: 1.65,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Row(
                children: [
                  _StatBlock(number: '2M+', label: 'Active Users'),
                  SizedBox(width: 30),
                  _StatBlock(number: '50K+', label: 'Artists'),
                  SizedBox(width: 30),
                  _StatBlock(number: '10M+', label: 'Tracks'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_primary, _gold],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _primary.withOpacity(0.30),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Text('🎵', style: TextStyle(fontSize: 21)),
          ),
        ),
        const SizedBox(width: 12),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            children: [
              TextSpan(text: 'We'),
              TextSpan(
                text: 'Africa',
                style: TextStyle(color: _primary),
              ),
              TextSpan(text: ' Music'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 38),
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Welcome back',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _isCreateMode
                            ? 'Already have an account? '
                            : "Don't have an account? ",
                        style: const TextStyle(
                          color: _textSecondary,
                          fontSize: 15,
                        ),
                      ),
                      GestureDetector(
                        onTap: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _isCreateMode = !_isCreateMode;
                                  _error = null;
                                });
                              },
                        child: Text(
                          _isCreateMode ? 'Sign in' : 'Sign up free',
                          style: const TextStyle(
                            color: _primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _buildRoleSection(),
                  const SizedBox(height: 22),
                  _buildInput(
                    controller: _emailController,
                    label: 'Email Address',
                    hint: 'you@example.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) return 'Email is required.';
                      if (!email.contains('@')) return 'Enter a valid email.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildInput(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Enter your password',
                    icon: Icons.lock_outline,
                    obscureText: _obscure,
                    suffix: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: _textMuted,
                        size: 20,
                      ),
                    ),
                    validator: (value) {
                      final password = value ?? '';
                      if (password.isEmpty) return 'Password is required.';
                      if (_isCreateMode && password.length < 6) {
                        return 'Password must be at least 6 characters.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildOptionsRow(),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4757).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFF4757).withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFFF7B88),
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  _buildMainButton(),
                  const SizedBox(height: 22),
                  _buildDivider(),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSocialButton(
                          label: 'Google',
                          icon: '🌐',
                          onTap: _isLoading ? null : _signInWithGoogle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSocialButton(
                          label: 'Facebook',
                          icon: '📘',
                          borderColor: _facebook,
                          onTap: _isLoading ? null : _signInWithFacebook,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.only(top: 18),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: _border)),
                    ),
                    child: const Center(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'Prefer phone? '),
                            TextSpan(
                              text: 'Login with phone number',
                              style: TextStyle(
                                color: _primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        style: TextStyle(color: _textSecondary, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          const Text(
            'CHOOSE YOUR ROLE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 340;
              if (compact) {
                return Column(
                  children: [
                    _roleCard(
                      UserRole.artist,
                      'Artist',
                      'Upload & perform',
                      '🎤',
                    ),
                    const SizedBox(height: 10),
                    _roleCard(UserRole.dj, 'DJ', 'Mix & stream live', '🎧'),
                    const SizedBox(height: 10),
                    _roleCard(
                      UserRole.consumer,
                      'Fan',
                      'Listen & support',
                      '🎶',
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: _roleCard(
                      UserRole.artist,
                      'Artist',
                      'Upload & perform',
                      '🎤',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _roleCard(
                      UserRole.dj,
                      'DJ',
                      'Mix & stream live',
                      '🎧',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _roleCard(
                      UserRole.consumer,
                      'Fan',
                      'Listen & support',
                      '🎶',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _roleColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _roleColor.withOpacity(0.18)),
            ),
            child: Text(
              _roleInfo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleCard(UserRole role, String name, String desc, String emoji) {
    final active = _roleIntent == role;
    final color = role == UserRole.artist
        ? _primary
        : role == UserRole.dj
        ? _purple
        : _teal;

    return GestureDetector(
      onTap: _isLoading ? null : () => _setRoleIntent(role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.08) : _input,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? color : _border, width: 2),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.16),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            if (active)
              Positioned(
                top: -28,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'SELECTED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(height: 8),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          validator: validator,
          enabled: !_isLoading,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: _textMuted),
            prefixIcon: Icon(icon, color: _textMuted, size: 20),
            suffixIcon: suffix,
            filled: true,
            fillColor: _input,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _border, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _roleColor, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFFF4757), width: 2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFFF4757), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsRow() {
    return Row(
      children: [
        GestureDetector(
          onTap: _isLoading
              ? null
              : () => setState(() => _rememberMe = !_rememberMe),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _rememberMe ? _roleColor : _input,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _rememberMe ? _roleColor : _border,
                    width: 2,
                  ),
                ),
                child: _rememberMe
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 10),
              const Text(
                'Remember me',
                style: TextStyle(color: _textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _isLoading ? null : _forgotPassword,
          child: const Text(
            'Forgot password?',
            style: TextStyle(
              color: _primary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _submit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _buttonGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _roleColor.withOpacity(0.35),
              blurRadius: 34,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  _isCreateMode
                      ? 'Create $_roleName Account'
                      : 'Sign In as $_roleName',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Row(
      children: [
        Expanded(child: Divider(color: _border)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or continue with',
            style: TextStyle(
              color: _textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: _border)),
      ],
    );
  }

  Widget _buildSocialButton({
    required String label,
    required String icon,
    required VoidCallback? onTap,
    Color? borderColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          color: _input,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor?.withOpacity(0.65) ?? _border,
            width: 2,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.13),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.22),
              blurRadius: 80,
              spreadRadius: 35,
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingBubble extends StatefulWidget {
  const _FloatingBubble({
    required this.emoji,
    required this.size,
    required this.colors,
    this.delay = 0,
  });

  final String emoji;
  final double size;
  final List<Color> colors;
  final int delay;

  @override
  State<_FloatingBubble> createState() => _FloatingBubbleState();
}

class _FloatingBubbleState extends State<_FloatingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _float;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );

    _float = Tween<double>(
      begin: 0,
      end: -18,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _float,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _float.value),
          child: child,
        );
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: widget.colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.32),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Center(
          child: Text(
            widget.emoji,
            style: TextStyle(fontSize: widget.size * 0.36),
          ),
        ),
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B6B80),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
