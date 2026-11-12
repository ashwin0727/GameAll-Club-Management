import '../../data/models/facility.dart';

/// Pure rules for the Facility Information step — the same rules as the website's `facilityDetailsSchema`, kept out of widgets so
/// they can be unit-tested and never drift between the two apps.
class FacilitySetupValidation {
  const FacilitySetupValidation._();

  static const int descriptionMax = 500;
  static const int maxSetupPhotos = 5;

  static final RegExp _tenDigits = RegExp(r'^\d{10}$');
  static final RegExp _personName = RegExp(r"^[A-Za-z][A-Za-z .'-]*$");
  static final RegExp _amenityName = RegExp(r"^[A-Za-z0-9][A-Za-z0-9 &/'().,+-]*$");

  static String _digits(String? v) => (v?.trim() ?? '').replaceFirst(RegExp(r'^\+91'), '');

  static String? facilityName(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 2) return 'Facility name must be at least 2 characters.';
    if (v.length > 100) return 'Facility name is too long.';
    return null;
  }

  /// The facility's own number: required, 10 digits, starting 6-9.
  static String? contactNumber(String? value) {
    final digits = _digits(value);
    if (digits.isEmpty) return 'Contact number is required.';
    if (!_tenDigits.hasMatch(digits)) return 'Enter a valid 10-digit mobile number.';
    if (!RegExp(r'^[6-9]').hasMatch(digits)) return 'Mobile number must start with 6, 7, 8 or 9.';
    return null;
  }

  /// WhatsApp / alternate numbers: empty is fine, otherwise the same rules.
  static String? optionalMobile(String? value) {
    if (_digits(value).isEmpty) return null;
    return contactNumber(value);
  }

  /// The alternate number must differ from the contact number.
  static String? alternateNumber(String? alternate, String? contact) {
    final problem = optionalMobile(alternate);
    if (problem != null) return problem;
    final alt = _digits(alternate);
    if (alt.isNotEmpty && alt == _digits(contact)) return 'Use a different number from the contact number.';
    return null;
  }

  static String? address(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Address is required.';
    if (v.length > 250) return 'Address is too long.';
    return null;
  }

  static String? area(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Area / locality is required.';
    if (v.length > 100) return 'Area is too long.';
    return null;
  }

  static String? city(String? value) => (value?.trim().isEmpty ?? true) ? 'City is required.' : null;

  static String? state(String? value) => (value?.trim().isEmpty ?? true) ? 'State is required.' : null;

  static String? customType(String? value, {required bool required}) {
    final v = value?.trim() ?? '';
    if (required && v.isEmpty) return 'Specify your facility type.';
    if (v.length > 50) return 'Keep this under 50 characters.';
    return null;
  }

  static String? description(String? value) {
    if ((value?.trim().length ?? 0) > descriptionMax) return 'Description can be up to $descriptionMax characters.';
    return null;
  }

  static String? personName(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 2) return "Enter the contact person's name.";
    if (v.length > 80) return 'Name is too long.';
    if (!_personName.hasMatch(v)) return "Name can contain letters, spaces and . ' - only.";
    return null;
  }

  static String? role(String? value) => (value == null || !kContactRoles.contains(value)) ? 'Choose a role.' : null;

  /// The message to show when a typed custom amenity can't be added (null when it is fine).
  static String? customAmenity(String name, List<String> existing) {
    final v = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (v.length < 2) return 'Amenity name must be at least 2 characters.';
    if (v.length > 30) return 'Keep the amenity name under 30 characters.';
    if (!_amenityName.hasMatch(v)) return 'Use letters, numbers and common punctuation only.';
    if (existing.length >= kMaxCustomAmenities) return 'Add up to $kMaxCustomAmenities custom amenities.';
    final key = v.toLowerCase();
    final taken = [...existing, ...kFacilityAmenities.map((a) => a.label)].any((n) => n.trim().toLowerCase() == key);
    return taken ? '"$v" is already in the list.' : null;
  }
}

/// The Indian states and union territories offered in the State dropdown.
const List<String> kIndianStates = [
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chhattisgarh',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
  'Andaman and Nicobar Islands',
  'Chandigarh',
  'Dadra and Nagar Haveli and Daman and Diu',
  'Delhi',
  'Jammu and Kashmir',
  'Ladakh',
  'Lakshadweep',
  'Puducherry',
];
