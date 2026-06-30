// Modelos de dados que espelham o JSON retornado pelo backend.
//
// Formato esperado de /resultado/{job_id}:
// {
//   "job_id": "abc123",
//   "status": "done",
//   "segments": [
//     { "speaker": "SPEAKER_00", "start": 0.0, "end": 4.2, "text": "Bom dia." }
//   ],
//   "questions": [
//     { "speaker": "SPEAKER_01", "time": 12.5, "text": "Qual o prazo?" }
//   ]
// }

/// Um trecho da transcrição com falante e marcação de tempo.
class TranscriptSegment {
  final String speaker;
  final double start;
  final double end;
  final String text;

  TranscriptSegment({
    required this.speaker,
    required this.start,
    required this.end,
    required this.text,
  });

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      speaker: json['speaker'] as String? ?? 'SPEAKER',
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
      text: json['text'] as String? ?? '',
    );
  }
}

/// Uma pergunta extraída da reunião.
class Question {
  final String speaker;
  final double time;
  final String text;

  Question({
    required this.speaker,
    required this.time,
    required this.text,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      speaker: json['speaker'] as String? ?? 'SPEAKER',
      time: (json['time'] as num?)?.toDouble() ?? 0.0,
      text: json['text'] as String? ?? '',
    );
  }
}

/// Resultado completo do processamento de um job.
class MeetingResult {
  final String jobId;
  final String status;
  final List<TranscriptSegment> segments;
  final List<Question> questions;

  MeetingResult({
    required this.jobId,
    required this.status,
    required this.segments,
    required this.questions,
  });

  factory MeetingResult.fromJson(Map<String, dynamic> json) {
    return MeetingResult(
      jobId: json['job_id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      segments: (json['segments'] as List<dynamic>? ?? [])
          .map((e) => TranscriptSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
      questions: (json['questions'] as List<dynamic>? ?? [])
          .map((e) => Question.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
