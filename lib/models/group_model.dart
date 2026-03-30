class CareGroup {
  final String id;
  String name;
  String adminId;
  List<String> memberIds;
  String elderlyId;
  DateTime createdAt;

  static const int maxCaregivers = 5;

  CareGroup({
    required this.id,
    required this.name,
    required this.adminId,
    required this.memberIds,
    required this.elderlyId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'adminId': adminId,
        'memberIds': memberIds,
        'elderlyId': elderlyId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory CareGroup.fromJson(Map<String, dynamic> json) => CareGroup(
        id: json['id'],
        name: json['name'],
        adminId: json['adminId'],
        memberIds: List<String>.from(json['memberIds'] ?? []),
        elderlyId: json['elderlyId'],
        createdAt: DateTime.parse(json['createdAt']),
      );

  // Invite code is just group id for local storage
  String get inviteCode => id.substring(0, 8).toUpperCase();

  bool get isFull => memberIds.length >= maxCaregivers;

  CareGroup copyWith({
    String? name,
    String? adminId,
    List<String>? memberIds,
    String? elderlyId,
  }) =>
      CareGroup(
        id: id,
        name: name ?? this.name,
        adminId: adminId ?? this.adminId,
        memberIds: memberIds ?? List.from(this.memberIds),
        elderlyId: elderlyId ?? this.elderlyId,
        createdAt: createdAt,
      );
}
