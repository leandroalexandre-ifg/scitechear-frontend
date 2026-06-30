import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import '../models/meeting_result.dart';

/// Acompanha o progresso de um job e busca o resultado final.
///
/// Estratégia: WebSocket em /ws/{job_id} para progresso em tempo real,
/// com fallback de polling em /status/{job_id} caso o WS falhe.
class StatusService {
  final Dio _dio = Dio(BaseOptions(baseUrl: AppConfig.backendBaseUrl));
  WebSocketChannel? _channel;

  /// Abre um stream de status via WebSocket.
  ///
  /// Emite strings de estado: queued, transcribing, diarizing,
  /// extracting, done, error.
  Stream<String> watchStatus(String jobId) {
    final controller = StreamController<String>();

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('${AppConfig.backendWsUrl}/ws/$jobId'),
      );

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String);
            final status = data is Map ? data['status']?.toString() : null;
            if (status != null) controller.add(status);
          } catch (_) {
            controller.add(message.toString());
          }
        },
        onError: (_) {
          // Fallback para polling se o WebSocket falhar.
          _pollStatus(jobId, controller);
        },
        onDone: () => controller.close(),
      );
    } catch (_) {
      _pollStatus(jobId, controller);
    }

    return controller.stream;
  }

  /// Polling de status a cada 3s como alternativa ao WebSocket.
  Future<void> _pollStatus(
    String jobId,
    StreamController<String> controller,
  ) async {
    while (!controller.isClosed) {
      try {
        final response = await _dio.get('/status/$jobId');
        final status = response.data['status']?.toString() ?? 'unknown';
        controller.add(status);
        if (status == 'done' || status == 'error') {
          await controller.close();
          break;
        }
      } catch (_) {
        // Mantém tentando; o backend pode estar ocupado.
      }
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  /// Busca o resultado final em /resultado/{job_id}.
  Future<MeetingResult> fetchResult(String jobId) async {
    final response = await _dio.get('/resultado/$jobId');
    return MeetingResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// Encerra o WebSocket.
  void dispose() {
    _channel?.sink.close();
  }
}
