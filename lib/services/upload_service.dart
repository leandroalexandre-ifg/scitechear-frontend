import 'package:dio/dio.dart';
import '../config.dart';
import '../models/participant.dart';

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

    for (var i = 0; i < participants.length; i++) {
      formData.fields.add(MapEntry('participant_names[$i]', participants[i].name));
      final sample = participants[i].voiceSamplePath;
      if (sample != null) {
        formData.files.add(MapEntry(
          'voice_samples[$i]',
          await MultipartFile.fromFile(sample, filename: 'sample_$i.wav'),
        ));
      }
    }

    final response = await _dio.post(
      '/upload',
      data: formData,
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      },
    );

    final jobId = response.data['job_id']?.toString();
    if (jobId == null) throw Exception('Resposta inválida do servidor.');
    return jobId;
  }
}
