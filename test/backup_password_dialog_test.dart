import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/ui/backup_password_dialog.dart';

/// The backup password dialogs: encrypted by default, a plain file only by an
/// explicit choice, and no way to confirm a password that does not match.
void main() {
  Future<void> pumpLauncher(
      WidgetTester tester,
      Future<Object?> Function(BuildContext) open,
      void Function(Object?) onResult) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => onResult(await open(context)),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('creating needs two matching passwords of six or more',
      (tester) async {
    Object? result = 'unset';
    await pumpLauncher(tester, askNewBackupPassword, (r) => result = r);

    FilledButton create() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'إنشاء النسخة'));
    expect(create().onPressed, isNull);

    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور'), 'abc');
    await tester.enterText(
        find.widgetWithText(TextField, 'تأكيد كلمة المرور'), 'abc');
    await tester.pump();
    expect(create().onPressed, isNull, reason: 'too short');
    expect(find.textContaining('على الأقل 6'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'كلمة المرور'), 'abcdef');
    await tester.enterText(
        find.widgetWithText(TextField, 'تأكيد كلمة المرور'), 'abcdeg');
    await tester.pump();
    expect(create().onPressed, isNull, reason: 'they differ');
    expect(find.text('كلمتا المرور غير متطابقتين'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'تأكيد كلمة المرور'), 'abcdef');
    await tester.pump();
    await tester.tap(find.text('إنشاء النسخة'));
    await tester.pumpAndSettle();
    expect(result, isA<WithPassword>());
    expect((result as WithPassword).password, 'abcdef');
  });

  testWidgets('a plain file is an explicit choice', (tester) async {
    Object? result = 'unset';
    await pumpLauncher(tester, askNewBackupPassword, (r) => result = r);
    expect(find.textContaining('فلا يمكن استرجاع هذه النسخة'), findsOneWidget);
    await tester.tap(find.text('بدون كلمة مرور'));
    await tester.pumpAndSettle();
    expect(result, isA<WithoutPassword>());
  });

  testWidgets('cancel makes no backup at all', (tester) async {
    Object? result = 'unset';
    await pumpLauncher(tester, askNewBackupPassword, (r) => result = r);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('opening says when the last password was wrong', (tester) async {
    Object? result = 'unset';
    await pumpLauncher(
        tester, (c) => askBackupPassword(c, wrong: true), (r) => result = r);
    expect(find.text('كلمة المرور غير صحيحة أو الملف تالف'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'abcdef');
    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    expect(result, 'abcdef');
  });
}
