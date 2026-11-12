import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/features/onboarding/setup_flow.dart';

void main() {
  late String content;
  late int saves;
  late int notices;
  late bool canSave;
  late DraftAutosave autosave;

  /// Created inside each test, so its timer runs on the test's own clock.
  void begin() {
    content = 'one';
    saves = 0;
    notices = 0;
    canSave = true;
    autosave = DraftAutosave(
      signature: () => content,
      save: () async {
        saves++;
        return canSave;
      },
      onSaved: () => notices++,
    )..start();
  }

  testWidgets('saves once, 10 seconds after the last change, and says so', (tester) async {
    begin();
    content = 'two';
    await tester.pump(const Duration(seconds: 9));
    expect(saves, 0);
    await tester.pump(const Duration(seconds: 3));
    expect((saves, notices), (1, 1));
    autosave.dispose(); // the test's own clock must have no timer left running
  });

  testWidgets('what was on screen when it started counts as saved', (tester) async {
    begin();
    await tester.pump(const Duration(seconds: 60));
    expect(saves, 0);
    autosave.dispose(); // the test's own clock must have no timer left running
  });

  testWidgets('every new change starts the 10 seconds over', (tester) async {
    begin();
    content = 'two';
    await tester.pump(const Duration(seconds: 8));
    content = 'three';
    await tester.pump(const Duration(seconds: 8));
    expect(saves, 0, reason: '16 seconds in, but only 8 since the last change');
    await tester.pump(const Duration(seconds: 4));
    expect(saves, 1);
    autosave.dispose(); // the test's own clock must have no timer left running
  });

  testWidgets('the same content is never saved twice', (tester) async {
    begin();
    content = 'two';
    await tester.pump(const Duration(seconds: 12));
    expect(saves, 1);
    await tester.pump(const Duration(seconds: 60));
    expect(saves, 1);
    expect(notices, 1);
    autosave.dispose(); // the test's own clock must have no timer left running
  });

  testWidgets('a later change after a save is saved again', (tester) async {
    begin();
    content = 'two';
    await tester.pump(const Duration(seconds: 12));
    content = 'three';
    await tester.pump(const Duration(seconds: 12));
    expect((saves, notices), (2, 2));
    autosave.dispose(); // the test's own clock must have no timer left running
  });

  testWidgets('when there is nothing it can save yet, it says nothing and does not keep trying the same content', (tester) async {
    begin();
    canSave = false;
    content = 'two';
    await tester.pump(const Duration(seconds: 12));
    expect((saves, notices), (1, 0));
    await tester.pump(const Duration(seconds: 60));
    expect(saves, 1, reason: 'the same unsaveable content is not retried');

    canSave = true;
    content = 'three'; // changed: it tries again
    await tester.pump(const Duration(seconds: 12));
    expect((saves, notices), (2, 1));
    autosave.dispose(); // the test's own clock must have no timer left running
  });

  testWidgets('markSaved: what the person saved or moved on with by themselves is not saved again', (tester) async {
    begin();
    content = 'two';
    autosave.markSaved();
    await tester.pump(const Duration(seconds: 30));
    expect(saves, 0);
    autosave.dispose(); // the test's own clock must have no timer left running
  });

  testWidgets('a save that throws is not shown and does not repeat for the same content', (tester) async {
    begin();
    autosave.dispose();
    var attempts = 0;
    autosave = DraftAutosave(
      signature: () => content,
      save: () async {
        attempts++;
        throw StateError('network down');
      },
      onSaved: () => notices++,
    )..start();
    content = 'two';
    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 60));
    expect((attempts, notices), (1, 0));
    autosave.dispose(); // the test's own clock must have no timer left running
  });

  testWidgets('after dispose it does nothing', (tester) async {
    begin();
    content = 'two';
    autosave.dispose();
    await tester.pump(const Duration(seconds: 30));
    expect(saves, 0);
  });
}
