import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import '../models/meeting_result.dart';
import 'api_client.dart';

/// Acompanha o progresso de um job e busca o resultado final.
///
/// Estratégia: WebSocket em /ws/{job_id} para progresso em tempo real,
/// com fallback de polling em /status/{job_id} caso o WS falhe.
///
/// O `/ws` do backend deixou de ser stub (Fase 8, validada em 05/09/2026):
/// mantém a conexão aberta e empurra cada mudança de estado até done/error,
/// ou até o teto de 1h por conexão. Por isso o cliente lê **em laço** — não
/// encerra por conta própria depois da primeira mensagem, senão descartaria
/// o push e cairia no polling sem necessidade.
///
/// Duas coisas que continuam valendo, e não devem ser "simplificadas":
///
/// - O polling **não** sai. Fechamento por teto de 1h, queda de rede ou
///   4401/4404 acontecem, e sem ele a tela trava. Remover é decisão
///   combinada com o backend, não do lado do app sozinho.
/// - `onDone` não pode assumir que o job terminou só porque o WS fechou: se
///   o último status recebido não for terminal, cai para o polling.
///
/// O backend empurra o estado **atual** a cada segundo, não a sequência
/// completa de transições — estágios curtos (`identifying`, `summarizing`)
/// podem não aparecer nenhuma vez. Quem consome este stream não pode exigir
/// que o job passe por todos os estados.
class StatusService {
  /// O cliente HTTP e o intervalo de polling são injetáveis só para os testes
  /// poderem responder sem rede e sem esperar 3s por tentativa. Em produção o
  /// cliente vem do [ApiClient], que é quem sabe do `Bearer`.
  StatusService({
    Dio? dio,
    Duration pollInterval = const Duration(seconds: 3),
  })  : _dio = dio ?? ApiClient.instance.client(),
        _pollInterval = pollInterval;

  final Dio _dio;
  final Duration _pollInterval;
  WebSocketChannel? _channel;

  /// Abre um stream de status via WebSocket, com fallback de polling.
  ///
  /// Emite strings de estado: queued, transcribing, diarizing, identifying,
  /// summarizing, extracting, done, error. Emite também dois sinais
  /// inventados pelo cliente, que o backend nunca envia:
  ///
  /// - `offline`: o polling esgotou as tentativas e não consegue mais falar
  ///   com o servidor.
  /// - `removed`: o servidor respondeu 404 — o job não existe mais para este
  ///   usuário. Terminal, e diferente de falha: não adianta tentar de novo.
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
          // Fechar sem status terminal significa "preciso continuar de outro
          // jeito" (teto de 1h da conexão, queda de rede, o backend soltando
          // a conexão na dúvida), nunca "o job acabou".
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

  /// Polling de status como alternativa ao WebSocket.
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
      } on DioException catch (e) {
        // 404 é resposta, não falha de rede: o job não existe mais para este
        // usuário — removido em outro aparelho, ou nunca foi dele. Insistir
        // quatro vezes para então dizer "verifique sua conexão" seria mandar
        // o usuário procurar defeito no lugar errado.
        if (e.response?.statusCode == 404) {
          controller.add('removed');
          await controller.close();
          break;
        }
        failures++;
        if (failures >= _maxConsecutiveFailures) {
          controller.add('offline');
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
      await Future.delayed(_pollInterval);
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
