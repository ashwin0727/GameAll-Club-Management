import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/coaching_detail_repository.dart';
import '../domain/coaching_detail.dart';

/// The data source. Tests override this with a fake.
final coachingDetailRepositoryProvider = Provider<CoachingDetailRepository>(
  (ref) => SupabaseCoachingDetailRepository(),
);

/// The signed-in player's coaching enrolments with all their details. Reloads when invalidated (after paying, on coming back).
final myCoachingDetailsProvider =
    FutureProvider.autoDispose<List<CoachingDetail>>(
      (ref) => ref.watch(coachingDetailRepositoryProvider).mine(),
    );
