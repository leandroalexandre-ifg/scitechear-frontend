import 'dart:convert';

import 'package:app/models/meeting.dart';
import 'package:app/models/meeting_result.dart';
import 'package:app/models/participant.dart';
import 'package:app/services/api_client.dart';
import 'package:app/services/local_scope.dart';
import 'package:app/services/meeting_service.dart';
import 'package:app/services/offline_service.dart';
import 'package:app/services/participant_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Meeting _meeting(String id, String title) => Meeting(
      id: id,
      jobId: 'job-$id',
      title: title,
      createdAt: DateTime(2026, 9, 7),
      participantNames: const ['José'],
    );

MeetingResult _result(String jobId, String text) => MeetingResult(
      jobId: jobId,
      status: 'done',
      segments: [
        TranscriptSegment(
          id: 'seg_1',
          cluster: 'SPEAKER_00',
          identified: false,
          start: 0,
          end: 1,
          text: text,
        ),
      ],
      questions: const [],
    );

void main() {
  final api = ApiClient.instance;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await api.clearSession();
  });

  test('histórico de um usuário não aparece para outro', () async {
    await api.setUserId('user-a');
    await MeetingHistoryService().add(_meeting('1', 'Reunião da Ana'));
    expect((await MeetingHistoryService().loadAll()).length, 1);

    // Troca de conta no mesmo aparelho.
    await api.clearSession();
    await api.setUserId('user-b');

    expect(await MeetingHistoryService().loadAll(), isEmpty);
  });

  test('transcrição em cache não é legível por outro usuário', () async {
    await api.setUserId('user-a');
    await LocalResultCache().save('job-1', _result('job-1', 'assunto sigiloso'));

    await api.clearSession();
    await api.setUserId('user-b');

    // O caso mais sério: o cache abre resultado sem consultar o backend,
    // então uma chave global entregaria a transcrição sem passar pelo
    // escopo do servidor.
    expect(await LocalResultCache().load('job-1'), isNull);
  });

  test('participantes e amostras de voz não vazam entre contas', () async {
    await api.setUserId('user-a');
    await ParticipantService().add(
      const Participant(id: 'p1', name: 'José', colorIndex: 0),
    );
    expect((await ParticipantService().loadAll()).length, 1);

    await api.clearSession();
    await api.setUserId('user-b');

    expect(await ParticipantService().loadAll(), isEmpty);
  });

  test('os dados voltam quando o dono entra de novo', () async {
    await api.setUserId('user-a');
    await MeetingHistoryService().add(_meeting('1', 'Reunião da Ana'));

    await api.clearSession();
    await api.setUserId('user-b');
    await MeetingHistoryService().add(_meeting('2', 'Reunião do Bruno'));

    await api.clearSession();
    await api.setUserId('user-a');

    final ana = await MeetingHistoryService().loadAll();
    expect(ana.map((m) => m.title), ['Reunião da Ana']);
  });

  test('adota dados legados para o primeiro usuário que loga', () async {
    // Estado de quem já usava o app antes do escopo por usuário existir.
    SharedPreferences.setMockInitialValues({
      'meeting_history': jsonEncode([_meeting('1', 'Reunião antiga').toJson()]),
      'result_job-1': jsonEncode(_result('job-1', 'texto antigo').toJson()),
    });

    await api.setUserId('user-a');
    await LocalScope.adoptLegacyData();

    expect((await MeetingHistoryService().loadAll()).length, 1);
    expect((await LocalResultCache().load('job-1'))?.segments.first.text,
        'texto antigo');

    // A chave global some, senão o próximo usuário a logar adotaria os
    // mesmos dados e o vazamento voltaria por outro caminho.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('meeting_history'), isFalse);
    expect(prefs.containsKey('result_job-1'), isFalse);

    await api.clearSession();
    await api.setUserId('user-b');
    expect(await MeetingHistoryService().loadAll(), isEmpty);
  });

  test('a adoção não sobrescreve dados que o usuário já tem', () async {
    SharedPreferences.setMockInitialValues({
      'meeting_history': jsonEncode([_meeting('1', 'Reunião antiga').toJson()]),
    });

    await api.setUserId('user-a');
    await MeetingHistoryService().add(_meeting('2', 'Reunião nova'));
    await LocalScope.adoptLegacyData();

    final titles =
        (await MeetingHistoryService().loadAll()).map((m) => m.title).toList();
    expect(titles, ['Reunião nova']);
  });

  test('sem usuário logado, o escopo é isolado de qualquer conta real',
      () async {
    await MeetingHistoryService().add(_meeting('1', 'Sem sessão'));

    await api.setUserId('user-a');

    expect(await MeetingHistoryService().loadAll(), isEmpty);
  });
}
