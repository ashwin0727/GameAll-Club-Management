/// Mirrors `profiles` (see supabase/migrations/0001_init.sql).
class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.onboardingCompleted,
    this.mustResetPassword = false,
  });

  final String id;
  final String fullName;
  final String email;
  final String role;
  final bool onboardingCompleted;

  /// A staff account created by an administrator: signed in with a one-time
  /// password and must set their own before doing anything else.
  final bool mustResetPassword;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      mustResetPassword: json['must_reset_password'] as bool? ?? false,
    );
  }
}