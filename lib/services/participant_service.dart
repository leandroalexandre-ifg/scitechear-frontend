import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/participant.dart';
import 'api_client.dart';
import 'local_scope.dart';

/// Cadastro persistente de participantes (com biometria de voz), reutilizável
/// entre reuniões diferentes.
class ParticipantService {
  // Escopada por usuário: o cadastro inclui o caminho das amostras de voz,
  // que são biometria de uma pessoa específica.
  static String get _key => LocalScope.key('registered_participants');

  final Dio _dio = ApiClient.instance.client();

  Future<List<Participant>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Participant.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveAll(List<Participant> participants) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(participants.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> add(Participant participant) async {
    final all = await loadAll();
    all.add(participant);
    await _saveAll(all);
  }

  Future<void> update(Participant participant) async {
    final all = await loadAll();
    final idx = all.indexWhere((p) => p.id == participant.id);
    if (idx != -1) {
      all[idx] = participant;
      await _saveAll(all);
    }
  }

  /// Envia a amostra de voz local do participante ao backend, uma única vez
  /// (no cadastro/atualização — nunca por reunião). Em sucesso, marca
  /// [Participant.voiceProfileSynced] como true e persiste. Em falha, relança
  /// a exceção sem marcar como sincronizado, para a tela decidir como avisar.
  Future<void> syncVoiceSample(Participant participant) async {
    final path = participant.voiceSamplePath;
    if (path == null) return;

    final formData = FormData();
    formData.files.add(
      MapEntry('file', await MultipartFile.fromFile(path, filename: 'sample.wav')),
    );
    formData.fields.add(MapEntry('name', participant.name));

    await _dio.post('/participants/${participant.id}/voice-samples', data: formData);

    await update(participant.copyWith(voiceProfileSynced: true));
  }

  /// Remove o participante localmente (sempre) e tenta, best-effort, excluir
  /// o perfil de voz remoto. Retorna true se a exclusão remota também foi
  /// confirmada — falha de rede aqui nunca bloqueia a remoção local.
  Future<bool> remove(String id) async {
    final all = await loadAll();
    final removed = all.where((p) => p.id == id);
    for (final p in removed) {
      final path = p.voiceSamplePath;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
    all.removeWhere((p) => p.id == id);
    await _saveAll(all);

    try {
      await _dio.delete('/participants/$id/voice-profile');
      return true;
    } catch (_) {
      return false;
    }
  }
}
