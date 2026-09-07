import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/meeting_result.dart';
import 'local_scope.dart';

/// Habilita o caminho de demonstração (resultado fabricado localmente quando
/// o backend está indisponível). Flag de compilação — `--dart-define=
/// SCITECH_DEMO_MODE=true` — de propósito, para não correr o risco de uma
/// demo "esquecida ligada" continuar fabricando resultado depois que o
/// backend real volta a responder. O gate real fica nos pontos de chamada
/// (recording/processing/home screens), não nesta função pura.
const bool kDemoModeEnabled = bool.fromEnvironment(
  'SCITECH_DEMO_MODE',
  defaultValue: false,
);

/// Cache local de resultados (transcrição + perguntas), indexado por jobId.
///
/// Usado tanto para guardar resultados de demonstração (gerados quando o
/// backend está indisponível) quanto para permitir reabrir reuniões já
/// processadas sem depender de uma nova chamada de rede.
class LocalResultCache {
  // Escopada por usuário. É o cache mais sensível dos três: como ele abre
  // resultados sem consultar o backend, uma chave global deixaria a
  // transcrição de uma reunião legível por quem entrasse depois no aparelho,
  // por fora do escopo que o servidor aplica.
  static String _keyFor(String jobId) => LocalScope.key('result_$jobId');

  Future<void> save(String jobId, MeetingResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(jobId), jsonEncode(result.toJson()));
  }

  Future<MeetingResult?> load(String jobId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(jobId));
    if (raw == null) return null;
    return MeetingResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

/// Gera uma transcrição e perguntas plausíveis para uso quando o backend
/// (Whisper/pyannote/Ollama) não está disponível — ex.: durante uma
/// demonstração sem servidor no ar. O conteúdo é fictício, mas usa os
/// nomes reais dos participantes quando informados.
MeetingResult generateDemoResult({
  required String jobId,
  required List<String> participantNames,
}) {
  final names = participantNames.isEmpty
      ? const ['Participante 1', 'Participante 2']
      : participantNames;

  String clusterFor(int i) => 'SPEAKER_${(i % names.length).toString().padLeft(2, '0')}';
  String speakerFor(int i) => names[i % names.length];

  TranscriptSegment segment(
    String id,
    int speakerIndex,
    double start,
    double end,
    String text,
  ) => TranscriptSegment(
    id: id,
    cluster: clusterFor(speakerIndex),
    speaker: speakerFor(speakerIndex),
    identified: true,
    start: start,
    end: end,
    text: text,
  );

  final segments = <TranscriptSegment>[
    segment('seg_0001', 0, 0, 6,
        'Bom dia, pessoal. Vamos começar revisando os pontos da última reunião.'),
    segment('seg_0002', 1, 6, 14,
        'Bom dia! Já finalizei a parte que tinha ficado pendente e posso apresentar os resultados hoje.'),
    segment('seg_0003', 0, 14, 22,
        'Ótimo. Antes disso, alguém tem alguma dúvida sobre o cronograma que definimos?'),
    segment('seg_0004', 1, 22, 30,
        'Eu tenho uma dúvida: qual é o prazo final para a entrega da próxima etapa?'),
    segment('seg_0005', 0, 30, 40,
        'Boa pergunta. Vamos fechar isso até sexta-feira, mas ainda preciso confirmar com a equipe.'),
    segment('seg_0006', 1, 40, 50,
        'Perfeito. Também gostaria de saber se vamos precisar de mais recursos para a próxima fase.'),
    segment('seg_0007', 0, 50, 60,
        'Vou levantar isso com a coordenação e trago uma resposta na próxima reunião.'),
    segment('seg_0008', 1, 60, 66,
        'Combinado. Por enquanto acho que é isso, obrigado a todos.'),
  ];

  final questions = <Question>[
    Question(
      id: 'demo_q1',
      type: QuestionType.explicit,
      text: 'Qual é o prazo final para a entrega da próxima etapa?',
      speaker: speakerFor(1),
      time: 22,
      sourceSegmentIds: const ['seg_0004'],
    ),
    Question(
      id: 'demo_q2',
      type: QuestionType.explicit,
      text: 'Vamos precisar de mais recursos para a próxima fase?',
      speaker: speakerFor(1),
      time: 40,
      sourceSegmentIds: const ['seg_0006'],
    ),
  ];

  return MeetingResult(
    jobId: jobId,
    status: 'done',
    segments: segments,
    questions: questions,
    isDemo: true,
  );
}
