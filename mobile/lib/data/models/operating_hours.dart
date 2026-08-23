/// 0 = Sunday .. 6 = Saturday, matching the web app (`operating_days.day_of_week`,
/// itself matching JS `Date#getDay`).
const List<int> daysOfWeek = [0, 1, 2, 3, 4, 5, 6];
const List<String> dayLabels = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

/// Monday-first, matching every example in the product spec even though
/// day_of_week itself is Sunday-first for JS Date compatibility.
const List<int> displayOrder = [1, 2, 3, 4, 5, 6, 0];

class OperatingTimeSlot {
  const OperatingTimeSlot({
    required this.startTime,
    required this.endTime,
    required this.crossesMidnight,
    required this.displayOrder,
  });

  final String startTime; // "HH:MM"
  final String endTime;
  final bool crossesMidnight;
  final int displayOrder;

  factory OperatingTimeSlot.fromJson(Map<String, dynamic> json) {
    return OperatingTimeSlot(
      startTime: (json['start_time'] as String).substring(0, 5),
      endTime: (json['end_time'] as String).substring(0, 5),
      crossesMidnight: json['crosses_midnight'] as bool? ?? false,
      displayOrder: json['display_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toPayload() => {
    'startTime': startTime,
    'endTime': endTime,
    'crossesMidnight': crossesMidnight,
    'displayOrder': displayOrder,
  };
}

class OperatingDay {
  const OperatingDay({
    required this.dayOfWeek,
    required this.isClosed,
    required this.is24Hours,
    required this.slots,
  });

  final int dayOfWeek;
  final bool isClosed;
  final bool is24Hours;
  final List<OperatingTimeSlot> slots;

  factory OperatingDay.defaultOpen(int dayOfWeek) {
    return OperatingDay(
      dayOfWeek: dayOfWeek,
      isClosed: false,
      is24Hours: false,
      slots: const [
        OperatingTimeSlot(
          startTime: '06:00',
          endTime: '23:00',
          crossesMidnight: false,
          displayOrder: 0,
        ),
      ],
    );
  }

  static List<OperatingDay> defaultWeek() =>
      daysOfWeek.map(OperatingDay.defaultOpen).toList();

  OperatingDay copyWith({
    bool? isClosed,
    bool? is24Hours,
    List<OperatingTimeSlot>? slots,
  }) {
    return OperatingDay(
      dayOfWeek: dayOfWeek,
      isClosed: isClosed ?? this.isClosed,
      is24Hours: is24Hours ?? this.is24Hours,
      slots: slots ?? this.slots,
    );
  }

  factory OperatingDay.fromJson(Map<String, dynamic> json) {
    final slotsJson = (json['operating_time_slots'] as List<dynamic>? ?? []);
    final slots = slotsJson
        .cast<Map<String, dynamic>>()
        .map(OperatingTimeSlot.fromJson)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return OperatingDay(
      dayOfWeek: json['day_of_week'] as int,
      isClosed: json['is_closed'] as bool? ?? false,
      is24Hours: json['is_24_hours'] as bool? ?? false,
      slots: slots,
    );
  }

  Map<String, dynamic> toPayload() => {
    'dayOfWeek': dayOfWeek,
    'isClosed': isClosed,
    'is24Hours': is24Hours,
    'slots': isClosed || is24Hours ? [] : slots.map((s) => s.toPayload()).toList(),
  };

  /// e.g. "Closed" / "Open 24 hours" / "6:00 AM – 11:00 PM".
  String describe(String Function(String time24) formatTime) {
    if (isClosed) return 'Closed';
    if (is24Hours) return 'Open 24 hours';
    if (slots.isEmpty) return 'Closed';
    return slots
        .map(
          (s) =>
              '${formatTime(s.startTime)} – ${formatTime(s.endTime)}${s.crossesMidnight ? ' (next day)' : ''}',
        )
        .join(', ');
  }
}

class OperatingSchedule {
  const OperatingSchedule({
    required this.id,
    required this.facilityId,
    required this.scopeType,
    this.playingAreaId,
    required this.timezone,
    required this.days,
  });

  final String id;
  final String facilityId;
  final String scopeType; // FACILITY | PLAYING_AREA
  final String? playingAreaId;
  final String timezone;
  final List<OperatingDay> days;

  factory OperatingSchedule.fromJson(Map<String, dynamic> json) {
    final daysJson = (json['operating_days'] as List<dynamic>? ?? []);
    return OperatingSchedule(
      id: json['id'] as String,
      facilityId: json['facility_id'] as String,
      scopeType: json['scope_type'] as String,
      playingAreaId: json['playing_area_id'] as String?,
      timezone: json['timezone'] as String? ?? 'Asia/Kolkata',
      days: daysJson.cast<Map<String, dynamic>>().map(OperatingDay.fromJson).toList(),
    );
  }
}