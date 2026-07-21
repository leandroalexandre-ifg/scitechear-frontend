/// Referência local de uma reunião enviada ao backend.
///
/// Guarda apenas metadados (título, data, job_id, nomes dos participantes);
/// a transcrição e as perguntas são buscadas do backend sob demanda, via
/// `StatusService.fetchResult(jobId)`.
class Meeting {
  final String id;
  final String jobId;
  final String title;
  final DateTime createdAt;
  final List<String> participantNames;

  const Meeting({
    required this.id,
    required this.jobId,
    required this.title,
    required this.createdAt,
    required this.participantNames,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'jobId': jobId,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'participantNames': participantNames,
  };

  factory Meeting.fromJson(Map<String, dynamic> json) => Meeting(
    id: json['id'] as String,
    jobId: json['jobId'] as String,
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    participantNames: (json['participantNames'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList(),
  );
}
