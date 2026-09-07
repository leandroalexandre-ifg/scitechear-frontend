import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/participant.dart';
import 'api_client.dart';
import 'local_scope.dart';

/// Falha ao enviar a amostra de voz ao backend.
///
/// [permanent] separa o que reenviar resolve (queda de rede, servidor fora do
/// ar) do que não resolve (amostra grande demais). Sem essa distinção a tela
/// diria "tente mais tarde" para os dois casos, e no segundo o usuário
/// tentaria para sempre.
class VoiceSampleException implements Exception {
  final String message;
  final bool permanent;
  VoiceSampleException(this.message, {this.permanent = false});

  @override
  String toString() => message;
}

/// Estado do perfil de voz de um participante **segundo o servidor**.
///
/// Vem de `GET /participants/{id}/voice-profile`. Existe porque o app e o
/// servidor podem discordar: uma queda de rede no meio do envio da amostra
/// deixa o app achando que não sincronizou (ou que sincronizou) sem que isso
/// corresponda ao que o backend guardou.
class VoiceProfileStatus {
  final bool exists;
  final int sampleCount;

  const VoiceProfileStatus({required this.exists, required this.sampleCount});

  factory VoiceProfileStatus.fromJson(Map<String, dynamic> json) =>
      VoiceProfileStatus(
        exists: json['exists'] as bool? ?? false,
        sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
      );
}

/// Cadastro persistente de participantes (com biometria de voz), reutilizável
/// entre reuniões diferentes.
class ParticipantService {
  // Escopada por usuário: o cadastro inclui o caminho das amostras de voz,
  // que são biometria de uma pessoa específica.
  static String get _key => LocalScope.key('registered_participants');

  /// Ids cujo perfil de voz remoto ainda precisa ser apagado.
  ///
  /// O backend não tem rota que liste participantes: as três rotas de
  /// `/participants` exigem que o chamador já saiba o id. Um perfil cujo id o
  /// app esqueceu fica invisível **e** inapagável no servidor — gravação de
  /// voz de uma pessoa real que ninguém consegue mais alcançar.
  ///
  /// Por isso o id sobrevive à remoção local quando o `DELETE` falha: é a
  /// única referência que existe para aquele perfil.
  static String get _pendingDeletionsKey =>
      LocalScope.key('pending_voice_profile_deletions');

  /// O cliente HTTP é injetável só para os testes poderem trocar o adaptador;
  /// em produção sempre vem do [ApiClient], que é quem sabe do `Bearer`.
  ParticipantService({Dio? dio}) : _dio = dio ?? ApiClient.instance.client();

  final Dio _dio;

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

    try {
      await _dio.post('/participants/${participant.id}/voice-samples',
          data: formData);
    } on DioException catch (e) {
      // 413: teto de 25 MB (`MAX_VOICE_SAMPLE_MB`). Com os 20s que a folha de
      // gravação permite (~640 KB) isto não deveria acontecer nunca — mas se
      // acontecer, é a amostra que está errada, não a rede, e reenviar a
      // mesma não vai adiantar.
      if (e.response?.statusCode == 413) {
        throw VoiceSampleException(
          'A amostra de voz é grande demais para o servidor. '
          'Grave uma amostra mais curta.',
          permanent: true,
        );
      }
      throw VoiceSampleException(
        'Não foi possível enviar a amostra de voz ao servidor agora.',
      );
    }

    await update(participant.copyWith(voiceProfileSynced: true));
  }

  /// Estado do perfil de voz no servidor, ou `null` se não deu para perguntar.
  ///
  /// `null` é "não sei", e não "não existe": tratar falha de rede como
  /// ausência faria a tela dizer que a biometria sumiu toda vez que o servidor
  /// estivesse fora do ar.
  Future<VoiceProfileStatus?> fetchVoiceProfile(String id) async {
    try {
      final response = await _dio.get('/participants/$id/voice-profile');
      return VoiceProfileStatus.fromJson(
          response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Alinha o `voiceProfileSynced` local ao que o servidor de fato tem.
  ///
  /// Consulta um participante por vez (o endpoint é por id) e só grava quando
  /// há divergência. Serve para o caso de o envio da amostra cair no meio: o
  /// app pode estar mostrando "não sincronizado" para uma amostra que chegou,
  /// ou o contrário, se o perfil foi apagado no servidor.
  ///
  /// Best-effort: participante que não respondeu fica como está.
  Future<List<Participant>> reconcileVoiceProfiles() async {
    final all = await loadAll();
    var changed = false;

    for (var i = 0; i < all.length; i++) {
      final p = all[i];
      if (!p.hasVoiceSample) continue;
      final remote = await fetchVoiceProfile(p.id);
      if (remote == null) continue;
      if (remote.exists != p.voiceProfileSynced) {
        all[i] = p.copyWith(voiceProfileSynced: remote.exists);
        changed = true;
      }
    }

    if (changed) await _saveAll(all);
    return all;
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

    return _deleteRemoteProfile(id);
  }

  /// Apaga o perfil de voz no servidor, guardando o id para depois se falhar.
  ///
  /// 404 conta como sucesso: o objetivo era o perfil não existir mais, e ele
  /// não existe. Insistir só manteria o id numa fila que nunca esvazia.
  Future<bool> _deleteRemoteProfile(String id) async {
    try {
      await _dio.delete('/participants/$id/voice-profile');
      await _forgetPendingDeletion(id);
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        await _forgetPendingDeletion(id);
        return true;
      }
      await _rememberPendingDeletion(id);
      return false;
    } catch (_) {
      await _rememberPendingDeletion(id);
      return false;
    }
  }

  /// Tenta de novo as exclusões que ficaram pendentes.
  ///
  /// Best-effort e silenciosa: roda quando a tela de participantes abre, que
  /// é a próxima vez em que se sabe que há rede e sessão válida. Devolve
  /// quantas foram concluídas, para teste.
  Future<int> retryPendingDeletions() async {
    final pending = await pendingDeletions();
    if (pending.isEmpty) return 0;

    var done = 0;
    for (final id in pending) {
      if (await _deleteRemoteProfile(id)) done++;
    }
    return done;
  }

  Future<List<String>> pendingDeletions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingDeletionsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toList();
  }

  Future<void> _rememberPendingDeletion(String id) async {
    final pending = await pendingDeletions();
    if (pending.contains(id)) return;
    pending.add(id);
    await _savePendingDeletions(pending);
  }

  Future<void> _forgetPendingDeletion(String id) async {
    final pending = await pendingDeletions();
    if (!pending.remove(id)) return;
    await _savePendingDeletions(pending);
  }

  Future<void> _savePendingDeletions(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    if (ids.isEmpty) {
      await prefs.remove(_pendingDeletionsKey);
    } else {
      await prefs.setString(_pendingDeletionsKey, jsonEncode(ids));
    }
  }
}
