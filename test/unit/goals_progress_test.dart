import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/domain/models/models.dart';

void main() {
  group('SavingsGoal.progress', () {
    SavingsGoal goal({
      required double target,
      required double current,
    }) {
      return SavingsGoal.create(
        name: 'Emergency',
        targetAmount: target,
        currentAmount: current,
        currencyCode: 'EUR',
        ownerProfileId: 'p1',
        visibility: VisibilityScope.shared,
      );
    }

    test('is current / target in the goal currency', () {
      expect(goal(target: 1000, current: 250).progress, closeTo(0.25, 0.0001));
    });

    test('clamps overshoot at 100%', () {
      expect(goal(target: 1000, current: 1500).progress, 1);
    });

    test('clamps negative progress at 0%', () {
      expect(goal(target: 1000, current: -20).progress, 0);
    });

    test('zero or negative target is 0 rather than NaN', () {
      expect(goal(target: 0, current: 50).progress, 0);
      expect(goal(target: -5, current: 50).progress, 0);
    });

    test('copyWith contribute math matches Add progress', () {
      final before = goal(target: 5000, current: 1200);
      final after = before.copyWith(currentAmount: before.currentAmount + 50);
      expect(after.currentAmount, 1250);
      expect(after.progress, closeTo(1250 / 5000, 0.0001));
    });
  });
}
