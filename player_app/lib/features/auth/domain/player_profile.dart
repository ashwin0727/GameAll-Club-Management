/// A player's own profile: the name and email they gave, and the phone number they signed in with.
class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    this.email,
  });

  factory PlayerProfile.fromJson(Map<String, dynamic> json) => PlayerProfile(
    id: json['id'] as String,
    fullName: (json['fullName'] as String?) ?? '',
    phone: (json['phone'] as String?) ?? '',
    email: json['email'] as String?,
  );

  final String id;
  final String fullName;

  /// The ten-digit number (without +91).
  final String phone;
  final String? email;

  String get firstName {
    final name = fullName.trim();
    return name.isEmpty ? 'there' : name.split(RegExp(r'\s+')).first;
  }

  /// "AS" for "Asha Shah": the avatar when there is no photo.
  String get initials {
    final words = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    return (words.length == 1
            ? words.first.substring(0, 1)
            : words.first.substring(0, 1) + words.last.substring(0, 1))
        .toUpperCase();
  }
}

/// A ten-digit Indian mobile number: starts with 6, 7, 8 or 9.
bool isValidIndianMobile(String digits) =>
    RegExp(r'^[6-9]\d{9}$').hasMatch(digits);

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
bool isValidEmail(String email) => _emailPattern.hasMatch(email.trim());
