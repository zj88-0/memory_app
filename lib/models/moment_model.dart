class MomentComment {
  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime createdAt;

  MomentComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MomentComment.fromJson(Map<String, dynamic> json) => MomentComment(
        id: json['id'],
        authorId: json['authorId'],
        authorName: json['authorName'] ?? '',
        text: json['text'] ?? '',
        createdAt: DateTime.parse(json['createdAt']),
      );
}

class Moment {
  final String id;
  final String groupId;
  final String authorId;
  final String authorName;
  final String caption;
  final String? imageBase64; // local base64 for offline/immediate display
  final String? imageUrl;     // server URL once uploaded
  final DateTime createdAt;
  final List<MomentComment> comments;

  Moment({
    required this.id,
    required this.groupId,
    required this.authorId,
    required this.authorName,
    required this.caption,
    this.imageBase64,
    this.imageUrl,
    required this.createdAt,
    this.comments = const [],
  });

  Moment copyWith({
    String? id,
    String? groupId,
    String? authorId,
    String? authorName,
    String? caption,
    String? imageBase64,
    String? imageUrl,
    DateTime? createdAt,
    List<MomentComment>? comments,
  }) {
    return Moment(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      caption: caption ?? this.caption,
      imageBase64: imageBase64 ?? this.imageBase64,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      comments: comments ?? this.comments,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'authorId': authorId,
        'authorName': authorName,
        'caption': caption,
        'imageBase64': imageBase64,
        'imageUrl': imageUrl,
        'createdAt': createdAt.toIso8601String(),
        'comments': comments.map((c) => c.toJson()).toList(),
      };

  factory Moment.fromJson(Map<String, dynamic> json) => Moment(
        id: json['id'],
        groupId: json['groupId'],
        authorId: json['authorId'],
        authorName: json['authorName'] ?? '',
        caption: json['caption'] ?? '',
        imageBase64: json['imageBase64'],
        imageUrl: json['imageUrl'],
        createdAt: DateTime.parse(json['createdAt']),
        comments: json['comments'] != null
            ? (json['comments'] as List).map((c) => MomentComment.fromJson(c)).toList()
            : [],
      );
}
