import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/membership_detail_repository.dart';
import '../domain/membership_detail.dart';

/// The data source. Tests override this with a fake.
final membershipDetailRepositoryProvider = Provider<MembershipDetailRepository>(
  (ref) => SupabaseMembershipDetailRepository(),
);

/// The signed-in player's active memberships with all their details. Reloads when invalidated (after paying, on coming back to the page).
final myMembershipDetailsProvider =
    FutureProvider.autoDispose<List<MembershipDetail>>(
      (ref) => ref.watch(membershipDetailRepositoryProvider).mine(),
    );
