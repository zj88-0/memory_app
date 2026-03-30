
class QuickActionButton {
  final String id;
  String label;
  String description;
  String iconName;
  int colorValue;
  String groupId;
  String createdBy;
  DateTime createdAt;

  QuickActionButton({
    required this.id,
    required this.label,
    required this.description,
    required this.iconName,
    required this.colorValue,
    required this.groupId,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'description': description,
        'iconName': iconName,
        'colorValue': colorValue,
        'groupId': groupId,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  factory QuickActionButton.fromJson(Map<String, dynamic> json) =>
      QuickActionButton(
        id: json['id'],
        label: json['label'],
        description: json['description'] ?? '',
        iconName: json['iconName'] ?? 'notifications',
        colorValue: json['colorValue'] ?? 0xFF4CAF50,
        groupId: json['groupId'],
        createdBy: json['createdBy'],
        createdAt: DateTime.parse(json['createdAt']),
      );

  QuickActionButton copyWith({
    String? label,
    String? description,
    String? iconName,
    int? colorValue,
  }) =>
      QuickActionButton(
        id: id,
        label: label ?? this.label,
        description: description ?? this.description,
        iconName: iconName ?? this.iconName,
        colorValue: colorValue ?? this.colorValue,
        groupId: groupId,
        createdBy: createdBy,
        createdAt: createdAt,
      );
}
