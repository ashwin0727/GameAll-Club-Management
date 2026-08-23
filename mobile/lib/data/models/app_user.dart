/// Mirrors `profiles` (see supabase/migrations/0001_init.sql).
class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.onboardingCompleted,
  });

  final String id;
  final String fullName;
  final String email;
  final String role;
  final bool onboardingCompleted;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
    );
  }
}