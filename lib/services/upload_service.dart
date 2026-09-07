import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/participant.dart';
import 'api_client.dart';

/// Erro de upload com mensagem já pronta para exibir ao usuário.
class UploadException implements Exception {
  final String message;
  UploadException(this.message);

  @override
  String toString() => message;
}

class UploadService {
  /// Teto de 300 MB do backend (`MAX_UPLOAD_MB`). Sem uma mensagem própria,
  /// isto viraria "falha de rede" — que manda o usuário tentar de novo para
  /// falhar igual. Uma reunião de ~2h em WAV 16 kHz mono encosta no limite de
  /// verdade (~230 MB), então não é um caso hipotético.
  static const _tooLargeMessage =
      'A gravação é longa demais para envio (limite de 300 MB). '
      'Grave a reunião em partes menores.';

  final _dio = ApiClient.instance.client(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 5),
  );

  Future<String> uploadMeeting({
    required String audioPath,
    required List<Participant> participants,
    String? title,
    int? expectedSpeakerCount,
    void Function(double progress)? onProgress,
  }) async {
    final formData = FormData();

    formData.files.add(MapEntry(
      'file',
      await MultipartFile.fromFile(audioPath, filename: 'reuniao.wav'),
    ));

    if (title != null && title.isNotEmpty) {
      formData.fields.add(MapEntry('title', title));
    }

    formData.fields.add(MapEntry(
      'participants',
      jsonEncode(participants.map((p) => {'id': p.id, 'name': p.name}).toList()),
    ));

    if (expectedSpeakerCount != null) {
      formData.fields.add(
        MapEntry('expected_speaker_count', expectedSpeakerCount.toString()),
      );
    }

    Response<dynamic> response;
    try {
      response = await _dio.post(
        '/upload',
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
      );
    } on DioException catch (e) {
      throw UploadException(_messageFor(e));
    }

    final jobId = response.data['job_id']?.toString();
    if (jobId == null) {
      throw UploadException('Resposta inválida do servidor.');
    }
    return jobId;
  }

  String _messageFor(DioException e) {
    // Antes do `switch` por tipo: o backend aplica o teto de tamanho
    // *durante* a escrita em disco, então o 413 pode chegar com o corpo ainda
    // sendo enviado — e aí o dio pode classificar como erro de envio, não
    // como `badResponse`. O código HTTP é o sinal confiável.
    if (e.response?.statusCode == 413) return _tooLargeMessage;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Tempo esgotado ao enviar o áudio. Verifique sua conexão e tente novamente.';
      case DioExceptionType.connectionError:
        return 'Não foi possível conectar ao servidor. Verifique o endereço configurado.';
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        if (status == 401) {
          return 'Sua sessão expirou. Entre novamente para enviar a reunião.';
        }
        // O FastAPI devolve o erro em `detail`. `message` era lido aqui
        // antes e nunca casava, então todo erro do servidor virava o texto
        // genérico com o código.
        final data = e.response?.data;
        final detail = data is Map ? data['detail'] : null;
        if (detail is String && detail.isNotEmpty) {
          return detail;
        }
        return 'O servidor recusou o envio (código $status).';
      default:
        return 'Falha ao enviar o áudio: ${e.message ?? 'erro desconhecido'}.';
    }
  }
}
