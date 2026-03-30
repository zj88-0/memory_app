
enum RequestStatus { pending, claimed, completed }

class ActionRequest {
  final String id;
  final String groupId;
  final String elderlyId;
  final String elderlyName;
  final String buttonLabel;
  final String buttonIconName;
  final int buttonColorValue;
  final String additionalDetails; // text from elderly (typed or STT)
  RequestStatus status;
  String? claimedById;
  String? claimedByName;
  DateTime? claimedAt;
  DateTime? completedAt;
  final DateTime createdAt;

  ActionRequest({
    required this.id,
    required this.groupId,
    required this.elderlyId,
    required this.elderlyName,
    required this.buttonLabel,
    required this.buttonIconName,
    required this.buttonColorValue,
    this.additionalDetails = '',
    this.status = RequestStatus.pending,
    this.claimedById,
    this.claimedByName,
    this.claimedAt,
    this.completedAt,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'elderlyId': elderlyId,
        'elderlyName': elderlyName,
        'buttonLabel': buttonLabel,
        'buttonIconName': buttonIconName,
        'buttonColorValue': buttonColorValue,
        'additionalDetails': additionalDetails,
        'status': status.name,
        'claimedById': claimedById,
        'claimedByName': claimedByName,
        'claimedAt': claimedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory ActionRequest.fromJson(Map<String, dynamic> json) => ActionRequest(
        id: json['id'],
        groupId: json['groupId'],
        elderlyId: json['elderlyId'],
        elderlyName: json['elderlyName'] ?? '',
        buttonLabel: json['buttonLabel'],
        buttonIconName: json['buttonIconName'] ?? 'notifications',
        buttonColorValue: json['buttonColorValue'] ?? 0xFF2E7D9A,
        additionalDetails: json['additionalDetails'] ?? '',
        status: RequestStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => RequestStatus.pending,
        ),
        claimedById: json['claimedById'],
        claimedByName: json['claimedByName'],
        claimedAt: json['claimedAt'] != null ? DateTime.parse(json['claimedAt']) : null,
        completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null,
        createdAt: DateTime.parse(json['createdAt']),
      );

  ActionRequest copyWith({
    RequestStatus? status,
    String? claimedById,
    String? claimedByName,
    DateTime? claimedAt,
    DateTime? completedAt,
  }) =>
      ActionRequest(
        id: id, groupId: groupId, elderlyId: elderlyId,
        elderlyName: elderlyName, buttonLabel: buttonLabel,
        buttonIconName: buttonIconName, buttonColorValue: buttonColorValue,
        additionalDetails: additionalDetails,
        status: status ?? this.status,
        claimedById: claimedById ?? this.claimedById,
        claimedByName: claimedByName ?? this.claimedByName,
        claimedAt: claimedAt ?? this.claimedAt,
        completedAt: completedAt ?? this.completedAt,
        createdAt: createdAt,
      );
}
