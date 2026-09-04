import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/widgets/sheet_inset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SheetInset keeps bottom content above the system nav inset',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SheetInset(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Text('Delete'),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getRect(find.text('Delete')).bottom,
      lessThanOrEqualTo(800 - 48 + 0.5),
    );
  });
}
