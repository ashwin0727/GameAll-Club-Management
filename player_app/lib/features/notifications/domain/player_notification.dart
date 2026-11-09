import 'package:flutter/material.dart';

/// One message for the signed-in player (the `notifications` table, migration 0194): a booking about to start, a payment that went
/// through or failed, a membership or coaching payment coming up.
class PlayerNotification {
  const PlayerNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.route,
  });

  factory PlayerNotification.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return PlayerNotification(
      id: json['id'] as String,
      kind: (json['kind'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      readAt: json['readAt'] == null ? null : DateTime.parse(json['readAt'] as String).toLocal(),
      route: data is Map ? (data['route'] as String?) : null,
    );
  }

  final String id;
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  /// The page it is about (`/bookings`, `/my-membership`, `/my-coaching`), or null.
  final String? route;

  bool get isRead => readAt != null;

  PlayerNotification markedRead() => PlayerNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    createdAt: createdAt,
    readAt: readAt ?? DateTime.now(),
    route: route,
  );

  bool get isFailure => kind.contains('failed');
  bool get isSuccess => kind == 'player_payment_success';

  IconData get icon {
    if (isFailure) return Icons.error_outline_rounded;
    if (isSuccess) return Icons.check_circle_outline_rounded;
    if (kind.contains('booking')) return Icons.sports_tennis_rounded;
    if (kind.contains('membership')) return Icons.card_membership_rounded;
    if (kind.contains('coaching')) return Icons.school_outlined;
    return Icons.notifications_none_rounded;
  }

  /// "Just now", "5 min ago", "2 h ago", "Yesterday", "3 Nov".
  String ago(DateTime now) {
    final d = now.difference(createdAt);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'Yesterday';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${createdAt.day} ${m[createdAt.month - 1]}';
  }
}
