import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/login_response.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  AuthProvider() {
    ApiService.onSessionExpired = logout;
  }

  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _errorMessage;
  LoginResponse? _currentUser;

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get errorMessage => _errorMessage;
  LoginResponse? get currentUser => _currentUser;

  Future<void> checkAuthStatus() async {
    final token = await _secureStorage.read(key: 'accessToken');
    if (token != null) {
      _isAuthenticated = true;
      // You could optionally fetch user details with the token here if needed
    }
    notifyListeners();
  }

  Future<bool> login({
    required String usernameOrEmail,
    required String password,
    required String tenantId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final responseData = await _apiService.post(
        '/auth/login',
        {
          'usernameOrEmail': usernameOrEmail,
          'password': password,
          'tenantId': tenantId,
          'loginType': 'admin', // As requested, behaves like the admin panel
        },
        tenantId: tenantId,
      );

      _currentUser = LoginResponse.fromJson(responseData);
      
      if (_currentUser?.mfaRequired == true) {
        _errorMessage = '2FA doğrulaması mobil uygulamada henüz desteklenmiyor.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Save tokens securely
      await _secureStorage.write(key: 'accessToken', value: _currentUser!.token);
      await _secureStorage.write(key: 'refreshToken', value: _currentUser!.refreshToken);
      await _secureStorage.write(key: 'tenantId', value: tenantId);

      _isAuthenticated = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isAuthenticated = false;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _secureStorage.deleteAll();
    _isAuthenticated = false;
    _currentUser = null;
    notifyListeners();
  }
}
