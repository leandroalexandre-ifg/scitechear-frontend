class Participant {
  final String id;
  final String name;
  final String? voiceSamplePath;
  final int colorIndex;

  /// True quando `voiceSamplePath` já foi sincronizado com o backend via
  /// POST /participants/{id}/voice-samples.
  final bool voiceProfileSynced;

  const Participant({
    required this.id,
    required this.name,
    this.voiceSamplePath,
    this.colorIndex = 0,
    this.voiceProfileSynced = false,
  });

  bool get hasVoiceSample => voiceSamplePath != null;

  Participant copyWith({
    String? name,
    String? voiceSamplePath,
    bool? voiceProfileSynced,
  }) => Participant(
    id: id,
    name: name ?? this.name,
    voiceSamplePath: voiceSamplePath ?? this.voiceSamplePath,
    // Uma amostra nova invalida a sincronização anterior, a menos que o
    // chamador passe voiceProfileSynced explicitamente.
    voiceProfileSynced:
        voiceProfileSynced ??
        (voiceSamplePath != null ? false : this.voiceProfileSynced),
    colorIndex: colorIndex,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'voiceSamplePath': voiceSamplePath,
    'colorIndex': colorIndex,
    'voiceProfileSynced': voiceProfileSynced,
  };

  factory Participant.fromJson(Map<String, dynamic> json) => Participant(
    id: json['id'] as String,
    name: json['name'] as String,
    voiceSamplePath: json['voiceSamplePath'] as String?,
    colorIndex: json['colorIndex'] as int? ?? 0,
    voiceProfileSynced: json['voiceProfileSynced'] as bool? ?? false,
  );
}
