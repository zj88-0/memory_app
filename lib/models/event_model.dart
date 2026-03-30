/// Model for a Singapore elderly activity/event returned from the server.
class EventItem {
  final String id;
  final String title;
  final String category;
  final DateTime startTime;
  final DateTime endTime;
  final String location;
  final String imageUrl;
  final String eventUrl;
  final String description;

  const EventItem({
    required this.id,
    required this.title,
    required this.category,
    required this.startTime,
    required this.endTime,
    required this.location,
    required this.imageUrl,
    required this.eventUrl,
    required this.description,
  });

  factory EventItem.fromJson(Map<String, dynamic> json) {
    return EventItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? '',
      startTime: DateTime.tryParse(json['startTime'] as String? ?? '') ?? DateTime.now(),
      endTime: DateTime.tryParse(json['endTime'] as String? ?? '') ?? DateTime.now(),
      location: json['location'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      eventUrl: json['eventUrl'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'location': location,
        'imageUrl': imageUrl,
        'eventUrl': eventUrl,
        'description': description,
      };

  bool get isUpcoming => endTime.isAfter(DateTime.now());
  bool get isToday {
    final now = DateTime.now();
    return startTime.year == now.year &&
        startTime.month == now.month &&
        startTime.day == now.day;
  }
}
