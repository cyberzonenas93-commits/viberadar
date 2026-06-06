import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform.dart';
import '../../core/theme/app_theme.dart';
import '../../models/session_state.dart';
import '../../providers/app_state.dart';
import '../../providers/repositories.dart';
import '../mobile/mobile_shell.dart';
import '../shell/vibe_shell.dart';
import '../widgets/ui_kit.dart';
import 'onboarding_screen.dart';
import 'splash_screen.dart';

enum _AuthPhase { splash, onboarding, login }

enum _LoginMode { main, emailSignIn, emailCreate }

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({
    super.key,
    required this.statusMessage,
    this.isDemoMode = false,
  });
  final String statusMessage;
  final bool isDemoMode;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  _AuthPhase _phase = _AuthPhase.splash;
  bool _checkedOnboarding = false;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('onboarding_completed') ?? false;
    if (mounted) {
      setState(() {
        _checkedOnboarding = true;
        _phase = completed ? _AuthPhase.login : _AuthPhase.splash;
      });
    }
  }

  Future<void> _completeOnboarding(List<String> artists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    if (artists.isNotEmpty) {
      await prefs.setStringList('pending_followed_artists', artists);
    }
    if (mounted) setState(() => _phase = _AuthPhase.login);
  }

  bool _syncedArtists = false;

  Future<void> _syncPendingArtists(SessionState session) async {
    if (_syncedArtists) return;
    _syncedArtists = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList('pending_followed_artists');
      if (pending != null && pending.isNotEmpty) {
        await prefs.remove('pending_followed_artists');
        await ref
            .read(userRepositoryProvider)
            .setFollowedArtists(
              userId: session.userId,
              fallbackName: session.displayName,
              artists: pending,
            );
      }
    } catch (e, st) {
      developer.log(
        'Failed to sync pending followed artists',
        name: 'AuthGate',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedOnboarding) {
      return const Scaffold(
        backgroundColor: AppTheme.ink,
        body: Center(child: CircularProgressIndicator(color: AppTheme.cyan)),
      );
    }

    switch (_phase) {
      case _AuthPhase.splash:
        return SplashScreen(
          onFinished: () => setState(() => _phase = _AuthPhase.onboarding),
        );
      case _AuthPhase.onboarding:
        return OnboardingScreen(
          onComplete: (artists) => _completeOnboarding(artists),
        );
      case _AuthPhase.login:
        break;
    }

    final sessionAsync = ref.watch(sessionProvider);
    final session = sessionAsync.value;

    if (sessionAsync.isLoading && session == null) {
      return const Scaffold(
        backgroundColor: AppTheme.ink,
        body: Center(child: CircularProgressIndicator(color: AppTheme.cyan)),
      );
    }

    if (sessionAsync.hasValue) {
      if (session?.isAuthenticated == true) {
        _syncPendingArtists(session!);
      }
      // Require a signed-in session (real account or explicit guest) before the
      // app on every platform — this surfaces onboarding + sign-in / account
      // creation instead of silently admitting an anonymous session. Demo mode
      // (Firebase unavailable) bypasses the gate so the app still works offline.
      if (!widget.isDemoMode && session?.isAuthenticated != true) {
        return _LoginScreen(statusMessage: widget.statusMessage);
      }
      return isMobileForm
          ? const MobileShell()
          : VibeShell(
              statusMessage: widget.statusMessage,
              isDemoMode: widget.isDemoMode,
            );
    }

    return _LoginScreen(statusMessage: widget.statusMessage);
  }
}

// ---------------------------------------------------------------------------
// Login screen — Google, Email/Password, or Anonymous
// ---------------------------------------------------------------------------

class _LoginScreen extends ConsumerStatefulWidget {
  const _LoginScreen({required this.statusMessage});
  final String statusMessage;

