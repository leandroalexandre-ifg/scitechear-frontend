import 'dart:io' show Platform;
import 'package:flutter_background/flutter_background.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Gerencia a execução em segundo plano durante a gravação.
///
/// No Android, ativa um foreground service (com notificação persistente) que
/// impede o sistema de encerrar o app quando a tela é bloqueada.
/// No iOS, o background audio é habilitado via Info.plist (UIBackgroundModes),
/// então aqui basta manter o wakelock; o sistema mantém o áudio ativo.
class BackgroundService {
  static const _androidConfig = FlutterBackgroundAndroidConfig(
    notificationTitle: 'Gravando reunião',
    notificationText: 'A gravação continua em segundo plano.',
    notificationImportance: AndroidNotificationImportance.normal,
    notificationIcon: AndroidResource(
      name: 'ic_launcher',
      defType: 'mipmap',
    ),
  );

  /// Solicita permissões e inicializa o modo background.
  /// Deve ser chamado antes de iniciar a gravação. Retorna true se pronto.
  Future<bool> enable() async {
    if (Platform.isAndroid) {
      final hasPermissions =
          await FlutterBackground.initialize(androidConfig: _androidConfig);
      if (!hasPermissions) return false;
      final enabled = await FlutterBackground.enableBackgroundExecution();
      if (!enabled) return false;
    }
    // Mantém o dispositivo de "dormir" o processo durante a captura.
    await WakelockPlus.enable();
    return true;
  }

  /// Desliga o modo background ao terminar a gravação.
  Future<void> disable() async {
    await WakelockPlus.disable();
    if (Platform.isAndroid && FlutterBackground.isBackgroundExecutionEnabled) {
      await FlutterBackground.disableBackgroundExecution();
    }
  }
}
