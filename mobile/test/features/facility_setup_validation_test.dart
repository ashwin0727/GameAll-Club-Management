import 'package:flutter_test/flutter_test.dart';

import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/repositories/facility_repository.dart';
import 'package:gameall_club_mobile/features/onboarding/facility_setup_validation.dart';

void main() {
  group('contact numbers', () {
    test('the contact number is required, 10 digits, starting 6-9', () {
      expect(FacilitySetupValidation.contactNumber(''), 'Contact number is required.');
      expect(FacilitySetupValidation.contactNumber('12345'), 'Enter a valid 10-digit mobile number.');
      expect(FacilitySetupValidation.contactNumber('1234567890'), 'Mobile number must start with 6, 7, 8 or 9.');
      expect(FacilitySetupValidation.contactNumber('9876543210'), isNull);
      expect(FacilitySetupValidation.contactNumber('+919876543210'), isNull);
    });

    test('WhatsApp is optional but must be valid when given', () {
      expect(FacilitySetupValidation.optionalMobile(''), isNull);
      expect(FacilitySetupValidation.optionalMobile('   '), isNull);
      expect(FacilitySetupValidation.optionalMobile('98765'), 'Enter a valid 10-digit mobile number.');
      expect(FacilitySetupValidation.optionalMobile('9123456780'), isNull);
    });

    test('the alternate number must differ from the contact number', () {
      expect(FacilitySetupValidation.alternateNumber('', '9876543210'), isNull);
      expect(FacilitySetupValidation.alternateNumber('9123456780', '9876543210'), isNull);
      expect(FacilitySetupValidation.alternateNumber('9876543210', '9876543210'), 'Use a different number from the contact number.');
      expect(FacilitySetupValidation.alternateNumber('9876543210', '+919876543210'), 'Use a different number from the contact number.');
      expect(FacilitySetupValidation.alternateNumber('123', '9876543210'), 'Enter a valid 10-digit mobile number.');
    });
  });

  group('text fields', () {
    test('facility name', () {
      expect(FacilitySetupValidation.facilityName(''), isNotNull);
      expect(FacilitySetupValidation.facilityName(' G '), isNotNull);
      expect(FacilitySetupValidation.facilityName('GameAll Arena'), isNull);
      expect(FacilitySetupValidation.facilityName('a' * 101), 'Facility name is too long.');
    });

    test('address, area, city and state are required', () {
      expect(FacilitySetupValidation.address('  '), 'Address is required.');
      expect(FacilitySetupValidation.area(''), 'Area / locality is required.');
      expect(FacilitySetupValidation.city(null), 'City is required.');
      expect(FacilitySetupValidation.state(null), 'State is required.');
      expect(FacilitySetupValidation.state('Tamil Nadu'), isNull);
    });

    test('a custom facility type is required only for Other', () {
      expect(FacilitySetupValidation.customType('', required: true), 'Specify your facility type.');
      expect(FacilitySetupValidation.customType('', required: false), isNull);
      expect(FacilitySetupValidation.customType('a' * 51, required: false), 'Keep this under 50 characters.');
    });

    test('the description is capped at 500 characters', () {
      expect(FacilitySetupValidation.description('a' * 500), isNull);
      expect(FacilitySetupValidation.description('a' * 501), 'Description can be up to 500 characters.');
      expect(FacilitySetupValidation.description(null), isNull);
    });

    test('the contact person name takes letters, spaces and . - only', () {
      expect(FacilitySetupValidation.personName(''), "Enter the contact person's name.");
      expect(FacilitySetupValidation.personName('U'), "Enter the contact person's name.");
      expect(FacilitySetupValidation.personName('Uma123'), "Name can contain letters, spaces and . ' - only.");
      expect(FacilitySetupValidation.personName("Mary-Ann O'Neil Jr."), isNull);
    });

    test('the role must come from the list', () {
      expect(FacilitySetupValidation.role(null), 'Choose a role.');
      expect(FacilitySetupValidation.role('Janitor'), 'Choose a role.');
      for (final r in kContactRoles) {
        expect(FacilitySetupValidation.role(r), isNull);
      }
    });
  });

  group('custom amenities', () {
    test('rejects too-short, too-long and odd names', () {
      expect(FacilitySetupValidation.customAmenity('x', const []), 'Amenity name must be at least 2 characters.');
      expect(FacilitySetupValidation.customAmenity('a' * 31, const []), 'Keep the amenity name under 30 characters.');
      expect(FacilitySetupValidation.customAmenity('@@', const []), 'Use letters, numbers and common punctuation only.');
    });

    test('rejects a name already in the standard list or already added, ignoring case', () {
      expect(FacilitySetupValidation.customAmenity('wi-fi', const []), '"wi-fi" is already in the list.');
      expect(FacilitySetupValidation.customAmenity('spa', const ['Spa']), '"spa" is already in the list.');
    });

    test('accepts a new name until the limit of 10', () {
      expect(FacilitySetupValidation.customAmenity('Physio room', const []), isNull);
      final ten = List.generate(10, (i) => 'Extra ${String.fromCharCode(97 + i)}');
      expect(FacilitySetupValidation.customAmenity('One more', ten), 'Add up to 10 custom amenities.');
    });
  });

  test('there are exactly 12 standard amenities with unique keys', () {
    expect(kFacilityAmenities, hasLength(12));
    expect(kFacilityAmenities.map((a) => a.key).toSet(), hasLength(12));
  });

  group('Facility model and save payload', () {
    final row = <String, dynamic>{
      'id': 'f1',
      'owner_id': 'o1',
      'name': 'Champz Turf',
      'facility_type': 'MULTI_SPORT',
      'business_email': 'o@x.com',
      'business_phone': '9876543210',
      'ownership_type': 'LEASED',
      'whatsapp_number': '9123456780',
      'contact_person_name': 'Uma Shankar M',
      'contact_person_role': 'Manager',
      'contact_person_alt_phone': '9988776655',
      'allow_online_booking': true,
      'allow_walk_in_booking': false,
      'advance_payment_required': true,
      'allow_cancellations': false,
      'require_player_details': true,
      'amenity_keys': ['wifi', 'shower'],
      'custom_amenities': ['Physio room'],
      'status': 'ACTIVE',
      'onboarding_step': 'FACILITY_DETAILS',
    };

    test('reads the new columns', () {
      final f = Facility.fromJson(row);
      expect(f.ownershipType, OwnershipType.leased);
      expect(f.whatsappNumber, '9123456780');
      expect(f.contactPerson?.name, 'Uma Shankar M');
      expect(f.contactPerson?.role, 'Manager');
      expect(f.contactPerson?.alternatePhone, '9988776655');
      expect(f.policies.allowWalkIn, isFalse);
      expect(f.policies.advancePaymentRequired, isTrue);
      expect(f.amenityKeys, ['wifi', 'shower']);
      expect(f.customAmenities, ['Physio room']);
    });

    test('an older facility without them gets the defaults', () {
      final old = <String, dynamic>{
        'id': 'f2',
        'owner_id': 'o1',
        'name': 'Old Arena',
        'facility_type': 'BADMINTON',
        'status': 'ACTIVE',
        'onboarding_step': 'COMPLETED',
      };
      final f = Facility.fromJson(old);
      expect(f.ownershipType, OwnershipType.owned);
      expect(f.contactPerson, isNull);
      expect(f.policies.allowOnlineBooking, isTrue);
      expect(f.policies.advancePaymentRequired, isFalse);
      expect(f.amenityKeys, isEmpty);
      expect(f.customAmenities, isEmpty);
    });

    test('the save payload writes the list (never the legacy flags) and blanks become null', () {
      const extras = FacilitySetupExtras(
        ownership: OwnershipType.leased,
        whatsappNumber: '  ',
        description: ' Floodlit courts ',
        contactPerson: FacilityContactPerson(name: 'Uma', role: 'Manager', alternatePhone: ''),
        policies: FacilityPolicies(advancePaymentRequired: true),
        amenityKeys: ['wifi'],
        customAmenities: ['Spa'],
      );
      final db = extras.toDb();
      expect(db['ownership_type'], 'LEASED');
      expect(db['whatsapp_number'], isNull);
      expect(db['description'], 'Floodlit courts');
      expect(db['contact_person_name'], 'Uma');
      expect(db['contact_person_alt_phone'], isNull);
      expect(db['advance_payment_required'], isTrue);
      expect(db['amenity_keys'], ['wifi']);
      expect(db['custom_amenities'], ['Spa']);
      expect(db.containsKey('has_parking'), isFalse);
    });
  });
}
