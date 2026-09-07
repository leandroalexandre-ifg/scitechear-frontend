import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/services/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adaptador falso: responde a partir de um roteiro e registra o que foi
/// pedido, para os testes afirmarem sobre as chamadas de rede sem servidor.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

Map<String, dynamic> _tokenPair(String access, {int expiresIn = 1800}) => {
      'access_token': access,
      'refresh_token': 'refresh-$access',
      'token_type': 'bearer',
      'expires_in': expiresIn,
    };

void main() {
  final api = ApiClient.instance;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await api.clearSession();
  });

  test('persiste o par de tokens e o recupera no boot', () async {
    await api.saveSession(_tokenPair('a1'));
    expect(api.hasSession, isTrue);
    expect(api.refreshToken, 'refresh-a1');

    // Simula uma nova abertura do app: o estado em memória some, mas o que
    // foi para o disco tem que voltar.
    await api.clearSession();
    SharedPreferences.setMockInitialValues({
      'auth_access_token': 'a1',
      'auth_refresh_token': 'refresh-a1',
      'auth_expires_at':
          DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
    });
    await api.restore();

    expect(api.hasSession, isTrue);
    expect(await api.validAccessToken(), 'a1');
  });

  test('injeta o Bearer nas chamadas autenticadas', () async {
    await api.saveSession(_tokenPair('a1'));

    RequestOptions? seen;
    final adapter = _FakeAdapter((options) {
      seen = options;
      return _json({'ok': true});
    });
    final dio = api.client()..httpClientAdapter = adapter;

    await dio.get('/status/job-1');

    expect(seen?.headers['Authorization'], 'Bearer a1');
  });

  test('renova uma única vez quando várias chamadas tomam 401 juntas',
      () async {
    await api.saveSession(_tokenPair('velho'));

    var refreshCount = 0;
    var refreshed = false;

    final authAdapter = _FakeAdapter((options) {
      refreshCount++;
      refreshed = true;
      return _json(_tokenPair('novo'));
    });
    api.public.httpClientAdapter = authAdapter;

    final adapter = _FakeAdapter((options) {
      // Só aceita o token novo: antes da renovação, tudo é 401.
      if (options.headers['Authorization'] == 'Bearer novo') {
        return _json({'status': 'queued'});
      }
      return _json({'detail': 'Token expirado.'}, status: 401);
    });
    final dio = api.client()..httpClientAdapter = adapter;

    final responses = await Future.wait([
      dio.get('/status/job-1'),
      dio.get('/status/job-2'),
      dio.get('/status/job-3'),
    ]);

    expect(refreshed, isTrue);
    // O backend revoga o refresh token assim que ele é usado: se cada uma
    // das três chamadas disparasse a própria renovação, duas falhariam.
    expect(refreshCount, 1);
    for (final response in responses) {
      expect(response.statusCode, 200);
    }
  });

  test('renova proativamente quando o token está perto de vencer', () async {
    // 60s de vida restante, abaixo da margem de 2 minutos.
    await api.saveSession(_tokenPair('quase-vencido', expiresIn: 60));

    final authAdapter = _FakeAdapter((_) => _json(_tokenPair('novo')));
    api.public.httpClientAdapter = authAdapter;

    final adapter = _FakeAdapter((_) => _json({'ok': true}));
    final dio = api.client()..httpClientAdapter = adapter;

    await dio.get('/status/job-1');

    // Renovou antes de enviar, sem precisar levar um 401 primeiro.
    expect(authAdapter.paths, ['/auth/refresh']);
    expect(await api.validAccessToken(), 'novo');
  });

  test('derruba a sessão e avisa quando o refresh é recusado', () async {
    await api.saveSession(_tokenPair('velho'));

    api.public.httpClientAdapter = _FakeAdapter(
      (_) => _json({'detail': 'Refresh token inválido.'}, status: 401),
    );
    final dio = api.client()
      ..httpClientAdapter = _FakeAdapter(
        (_) => _json({'detail': 'Token expirado.'}, status: 401),
      );

    final expired = api.onSessionExpired.first;

    await expectLater(dio.get('/status/job-1'), throwsA(isA<DioException>()));
    await expired.timeout(const Duration(seconds: 2));

    expect(api.hasSession, isFalse);
    expect(api.refreshToken, isNull);
  });

  test('falha de rede no refresh não desloga o usuário', () async {
    await api.saveSession(_tokenPair('velho', expiresIn: 60));

    // Sem resposta do servidor: é queda de conexão, não credencial inválida.
    api.public.httpClientAdapter = _FakeAdapter((options) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'sem rede',
      );
    });
    final dio = api.client()
      ..httpClientAdapter = _FakeAdapter((_) => _json({'ok': true}));

    await dio.get('/status/job-1').catchError((_) => Response<dynamic>(
          requestOptions: RequestOptions(path: '/status/job-1'),
        ));

    // O refresh token continua no disco para a próxima tentativa — perder a
    // sessão a cada oscilação de Wi-Fi seria pior do que um erro passageiro.
    expect(api.hasSession, isTrue);
  });
}
