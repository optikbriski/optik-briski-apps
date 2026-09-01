import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/widgets/admin/premium_panel.dart';

void main() {
  testWidgets('accent bar + LayoutBuilder di ListView tidak crash',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              PremiumPanel(
                showAccentBar: true,
                child: _WidthLabel(),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('w='), findsOneWidget);
  });
}

class _WidthLabel extends StatelessWidget {
  const _WidthLabel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => Text('w=${c.maxWidth.round()}'),
    );
  }
}
