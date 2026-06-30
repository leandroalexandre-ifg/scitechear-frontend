import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class AuthService {
  static const _keyToken = 'auth_token';
  static const _keyUserId = 'user_id';
  static const _keyUserName = 'user_name';
  static const _keyUserEmail = 'user_email';

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_keyToken) != null) {
      _currentUser = AppUser(
        id: prefs.getString(_keyUserId) ?? '',
        name: prefs.getString(_keyUserName) ?? '',
        email: prefs.getString(_keyUserEmail) ?? '',
      );
    }
  }

  // Mock auth — substitua pelas chamadas reais ao backend quando disponível.
  Future<AppUser> login(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (email.isEmpty || password.length < 6) {
      throw Exception('E-mail ou senha inválidos.');
    }
    final user = AppUser(
      id: 'u_${email.hashCode.abs()}',
      name: email.split('@').first,
      email: email,
    );
    await _save(user, 'tok_${email.hashCode.abs()}');
    _currentUser = user;
    return user;
  }

  Future<AppUser> register(String name, String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (name.isEmpty || email.isEmpty || password.length < 6) {
      throw Exception('Preencha todos os campos (senha mínima: 6 caracteres).');
    }
    final user = AppUser(
      id: 'u_${email.hashCode.abs()}',
      name: name,
      email: email,
    );
    await _save(user, 'tok_${email.hashCode.abs()}');
    _currentUser = user;
    return user;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _currentUser = null;
  }

  Future<void> _save(AppUser user, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUserId, user.id);
    await prefs.setString(_keyUserName, user.name);
    await prefs.setString(_keyUserEmail, user.email);
  }
}
