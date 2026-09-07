import 'dart:convert';
import 'dart:typed_data';

import 'package:app/models/participant.dart';
import 'package:app/services/api_client.dart';
import 'package:app/services/participant_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Responde à listagem com um roteiro e conta o que foi chamado.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.participants, this.listStatus = 200, this.deleteStatus = 204});

  final List<Map<String, dynamic>>? participants;
  final int listStatus;
  final int deleteStatus;

  int listCalls = 0;
  final List<String> deleted = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'DELETE') {
      deleted.add(options.path);
      return ResponseBody.fromString('', deleteStatus, headers: _headers);
    }
    listCalls++;
    return ResponseBody.fromString(
      jsonEncode(participants ?? []),
      listStatus,
      headers: _headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

const _headers = {
  Headers.contentTypeHeader: [Headers.jsonContentType],
};

Map<String, dynamic> _remote(String id, {String? name, int samples = 1}) => {
      'participant_id': id,
      'name': name,
      'sample_count': samples,
      'model_version': 'speechbrain/spkrec-ecapa-voxceleb',
      'updated_at': '2026-09-05T17:08:41.251151+00:00',
    };

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

  ParticipantService serviceWith(_Adapter adapter) => ParticipantService(
        dio: ApiClient.instance.client()..httpClientAdapter = adapter,
      );

  Future<void> seedLocal(List<Participant> ps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'uuser-1:registered_participants',
      jsonEncode(ps.map((p) => p.toJson()).toList()),
    );
  }

  group('reinstalação', () {
    test('semeia o cadastro a partir do servidor quando não há nada local',
        () async {
      // O caso que órfava perfis: sem isto o usuário recadastraria as mesmas
      // pessoas com ids novos, e os perfis antigos ficariam inalcançáveis —
      // o id é a única forma de chegar neles.
      final service = serviceWith(_Adapter(participants: [
        _remote('1757260145123456', name: 'Ana Ribeiro', samples: 3),
        _remote('1757260145123457', name: 'Bruno Alves'),
      ]));

      final result = await service.seedFromServerIfEmpty();

      expect(result.map((p) => p.name), ['Ana Ribeiro', 'Bruno Alves']);
      expect(result.map((p) => p.id), ['1757260145123456', '1757260145123457']);
      // Voz no servidor, WAV nenhum neste aparelho: nada para regravar.
      expect(result.every((p) => p.hasVoiceProfile), isTrue);
      expect(result.every((p) => p.hasVoiceSample), isFalse);
      // E ficou persistido, não só devolvido.
      expect((await service.loadAll()).length, 2);
    });

    test('não mexe no cadastro quando já existe algo local', () async {
      await seedLocal([const Participant(id: 'p-local', name: 'Carla')]);
      final adapter = _Adapter(participants: [_remote('p-remoto')]);

      final result = await serviceWith(adapter).seedFromServerIfEmpty();

      expect(result.map((p) => p.id), ['p-local']);
      expect(adapter.listCalls, 0);
    });

    test('nome nulo ganha um rótulo distinguível, e o id é preservado',
        () async {
      // O app sempre manda o `name`, mas outro cliente pode não mandar. O que
      // importa recuperar é o id.
      final service = serviceWith(_Adapter(participants: [
        _remote('1757260145123456'),
        _remote('1757260145129999'),
      ]));

      final result = await service.seedFromServerIfEmpty();

      expect(result.map((p) => p.name), ['Participante 3456', 'Participante 9999']);
      expect(result.map((p) => p.id), ['1757260145123456', '1757260145129999']);
    });
  });

  group('reconciliação', () {
    test('marca como sincronizado o que o servidor confirma', () async {
      await seedLocal([
        const Participant(id: 'p-1', name: 'Ana', voiceSamplePath: '/tmp/a.wav'),
      ]);
      final service = serviceWith(_Adapter(participants: [_remote('p-1')]));

      final result = await service.syncFromServer();

      expect(result.single.voiceProfileSynced, isTrue);
    });

    test('perfil que sumiu do servidor volta a "não sincronizado", mas o '
        'participante fica', () async {
      await seedLocal([
        const Participant(
          id: 'p-1',
          name: 'Ana',
          voiceSamplePath: '/tmp/a.wav',
          voiceProfileSynced: true,
        ),
      ]);
      final service = serviceWith(_Adapter(participants: []));

      final result = await service.syncFromServer();

      // O cadastro é do usuário: some quando ele mandar, não quando o
      // servidor deixar de listar.
      expect(result.single.id, 'p-1');
      expect(result.single.voiceProfileSynced, isFalse);
    });

    test('uma chamada só, não uma por participante', () async {
      await seedLocal([
        const Participant(id: 'p-1', name: 'Ana', voiceSamplePath: '/a.wav'),
        const Participant(id: 'p-2', name: 'Bruno', voiceSamplePath: '/b.wav'),
        const Participant(id: 'p-3', name: 'Carla', voiceSamplePath: '/c.wav'),
      ]);
      final adapter = _Adapter(participants: [_remote('p-1'), _remote('p-2')]);

      await serviceWith(adapter).syncFromServer();

      expect(adapter.listCalls, 1);
    });

    test('falha de rede não é ausência: nada muda', () async {
      await seedLocal([
        const Participant(
          id: 'p-1',
          name: 'Ana',
          voiceSamplePath: '/tmp/a.wav',
          voiceProfileSynced: true,
        ),
      ]);
      final service = serviceWith(_Adapter(listStatus: 500));

      final result = await service.syncFromServer();

      expect(result.single.voiceProfileSynced, isTrue);
    });
  });

  group('exclusão pendente vs. listagem', () {
    /// Deixa 'p-1' removido localmente e pendente de exclusão no servidor,
    /// que é o estado de quem apagou um participante sem rede.
    Future<void> removeWhileOffline() async {
      await seedLocal([const Participant(id: 'p-1', name: 'Ana')]);
      final offline = serviceWith(_Adapter(deleteStatus: 500));
      await offline.remove('p-1');
      expect(await offline.pendingDeletions(), ['p-1']);
    }

    test('a exclusão é retomada antes da listagem', () async {
      // A ordem importa: a exclusão vem primeiro justamente para o servidor
      // já não listar o perfil quando a listagem chegar.
      await removeWhileOffline();

      final adapter = _Adapter(participants: []);
      final result = await serviceWith(adapter).syncFromServer();

      expect(adapter.deleted, ['/participants/p-1/voice-profile']);
      expect(result, isEmpty);
      expect(await serviceWith(adapter).pendingDeletions(), isEmpty);
    });

    test('se a exclusão falhar de novo, a listagem não ressuscita o '
        'participante', () async {
      // O DELETE continua falhando (500) enquanto o GET funciona, então o
      // servidor ainda lista o perfil. Sem o filtro pela fila, o app traria de
      // volta justamente quem o usuário mandou apagar.
      await removeWhileOffline();

      final adapter = _Adapter(
        participants: [_remote('p-1', name: 'Ana')],
        deleteStatus: 500,
      );
      final service = serviceWith(adapter);
      final result = await service.syncFromServer();

      expect(result, isEmpty);
      // E o id continua na fila, para uma próxima tentativa.
      expect(await service.pendingDeletions(), ['p-1']);
    });
  });
}
