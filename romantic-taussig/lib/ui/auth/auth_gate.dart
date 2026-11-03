import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../models/session_state.dart';
import '../../providers/app_state.dart';
import '../../providers/repositories.dart';
import '../shell/vibe_shell.dart';
import 'onboarding_screen.dart';
import 'splash_screen.dart';

enum _AuthPhase { splash, onboarding, login }
enum _LoginMode { main, emailSignIn, emailCreate }

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key, required this.statusMessage});
  final String statusMessage;

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
        await ref.read(userRepositoryProvider).setFollowedArtists(
              userId: session.userId,
              fallbackName: session.displayName,
              artists: pending,
            );
      }
    } catch (_) {}
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
        return OnboardingScreen(onComplete: (artists) => _completeOnboarding(artists));
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

    if (session?.isAuthenticated == true) {
      _syncPendingArtists(session!);
      return VibeShell(statusMessage: widget.statusMessage);
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
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppTheme.edge),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.violet.withValues(alpha: 0.08),
                  blurRadius: 60,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _mode == _LoginMode.main
                  ? _mainView(theme: theme)
                  : _emailView(theme: theme),
            ),
          ),
        ),
      ),
    );
  }

  // ── Logo + brand ──────────────────────────────────────────────────────────

  Widget _logo() => Container(
    width: 72,
    height: 72,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppTheme.violet, AppTheme.pink, AppTheme.cyan],
      ),
      boxShadow: [
        BoxShadow(
          color: AppTheme.violet.withValues(alpha: 0.3),
          blurRadius: 24,
          spreadRadius: 2,
        ),
      ],
    ),
    child: const Padding(
      padding: EdgeInsets.all(10),
      child: CustomPaint(
        painter: _AuthLogoPainter(),
        child: SizedBox.expand(),
      ),
    ),
  );

  Widget _brand(ThemeData theme) => Column(
    children: [
      _logo(),
      const SizedBox(height: 24),
      Text(
        'VibeRadar',
        style: theme.textTheme.headlineMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
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
        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
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
            width: 20, height: 20,
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
            child: const Text('Keep me signed in', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
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
          errorBuilder: (_, __, ___) => const Icon(Icons.login, size: 20, color: Colors.white),
        ),
        label: 'Continue with Google',
      ),
      const SizedBox(height: 12),

      // Email sign-in
      _OutlineButton(
        onPressed: _isLoading ? null : () => setState(() { _mode = _LoginMode.emailSignIn; _error = null; }),
        icon: const Icon(Icons.mail_outline_rounded, size: 20),
        label: 'Sign in with Email',
      ),
      const SizedBox(height: 12),

      // Divider
      Row(
        children: [
          const Expanded(child: Divider(color: AppTheme.edge)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('or', style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
          ),
          const Expanded(child: Divider(color: AppTheme.edge)),
        ],
      ),
      const SizedBox(height: 12),

      // Guest / anonymous
      TextButton(
        onPressed: _isLoading ? null : _signInAnonymously,
        child: Text(
          'Continue as Guest',
          style: TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w600),
        ),
      ),

      if (_error != null) ...[const SizedBox(height: 16), _errorBanner(theme)],

      const SizedBox(height: 16),
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
            onPressed: () => setState(() { _mode = _LoginMode.main; _error = null; }),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 8),
          Text(
            _mode == _LoginMode.emailCreate ? 'Create Account' : 'Sign In',
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      const SizedBox(height: 24),

      if (_mode == _LoginMode.emailCreate) ...[
        _textField(controller: _nameCtrl, hint: 'Display name', icon: Icons.person_outline),
        const SizedBox(height: 12),
      ],

      _textField(controller: _emailCtrl, hint: 'Email address', icon: Icons.mail_outline, keyboardType: TextInputType.emailAddress),
      const SizedBox(height: 12),
      _textField(
        controller: _passwordCtrl,
        hint: 'Password',
        icon: Icons.lock_outline,
        obscure: _obscurePassword,
        suffix: IconButton(
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppTheme.textSecondary, size: 18),
        ),
      ),

      // Remember me checkbox
      Row(
        children: [
          SizedBox(
            width: 20, height: 20,
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
            child: const Text('Keep me signed in', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ),
        ],
      ),
      const SizedBox(height: 16),

      _PrimaryButton(
        onPressed: _isLoading ? null : (_mode == _LoginMode.emailCreate ? _createAccount : _signInWithEmail),
        isLoading: _isLoading,
        label: _mode == _LoginMode.emailCreate ? 'Create Account' : 'Sign In',
      ),
      const SizedBox(height: 12),

      TextButton(
        onPressed: () => setState(() {
          _mode = _mode == _LoginMode.emailCreate ? _LoginMode.emailSignIn : _LoginMode.emailCreate;
          _error = null;
        }),
        child: Text(
          _mode == _LoginMode.emailCreate ? 'Already have an account? Sign in' : "Don't have an account? Create one",
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
        borderSide: BorderSide(color: AppTheme.edge),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.edge),
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
    setState(() { _isLoading = true; _error = null; });
    try {
      await ref.read(sessionRepositoryProvider).signInWithGoogle();
      await _saveRememberMe();
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInAnonymously() async {
    setState(() { _isLoading = true; _error = null; });
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
    setState(() { _isLoading = true; _error = null; });
    try {
      await ref.read(sessionRepositoryProvider).signInWithEmail(
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
    setState(() { _isLoading = true; _error = null; });
    try {
      await ref.read(sessionRepositoryProvider).createAccount(
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
    if (msg.contains('network-request-failed')) return 'Network error. Check your connection.';
    if (msg.contains('popup-closed-by-user') || msg.contains('canceled')) return 'Sign-in was cancelled.';
    if (msg.contains('too-many-requests')) return 'Too many attempts. Wait a moment.';
    if (msg.contains('wrong-password') || msg.contains('invalid-credential')) return 'Incorrect email or password.';
    if (msg.contains('user-not-found')) return 'No account found with this email.';
    if (msg.contains('email-already-in-use')) return 'An account with this email already exists.';
    if (msg.contains('weak-password')) return 'Password must be at least 6 characters.';
    if (msg.contains('invalid-email')) return 'Invalid email address.';
    if (msg.contains('keychain')) return 'Google Sign-In keychain error — try Email or Guest sign-in instead.';
    if (msg.contains('ID token')) return 'Google Sign-In token error — try Email or Guest sign-in.';
    if (msg.contains('sign_in_failed') || msg.contains('sign-in-failed')) return 'Sign-in failed: $msg';
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
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : (icon ?? const SizedBox.shrink()),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.violet,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.onPressed, required this.label, this.icon});
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
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          foregroundColor: Colors.white,
          side: BorderSide(color: AppTheme.edge),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Logo painter
// ---------------------------------------------------------------------------

class _AuthLogoPainter extends CustomPainter {
  const _AuthLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.96)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.1;

    final xPositions = [
      size.width * 0.14, size.width * 0.34, size.width * 0.5,
      size.width * 0.66, size.width * 0.86,
    ];
    final heights = [
      size.height * 0.38, size.height * 0.72, size.height * 0.96,
      size.height * 0.68, size.height * 0.44,
    ];
    final centerY = size.height / 2;

    for (var i = 0; i < xPositions.length; i++) {
      final halfH = heights[i] / 2;
      canvas.drawLine(
        Offset(xPositions[i], centerY - halfH),
        Offset(xPositions[i], centerY + halfH),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
