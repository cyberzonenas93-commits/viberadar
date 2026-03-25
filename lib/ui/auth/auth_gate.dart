import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../providers/repositories.dart';
import '../shell/vibe_shell.dart';
import 'onboarding_screen.dart';
import 'splash_screen.dart';

enum _AuthPhase { splash, onboarding, login }

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key, required this.statusMessage});

  final String statusMessage;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  _AuthPhase _phase = _AuthPhase.splash;

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionProvider);

    return sessionAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppTheme.ink,
        body: Center(child: CircularProgressIndicator(color: AppTheme.cyan)),
      ),
      error: (_, _) => VibeShell(statusMessage: widget.statusMessage),
      data: (session) {
        if (session.isAuthenticated) {
          return VibeShell(statusMessage: widget.statusMessage);
        }

        return switch (_phase) {
          _AuthPhase.splash => SplashScreen(
              onFinished: () => setState(() => _phase = _AuthPhase.onboarding),
            ),
          _AuthPhase.onboarding => OnboardingScreen(
              onComplete: () => setState(() => _phase = _AuthPhase.login),
            ),
          _AuthPhase.login =>
            _LoginScreen(statusMessage: widget.statusMessage),
        };
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Login / Sign-up screen (email + password only)
// ---------------------------------------------------------------------------

class _LoginScreen extends ConsumerStatefulWidget {
  const _LoginScreen({required this.statusMessage});

  final String statusMessage;

  @override
  ConsumerState<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<_LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _djNameController = TextEditingController();

  bool _isSignUp = false;
  int _signUpStep = 0; // 0 = email+password, 1 = profile info
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  static const _genreOptions = [
    'Afrobeats',
    'Amapiano',
    'Hip-Hop',
    'R&B',
    'Pop',
    'House',
    'Techno',
    'Drill',
    'Dancehall',
    'Reggaeton',
    'Afro-House',
    'Gospel',
    'Latin',
    'Rock',
    'Jazz',
  ];
  final Set<String> _selectedGenres = {};

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _djNameController.dispose();
    super.dispose();
  }

  int get _passwordStrength {
    final pw = _passwordController.text;
    if (pw.isEmpty) return 0;
    var score = 0;
    if (pw.length >= 8) score++;
    if (pw.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(pw) && RegExp(r'[a-z]').hasMatch(pw)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(pw)) score++;
    if (RegExp(r'[!@#\$%\^&\*\(\)_\+\-=\[\]\{\};:,.<>?/\\|`~]')
        .hasMatch(pw)) {
      score++;
    }
    return score.clamp(0, 4);
  }

  String get _strengthLabel {
    return switch (_passwordStrength) {
      0 => '',
      1 => 'Weak',
      2 => 'Fair',
      3 => 'Good',
      4 => 'Strong',
      _ => '',
    };
  }

  Color get _strengthColor {
    return switch (_passwordStrength) {
      1 => Colors.redAccent,
      2 => Colors.orange,
      3 => AppTheme.cyan,
      4 => AppTheme.lime,
      _ => AppTheme.edge,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(36),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Container(
                  width: 64,
                  height: 64,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.violet, AppTheme.pink, AppTheme.cyan],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.violet.withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: CustomPaint(
                      painter: _AuthLogoPainter(),
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'VibeRadar',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isSignUp
                      ? (_signUpStep == 0
                          ? 'Create your account'
                          : 'Set up your DJ profile')
                      : 'Sign in to continue',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white60,
                  ),
                ),

                // Step indicator for sign-up
                if (_isSignUp) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStepDot(0, 'Account'),
                      Container(
                        width: 40,
                        height: 2,
                        color:
                            _signUpStep >= 1 ? AppTheme.cyan : AppTheme.edge,
                      ),
                      _buildStepDot(1, 'Profile'),
                    ],
                  ),
                ],

                const SizedBox(height: 28),

                // ---- Sign-up Step 0: Email + Password ----
                if (_isSignUp && _signUpStep == 0) ...[
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.email_rounded),
                      hintText: 'you@example.com',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_rounded),
                      hintText: 'At least 8 characters',
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_passwordController.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _passwordStrength / 4,
                              backgroundColor: AppTheme.edge,
                              color: _strengthColor,
                              minHeight: 4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _strengthLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _strengthColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _buildPasswordRequirements(theme),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: 'Confirm password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _nextOrSubmit(),
                  ),
                ],

                // ---- Sign-up Step 1: Profile ----
                if (_isSignUp && _signUpStep == 1) ...[
                  TextField(
                    controller: _djNameController,
                    decoration: const InputDecoration(
                      labelText: 'DJ / Artist name',
                      prefixIcon: Icon(Icons.person_rounded),
                      hintText: 'What should we call you?',
                    ),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Favorite genres (pick at least 1)',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _genreOptions.map((genre) {
                      final selected = _selectedGenres.contains(genre);
                      return FilterChip(
                        label: Text(genre),
                        selected: selected,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedGenres.add(genre);
                            } else {
                              _selectedGenres.remove(genre);
                            }
                          });
                        },
                        selectedColor:
                            AppTheme.cyan.withValues(alpha: 0.25),
                        checkmarkColor: AppTheme.cyan,
                        side: BorderSide(
                          color: selected ? AppTheme.cyan : AppTheme.edge,
                        ),
                        labelStyle: TextStyle(
                          color: selected ? AppTheme.cyan : Colors.white70,
                        ),
                      );
                    }).toList(),
                  ),
                ],

                // ---- Sign-in form ----
                if (!_isSignUp) ...[
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_rounded),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _nextOrSubmit(),
                  ),
                ],

                // Error
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
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
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 22),

                // Primary action button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _nextOrSubmit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppTheme.cyan,
                      foregroundColor: AppTheme.ink,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isSignUp
                                ? (_signUpStep == 0
                                    ? 'Continue'
                                    : 'Create Account')
                                : 'Sign In',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),

                // Back button on step 1
                if (_isSignUp && _signUpStep == 1) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() {
                                _signUpStep = 0;
                                _error = null;
                              }),
                      child: const Text('Back'),
                    ),
                  ),
                ],

                const SizedBox(height: 18),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => setState(() {
                            _isSignUp = !_isSignUp;
                            _signUpStep = 0;
                            _error = null;
                          }),
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign in'
                        : "Don't have an account? Create one",
                    style: TextStyle(color: AppTheme.cyan),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepDot(int step, String label) {
    final isActive = _signUpStep >= step;
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? AppTheme.cyan : AppTheme.edge,
          ),
          child: Center(
            child: isActive && _signUpStep > step
                ? const Icon(Icons.check_rounded,
                    size: 16, color: AppTheme.ink)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      color: isActive ? AppTheme.ink : Colors.white54,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isActive ? AppTheme.cyan : Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordRequirements(ThemeData theme) {
    final pw = _passwordController.text;
    final checks = <(String, bool)>[
      ('8+ characters', pw.length >= 8),
      (
        'Uppercase & lowercase',
        RegExp(r'[A-Z]').hasMatch(pw) && RegExp(r'[a-z]').hasMatch(pw)
      ),
      ('Number', RegExp(r'[0-9]').hasMatch(pw)),
      (
        'Special character',
        RegExp(r'[!@#\$%\^&\*\(\)_\+\-=\[\]\{\};:,.<>?/\\|`~]').hasMatch(pw)
      ),
    ];

    return Column(
      children: checks.map((check) {
        final (label, met) = check;
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Icon(
                met ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 14,
                color: met ? AppTheme.lime : Colors.white24,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: met ? Colors.white60 : Colors.white30,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _nextOrSubmit() {
    if (!_isSignUp) {
      _submitLogin();
    } else if (_signUpStep == 0) {
      _validateAndAdvance();
    } else {
      _submitSignUp();
    }
  }

  void _validateAndAdvance() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address.');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (_passwordStrength < 2) {
      setState(() => _error =
          'Password is too weak. Add uppercase, numbers, or special characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _signUpStep = 1;
      _error = null;
    });
  }

  Future<void> _submitLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref
          .read(sessionRepositoryProvider)
          .signInWithEmail(email: email, password: password);
    } catch (e, st) {
      debugPrint('VIBERADAR SIGN-IN ERROR: $e\n$st');
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitSignUp() async {
    final djName = _djNameController.text.trim();
    if (djName.isEmpty) {
      setState(() => _error = 'Please enter your DJ / artist name.');
      return;
    }
    if (_selectedGenres.isEmpty) {
      setState(() => _error = 'Pick at least one genre you play.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(sessionRepositoryProvider).createAccount(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            displayName: djName,
          );
    } catch (e, st) {
      debugPrint('VIBERADAR SIGN-UP ERROR: $e\n$st');
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(Object error) {
    final msg = error.toString();
    if (msg.contains('user-not-found')) {
      return 'No account found with that email.';
    }
    if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
      return 'Incorrect password. Please try again.';
    }
    if (msg.contains('email-already-in-use')) {
      return 'An account with that email already exists. Try signing in.';
    }
    if (msg.contains('invalid-email')) {
      return 'Please enter a valid email address.';
    }
    if (msg.contains('weak-password')) {
      return 'Password is too weak. Use at least 8 characters with mixed case and numbers.';
    }
    if (msg.contains('network-request-failed')) {
      return 'Network error. Check your connection and try again.';
    }
    if (msg.contains('operation-not-allowed')) {
      return 'Email/password sign-in is not enabled. Enable it in the Firebase console under Authentication → Sign-in methods.';
    }
    if (msg.contains('too-many-requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (msg.contains('configuration-not-found') ||
        msg.contains('CONFIGURATION_NOT_FOUND')) {
      return 'Firebase is not fully configured. Check your project settings.';
    }
    // Surface the raw error so it can be diagnosed rather than silently swallowed.
    return 'Authentication failed: $error';
  }
}

class _AuthLogoPainter extends CustomPainter {
  const _AuthLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.96)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.1;

    final xPositions = <double>[
      size.width * 0.14,
      size.width * 0.34,
      size.width * 0.5,
      size.width * 0.66,
      size.width * 0.86,
    ];
    final heights = <double>[
      size.height * 0.38,
      size.height * 0.72,
      size.height * 0.96,
      size.height * 0.68,
      size.height * 0.44,
    ];
    final centerY = size.height / 2;

    for (var i = 0; i < xPositions.length; i++) {
      final halfHeight = heights[i] / 2;
      canvas.drawLine(
        Offset(xPositions[i], centerY - halfHeight),
        Offset(xPositions[i], centerY + halfHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
