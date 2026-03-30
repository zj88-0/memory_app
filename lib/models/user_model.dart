
enum UserRole { elderly, caregiver }

class UserModel {
  final String id;
  String name;
  String email;
  String password;
  UserRole role;
  String? groupId;
  String preferredLanguage;
  DateTime createdAt;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    this.groupId,
    this.preferredLanguage = 'en',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'password': password,
        'role': role.name,
        'groupId': groupId,
        'preferredLanguage': preferredLanguage,
        'createdAt': createdAt.toIso8601String(),
      };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        name: json['name'],
        email: json['email'],
        password: json['password'],
        role: UserRole.values.firstWhere((e) => e.name == json['role']),
        groupId: json['groupId'],
        preferredLanguage: json['preferredLanguage'] ?? 'en',
        createdAt: DateTime.parse(json['createdAt']),
      );

  UserModel copyWith({
    String? name,
    String? email,
    String? password,
    UserRole? role,
    String? groupId,
    String? preferredLanguage,
  }) =>
      UserModel(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        password: password ?? this.password,
        role: role ?? this.role,
        groupId: groupId ?? this.groupId,
        preferredLanguage: preferredLanguage ?? this.preferredLanguage,
        createdAt: createdAt,
      );
}
