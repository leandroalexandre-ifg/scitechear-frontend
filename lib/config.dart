/// Configuração central do app.
///
/// Configurável via `--dart-define=SCITECH_API_BASE_URL=...` e
/// `--dart-define=SCITECH_WS_BASE_URL=...`. Sem esses defines, cai no
/// default do emulador Android.
/// - Emulador Android: use 10.0.2.2 para acessar o localhost da sua máquina.
/// - Dispositivo físico: use o IP da máquina na rede local (ex.: 192.168.0.10).
/// - Produção: o domínio/HTTPS do servidor.
class AppConfig {
  /// Base HTTP do backend (sem barra no final).
  static const String backendBaseUrl = String.fromEnvironment(
    'SCITECH_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Base WebSocket do backend (ws:// em dev, wss:// em produção).
  static const String backendWsUrl = String.fromEnvironment(
    'SCITECH_WS_BASE_URL',
    defaultValue: 'ws://10.0.2.2:8000',
  );
}
