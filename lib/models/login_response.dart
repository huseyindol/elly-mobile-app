class LoginResponse {
  final String token;
  final String refreshToken;
  final String userId;
  final String username;
  final String email;
  final bool mfaRequired;
  final String? mfaToken;

  LoginResponse({
    required this.token,
    required this.refreshToken,
    required this.userId,
    required this.username,
    required this.email,
    this.mfaRequired = false,
    this.mfaToken,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      token: json['token']?.toString() ?? '',
      refreshToken: json['refreshToken']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      mfaRequired: json['mfaRequired'] ?? false,
      mfaToken: json['mfaToken']?.toString(),
    );
  }
}
