import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';
import 'package:app/services/auth_service.dart';

void main() {
  testWidgets('App smoke test', (tester) async {
    final auth = AuthService();
    await tester.pumpWidget(ReunioesApp(authService: auth));
    expect(find.byType(ReunioesApp), findsOneWidget);
  });
}
