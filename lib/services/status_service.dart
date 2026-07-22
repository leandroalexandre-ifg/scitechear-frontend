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
    _connectWebSocket(jobId, controller);
    return controller.stream;
  }

  Future<void> _connectWebSocket(
    String jobId,
    StreamController<String> controller,
  ) async {
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('${AppConfig.backendWsUrl}/ws/$jobId'),
      );
      // A conexão do WebSocket é assíncrona; `ready` só completa (ou lança)
      // depois do handshake, então é aqui que falhas de conexão aparecem.
      await _channel!.ready;

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
  }

  /// Polling de status a cada 3s como alternativa ao WebSocket.
  ///
  /// Depois de [_maxConsecutiveFailures] falhas seguidas, desiste e emite
  /// 'offline' em vez de tentar para sempre — quem escuta o stream deve
  /// tratar esse status caindo para um resultado local/demonstração.
  static const _maxConsecutiveFailures = 4;

  Future<void> _pollStatus(
    String jobId,
    StreamController<String> controller,
  ) async {
    var failures = 0;
    while (!controller.isClosed) {
      try {
        final response = await _dio.get('/status/$jobId');
        failures = 0;
        final status = response.data['status']?.toString() ?? 'unknown';
        controller.add(status);
        if (status == 'done' || status == 'error') {
          await controller.close();
          break;
        }
      } catch (_) {
        failures++;
        if (failures >= _maxConsecutiveFailures) {
          controller.add('offline');
          await controller.close();
          break;
        }
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
