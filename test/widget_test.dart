import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';
import 'package:app/screens/auth_screen.dart';
import 'package:app/services/auth_service.dart';

void main() {
  // `pumpAndSettle` (e não um `pump` único) porque as telas usam
  // flutter_animate, que agenda um Timer já no initState — terminar o teste
  // antes dele disparar faz o framework acusar timer pendente.
  testWidgets('sem sessão salva, o app abre na tela de autenticação',
      (tester) async {
    // Um AuthService recém-criado, sem `initialize()`, está deslogado —
    // não depende de SharedPreferences.
    final auth = AuthService();
    await tester.pumpWidget(ReunioesApp(authService: auth));
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsOneWidget);
  });
}
