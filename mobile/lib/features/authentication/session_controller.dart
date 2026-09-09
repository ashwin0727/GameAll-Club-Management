import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/app_user.dart';
import '../../data/models/facility.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/services/supabase_provider.dart';

class SessionState {
  const SessionState({
    this.user,
    this.facility,
    this.baseRole,
    this.permissions = const <String>{},
    this.isLoading = true,
  });

  final AppUser? user;
  final Facility? facility;

  /// The signed-in user's facility_users.role for [facility] — owner / manager
  /// / staff. Null while unresolved or when the user has no assignment.
  final String? baseRole;

  /// The permission keys the user holds for [facility] (my_facility_permissions).
  final Set<String> permissions;
  final bool isLoading;

  bool get isAuthenticated => user != null;

  /// UX gate only — the database (has_permission + RLS) is the real boundary.
  /// A facility owner implicitly holds everything, mirroring has_permission.
  bool can(String key) => baseRole == 'owner' || permissions.contains(key);
  bool canAny(Iterable<String> keys) => keys.any(can);

  SessionState copyWith({
    AppUser? user,
    Facility? facility,
    String? baseRole,
    Set<String>? permissions,
    bool? isLoading,
  }) {
    return SessionState(
      user: user ?? this.user,
      facility: facility ?? this.facility,
      baseRole: baseRole ?? this.baseRole,
      permissions: permissions ?? this.permissions,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// The single place that resolves "who is signed in, which facility they
/// operate, and what they may do there" — the mobile equivalent of the web's
/// useCurrentUser() + getFacilityContext() pairing.
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    ref.listen(authStateProvider, (previous, next) {
      refresh();
    });
    Future.microtask(refresh);
    return const SessionState();
  }

  bool _resolvedOnce = false;

  Future<void> refresh() async {
    if (!_resolvedOnce) state = state.copyWith(isLoading: true);

    final authRepo = ref.read(authRepositoryProvider);
    final user = await authRepo.getCurrentUser();

    Facility? facility;
    String? baseRole;
    var permissions = const <String>{};

    if (user != null) {
      facility = await ref.read(facilityRepositoryProvider).getFacility();
      if (facility != null) {
        final client = ref.read(supabaseClientProvider);
        final assignment = await client
            .from('facility_users')
            .select('role')
            .eq('facility_id', facility.id)
            .eq('user_id', user.id)
            .maybeSingle();
        baseRole = (assignment?['role'] as String?) ?? (facility.ownerId == user.id ? 'owner' : null);
        final staff = ref.read(staffRepositoryProvider);
        permissions = (await staff.myFacilityPermissions(facility.id)).toSet();
        await staff.recordMyLogin(); // last-login stamp for the Staff list
      }
    }

    _resolvedOnce = true;
    state = SessionState(
      user: user,
      facility: facility,
      baseRole: baseRole,
      permissions: permissions,
      isLoading: false,
    );
  }

  Future<void> signOut() async {
    _resolvedOnce = true;
    state = const SessionState(isLoading: false);
    try {
      await ref.read(authRepositoryProvider).logout();
    } catch (_) {}
  }
}

final sessionControllerProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);
