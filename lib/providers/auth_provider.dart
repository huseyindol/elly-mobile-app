import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/login_response.dart';
import '../services/api_service.dart';
import '../services/user_admin.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  AuthProvider({ApiService? apiService}) : _apiService = apiService ?? ApiService() {
    ApiService.onSessionExpired = logout;
  }

  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _errorMessage;
  LoginResponse? _currentUser;

  // 2FA second step: set while waiting for the 6-digit code.
  String? _mfaToken;
  String? _mfaTenantId;

  // null = not loaded yet (or failed before any load) → UI hides gated actions.
  Set<String>? _permissions;
  List<String> _roles = const [];
  String? _permissionsError;
  bool _permissionsLoading = false;

  // GET /users/me (DtoUserResponse); null until loaded — the login response has only the username.
  Map<String, dynamic>? _profile;

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get errorMessage => _errorMessage;
  LoginResponse? get currentUser => _currentUser;
  bool get mfaPending => _mfaToken != null;
  bool get permissionsLoaded => _permissions != null;
  String? get permissionsError => _permissionsError;

  /// Role names (SUPER_ADMIN, ADMIN, …). Gating uses permissions; roles only where the backend itself checks a
  /// role: the user-management hierarchy ([roleLevel]) and `ROLE_SUPER_ADMIN` endpoints (storage quota limit).
  List<String> get roles => _roles;

  /// Highest role level (SUPER_ADMIN 4 … VIEWER 1; unknown/none 1 = most restrictive), admin `useMyRoleLevel`.
  int get roleLevel => maxRoleLevel(_roles);

  /// Sorted `<module>:<action>` keys (profile "İzinler").
  List<String> get permissions => (_permissions?.toList() ?? <String>[])..sort();

  Map<String, dynamic>? get profile => _profile;

  /// Signed-in user's id (self-action guards); from the profile, else the login response.
  int? get userId => (_profile?['id'] as num?)?.toInt() ?? int.tryParse(_currentUser?.userId ?? '');

  /// Drawer / dashboard name: "Ad Soyad" (admin sidebar), else the username; '' while unknown.
  String get displayName {
    final name = displayNameOf(_profile);
    return name.isNotEmpty ? name : (_currentUser?.username ?? '');
  }

  /// GET /users/me. Errors are swallowed (callers that show the profile use [fetchProfile]); the drawer then
  /// falls back to the login username.
  Future<void> loadProfile() async {
    try {
      await fetchProfile();
    } catch (_) {}
  }

  /// GET /users/me → [profile] (throws on failure).
  Future<Map<String, dynamic>> fetchProfile() async {
    final data = await _apiService.get('/users/me');
    setProfile(Map<String, dynamic>.from(data as Map));
    return _profile!;
  }

  /// After PUT /users/me: the response is the new profile.
  void setProfile(Map<String, dynamic> profile) {
    if (!_isAuthenticated) return; // a late response after logout must not resurrect the old user
    _profile = profile;
    notifyListeners();
  }

  /// Same label as the admin sidebar profile card.
  String get roleLabel {
    for (final (role, label) in const [
      ('SUPER_ADMIN', 'Süper Admin'),
      ('ADMIN', 'Admin'),
      ('EDITOR', 'Editör'),
      ('VIEWER', 'Görüntüleyici'),
    ]) {
      if (_roles.contains(role)) return label;
    }
    return _roles.isNotEmpty ? _roles.first : 'Kullanıcı';
  }

  /// UI gating only; the backend enforces the same keys with @PreAuthorize.
  /// [action]: read | create | update | delete.
  bool can(String module, String action) => has('$module:$action');

  /// Full `<module>:<action>` key, e.g. `users:manage`.
  bool has(String permission) => _permissions?.contains(permission) ?? false;

  Future<void> checkAuthStatus() async {
    final token = await _secureStorage.read(key: 'accessToken');
    if (token != null) {
      _isAuthenticated = true;
      notifyListeners();
      await Future.wait([loadPermissions(), loadProfile()]);
    }
    notifyListeners();
  }

  /// GET /users/me/permissions. On failure the last known set is kept (if any) and
  /// [permissionsError] is set so the UI can offer a retry.
  Future<void> loadPermissions() async {
    if (_permissionsLoading) return;
    _permissionsLoading = true;
    _permissionsError = null; // back to the spinner while retrying
    notifyListeners();
    try {
      final data = await _apiService.get('/users/me/permissions');
      final list = (data is Map ? data['permissions'] as List? : null) ?? const [];
      _permissions = list.map((e) => e.toString()).toSet();
      final roles = data is Map ? data['roles'] as List? : null;
      if (roles != null) _roles = roles.map((e) => e.toString()).toList();
      _permissionsError = null;
    } catch (e) {
      if (_isAuthenticated) _permissionsError = e.toString().replaceAll('Exception: ', '');
    }
    _permissionsLoading = false;
    notifyListeners();
  }

  Future<bool> login({required String usernameOrEmail, required String password, required String tenantId}) =>
      _authenticate(
        () => _apiService.post('/auth/login', {
          'usernameOrEmail': usernameOrEmail,
          'password': password,
          'tenantId': tenantId,
          'loginType': 'admin', // As requested, behaves like the admin panel
        }, tenantId: tenantId),
        tenantId,
      );

  /// Second login step for 2FA users: POST /auth/mfa/verify with the login's mfaToken.
  Future<bool> verifyMfa(String code) {
    final tenantId = _mfaTenantId!;
    return _authenticate(
      () => _apiService.post('/auth/mfa/verify', {'mfaToken': _mfaToken, 'code': code}, tenantId: tenantId),
      tenantId,
    );
  }

  /// Leave the code step and return to the credentials form.
  void cancelMfa() {
    _mfaToken = null;
    _mfaTenantId = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> _authenticate(Future<dynamic> Function() request, String tenantId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = LoginResponse.fromJson(Map<String, dynamic>.from(await request() as Map));
      _currentUser = user;

      if (user.mfaRequired) {
        _mfaToken = user.mfaToken;
        _mfaTenantId = tenantId;
        if (_mfaToken == null) _errorMessage = '2FA doğrulama token\'ı alınamadı.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      await _secureStorage.write(key: 'accessToken', value: user.token);
      await _secureStorage.write(key: 'refreshToken', value: user.refreshToken);
      await _secureStorage.write(key: 'tenantId', value: tenantId);

      _mfaToken = null;
      _mfaTenantId = null;
      // Seed from the auth response so a failed permissions call still leaves a usable UI.
      _permissions = user.permissions?.toSet();
      _roles = user.roles ?? const [];
      _permissionsError = null;
      _isAuthenticated = true;
      await Future.wait([loadPermissions(), loadProfile()]);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _secureStorage.deleteAll();
    _isAuthenticated = false;
    _currentUser = null;
    _mfaToken = null;
    _mfaTenantId = null;
    _permissions = null;
    _roles = const [];
    _permissionsError = null;
    _profile = null;
    notifyListeners();
  }
}