  @override
  ConsumerState<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<_LoginScreen> {
  _LoginMode _mode = _LoginMode.main;
  bool _isLoading = false;
  String? _error;
  bool _rememberMe = true;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.42),
            radius: 1.1,
            colors: [Color(0xFF121E31), AppTheme.ink],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              vertical: AppTheme.s10,
              horizontal: AppTheme.s5,
            ),
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(36),
              decoration: AppTheme.glass(
                radius: AppTheme.r2xl,
                glowShadow: AppTheme.glow(
                  AppTheme.violet,
                  blur: 64,
                  spread: 4,
                  opacity: 0.12,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: _mode == _LoginMode.main
                    ? _mainView(theme: theme)
                    : _emailView(theme: theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Logo + brand ──────────────────────────────────────────────────────────

  Widget _logo() => Container(
    width: 78,
    height: 78,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AppTheme.rXl),
      boxShadow: AppTheme.glow(
        AppTheme.cyan,
        blur: 30,
        spread: 1,
        opacity: 0.34,
      ),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rXl),
      child: Image.asset(
        'assets/icon/app_icon.png',
        width: 78,
        height: 78,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    ),
  );

  Widget _brand(ThemeData theme) => Column(
    children: [
      _logo(),
      const SizedBox(height: 22),
      ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [AppTheme.textPrimary, AppTheme.cyan, AppTheme.violet],
        ).createShader(bounds),
        child: Text(
          'VibeRadar',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'DJ Trend Intelligence Platform',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppTheme.textSecondary,
        ),
      ),
    ],
  );

  // ── Error banner ──────────────────────────────────────────────────────────

  Widget _errorBanner(ThemeData theme) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.red.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Colors.redAccent,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.redAccent),
          ),
        ),
      ],
    ),
  );

  // ── Main view ─────────────────────────────────────────────────────────────

  Widget _mainView({required ThemeData theme}) => Column(
    key: const ValueKey('main'),
    mainAxisSize: MainAxisSize.min,
    children: [
      _brand(theme),
      const SizedBox(height: 28),

      // Keep me signed in
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: _rememberMe,
              onChanged: (v) => setState(() => _rememberMe = v ?? true),
              activeColor: AppTheme.violet,
              side: BorderSide(color: AppTheme.edge.withValues(alpha: 0.6)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _rememberMe = !_rememberMe),
            child: const Text(
              'Keep me signed in',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),

      // Google Sign-In
      _PrimaryButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        isLoading: _isLoading,
        icon: Image.network(
          'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
          width: 20,
          height: 20,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.login, size: 20, color: Colors.white),
        ),
        label: 'Continue with Google',
      ),
      const SizedBox(height: 12),

      // Sign in with Apple — iOS only (native flow, works). Web/Android need a
      // real Sign-in-with-Apple key in Firebase; the one configured is an ASC
      // API key, not a Sign-in key — so they're gated off until that's swapped.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
        SizedBox(
          width: double.infinity,
          child: SignInWithAppleButton(
            onPressed: _isLoading ? () {} : _signInWithApple,
            style: SignInWithAppleButtonStyle.white,
            height: 52,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        const SizedBox(height: 12),
      ],

      // Email sign-in
      _OutlineButton(
        onPressed: _isLoading
            ? null
            : () => setState(() {
                _mode = _LoginMode.emailSignIn;
                _error = null;
              }),
        icon: const Icon(Icons.mail_outline_rounded, size: 20),
        label: 'Sign in with Email',
      ),
      const SizedBox(height: 12),

      // Guest / anonymous — desktop only. On phones, pairing + AI require a
      // real account (claimPairing rejects anonymous users), so a guest could
      // enter the app but couldn't actually use it. Hide the option on mobile.
      if (!isMobileForm) ...[
        // Divider
        Row(
          children: [
            const Expanded(child: Divider(color: AppTheme.hairlineStrong)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or',
                style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
              ),
            ),
            const Expanded(child: Divider(color: AppTheme.hairlineStrong)),
          ],
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isLoading ? null : _signInAnonymously,
          child: Text(
            'Continue as Guest',
            style: TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w600),
          ),
        ),
      ],

      if (_error != null) ...[const SizedBox(height: 16), _errorBanner(theme)],

      const SizedBox(height: 8),
      TextButton(
        onPressed: () => launchUrl(
          Uri.parse('https://viberadar-462b8.web.app/privacy.html'),
          mode: LaunchMode.externalApplication,
        ),
        child: Text(
          'Privacy Policy',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppTheme.textTertiary,
            fontSize: 11,
          ),
        ),
      ),
      Text(
        'Built by Angelo Nartey.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppTheme.textTertiary,
          fontSize: 10,
        ),
      ),
    ],
  );

  // ── Email view ────────────────────────────────────────────────────────────

  Widget _emailView({required ThemeData theme}) => Column(
    key: const ValueKey('email'),
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          IconButton(
            onPressed: () => setState(() {
              _mode = _LoginMode.main;
              _error = null;
            }),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 8),
          Text(
            _mode == _LoginMode.emailCreate ? 'Create Account' : 'Sign In',
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),

      if (_mode == _LoginMode.emailCreate) ...[
        _textField(
          controller: _nameCtrl,
          hint: 'Display name',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 12),
      ],

      _textField(
        controller: _emailCtrl,
        hint: 'Email address',
        icon: Icons.mail_outline,
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 12),
      _textField(
        controller: _passwordCtrl,
        hint: 'Password',
        icon: Icons.lock_outline,
        obscure: _obscurePassword,
        suffix: IconButton(
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: AppTheme.textSecondary,
            size: 18,
          ),
        ),
      ),

      // Remember me checkbox
      Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: _rememberMe,
              onChanged: (v) => setState(() => _rememberMe = v ?? true),
              activeColor: AppTheme.violet,
              side: BorderSide(color: AppTheme.edge.withValues(alpha: 0.6)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _rememberMe = !_rememberMe),
            child: const Text(
              'Keep me signed in',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),

      _PrimaryButton(
        onPressed: _isLoading
            ? null
            : (_mode == _LoginMode.emailCreate
                  ? _createAccount
                  : _signInWithEmail),
        isLoading: _isLoading,
        label: _mode == _LoginMode.emailCreate ? 'Create Account' : 'Sign In',
      ),
      const SizedBox(height: 12),

      TextButton(
        onPressed: () => setState(() {
          _mode = _mode == _LoginMode.emailCreate
              ? _LoginMode.emailSignIn
              : _LoginMode.emailCreate;
          _error = null;
        }),
        child: Text(
          _mode == _LoginMode.emailCreate
              ? 'Already have an account? Sign in'
              : "Don't have an account? Create one",
          style: TextStyle(color: AppTheme.cyan, fontSize: 13),
        ),
      ),

      if (_error != null) ...[const SizedBox(height: 12), _errorBanner(theme)],
    ],
  );

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffix,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    keyboardType: keyboardType,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppTheme.textTertiary),
      prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 18),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppTheme.panelRaised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.hairlineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.hairlineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.cyan, width: 1.5),
      ),
    ),
  );

  // ── Auth actions ──────────────────────────────────────────────────────────

  Future<void> _saveRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', _rememberMe);
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref.read(sessionRepositoryProvider).signInWithGoogle();
      await _saveRememberMe();
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref.read(sessionRepositoryProvider).signInWithApple();
      await _saveRememberMe();
    } on SignInWithAppleAuthorizationException catch (e) {
      // User cancelling the Apple sheet is not an error worth showing.
      if (e.code != AuthorizationErrorCode.canceled && mounted) {
        setState(() => _error = _friendly(e));
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInAnonymously() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref.read(sessionRepositoryProvider).signInAnonymously();
      await _saveRememberMe();
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithEmail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionRepositoryProvider)
          .signInWithEmail(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      await _saveRememberMe();
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createAccount() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionRepositoryProvider)
          .createAccount(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            displayName: _nameCtrl.text.trim(),
          );
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendly(Object error) {
    final msg = error.toString();
    if (msg.contains('network-request-failed')) {
      return 'Network error. Check your connection.';
    }
    if (msg.contains('popup-closed-by-user') || msg.contains('canceled')) {
      return 'Sign-in was cancelled.';
    }
    if (msg.contains('too-many-requests')) {
      return 'Too many attempts. Wait a moment.';
    }
    if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
      return 'Incorrect email or password.';
    }
    if (msg.contains('user-not-found')) {
      return 'No account found with this email.';
    }
    if (msg.contains('email-already-in-use')) {
      return 'An account with this email already exists.';
    }
    if (msg.contains('weak-password')) {
      return 'Password must be at least 6 characters.';
    }
    if (msg.contains('invalid-email')) return 'Invalid email address.';
    if (msg.contains('keychain')) {
      return 'Google Sign-In keychain error — try Email or Guest sign-in instead.';
    }
    if (msg.contains('ID token')) {
      return 'Google Sign-In token error — try Email or Guest sign-in.';
    }
    if (msg.contains('sign_in_failed') || msg.contains('sign-in-failed')) {
      return 'Sign-in failed: $msg';
    }
    return 'Sign-in failed. Please try again.';
  }
}

// ---------------------------------------------------------------------------
// Reusable button widgets
// ---------------------------------------------------------------------------

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.onPressed,
    required this.label,
    this.isLoading = false,
    this.icon,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool isLoading;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return PressableScale(
      onTap: enabled ? onPressed : null,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Container(
          width: double.infinity,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppTheme.ctaGradient,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            boxShadow: enabled
                ? AppTheme.glow(AppTheme.violet, blur: 22, opacity: 0.42)
                : null,
          ),
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      icon!,
                      const SizedBox(width: AppTheme.s2 + 2),
                    ],
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.onPressed,
    required this.label,
    this.icon,
  });
  final VoidCallback? onPressed;
  final String label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon ?? const SizedBox.shrink(),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          foregroundColor: Colors.white,
          side: const BorderSide(color: AppTheme.hairlineStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
          ),
        ),
      ),
    );
  }
}
