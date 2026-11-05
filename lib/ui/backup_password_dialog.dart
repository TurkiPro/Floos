import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// What the user chose when making a backup.
sealed class BackupProtection {
  const BackupProtection();
}

/// Encrypt under this password.
class WithPassword extends BackupProtection {
  final String password;
  const WithPassword(this.password);
}

/// A plain file, by explicit choice.
class WithoutPassword extends BackupProtection {
  const WithoutPassword();
}

/// The shortest password accepted. The KDF makes guessing slow, but a
/// four-character password is still a short list to try.
const minBackupPasswordLength = 6;

/// Asks for a password for a new backup, twice. Encrypted is the default; a
/// plain file needs an explicit «بدون كلمة مرور». Null means cancelled.
Future<BackupProtection?> askNewBackupPassword(BuildContext context) {
  return showDialog<BackupProtection>(
    context: context,
    builder: (_) => const _NewPasswordDialog(),
  );
}

class _NewPasswordDialog extends StatefulWidget {
  const _NewPasswordDialog();

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  String? get _problem {
    if (_first.text.length < minBackupPasswordLength) {
      return 'على الأقل $minBackupPasswordLength أحرف';
    }
    if (_first.text != _second.text) return 'كلمتا المرور غير متطابقتين';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final problem = _problem;
    final touched = _first.text.isNotEmpty || _second.text.isNotEmpty;
    return AlertDialog(
      title: const Text('حماية النسخة بكلمة مرور'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
                'النسخة تحتوي كل بياناتك المالية، وستغادر جهازك عند مشاركتها.'),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _first,
              obscureText: _obscure,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'كلمة المرور',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'إظهار' : 'إخفاء',
                  icon:
                      Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _second,
              obscureText: _obscure,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور',
                border: const OutlineInputBorder(),
                errorText: touched ? problem : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'إذا نسيت كلمة المرور فلا يمكن استرجاع هذه النسخة. '
              'لا تُحفظ كلمة المرور في أي مكان.',
              style:
                  TextStyle(fontSize: AppTextSizes.label, color: scheme.error),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(const WithoutPassword()),
          child: const Text('بدون كلمة مرور'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: problem == null
              ? () => Navigator.of(context).pop(WithPassword(_first.text))
              : null,
          child: const Text('إنشاء النسخة'),
        ),
      ],
    );
  }
}

/// Asks for the password of an encrypted backup being restored. Null means
/// cancelled. [wrong] shows that the previous attempt failed.
Future<String?> askBackupPassword(BuildContext context, {bool wrong = false}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _OpenPasswordDialog(wrong: wrong),
  );
}

class _OpenPasswordDialog extends StatefulWidget {
  final bool wrong;
  const _OpenPasswordDialog({required this.wrong});

  @override
  State<_OpenPasswordDialog> createState() => _OpenPasswordDialogState();
}

class _OpenPasswordDialogState extends State<_OpenPasswordDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('نسخة محمية بكلمة مرور'),
      content: TextField(
        controller: _ctrl,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'كلمة المرور',
          border: const OutlineInputBorder(),
          errorText:
              widget.wrong ? 'كلمة المرور غير صحيحة أو الملف تالف' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('فتح'),
        ),
      ],
    );
  }
}
