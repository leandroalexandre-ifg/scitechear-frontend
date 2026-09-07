import 'package:dio/dio.dart';

import '../models/user.dart';
import 'api_client.dart';
import 'local_scope.dart';

/// Erro de autenticação com mensagem já pronta para exibir ao usuário.
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

/// Autenticação real contra o backend (`/auth/*`, JWT + refresh token).
///
/// Substituiu um mock local que aceitava qualquer credencial e nunca falava
/// com o servidor. Os tokens não moram aqui: quem guarda e renova é o
/// [ApiClient], porque todo serviço autenticado depende deles.
class AuthService {
  final ApiClient _api = ApiClient.instance;

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  /// Recupera a sessão salva no boot do app.
  ///
  /// Ter um refresh token no disco não é o mesmo que estar logado — ele pode
  /// ter sido revogado ou expirado (30 dias). A confirmação é o `/auth/me`
  /// responder; se ele falhar por credencial, a sessão é descartada.
  Future<void> initialize() async {
    await _api.restore();
    if (!_api.hasSession) return;
    try {
      _currentUser = await _fetchCurrentUser();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _api.clearSession();
      }
      // Falha de rede não desloga: o usuário continua sem sessão *nesta*
      // abertura, mas o refresh token segue no disco para a próxima.
      _currentUser = null;
    }
  }

  Future<AppUser> login(String email, String password) async {
    try {
      final response = await _api.public.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      await _api.saveSession(response.data as Map<String, dynamic>);
      final user = await _fetchCurrentUser();
      _currentUser = user;
      return user;
    } on DioException catch (e) {
      throw AuthException(_messageFor(e, isLogin: true));
    }
  }

  /// Cadastra e já entra.
  ///
  /// `/auth/register` devolve o usuário criado, não um par de tokens — por
  /// isso o login logo em seguida. Fazer o usuário digitar as credenciais de
  /// novo, na tela seguinte à que ele acabou de preenchê-las, seria só
  /// repassar a ele um detalhe da API.
  Future<AppUser> register(String name, String email, String password) async {
    try {
      await _api.public.post(
        '/auth/register',
        data: {'email': email, 'password': password, 'name': name},
      );
    } on DioException catch (e) {
      throw AuthException(_messageFor(e, isLogin: false));
    }
    return login(email, password);
  }

  Future<void> logout() async {
    final refreshToken = _api.refreshToken;
    _currentUser = null;
    // Revoga do lado do servidor; esquecer só localmente deixaria o refresh
    // token válido por 30 dias. Falha aqui não pode impedir o logout local.
    if (refreshToken != null) {
      try {
        await _api.public.post(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
        );
      } on DioException {
        // Sem rede: segue com a limpeza local.
      }
    }
    await _api.clearSession();
  }

  /// Chamado quando o [ApiClient] descobre que a sessão morreu, para o
  /// estado daqui não continuar dizendo que há um usuário logado.
  void handleSessionExpired() {
    _currentUser = null;
  }

  Future<AppUser> _fetchCurrentUser() async {
    final response = await _api.client().get('/auth/me');
    final data = response.data as Map<String, dynamic>;
    final user = AppUser(
      id: data['user_id'] as String? ?? '',
      name: (data['name'] as String?)?.trim().isNotEmpty == true
          ? data['name'] as String
          : (data['email'] as String? ?? ''),
      email: data['email'] as String? ?? '',
    );

    // O armazenamento local é escopado por usuário, então saber quem é
    // precisa vir antes de qualquer tela ler histórico ou participantes.
    await _api.setUserId(user.id);
    await LocalScope.adoptLegacyData();

    return user;
  }

  String _messageFor(DioException e, {required bool isLogin}) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'O servidor demorou demais para responder. Tente novamente.';
      case DioExceptionType.connectionError:
        return 'Não foi possível conectar ao servidor. Verifique o endereço configurado e sua conexão.';
      case DioExceptionType.badResponse:
        return _messageForStatus(e, isLogin: isLogin);
      default:
        return 'Falha na autenticação: ${e.message ?? 'erro desconhecido'}.';
    }
  }

  String _messageForStatus(DioException e, {required bool isLogin}) {
    final status = e.response?.statusCode;
    switch (status) {
      case 401:
        return 'E-mail ou senha incorretos.';
      case 409:
        return 'Já existe uma conta com esse e-mail.';
      case 429:
        final retryAfter = e.response?.headers.value('Retry-After');
        final seconds = int.tryParse(retryAfter ?? '');
        if (seconds != null) {
          final minutes = (seconds / 60).ceil();
          return 'Muitas tentativas. Tente novamente em '
              '${minutes <= 1 ? 'cerca de 1 minuto' : 'cerca de $minutes minutos'}.';
        }
        return 'Muitas tentativas. Tente novamente mais tarde.';
      case 422:
        // Validação do Pydantic — a mensagem crua é uma estrutura aninhada,
        // ilegível para o usuário. O que de fato pode falhar aqui é o
        // formato do e-mail ou o mínimo de 8 caracteres da senha.
        return isLogin
            ? 'Dados inválidos. Confira o e-mail e a senha.'
            : 'Dados inválidos. Use um e-mail válido e uma senha de pelo menos 8 caracteres.';
      default:
        final detail = _detailOf(e.response?.data);
        if (detail != null) return detail;
        return 'O servidor recusou a requisição (código $status).';
    }
  }

  /// O FastAPI devolve o erro em `detail`, não em `message`.
  String? _detailOf(dynamic data) {
    if (data is! Map) return null;
    final detail = data['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    return null;
  }
}
