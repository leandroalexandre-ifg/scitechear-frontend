import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/meeting.dart';

/// Histórico local de reuniões enviadas ao backend (metadados apenas).
class MeetingHistoryService {
  static const _key = 'meeting_history';

  Future<List<Meeting>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    final meetings = list
        .map((e) => Meeting.fromJson(e as Map<String, dynamic>))
        .toList();
    meetings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return meetings;
  }

  Future<void> _saveAll(List<Meeting> meetings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(meetings.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> add(Meeting meeting) async {
    final all = await loadAll();
    all.add(meeting);
    await _saveAll(all);
  }

  Future<void> remove(String id) async {
    final all = await loadAll();
    all.removeWhere((m) => m.id == id);
    await _saveAll(all);
  }

  Future<void> update(Meeting meeting) async {
    final all = await loadAll();
    final i = all.indexWhere((m) => m.id == meeting.id);
    if (i == -1) return;
    all[i] = meeting;
    await _saveAll(all);
  }
}
