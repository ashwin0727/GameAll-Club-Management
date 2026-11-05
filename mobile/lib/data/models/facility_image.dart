/// What GameAll's admin decided about a facility photo or map link.
enum VerificationStatus {
  pending,
  verified,
  rejected;

  static VerificationStatus fromDb(String? value) => switch (value) {
        'VERIFIED' => VerificationStatus.verified,
        'REJECTED' => VerificationStatus.rejected,
        _ => VerificationStatus.pending,
      };

  String get label => switch (this) {
        VerificationStatus.pending => 'Waiting for GameAll to verify',
        VerificationStatus.verified => 'Verified',
        VerificationStatus.rejected => 'Rejected',
      };
}

/// One uploaded facility photo (`facility_images`). The first one is the cover players see once it is verified.
class FacilityImage {
  const FacilityImage({required this.id, required this.url, required this.sortOrder, required this.status, this.note});

  factory FacilityImage.fromJson(Map<String, dynamic> json) => FacilityImage(
        id: json['id'] as String,
        url: json['url'] as String,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        status: VerificationStatus.fromDb(json['verification_status'] as String?),
        note: json['verification_note'] as String?,
      );

  final String id;
  final String url;
  final int sortOrder;
  final VerificationStatus status;
  final String? note;
}

const maxFacilityPhotos = 8;
