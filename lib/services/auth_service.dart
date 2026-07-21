import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

// Credenciais fixas pré-cadastradas (admin).
const _seededUsers = [
  _SeededUser(
    username: 'leandro',
    password: 'leandro',
    name: 'Leandro',
    email: 'leandro@reuniao.app',
    isAdmin: true,
  ),
];

class AuthService {
  static const _keyToken = 'auth_token';
  static const _keyUserId = 'user_id';
  static const _keyUserName = 'user_name';
  static const _keyUserEmail = 'user_email';
  static const _keyUserIsAdmin = 'user_is_admin';

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
        isAdmin: prefs.getBool(_keyUserIsAdmin) ?? false,
      );
    }
  }

  Future<AppUser> login(String emailOrUsername, String password) async {
    await Future.delayed(const Duration(milliseconds: 900));

    // Verifica usuários pré-cadastrados (por username ou email).
    for (final s in _seededUsers) {
      if ((emailOrUsername == s.username || emailOrUsername == s.email) &&
          password == s.password) {
        final user = AppUser(
          id: 'u_${s.username}',
          name: s.name,
          email: s.email,
          isAdmin: s.isAdmin,
        );
        await _save(user, 'tok_${s.username}');
        _currentUser = user;
        return user;
      }
    }

    // Fallback: qualquer conta registrada dinamicamente.
    if (emailOrUsername.isEmpty || password.length < 6) {
      throw Exception('E-mail/usuário ou senha inválidos.');
    }
    final user = AppUser(
      id: 'u_${emailOrUsername.hashCode.abs()}',
      name: emailOrUsername.split('@').first,
      email: emailOrUsername.contains('@')
          ? emailOrUsername
          : '$emailOrUsername@reuniao.app',
    );
    await _save(user, 'tok_${emailOrUsername.hashCode.abs()}');
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
    await prefs.setBool(_keyUserIsAdmin, user.isAdmin);
  }
}

class _SeededUser {
  final String username;
  final String password;
  final String name;
  final String email;
  final bool isAdmin;
  const _SeededUser({
    required this.username,
    required this.password,
    required this.name,
    required this.email,
    this.isAdmin = false,
  });
}
