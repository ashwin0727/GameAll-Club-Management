import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player_home/application/player_home_controller.dart';
import '../data/player_auth_repository.dart';
import '../domain/player_profile.dart';

/// The sign-in backend. Tests override this with a fake.
final playerAuthRepositoryProvider = Provider<PlayerAuthRepository>((ref) => SupabasePlayerAuthRepository());

/// Where the visitor is: not signed in, signed in but no profile yet (still to give name and email), or a full player.
sealed class AuthStatus {
  const AuthStatus();
}

class SignedOut extends AuthStatus {
  const SignedOut();
}

class NeedsProfile extends AuthStatus {
  const NeedsProfile();
}

class SignedIn extends AuthStatus {
  const SignedIn(this.profile);
  final PlayerProfile profile;
}

class AuthController extends AsyncNotifier<AuthStatus> {
  StreamSubscription<void>? _sub;

  @override
  Future<AuthStatus> build() async {
    final repo = ref.watch(playerAuthRepositoryProvider);
    // Signing in or out (here or in another tab) re-reads the state.
    _sub?.cancel();
    _sub = repo.changes.listen((_) => refresh());
    ref.onDispose(() => _sub?.cancel());
    return _read(repo);
  }

  Future<AuthStatus> _read(PlayerAuthRepository repo) async {
    if (!repo.isSignedIn) return const SignedOut();
    final profile = await repo.myProfile();
    return profile == null ? const NeedsProfile() : SignedIn(profile);
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(() => _read(ref.read(playerAuthRepositoryProvider)));
    state = next;
    // Home shows a different page for a signed-in player: reload it.
    ref.invalidate(playerHomeProvider);
  }

  /// Creates the profile after the first sign-in.
  Future<void> register({required String fullName, required String email}) async {
    final profile = await ref.read(playerAuthRepositoryProvider).register(fullName: fullName, email: email);
    state = AsyncData(SignedIn(profile));
    ref.invalidate(playerHomeProvider);
  }

  Future<void> signOut() async {
    await ref.read(playerAuthRepositoryProvider).signOut();
    state = const AsyncData(SignedOut());
    ref.invalidate(playerHomeProvider);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthStatus>(AuthController.new);

/// The signed-in player's profile, or null.
final currentPlayerProvider = Provider<PlayerProfile?>((ref) {
  final s = ref.watch(authControllerProvider).value;
  return s is SignedIn ? s.profile : null;
});
