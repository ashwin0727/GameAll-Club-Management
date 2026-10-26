/// One row of `notifications` (migration 0161): a message for the signed-in person.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.route,
  });

  final String id;
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  /// The web path the message points at (e.g. `/memberships`); [notificationTarget] maps it to a screen.
  final String? route;

  bool get isRead => readAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return AppNotification(
      id: json['id'] as String,
      kind: json['kind'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String).toLocal(),
      route: data is Map ? data['route'] as String? : null,
    );
  }
}
