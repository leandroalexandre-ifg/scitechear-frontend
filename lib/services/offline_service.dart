import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/meeting_result.dart';

/// Cache local de resultados (transcrição + perguntas), indexado por jobId.
///
/// Usado tanto para guardar resultados de demonstração (gerados quando o
/// backend está indisponível) quanto para permitir reabrir reuniões já
/// processadas sem depender de uma nova chamada de rede.
class LocalResultCache {
  static const _prefix = 'result_';

  Future<void> save(String jobId, MeetingResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$jobId', jsonEncode(result.toJson()));
  }

  Future<MeetingResult?> load(String jobId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$jobId');
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

  String speakerFor(int i) => 'SPEAKER_${(i % names.length).toString().padLeft(2, '0')}';

  final segments = <TranscriptSegment>[
    TranscriptSegment(
      speaker: speakerFor(0),
      start: 0,
      end: 6,
      text: 'Bom dia, pessoal. Vamos começar revisando os pontos da última reunião.',
    ),
    TranscriptSegment(
      speaker: speakerFor(1),
      start: 6,
      end: 14,
      text: 'Bom dia! Já finalizei a parte que tinha ficado pendente e posso apresentar os resultados hoje.',
    ),
    TranscriptSegment(
      speaker: speakerFor(0),
      start: 14,
      end: 22,
      text: 'Ótimo. Antes disso, alguém tem alguma dúvida sobre o cronograma que definimos?',
    ),
    TranscriptSegment(
      speaker: speakerFor(1),
      start: 22,
      end: 30,
      text: 'Eu tenho uma dúvida: qual é o prazo final para a entrega da próxima etapa?',
    ),
    TranscriptSegment(
      speaker: speakerFor(0),
      start: 30,
      end: 40,
      text: 'Boa pergunta. Vamos fechar isso até sexta-feira, mas ainda preciso confirmar com a equipe.',
    ),
    TranscriptSegment(
      speaker: speakerFor(1),
      start: 40,
      end: 50,
      text: 'Perfeito. Também gostaria de saber se vamos precisar de mais recursos para a próxima fase.',
    ),
    TranscriptSegment(
      speaker: speakerFor(0),
      start: 50,
      end: 60,
      text: 'Vou levantar isso com a coordenação e trago uma resposta na próxima reunião.',
    ),
    TranscriptSegment(
      speaker: speakerFor(1),
      start: 60,
      end: 66,
      text: 'Combinado. Por enquanto acho que é isso, obrigado a todos.',
    ),
  ];

  final questions = <Question>[
    Question(
      speaker: speakerFor(1),
      time: 22,
      text: 'Qual é o prazo final para a entrega da próxima etapa?',
    ),
    Question(
      speaker: speakerFor(1),
      time: 40,
      text: 'Vamos precisar de mais recursos para a próxima fase?',
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
