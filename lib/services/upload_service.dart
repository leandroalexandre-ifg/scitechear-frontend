import 'dart:convert';
import 'package:dio/dio.dart';
import '../config.dart';
import '../models/participant.dart';

/// Erro de upload com mensagem já pronta para exibir ao usuário.
class UploadException implements Exception {
  final String message;
  UploadException(this.message);

  @override
  String toString() => message;
}

class UploadService {
  final _dio = Dio(BaseOptions(
    baseUrl: AppConfig.backendBaseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 5),
  ));

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
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Tempo esgotado ao enviar o áudio. Verifique sua conexão e tente novamente.';
      case DioExceptionType.connectionError:
        return 'Não foi possível conectar ao servidor. Verifique o endereço configurado.';
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        final serverMessage = e.response?.data is Map
            ? (e.response?.data as Map)['message']?.toString()
            : null;
        if (serverMessage != null && serverMessage.isNotEmpty) {
          return serverMessage;
        }
        return 'O servidor recusou o envio (código $status).';
      default:
        return 'Falha ao enviar o áudio: ${e.message ?? 'erro desconhecido'}.';
    }
  }
}
