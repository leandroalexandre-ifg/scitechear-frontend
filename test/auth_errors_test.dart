import 'dart:convert';
import 'dart:typed_data';

import 'package:app/services/api_client.dart';
import 'package:app/services/auth_service.dart';
import 'package:app/services/job_errors.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adaptador falso que responde sempre a mesma coisa — aqui só interessa
/// como o app traduz a resposta de erro, não o que ele pediu.
class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter(this.status, this.body, {this.headers = const {}});

  final int status;
  final Map<String, dynamic> body;
  final Map<String, List<String>> headers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final api = ApiClient.instance;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await api.clearSession();
  });

  group('cadastro recusado pela allowlist institucional', () {
    test('403 vira erro do campo e-mail, com o texto do servidor', () async {
      api.public.httpClientAdapter = _FixedAdapter(403, {
        'detail': 'Registro restrito a e-mails institucionais.',
      });

      // O 403 do backend é condição permanente do endereço (domínio fora de
      // `AUTH_ALLOWED_EMAIL_DOMAINS`), não credencial errada nem falha de
      // rede: a tela precisa saber que é o campo do e-mail que está errado.
      final error = await _registerError();
      expect(error.field, 'email');
      expect(error.message, 'Registro restrito a e-mails institucionais.');
    });

    test('sem detail no corpo, ainda diz do que se trata', () async {
      api.public.httpClientAdapter = _FixedAdapter(403, {});

      final error = await _registerError();
      expect(error.field, 'email');
      expect(error.message, contains('institucional'));
    });

    test('409 também é erro do campo e-mail', () async {
      api.public.httpClientAdapter = _FixedAdapter(409, {
        'detail': 'E-mail já cadastrado.',
      });

      final error = await _registerError();
      expect(error.field, 'email');
    });

    test('401 não é erro de campo — vale para e-mail ou senha', () async {
      api.public.httpClientAdapter = _FixedAdapter(401, {
        'detail': 'Credenciais inválidas.',
      });

      final error = await _loginError();
      expect(error.field, isNull);
    });
  });

  group('rate limit', () {
    test('o Retry-After vira um limite superior, não uma promessa', () async {
      // O backend devolve a janela inteira (3600s no registro), não o tempo
      // que falta — dizer "em ~60 minutos" faltando um seria mentir para
      // mais. "Até" é o que o número de fato garante.
      api.public.httpClientAdapter = _FixedAdapter(
        429,
        {'detail': 'Muitas tentativas.'},
        headers: {
          'retry-after': ['3600']
        },
      );

      final error = await _registerError();
      expect(error.message, contains('Aguarde até 60 minutos'));
      expect(error.field, isNull);
    });

    test('sem o header, não inventa um prazo', () async {
      api.public.httpClientAdapter =
          _FixedAdapter(429, {'detail': 'Muitas tentativas.'});

      final error = await _registerError();
      expect(error.message, contains('mais tarde'));
      expect(error.message, isNot(contains('minuto')));
    });
  });

  group('falha de job traduzida por código', () {
    test('cada código do backend tem mensagem em português', () {
      // O conjunto fechado confirmado pelo backend em 07/09/2026. Um código
      // novo aparecer aqui sem tradução é o sinal de que a tabela ficou para
      // trás — o teste falha antes de o usuário ver o texto genérico.
      const codes = [
        'AUDIO_NAO_ENCONTRADO',
        'TRANSCRIPTION_ERROR',
        'DIARIZATION_ERROR',
        'IDENTIFICATION_ERROR',
        'SUMMARIZATION_ERROR',
        'EXTRACTION_ERROR',
        'WORKER_MAX_TENTATIVAS_EXCEDIDO',
      ];
      const generic =
          'O processamento falhou no servidor. Tente enviar a reunião novamente.';

      for (final code in codes) {
        final message = jobErrorMessage({'code': code, 'message': 'boom'});
        expect(message, isNot(generic), reason: '$code sem tradução');
        expect(message, isNot(contains('boom')));
      }
    });

    test('o message cru do servidor nunca chega à tela', () {
      // `error.message` é o `str(exc)` da exceção Python: inglês, e às vezes
      // com caminho de arquivo do servidor dentro.
      final message = jobErrorMessage({
        'code': 'TRANSCRIPTION_ERROR',
        'message': "FileNotFoundError: '/srv/scitech/audio/x.wav'",
      });
      expect(message, isNot(contains('/srv/')));
      expect(message, isNot(contains('FileNotFoundError')));
    });

    test('código desconhecido cai no genérico, sem vazar o message', () {
      final message = jobErrorMessage({
        'code': 'CODIGO_QUE_AINDA_NAO_EXISTE',
        'message': 'Traceback (most recent call last)',
      });
      expect(message, isNot(contains('Traceback')));
      expect(message, contains('falhou no servidor'));
    });

    test('sem error no corpo, ainda há o que mostrar', () {
      expect(jobErrorMessage(null), isNotEmpty);
      expect(jobErrorCode(null), isNull);
    });
  });
}

/// Executa um cadastro que vai falhar e devolve a [AuthException] resultante.
Future<AuthException> _registerError() async {
  try {
    await AuthService().register('Fulano', 'fulano@gmail.com', 'senha12345');
    fail('esperava AuthException');
  } on AuthException catch (e) {
    return e;
  }
}

Future<AuthException> _loginError() async {
  try {
    await AuthService().login('fulano@ifg.edu.br', 'errada');
    fail('esperava AuthException');
  } on AuthException catch (e) {
    return e;
  }
}
