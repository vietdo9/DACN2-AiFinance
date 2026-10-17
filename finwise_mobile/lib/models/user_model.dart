class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final String? token;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    this.token,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, {String? token}) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      fullName: json['full_name']?.toString() ??
          json['fullName']?.toString() ??
          (json['email'] != null ? json['email'].toString().split('@')[0] : 'Người Dùng FinWise'),
      avatarUrl: json['avatar_url']?.toString(),
      token: token ?? json['token']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'token': token,
    };
  }
}
