import 'dart:convert';
import 'dart:typed_data';

import 'package:app/models/participant.dart';
import 'package:app/services/api_client.dart';
import 'package:app/services/participant_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adaptador falso roteirizado por caminho, que registra o que foi chamado.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final List<String> deleted = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'DELETE') deleted.add(options.path);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _empty(int status) => ResponseBody.fromString(
      '',
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
    await api.clearSession();
    await api.saveSession({
      'access_token': 'a1',
      'refresh_token': 'r1',
      'token_type': 'bearer',
      'expires_in': 1800,
    });
    await api.setUserId('user-1');
  });

  /// Instala um participante já cadastrado e devolve um serviço cujo HTTP
  /// responde pelo [adapter], sem passar pela tela nem pela rede.
  Future<ParticipantService> serviceWith(
    Participant p,
    HttpClientAdapter adapter,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'uuser-1:registered_participants',
      jsonEncode([p.toJson()]),
    );
    return ParticipantService(
      dio: ApiClient.instance.client()..httpClientAdapter = adapter,
    );
  }

  const participant = Participant(id: 'p-1', name: 'Ana');

  test('o id sobrevive quando o DELETE do perfil de voz falha', () async {
    // O backend não tem rota que liste participantes: quem esquece o id perde
    // a única forma de alcançar aquele perfil, e a gravação de voz fica no
    // servidor para sempre, invisível e inapagável.
    final service = await serviceWith(participant, _ScriptedAdapter((_) => _empty(500)));

    final remoteDeleted = await service.remove('p-1');

    expect(remoteDeleted, isFalse);
    // Sumiu da lista local — o usuário pediu para remover, e removeu.
    expect(await service.loadAll(), isEmpty);
    // Mas o id ficou guardado para uma segunda tentativa.
    expect(await service.pendingDeletions(), ['p-1']);
  });

  test('a exclusão pendente é retomada e some da fila', () async {
    final failing = await serviceWith(participant, _ScriptedAdapter((_) => _empty(500)));
    await failing.remove('p-1');
    expect(await failing.pendingDeletions(), ['p-1']);

    final adapter = _ScriptedAdapter((_) => _empty(204));
    final service = ParticipantService(
      dio: ApiClient.instance.client()..httpClientAdapter = adapter,
    );
    final done = await service.retryPendingDeletions();

    expect(done, 1);
    expect(adapter.deleted, ['/participants/p-1/voice-profile']);
    expect(await service.pendingDeletions(), isEmpty);
  });

  test('404 encerra a pendência — o perfil já não existe', () async {
    // O objetivo era o perfil não existir mais, e ele não existe. Insistir
    // manteria um id numa fila que nunca esvazia.
    final service = await serviceWith(participant, _ScriptedAdapter((_) => _empty(404)));

    final remoteDeleted = await service.remove('p-1');

    expect(remoteDeleted, isTrue);
    expect(await service.pendingDeletions(), isEmpty);
  });

  test('a fila não acumula o mesmo id duas vezes', () async {
    final service = await serviceWith(participant, _ScriptedAdapter((_) => _empty(500)));

    await service.remove('p-1');
    await service.retryPendingDeletions();
    await service.retryPendingDeletions();

    expect(await service.pendingDeletions(), ['p-1']);
  });

  test('a fila de exclusões é escopada por usuário', () async {
    // Um id só faz sentido dentro do namespace de quem o criou: o perfil vive
    // em storage/voices/<user_id>/<participant_id>/ no servidor.
    final service = await serviceWith(participant, _ScriptedAdapter((_) => _empty(500)));
    await service.remove('p-1');

    await api.setUserId('user-2');
    expect(await ParticipantService().pendingDeletions(), isEmpty);

    await api.setUserId('user-1');
    expect(await ParticipantService().pendingDeletions(), ['p-1']);
  });
}
