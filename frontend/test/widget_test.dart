import 'package:flutter_test/flutter_test.dart';
import 'package:pharmatrace_frontend/main.dart';

void main() {
  testWidgets('PharmaTraceApp renders successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const PharmaTraceApp());
    expect(find.text('PharmaTrace'), findsOneWidget);
    expect(find.text('Pharmaceutical Supply Chain Traceability'), findsOneWidget);
  });
}
