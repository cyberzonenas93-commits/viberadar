import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../ui/auth/auth_gate.dart';
import 'bootstrap.dart';

class VibeRadarApp extends StatelessWidget {
  const VibeRadarApp({super.key, required this.bootstrap});

  final AppBootstrapResult bootstrap;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VibeRadar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      home: AuthGate(statusMessage: bootstrap.statusMessage),
    );
  }
}
