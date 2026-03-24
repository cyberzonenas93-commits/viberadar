import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/session_repository.dart';
import '../data/repositories/track_repository.dart';
import '../data/repositories/user_repository.dart';

final trackRepositoryProvider = Provider<TrackRepository>(
  (ref) => throw UnimplementedError('TrackRepository override missing.'),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => throw UnimplementedError('UserRepository override missing.'),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => throw UnimplementedError('SessionRepository override missing.'),
);
