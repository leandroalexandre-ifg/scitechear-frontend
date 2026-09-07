import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cobre a causa mais provável de mojibake do lado cliente: perda de
/// acentuação/cedilha ao persistir localmente (SharedPreferences via
/// jsonEncode/jsonDecode) ou ao montar o multipart enviado ao backend
/// (dio FormData). Não cobre a rede real — isso exige um backend rodando.
void main() {
  const names = ['José', 'João', 'Conceição', 'André'];

  test('jsonEncode/jsonDecode preserva acentos e cedilha', () {
    final encoded = jsonEncode({'participants': names});
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    expect(decoded['participants'], names);
  });

  test('FormData (multipart) preserva acentos e cedilha nos campos', () async {
    final formData = FormData();
    formData.fields.add(const MapEntry('title', 'Reunião com José e Conceição'));
    formData.fields.add(
      MapEntry('participants', jsonEncode(names.map((n) => {'name': n}).toList())),
    );

    final bytes = <int>[];
    await for (final chunk in formData.finalize()) {
      bytes.addAll(chunk);
    }
    final body = utf8.decode(Uint8List.fromList(bytes));

    expect(body, contains('Reunião com José e Conceição'));
    for (final name in names) {
      expect(body, contains(name));
    }
  });
}
