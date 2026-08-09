// Modelos de dados que espelham o JSON retornado pelo backend.
//
// Formato canônico de GET /resultado/{job_id} (status == "done"):
// {
//   "job_id": "uuid",
//   "status": "done",
//   "segments": [{
//     "id": "seg_0001", "cluster": "SPEAKER_00", "participant_id": "p1" | null,
//     "speaker": "Leandro" | null, "identified": true, "confidence": 0.82 | null,
//     "start": 0.0, "end": 4.2, "text": "Bom dia."
//   }],
//   "questions": [{
//     "id": "P1", "type": "explicit" | "implicit", "text": "Qual é o prazo?",
//     "participant_id": "p1" | null, "speaker": "Leandro" | null, "time": 12.5 | null,
//     "source_segment_ids": ["seg_0004"]
//   }],
//   "metadata": {"whisperx_model", "diarization_model", "voice_model", "llm_model", "generated_at", "stub"}
// }
//
// Regra importante: "confidence" vem preenchido com o melhor score mesmo
// quando "identified" é false (rejeitado por threshold/margem) — não é por
// si só um sinal de identificação, só o campo "identified" diz isso.
// Perguntas "implicit" sempre têm participant_id/speaker/time nulos — nunca
// inventados pelo cliente.

/// Um trecho da transcrição com falante e marcação de tempo.
class TranscriptSegment {
  final String id;

  /// Label bruto de diarização (ex.: "SPEAKER_00"), sempre presente.
  final String cluster;
  final String? participantId;

  /// Nome resolvido do participante, ou null se não identificado.
  final String? speaker;
  final bool identified;

  /// Melhor score de identificação — presente mesmo quando [identified] é
  /// false. Nunca usar isto para inferir identificação, só [identified].
  final double? confidence;
  final double start;
  final double end;
  final String text;

  TranscriptSegment({
    required this.id,
    required this.cluster,
    this.participantId,
    this.speaker,
    required this.identified,
    this.confidence,
    required this.start,
    required this.end,
    required this.text,
  });

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      id: json['id'] as String? ?? '',
      cluster: json['cluster'] as String? ?? 'SPEAKER',
      participantId: json['participant_id'] as String?,
      speaker: json['speaker'] as String?,
      identified: json['identified'] as bool? ?? false,
      confidence: (json['confidence'] as num?)?.toDouble(),
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
      text: json['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'cluster': cluster,
    'participant_id': participantId,
    'speaker': speaker,
    'identified': identified,
    'confidence': confidence,
    'start': start,
    'end': end,
    'text': text,
  };
}

/// Tipo de uma pergunta extraída: dita explicitamente ou inferida do contexto.
enum QuestionType {
  explicit,
  implicit;

  static QuestionType fromString(String? value) {
    switch (value) {
      case 'implicit':
        return QuestionType.implicit;
      case 'explicit':
        return QuestionType.explicit;
      default:
        return QuestionType.explicit;
    }
  }

  @override
  String toString() => name;
}

/// Uma pergunta extraída da reunião.
class Question {
  final String id;
  final QuestionType type;
  final String text;
  final String? participantId;

  /// Nome do participante, null para perguntas implícitas (nunca inventado).
  final String? speaker;

  /// Instante em segundos, null para perguntas implícitas.
  final double? time;
  final List<String> sourceSegmentIds;

  Question({
    required this.id,
    required this.type,
    required this.text,
    this.participantId,
    this.speaker,
    this.time,
    this.sourceSegmentIds = const [],
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'] as String? ?? '',
      type: QuestionType.fromString(json['type'] as String?),
      text: json['text'] as String? ?? '',
      participantId: json['participant_id'] as String?,
      speaker: json['speaker'] as String?,
      time: (json['time'] as num?)?.toDouble(),
      sourceSegmentIds:
          (json['source_segment_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.toString(),
    'text': text,
    'participant_id': participantId,
    'speaker': speaker,
    'time': time,
    'source_segment_ids': sourceSegmentIds,
  };
}

/// Metadados do processamento (modelos usados, timestamp, modo stub do
/// backend). `stub` é um conceito diferente de [MeetingResult.isDemo]: o
/// backend pode estar em modo stub mesmo estando no ar; `isDemo` é o
/// resultado fabricado localmente quando o backend está inacessível.
class ResultMetadata {
  final String? whisperxModel;
  final String? diarizationModel;
  final String? voiceModel;
  final String? llmModel;
  final String? generatedAt;
  final bool stub;

  ResultMetadata({
    this.whisperxModel,
    this.diarizationModel,
    this.voiceModel,
    this.llmModel,
    this.generatedAt,
    this.stub = false,
  });

  factory ResultMetadata.fromJson(Map<String, dynamic> json) {
    return ResultMetadata(
      whisperxModel: json['whisperx_model'] as String?,
      diarizationModel: json['diarization_model'] as String?,
      voiceModel: json['voice_model'] as String?,
      llmModel: json['llm_model'] as String?,
      generatedAt: json['generated_at'] as String?,
      stub: json['stub'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'whisperx_model': whisperxModel,
    'diarization_model': diarizationModel,
    'voice_model': voiceModel,
    'llm_model': llmModel,
    'generated_at': generatedAt,
    'stub': stub,
  };
}

/// Resultado completo do processamento de um job.
class MeetingResult {
  final String jobId;
  final String status;
  final List<TranscriptSegment> segments;
  final List<Question> questions;
  final ResultMetadata? metadata;

  /// True quando este resultado foi gerado localmente porque o backend
  /// estava indisponível, em vez de vir de um processamento real. Campo
  /// só do cliente — o backend nunca envia isto.
  final bool isDemo;

  MeetingResult({
    required this.jobId,
    required this.status,
    required this.segments,
    required this.questions,
    this.metadata,
    this.isDemo = false,
  });

  factory MeetingResult.fromJson(Map<String, dynamic> json) {
    final metadataJson = json['metadata'] as Map<String, dynamic>?;
    return MeetingResult(
      jobId: json['job_id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      segments: (json['segments'] as List<dynamic>? ?? [])
          .map((e) => TranscriptSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
      questions: (json['questions'] as List<dynamic>? ?? [])
          .map((e) => Question.fromJson(e as Map<String, dynamic>))
          .toList(),
      metadata: metadataJson != null
          ? ResultMetadata.fromJson(metadataJson)
          : null,
      isDemo: json['is_demo'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'job_id': jobId,
    'status': status,
    'segments': segments.map((s) => s.toJson()).toList(),
    'questions': questions.map((q) => q.toJson()).toList(),
    'metadata': metadata?.toJson(),
    'is_demo': isDemo,
  };
}
