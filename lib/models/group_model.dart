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

  /// The invite code is the first 8 characters of the group id (uppercase).
  /// It is also stored as a top-level Firestore field ('inviteCode') so that
  /// DataService can query groups by invite code without a full collection scan.
  String get inviteCode => id.substring(0, 8).toUpperCase();

  bool get isFull => memberIds.length >= maxCaregivers;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'adminId': adminId,
        'memberIds': memberIds,
        'elderlyId': elderlyId,
        'createdAt': createdAt.toIso8601String(),
        // Stored explicitly so Firestore can index and query it.
        'inviteCode': inviteCode,
      };

  factory CareGroup.fromJson(Map<String, dynamic> json) => CareGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        adminId: json['adminId'] as String,
        memberIds: List<String>.from(json['memberIds'] ?? []),
        elderlyId: json['elderlyId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

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
