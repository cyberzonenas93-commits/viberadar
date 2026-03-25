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
// Login screen — Google Sign-In only
// ---------------------------------------------------------------------------

class _LoginScreen extends ConsumerStatefulWidget {
  const _LoginScreen({required this.statusMessage});

  final String statusMessage;

  @override
  ConsumerState<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<_LoginScreen> {
  bool _isLoading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Center(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              Container(
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
              ),
              const SizedBox(height: 24),
              Text(
                'VibeRadar',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'DJ Trend Intelligence Platform',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 36),

              // Google Sign-In button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Image.network(
                          'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                          width: 20, height: 20,
                          errorBuilder: (_, e, s) => const Icon(Icons.login_rounded, size: 20, color: Colors.white),
                        ),
                  label: Text(
                    _isLoading ? 'Signing in...' : 'Continue with Google',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.white,
                    side: BorderSide(color: AppTheme.edge),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
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
                        child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Skip to demo
              TextButton(
                onPressed: _isLoading ? null : () {
                  // Skip login — go straight to dashboard in demo mode
                },
                child: Text(
                  'Continue without signing in',
                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                ),
              ),

              const SizedBox(height: 16),
              Text(
                'Designed and Built by Angelo Nartey.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      await ref.read(sessionRepositoryProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(Object error) {
    final msg = error.toString();
    if (msg.contains('network-request-failed')) return 'Network error. Check your connection.';
    if (msg.contains('popup-closed-by-user') || msg.contains('canceled')) return 'Sign-in was cancelled.';
    if (msg.contains('too-many-requests')) return 'Too many attempts. Wait a moment.';
    return 'Sign-in failed. Please try again.';
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
