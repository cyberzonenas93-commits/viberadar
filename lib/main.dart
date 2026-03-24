import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await AppBootstrap.initialize();
  runApp(
    ProviderScope(
      overrides: bootstrap.providerOverrides.cast(),
      child: VibeRadarApp(bootstrap: bootstrap),
    ),
  );
}
