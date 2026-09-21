import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

/// Confiança TLS do app: as raízes públicas **mais** a CA interna que assina
/// o certificado do servidor de produção.
///
/// Existe porque o `dart:io` não consulta o armazenamento de CAs do sistema:
/// ele carrega o seu próprio conjunto de raízes, compilado na engine. A CA
/// interna não está lá, então sem isto todo HTTPS/WSS contra o servidor
/// morre em `HandshakeException` — e instalar a CA no aparelho não muda
/// nada, porque não é esse o armazenamento consultado.
///
/// Pelo mesmo motivo, `network_security_config.xml` não resolveria isto e
/// por isso não existe no projeto: aquele configura a pilha de rede do
/// Android (Java), que nem o `dio` nem o `web_socket_channel` usam. Os dois
/// falam por `dart:io`, e é aqui que a confiança deles é decidida.
class AppTls {
  AppTls._();

  static const _caAsset = 'assets/certs/scitechear-root-ca.crt';

  static SecurityContext? _context;

  /// Carrega a CA embutida. Chamado uma vez em `main()`, antes de qualquer
  /// coisa que possa falar com a rede.
  ///
  /// `withTrustedRoots: true` mantém as raízes públicas: a CA interna é
  /// somada a elas, não as substitui — o app continua capaz de falar com
  /// qualquer HTTPS normal.
  ///
  /// Deixa a exceção subir de propósito. Falhar aqui significa que o asset
  /// não entrou na build ou não é um PEM válido; como o app só fala com o
  /// servidor interno, seguir sem a CA não deixaria nada funcionando — e o
  /// erro apareceria depois, disfarçado de falha de rede em cada tela.
  static Future<void> initialize() async {
    if (_context != null) return;
    final context = SecurityContext(withTrustedRoots: true);
    final ca = await rootBundle.load(_caAsset);
    context.setTrustedCertificatesBytes(ca.buffer.asUint8List());
    _context = context;
  }

  /// Um `HttpClient` novo que confia na CA interna.
  ///
  /// Novo a cada chamada, e não um compartilhado: quem recebe o cliente
  /// (cada `Dio`, cada WebSocket) assume o dono dele e o fecha quando
  /// termina — um só instância derrubaria os outros junto. O que é
  /// compartilhado é o [SecurityContext], que é o caro de montar.
  ///
  /// Antes de [initialize] o contexto é nulo e o cliente cai no padrão do
  /// `dart:io`, sem a CA interna. Por isso [initialize] vem primeiro em
  /// `main()`.
  static HttpClient newHttpClient() => HttpClient(context: _context);
}
