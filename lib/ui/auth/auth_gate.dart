import 'dart:async';
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
import '../../providers/onboarding_state.dart';
import '../../providers/repositories.dart';
import '../../services/messaging_service.dart';
import '../mobile/mobile_shell.dart';
import '../onboarding/intro_carousel.dart';
import '../shell/vibe_shell.dart';
import '../widgets/ui_kit.dart';
import 'onboarding_screen.dart';
import 'splash_screen.dart';

enum _AuthPhase { splash, intro, onboarding, login }

enum _LoginMode { main, emailSignIn, emailCreate }

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({
    super.key,
    required this.statusMessage,
    this.isDemoMode = false,
    this.artistSearch,
    this.artistImageLookup,
  });
  final String statusMessage;
  final bool isDemoMode;
  final ArtistSearch? artistSearch;
  final ArtistImageLookup? artistImageLookup;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  _AuthPhase _phase = _AuthPhase.splash;
  bool _checkedOnboarding = false;
  bool _featureOnboardingCompleted = false;
  bool _introSeen = false;
  String? _artistPreferencesUid;
  bool _artistPreferencesReady = false;
  bool _artistPreferencesCompleted = false;
  bool _savingArtistPreferences = false;
  String? _artistPreferencesError;

  /// UID currently registered for push, so we register/unregister only on real
  /// sign-in / sign-out transitions rather than every rebuild.
  String? _messagingUid;

  /// Registers (or drops) this device's push token as the session changes.
  void _syncMessaging(SessionState? session) {
    final authed = session?.isAuthenticated == true && session?.isDemo != true;
    final uid = authed ? session!.userId : null;
    if (uid == _messagingUid) return;
    final previous = _messagingUid;
    _messagingUid = uid;
    final service = ref.read(messagingServiceProvider);
    if (uid != null) {
      unawaited(service.register(uid));
    } else if (previous != null) {
      unawaited(service.unregister());
    }
  }

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final completed =
        prefs.getBool('feature_onboarding_completed_v1') ??
        prefs.getBool('onboarding_completed') ??
        false;
    final introSeen = await ref.read(onboardingStateProvider).isIntroSeen();
    if (mounted) {
      setState(() {
        _checkedOnboarding = true;
        _featureOnboardingCompleted = completed;
        _introSeen = introSeen;
        _phase = _AuthPhase.splash;
      });
    }
  }

  Future<void> _completeFeatureOnboarding(List<String> _) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('feature_onboarding_completed_v1', true);
    if (mounted) {
      setState(() {
        _featureOnboardingCompleted = true;
        _phase = _AuthPhase.login;
      });
    }
  }

  void _finishSplash() {
    setState(() {
      _phase = !_introSeen
          ? _AuthPhase.intro
          : (_featureOnboardingCompleted
                ? _AuthPhase.login
                : _AuthPhase.onboarding);
    });
  }

  Future<void> _finishIntro() async {
    await ref.read(onboardingStateProvider).markIntroSeen();
    if (!mounted) return;
    setState(() {
      _introSeen = true;
      _phase = _featureOnboardingCompleted
          ? _AuthPhase.login
          : _AuthPhase.onboarding;
    });
  }

  String _artistPreferencesKey(String uid) =>
      'artist_preferences_completed_v1_$uid';

  bool _shouldCollectArtistPreferences(SessionState session) {
    return session.isAuthenticated &&
        !session.isDemo &&
        session.providerLabel != 'Guest';
  }

  void _prepareArtistPreferences(SessionState session) {
    if (!_shouldCollectArtistPreferences(session)) return;
    if (_artistPreferencesUid == session.userId && _artistPreferencesReady) {
      return;
    }
    _artistPreferencesUid = session.userId;
    _artistPreferencesReady = false;
    _artistPreferencesCompleted = false;
    _artistPreferencesError = null;
    unawaited(_loadArtistPreferencesStatus(session));
  }

  Future<void> _loadArtistPreferencesStatus(SessionState session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _artistPreferencesKey(session.userId);
      var completed = prefs.getBool(key) ?? false;
      final pending = prefs.getStringList('pending_followed_artists');

      if (!completed && pending != null && pending.isNotEmpty) {
        await ref
            .read(userRepositoryProvider)
            .setFollowedArtists(
              userId: session.userId,
              fallbackName: session.displayName,
              artists: pending,
            );
        await prefs.remove('pending_followed_artists');
        await prefs.setBool(key, true);
        await prefs.setBool('onboarding_completed', true);
        completed = true;
      }

      if (!completed) {
        final profile = await ref
            .read(userRepositoryProvider)
            .watchUser(
              userId: session.userId,
              fallbackName: session.displayName,
            )
            .first;
        if (profile.followedArtists.isNotEmpty) {
          await prefs.setBool(key, true);
          await prefs.setBool('onboarding_completed', true);
          completed = true;
        }
      }

      if (!mounted || _artistPreferencesUid != session.userId) return;
      setState(() {
        _artistPreferencesReady = true;
        _artistPreferencesCompleted = completed;
      });
    } catch (e, st) {
      developer.log(
        'Failed to load artist preference onboarding status',
        name: 'AuthGate',
        error: e,
        stackTrace: st,
      );
      if (!mounted || _artistPreferencesUid != session.userId) return;
      setState(() {
        _artistPreferencesReady = true;
        _artistPreferencesCompleted = true;
        _artistPreferencesError = null;
      });
    }
  }

  Future<void> _completeArtistPreferences(
    SessionState session,
    List<String> artists,
  ) async {
    if (_savingArtistPreferences) return;
    setState(() {
      _savingArtistPreferences = true;
      _artistPreferencesError = null;
    });

    var remoteSaveFailed = false;
    if (artists.isNotEmpty) {
      try {
        await ref
            .read(userRepositoryProvider)
            .setFollowedArtists(
              userId: session.userId,
              fallbackName: session.displayName,
              artists: artists,
            );
      } catch (e, st) {
        remoteSaveFailed = true;
        developer.log(
          'Failed to save followed artists remotely',
          name: 'AuthGate',
          error: e,
          stackTrace: st,
        );
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_artistPreferencesKey(session.userId), true);
      await prefs.setBool('onboarding_completed', true);
      if (remoteSaveFailed && artists.isNotEmpty) {
        await prefs.setStringList('pending_followed_artists', artists);
      } else {
        await prefs.remove('pending_followed_artists');
      }

      if (!mounted || _artistPreferencesUid != session.userId) return;
      setState(() {
        _artistPreferencesReady = true;
        _artistPreferencesCompleted = true;
        _savingArtistPreferences = false;
      });
    } catch (e, st) {
      developer.log(
        'Failed to save followed artists',
        name: 'AuthGate',
        error: e,
        stackTrace: st,
      );
      if (!mounted || _artistPreferencesUid != session.userId) return;
      setState(() {
        _artistPreferencesReady = true;
        _artistPreferencesCompleted = true;
        _savingArtistPreferences = false;
        _artistPreferencesError = null;
      });
    }
  }

  Widget _artistPreferenceSetup(SessionState session) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Stack(
        children: [
          OnboardingArtistPicker(
            onComplete: (artists) =>
                unawaited(_completeArtistPreferences(session, artists)),
            onSkip: () =>
                unawaited(_completeArtistPreferences(session, const [])),
            artistSearch: widget.artistSearch,
            artistImageLookup: widget.artistImageLookup,
          ),
          if (_savingArtistPreferences)
            Container(
              color: AppTheme.ink.withValues(alpha: 0.62),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.cyan),
              ),
            ),
          if (_artistPreferencesError != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: _SetupErrorBanner(message: _artistPreferencesError!),
            ),
        ],
      ),
    );
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
        return SplashScreen(onFinished: _finishSplash);
      case _AuthPhase.intro:
        return IntroCarousel(onFinish: _finishIntro);
      case _AuthPhase.onboarding:
        return OnboardingScreen(onComplete: _completeFeatureOnboarding);
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
      _syncMessaging(session);
      // Require a signed-in session (real account or explicit guest) before the
      // app on every platform — this surfaces onboarding + sign-in / account
      // creation instead of silently admitting an anonymous session. Demo mode
      // (Firebase unavailable) bypasses the gate so the app still works offline.
      if (!widget.isDemoMode &&
          session?.isAuthenticated != true &&
          session?.isDemo != true) {
        return _LoginScreen(statusMessage: widget.statusMessage);
      }

      if (session != null && _shouldCollectArtistPreferences(session)) {
        _prepareArtistPreferences(session);
        if (!_artistPreferencesReady) {
          return const Scaffold(
            backgroundColor: AppTheme.ink,
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.cyan),
            ),
          );
        }
        if (!_artistPreferencesCompleted) {
          return _artistPreferenceSetup(session);
        }
      }

      return isMobileForm
          ? const MobileShell()
          : VibeShell(
              statusMessage: widget.statusMessage,
              isDemoMode: widget.isDemoMode || session?.isDemo == true,
            );
    }

    return _LoginScreen(statusMessage: widget.statusMessage);
  }
}

