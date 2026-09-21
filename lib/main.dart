import 'dart:async';

import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/tls.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Antes de qualquer coisa que fale com a rede: `auth.initialize()` já
  // tenta renovar a sessão, e sem a CA interna carregada essa primeira
  // chamada falharia no handshake.
  await AppTls.initialize();
  final auth = AuthService();
  await auth.initialize();
  runApp(ReunioesApp(authService: auth));
}

class ReunioesApp extends StatefulWidget {
  final AuthService authService;
  const ReunioesApp({super.key, required this.authService});

  @override
  State<ReunioesApp> createState() => _ReunioesAppState();
}

class _ReunioesAppState extends State<ReunioesApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<void>? _sessionSub;

  @override
  void initState() {
    super.initState();
    // A sessão pode morrer no meio de qualquer tela — o refresh token dura
    // 30 dias, mas pode ser revogado a qualquer momento. Tratar isso aqui,
    // num ponto só, evita que cada tela precise decidir o que fazer com um
    // 401 que não é sobre a operação que ela estava tentando.
    _sessionSub = ApiClient.instance.onSessionExpired.listen((_) {
      widget.authService.handleSessionExpired();
      _messengerKey.currentState
        ?..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Sua sessão expirou. Entre novamente.')),
        );
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => AuthScreen(authService: widget.authService),
        ),
        (route) => false,
      );
    });
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SciTech Ear',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      home: widget.authService.isLoggedIn
          ? HomeScreen(authService: widget.authService)
          : AuthScreen(authService: widget.authService),
    );
  }
}
