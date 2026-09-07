class Participant {
  final String id;
  final String name;
  final String? voiceSamplePath;
  final int colorIndex;

  /// True quando o servidor tem o perfil de voz deste participante — porque
  /// `voiceSamplePath` foi enviado via POST /participants/{id}/voice-samples,
  /// ou porque `GET /participants` o listou.
  final bool voiceProfileSynced;

  const Participant({
    required this.id,
    required this.name,
    this.voiceSamplePath,
    this.colorIndex = 0,
    this.voiceProfileSynced = false,
  });

  /// Há um WAV **neste aparelho** — o que `syncVoiceSample` tem para enviar.
  bool get hasVoiceSample => voiceSamplePath != null;

  /// Esta pessoa tem voz cadastrada, aqui ou no servidor.
  ///
  /// Depois de reinstalar o app, `GET /participants` devolve os participantes
  /// da conta e o cadastro é semeado de volta: eles têm perfil de voz no
  /// servidor e nenhum arquivo local. É esta a pergunta que a tela faz — "esta
  /// pessoa precisa gravar voz?" —, não a de [hasVoiceSample].
  bool get hasVoiceProfile => voiceProfileSynced || hasVoiceSample;

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
