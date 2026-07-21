import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/participant.dart';

/// Cadastro persistente de participantes (com biometria de voz), reutilizável
/// entre reuniões diferentes.
class ParticipantService {
  static const _key = 'registered_participants';

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

  Future<void> remove(String id) async {
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
  }
}
