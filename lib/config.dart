/// Configuração central do app.
///
/// Ajuste [backendBaseUrl] para o endereço do seu servidor (FastAPI).
/// - Emulador Android: use 10.0.2.2 para acessar o localhost da sua máquina.
/// - Dispositivo físico: use o IP da máquina na rede local (ex.: 192.168.0.10).
/// - Produção: o domínio/HTTPS do servidor.
class AppConfig {
  /// Base HTTP do backend (sem barra no final).
  static const String backendBaseUrl = 'http://10.0.2.2:8000';

  /// Base WebSocket do backend (ws:// em dev, wss:// em produção).
  static const String backendWsUrl = 'ws://10.0.2.2:8000';
}
