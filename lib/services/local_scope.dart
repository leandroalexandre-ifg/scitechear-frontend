import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Escopo por usuário das chaves guardadas no aparelho.
///
/// O que o app persiste localmente — histórico de reuniões, cadastro de
/// participantes (com o caminho das amostras de voz) e cache de transcrições
/// — pertence a uma pessoa, não ao aparelho. O backend já escopa tudo por
/// `user_id`; o armazenamento local precisa fazer o mesmo.
///
/// Sem isso há vazamento real entre contas: como `LocalResultCache` abre
/// resultados sem consultar o servidor, quem entrasse depois leria as
/// transcrições e o histórico de quem entrou antes, passando por baixo do
/// escopo do backend.
class LocalScope {
  /// Prefixo de escopo. Chaves antigas (globais) não têm nenhum prefixo,
  /// então as duas gerações nunca se confundem.
  static String _prefixFor(String userId) => 'u$userId:';

  /// Escopo de quando não há ninguém logado. Não é um balde compartilhado —
  /// é um escopo próprio, isolado de qualquer usuário real.
  static const _anonymous = 'anon';

  /// Chave escopada para o usuário atual.
  static String key(String base) =>
      '${_prefixFor(ApiClient.instance.userId ?? _anonymous)}$base';

  /// Bases de chave únicas (as de prefixo, como o cache de resultados, são
  /// tratadas à parte em [adoptLegacyData]).
  static const _singleKeys = ['meeting_history', 'registered_participants'];
  static const _legacyResultPrefix = 'result_';

  /// Adota dados gravados antes de o escopo por usuário existir.
  ///
  /// Sem isto, quem já usava o app veria histórico e participantes sumirem
  /// na atualização — os dados continuariam no disco, só que sob chaves que
  /// ninguém mais lê. O dono legítimo é indeterminável em retrospecto, então
  /// vão para o primeiro usuário que logar depois da atualização: é o
  /// palpite mais provável (o app tinha um login mock, de uso pessoal) e, de
  /// todo modo, melhor do que deixá-los visíveis para todo mundo.
  ///
  /// Roda uma vez por sessão, logo depois de o usuário ser conhecido.
  static Future<void> adoptLegacyData() async {
    if (ApiClient.instance.userId == null) return;
    final prefs = await SharedPreferences.getInstance();

    for (final base in _singleKeys) {
      await _adopt(prefs, legacyKey: base, scopedKey: key(base));
    }

    // Cache de resultados: as chaves antigas são `result_<jobId>`; as novas
    // começam com o prefixo de usuário, então filtrar por `result_` pega
    // exatamente as legadas.
    final legacyResults =
        prefs.getKeys().where((k) => k.startsWith(_legacyResultPrefix)).toList();
    for (final legacyKey in legacyResults) {
      await _adopt(prefs, legacyKey: legacyKey, scopedKey: key(legacyKey));
    }
  }

  static Future<void> _adopt(
    SharedPreferences prefs, {
    required String legacyKey,
    required String scopedKey,
  }) async {
    final value = prefs.getString(legacyKey);
    if (value == null) return;
    // Não sobrescreve o que o usuário já tem no escopo dele.
    if (!prefs.containsKey(scopedKey)) {
      await prefs.setString(scopedKey, value);
    }
    await prefs.remove(legacyKey);
  }
}
