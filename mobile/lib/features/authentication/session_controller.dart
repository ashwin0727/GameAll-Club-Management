import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/app_user.dart';
import '../../data/models/facility.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/services/supabase_provider.dart';

class SessionState {
  const SessionState({this.user, this.facility, this.isLoading = true});

  final AppUser? user;
  final Facility? facility;
  final bool isLoading;

  bool get isAuthenticated => user != null;

  SessionState copyWith({AppUser? user, Facility? facility, bool? isLoading}) {
    return SessionState(
      user: user ?? this.user,
      facility: facility ?? this.facility,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// The single place that resolves "who is signed in, and how far along is
/// their facility's onboarding" — the mobile equivalent of the web app's
/// `useCurrentUser()` + `getFacilityService().getFacility()` pairing, kept
/// together here since both are needed for every routing decision.
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    // Re-resolve whenever Supabase's own auth state changes (sign in/out,
    // token refresh) instead of only once at app start.
    ref.listen(authStateProvider, (previous, next) {
      refresh();
    });
    // Kick off the first resolution; the initial synchronous state is
    // "loading" until it completes.
    Future.microtask(refresh);
    return const SessionState();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final authRepo = ref.read(authRepositoryProvider);
    final user = await authRepo.getCurrentUser();

    if (user == null) {
      state = const SessionState(isLoading: false);
      return;
    }

    final facilityRepo = ref.read(facilityRepositoryProvider);
    final facility = await facilityRepo.getFacility();
    state = SessionState(user: user, facility: facility, isLoading: false);
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).logout();
    state = const SessionState(isLoading: false);
  }
}

final sessionControllerProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);