class _SetupErrorBanner extends StatelessWidget {
  const _SetupErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF3A1720).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.45)),
          boxShadow: AppTheme.glow(Colors.redAccent, blur: 22, opacity: 0.18),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
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
            letterSpacing: 0,
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

      // Sign in with Apple — native on Apple platforms. Web/Android need a real
      // Sign-in-with-Apple Services ID in Firebase before this button can ship.
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS)) ...[
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

      // Guest / continue-without-account — available on every platform. It is
      // local mock data only, with no Firebase anonymous account and no live
      // API-backed screens.
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
    // Best-effort: a "remember me" preference write must never surface as a
    // sign-in error after the user has already authenticated.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', _rememberMe);
    } catch (_) {
      // Non-fatal; the user is signed in regardless.
    }
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
      if (mounted) setState(() => _error = _friendly(e, oauth: true));
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
        setState(() => _error = _friendly(e, oauth: true));
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e, oauth: true));
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

  String _friendly(Object error, {bool oauth = false}) {
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
    // For Apple/Google, `invalid-credential` means the OAuth token was rejected
    // — NOT a wrong password. Showing "Incorrect email or password" there is
    // misleading, so give an OAuth-specific message instead.
    if (oauth) {
      if (msg.contains('account-exists-with-different-credential')) {
        return 'This email is already registered with a different sign-in '
            'method. Use that method, or Email/Password.';
      }
      if (msg.contains('operation-not-allowed')) {
        return 'This sign-in method is not enabled. Try Email or Guest.';
      }
      return 'Could not complete sign-in. Please try again.';
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
