import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'tls.dart';

/// A sessão acabou e não foi possível renovar — o usuário precisa entrar de
/// novo. Distinta de uma falha de rede: aqui o servidor respondeu, e a
/// resposta foi que o token não vale mais.
class SessionExpiredException implements Exception {
  final String message;
  SessionExpiredException([
    this.message = 'Sua sessão expirou. Entre novamente.',
  ]);

  @override
  String toString() => message;
}

/// Dono do par de tokens e de todo cliente HTTP autenticado do app.
///
/// Singleton porque o token é estado de processo: se cada serviço tivesse
/// sua própria cópia, renovar em um não renovaria nos outros, e o app
/// alternaria entre chamadas válidas e 401 conforme quem tivesse falado
/// primeiro com o backend.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _keyAccess = 'auth_access_token';
  static const _keyRefresh = 'auth_refresh_token';
  static const _keyExpiresAt = 'auth_expires_at';
  static const _keyUserId = 'auth_user_id';

  /// Margem para renovar *antes* de expirar, em vez de esperar o 401. O
  /// access token dura 30 minutos no backend, e uma requisição pode demorar
  /// (upload de reunião longa) — renovar na borda evitaria pouca coisa.
  /// Também absorve relógio dessincronizado entre aparelho e servidor.
  static const _renewMargin = Duration(minutes: 2);

  /// Marca uma requisição já reenviada, para um 401 no reenvio não disparar
  /// outra rodada de renovação (e outro reenvio, indefinidamente).
  static const _retriedFlag = 'scitech_retried';

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  String? _userId;

  /// De quem é esta sessão. Persistido junto dos tokens porque o
  /// armazenamento local é escopado por usuário (ver `local_scope.dart`) e
  /// precisa saber a resposta antes de `/auth/me` responder.
  String? get userId => _userId;

  /// Renovação em andamento. Sem isto, várias chamadas simultâneas com o
  /// token vencido (o polling de status enquanto um upload roda) dispararia
  /// cada uma o seu `/auth/refresh` — e todas menos a primeira falhariam,
  /// porque o backend revoga o refresh token assim que ele é usado.
  Future<bool>? _refreshInFlight;

  final _sessionExpired = StreamController<void>.broadcast();

  /// Emite quando a sessão morre de vez. `main.dart` escuta e leva o usuário
  /// de volta ao login, para nenhuma tela precisar tratar isso sozinha.
  Stream<void> get onSessionExpired => _sessionExpired.stream;

  bool get hasSession => _refreshToken != null;

  /// Cliente sem `Authorization` e sem renovação automática. Usado pelas
  /// rotas públicas de `/auth` e pelo próprio refresh — se o refresh
  /// passasse pelo interceptor, um 401 nele dispararia outro refresh.
  /// `late` para ser construído na primeira chamada, não junto do
  /// singleton: assim não depende de `AppTls.initialize()` já ter rodado no
  /// instante em que alguém toca em `ApiClient.instance`.
  late final Dio public = _build(Dio(BaseOptions(
    baseUrl: AppConfig.backendBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  )));

  /// Liga o cliente à CA interna. Todo `Dio` do app passa por aqui — o
  /// `dart:io` não confia nela por conta própria (ver `tls.dart`).
  static Dio _build(Dio dio) {
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: AppTls.newHttpClient,
    );
    return dio;
  }

  /// Cria um cliente autenticado. Cada serviço pede o seu porque os timeouts
  /// diferem muito (o upload espera minutos; o polling de status, segundos) —
  /// o que é compartilhado é o token, não a configuração de rede.
  Dio client({
    Duration connectTimeout = const Duration(seconds: 15),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) {
    final dio = _build(Dio(BaseOptions(
      baseUrl: AppConfig.backendBaseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
    )));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        await _ensureFresh();
        final token = _accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final retried = await _retryAfterRefresh(dio, error);
        if (retried != null) {
          handler.resolve(retried);
        } else {
          handler.next(error);
        }
      },
    ));
    return dio;
  }

  /// Access token válido, renovado se estava perto de vencer. O WebSocket
  /// precisa dele explicitamente: o handshake não aceita header
  /// `Authorization`, então o backend lê o token de `?token=`.
  Future<String?> validAccessToken() async {
    await _ensureFresh();
    return _accessToken;
  }

  /// Recarrega a sessão persistida. Chamado uma vez no boot do app.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_keyAccess);
    _refreshToken = prefs.getString(_keyRefresh);
    _userId = prefs.getString(_keyUserId);
    final raw = prefs.getString(_keyExpiresAt);
    _expiresAt = raw == null ? null : DateTime.tryParse(raw);
  }

  /// Registra de quem é a sessão, depois que `/auth/me` responde.
  Future<void> setUserId(String userId) async {
    _userId = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, userId);
  }

  /// Guarda o par de tokens devolvido por `/auth/login` ou `/auth/refresh`.
  Future<void> saveSession(Map<String, dynamic> tokenPair) async {
    _accessToken = tokenPair['access_token'] as String?;
    _refreshToken = tokenPair['refresh_token'] as String?;
    final expiresIn = (tokenPair['expires_in'] as num?)?.toInt();
    _expiresAt = expiresIn == null
        ? null
        : DateTime.now().add(Duration(seconds: expiresIn));

    final prefs = await SharedPreferences.getInstance();
    await _write(prefs, _keyAccess, _accessToken);
    await _write(prefs, _keyRefresh, _refreshToken);
    await _write(prefs, _keyExpiresAt, _expiresAt?.toIso8601String());
  }

  /// Encerra a sessão. Não toca nos dados escopados do usuário (histórico,
  /// participantes, cache): eles continuam no aparelho, isolados sob a chave
  /// dele, e voltam quando ele entrar de novo.
  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    _userId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccess);
    await prefs.remove(_keyRefresh);
    await prefs.remove(_keyExpiresAt);
    await prefs.remove(_keyUserId);
  }

  /// Token de refresh atual — `/auth/logout` precisa mandá-lo no corpo para
  /// o backend revogá-lo de fato, em vez de só esquecê-lo aqui.
  String? get refreshToken => _refreshToken;

  Future<void> _write(SharedPreferences prefs, String key, String? value) {
    return value == null ? prefs.remove(key) : prefs.setString(key, value);
  }

  /// Renova o access token se ele estiver vencido ou perto disso.
  Future<void> _ensureFresh() async {
    if (_refreshToken == null) return;
    final expiresAt = _expiresAt;
    if (expiresAt != null &&
        DateTime.now().isBefore(expiresAt.subtract(_renewMargin))) {
      return;
    }
    await _refresh();
  }

  /// Uma renovação por vez; chamadas concorrentes aguardam a mesma.
  Future<bool> _refresh() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _doRefresh() async {
    final token = _refreshToken;
    if (token == null) return false;
    try {
      final response = await public.post(
        '/auth/refresh',
        data: {'refresh_token': token},
      );
      await saveSession(response.data as Map<String, dynamic>);
      return true;
    } on DioException catch (e) {
      // 401 aqui é definitivo: o refresh token foi revogado ou expirou.
      // Erro de rede, não — vale manter a sessão e tentar de novo depois,
      // senão uma queda de Wi-Fi deslogaria o usuário.
      if (e.response?.statusCode == 401) {
        await _expireSession();
      }
      return false;
    }
  }

  Future<void> _expireSession() async {
    await clearSession();
    _sessionExpired.add(null);
  }

  /// Reenvia uma requisição que tomou 401, uma única vez, depois de renovar.
  /// Devolve `null` quando não há o que reenviar (e o erro segue adiante).
  ///
  /// Na prática este caminho é raro — `_ensureFresh` renova antes de enviar.
  /// Ele cobre o resto: token revogado no servidor, relógio muito fora de
  /// hora, ou um `expires_in` em que não dá para confiar.
  Future<Response<dynamic>?> _retryAfterRefresh(
    Dio dio,
    DioException error,
  ) async {
    final options = error.requestOptions;
    if (error.response?.statusCode != 401) return null;
    if (options.extra[_retriedFlag] == true) return null;
    if (_refreshToken == null) return null;

    if (!await _refresh()) {
      await _expireSession();
      return null;
    }

    options.extra[_retriedFlag] = true;
    options.headers['Authorization'] = 'Bearer $_accessToken';
    // O corpo multipart já foi consumido no primeiro envio; `clone()` monta
    // um novo a partir do arquivo em disco. Sem isto, o reenvio de um upload
    // subiria um corpo vazio.
    if (options.data is FormData) {
      options.data = (options.data as FormData).clone();
    }

    try {
      return await dio.fetch(options);
    } on DioException {
      return null;
    }
  }
}
