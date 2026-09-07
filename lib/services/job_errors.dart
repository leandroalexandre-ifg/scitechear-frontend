/// Tradução dos códigos de falha de job para mensagens em português.
///
/// O `error` de `GET /status/{job_id}` é `{code, message}`. O `message` é o
/// `str(exc)` da exceção Python do servidor: inglês, e às vezes com caminho
/// de arquivo do servidor dentro. Não é texto para usuário final — por isso a
/// tela mostra o que está aqui, indexado pelo `code`, que é um conjunto
/// fechado confirmado pelo backend em 07/09/2026.
///
/// Um `code` desconhecido (o backend avisa antes de acrescentar, mas versões
/// diferentes de app e servidor convivem) cai numa mensagem genérica; o
/// `message` cru continua fora da tela em qualquer caso.
library;

const _messages = <String, String>{
  'AUDIO_NAO_ENCONTRADO':
      'O servidor não encontrou o áudio desta reunião. Ele pode ter sido '
          'removido antes do processamento — grave e envie novamente.',
  'TRANSCRIPTION_ERROR':
      'Não foi possível transcrever o áudio. Verifique se a gravação tem som '
          'audível e tente enviar de novo.',
  'DIARIZATION_ERROR':
      'Não foi possível separar as falas por participante. Isso costuma '
          'acontecer com áudios muito curtos ou com pouca fala.',
  'IDENTIFICATION_ERROR':
      'Não foi possível identificar os participantes pela voz. As amostras de '
          'voz cadastradas podem estar com problema.',
  'SUMMARIZATION_ERROR':
      'Não foi possível gerar o resumo da reunião.',
  'EXTRACTION_ERROR':
      'Não foi possível extrair as perguntas da transcrição.',
  'WORKER_MAX_TENTATIVAS_EXCEDIDO':
      'O servidor tentou processar esta reunião três vezes e não conseguiu '
          'concluir. Fale com quem administra o servidor antes de reenviar.',
};

/// Mensagem para o usuário a partir do `error` de `/status/{job_id}`.
///
/// Aceita o mapa cru (`{code, message}`) e nunca devolve `null`: mesmo sem
/// `error` no corpo, a tela precisa de algo para mostrar.
String jobErrorMessage(dynamic error) {
  final code = error is Map ? error['code']?.toString() : null;
  return _messages[code] ??
      'O processamento falhou no servidor. Tente enviar a reunião novamente.';
}

/// Código bruto, para exibir discretamente junto da mensagem — é o que quem
/// suporta o usuário precisa saber para achar o job no log do servidor.
String? jobErrorCode(dynamic error) {
  final code = error is Map ? error['code']?.toString() : null;
  return (code != null && code.isNotEmpty) ? code : null;
}
