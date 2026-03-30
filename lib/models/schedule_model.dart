
enum RepeatType { none, daily, weekly, monthly }

class ScheduleItem {
  final String id;
  String title;
  String description;
  DateTime scheduledTime;
  int notifyMinutesBefore;
  RepeatType repeatType;
  bool isCompleted;
  String groupId;
  String createdBy;
  DateTime createdAt;

  ScheduleItem({
    required this.id,
    required this.title,
    required this.description,
    required this.scheduledTime,
    this.notifyMinutesBefore = 5,
    this.repeatType = RepeatType.none,
    this.isCompleted = false,
    required this.groupId,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'scheduledTime': scheduledTime.toIso8601String(),
        'notifyMinutesBefore': notifyMinutesBefore,
        'repeatType': repeatType.name,
        'isCompleted': isCompleted,
        'groupId': groupId,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ScheduleItem.fromJson(Map<String, dynamic> json) => ScheduleItem(
        id: json['id'],
        title: json['title'],
        description: json['description'] ?? '',
        scheduledTime: DateTime.parse(json['scheduledTime']),
        notifyMinutesBefore: json['notifyMinutesBefore'] ?? 5,
        repeatType: RepeatType.values.firstWhere(
          (e) => e.name == json['repeatType'],
          orElse: () => RepeatType.none,
        ),
        isCompleted: json['isCompleted'] ?? false,
        groupId: json['groupId'],
        createdBy: json['createdBy'],
        createdAt: DateTime.parse(json['createdAt']),
      );

  ScheduleItem copyWith({
    String? title,
    String? description,
    DateTime? scheduledTime,
    int? notifyMinutesBefore,
    RepeatType? repeatType,
    bool? isCompleted,
  }) =>
      ScheduleItem(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        scheduledTime: scheduledTime ?? this.scheduledTime,
        notifyMinutesBefore: notifyMinutesBefore ?? this.notifyMinutesBefore,
        repeatType: repeatType ?? this.repeatType,
        isCompleted: isCompleted ?? this.isCompleted,
        groupId: groupId,
        createdBy: createdBy,
        createdAt: createdAt,
      );
}
