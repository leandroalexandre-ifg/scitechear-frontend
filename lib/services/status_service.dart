import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import '../models/meeting_result.dart';
import 'api_client.dart';

/// Acompanha o progresso de um job e busca o resultado final.
///
/// Estratégia: WebSocket em /ws/{job_id} para progresso em tempo real,
/// com fallback de polling em /status/{job_id} caso o WS falhe.
///
/// IMPORTANTE: hoje (backend Fase 7) o WS é só um stub — aceita a conexão,
/// manda o status atual UMA vez e fecha. O push real de progresso é Fase 8
/// do backend (ainda não implementada). Por isso `onDone` NÃO pode assumir
/// que o job terminou só porque o WS fechou: se o último status recebido
/// não for terminal (done/error), cai para o polling. Não "simplificar"
/// isso de volta para WS-only até o backend realmente empurrar progresso.
class StatusService {
  final _dio = ApiClient.instance.client();
  WebSocketChannel? _channel;

  /// Abre um stream de status via WebSocket, com fallback de polling.
  ///
  /// Emite strings de estado: queued, transcribing, diarizing, identifying,
  /// summarizing, extracting, done, error. Também pode emitir 'offline' —
  /// um sinal inventado pelo cliente (nunca enviado pelo backend) quando o
  /// polling esgota as tentativas e não consegue mais falar com o servidor.
  Stream<String> watchStatus(String jobId) {
    final controller = StreamController<String>();
    _connectWebSocket(jobId, controller);
    return controller.stream;
  }

  Future<void> _connectWebSocket(
    String jobId,
    StreamController<String> controller,
  ) async {
    String? lastStatus;
    var pollingStarted = false;
    void startPolling() {
      if (pollingStarted) return;
      pollingStarted = true;
      _pollStatus(jobId, controller);
    }

    try {
      // O token vai por query param, não por header: o handshake de
      // WebSocket não aceita `Authorization` em todo cliente, e é assim que
      // o backend o lê (fecha com 4401 sem token, 4404 se o job for de
      // outro usuário). Sem sessão não adianta tentar — vai direto para o
      // polling, que produz uma mensagem de erro melhor.
      final token = await ApiClient.instance.validAccessToken();
      if (token == null) {
        startPolling();
        return;
      }
      _channel = WebSocketChannel.connect(
        Uri.parse('${AppConfig.backendWsUrl}/ws/$jobId'
            '?token=${Uri.encodeQueryComponent(token)}'),
      );
      // A conexão do WebSocket é assíncrona; `ready` só completa (ou lança)
      // depois do handshake, então é aqui que falhas de conexão aparecem.
      await _channel!.ready;

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String);
            final status = data is Map ? data['status']?.toString() : null;
            if (status != null) {
              lastStatus = status;
              controller.add(status);
            }
          } catch (_) {
            lastStatus = message.toString();
            controller.add(message.toString());
          }
        },
        onError: (_) {
          // Fallback para polling se o WebSocket falhar.
          startPolling();
        },
        onDone: () {
          // O stub do backend fecha a conexão depois de uma única mensagem,
          // quase sempre não-terminal — tratar isso como "preciso continuar
          // de outro jeito", não como "o job acabou".
          if (lastStatus == 'done' || lastStatus == 'error') {
            controller.close();
          } else {
            startPolling();
          }
        },
      );
    } catch (_) {
      startPolling();
    }
  }

  /// Polling de status a cada 3s como alternativa ao WebSocket.
  ///
  /// Depois de [_maxConsecutiveFailures] falhas seguidas, desiste e emite
  /// 'offline' em vez de tentar para sempre — quem escuta o stream deve
  /// tratar esse status como um erro real de conectividade, nunca cair
  /// silenciosamente para um resultado fictício.
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

  /// Busca o corpo completo de GET /status/{job_id}, incluindo `error`
  /// ({code, message}) quando o job falhou — usado para mostrar a mensagem
  /// real de erro do backend em vez de um texto genérico.
  Future<Map<String, dynamic>?> fetchStatusDetail(String jobId) async {
    try {
      final response = await _dio.get('/status/$jobId');
      return response.data as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Encerra o WebSocket.
  void dispose() {
    _channel?.sink.close();
  }
}
