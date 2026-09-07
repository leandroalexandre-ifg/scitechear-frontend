import 'dart:convert';
import 'dart:typed_data';

import 'package:app/services/api_client.dart';
import 'package:app/services/status_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.respond);

  final ResponseBody Function(int call) respond;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return respond(calls++);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  final api = ApiClient.instance;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // Sem sessão salva o WebSocket nem é tentado — `watchStatus` vai direto
    // para o polling, que é o caminho sob teste aqui.
    await api.clearSession();
  });

  test('404 no polling vira "removed", não "offline"', () async {
    // Reunião apagada em outro aparelho enquanto a tela de processamento
    // estava aberta. Sem esta distinção, o app gastaria quatro tentativas
    // para então dizer "verifique sua conexão" — mandando o usuário procurar
    // defeito na rede dele, que está perfeita.
    final adapter = _ScriptedAdapter((_) => _json({'detail': 'não existe'},
        status: 404));
    final service = StatusService(
      dio: ApiClient.instance.client()..httpClientAdapter = adapter,
      pollInterval: Duration.zero,
    );

    final emitted = await service.watchStatus('job-1').toList();

    expect(emitted, ['removed']);
    // Terminal na primeira resposta: não insiste no que já é definitivo.
    expect(adapter.calls, 1);
  });

  test('erro de rede continua virando "offline" depois de insistir', () async {
    final adapter = _ScriptedAdapter((_) => _json({}, status: 500));
    final service = StatusService(
      dio: ApiClient.instance.client()..httpClientAdapter = adapter,
      pollInterval: Duration.zero,
    );

    final emitted = await service.watchStatus('job-1').toList();

    expect(emitted, ['offline']);
    expect(adapter.calls, greaterThan(1));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('o estado terminal fecha o stream', () async {
    final adapter = _ScriptedAdapter((call) => _json({
          'job_id': 'job-1',
          'status': call == 0 ? 'transcribing' : 'done',
        }));
    final service = StatusService(
      dio: ApiClient.instance.client()..httpClientAdapter = adapter,
      pollInterval: Duration.zero,
    );

    final emitted = await service.watchStatus('job-1').toList();

    expect(emitted, ['transcribing', 'done']);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
