import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/theme.dart';
import 'package:optik_b_riski/shared/training/training_banner.dart';

void main() {
  test('training dialogs keep dark text on a light card', () {
    expect(TrainingDialogSkin.surface, OptikAdminTokens.card);
    expect(TrainingDialogSkin.title, OptikAdminTokens.navy);
    expect(TrainingDialogSkin.body, OptikAdminTokens.textSecondary);
    expect(TrainingDialogSkin.surface.computeLuminance(), greaterThan(0.85));
    expect(TrainingDialogSkin.title.computeLuminance(), lessThan(0.2));
    expect(TrainingDialogSkin.body.computeLuminance(), lessThan(0.35));
  });
}
