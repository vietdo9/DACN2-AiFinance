class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final String? token;
  final String role; // 'user' | 'admin'
  final String status; // 'active' | 'suspended'

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    this.token,
    this.role = 'user',
    this.status = 'active',
  });

  bool get isAdmin =>
      role.toLowerCase() == 'admin' ||
      email.toLowerCase() == 'admin@finwise.com' ||
      email.toLowerCase() == 'admin@finwise.vn';

  bool get isSuspended => status.toLowerCase() == 'suspended';

  factory UserModel.fromJson(Map<String, dynamic> json, {String? token}) {
    final emailStr = json['email']?.toString() ?? '';
    final roleStr = json['role']?.toString() ??
        (emailStr.toLowerCase() == 'admin@finwise.com' ||
                emailStr.toLowerCase() == 'admin@finwise.vn'
            ? 'admin'
            : 'user');

    return UserModel(
      id: json['id']?.toString() ?? '',
      email: emailStr,
      fullName: json['full_name']?.toString() ??
          json['fullName']?.toString() ??
          (emailStr.isNotEmpty ? emailStr.split('@')[0] : 'Người Dùng FinWise'),
      avatarUrl: json['avatar_url']?.toString(),
      token: token ?? json['token']?.toString(),
      role: roleStr,
      status: json['status']?.toString() ?? 'active',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'token': token,
      'role': role,
      'status': status,
    };
  }
}
