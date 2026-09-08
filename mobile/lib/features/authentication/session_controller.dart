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

  /// Only the first resolution (app start) shows the loading/splash state.
  /// Later auth-state changes (sign out, token refresh) update the session in
  /// place — flipping back to `isLoading` would bounce the router through the
  /// splash screen and flash an error mid-transition.
  bool _resolvedOnce = false;

  Future<void> refresh() async {
    if (!_resolvedOnce) state = state.copyWith(isLoading: true);

    final authRepo = ref.read(authRepositoryProvider);
    final user = await authRepo.getCurrentUser();

    final resolvedFacility = user == null
        ? null
        : await ref.read(facilityRepositoryProvider).getFacility();

    _resolvedOnce = true;
    state = SessionState(
      user: user,
      facility: resolvedFacility,
      isLoading: false,
    );
  }

  Future<void> signOut() async {
    // Clear the local session first so the UI reacts immediately, then tell
    // the auth backend. Any failure there is irrelevant — we're logged out.
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