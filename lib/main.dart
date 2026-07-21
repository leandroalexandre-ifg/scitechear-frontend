import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'services/auth_service.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthService();
  await auth.initialize();
  runApp(ReunioesApp(authService: auth));
}

class ReunioesApp extends StatelessWidget {
  final AuthService authService;
  const ReunioesApp({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SciTech Ear',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: authService.isLoggedIn
          ? HomeScreen(authService: authService)
          : AuthScreen(authService: authService),
    );
  }
}
