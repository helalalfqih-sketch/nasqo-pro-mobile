import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../services/dev_update_service.dart';

/// Both startup checks and manual checks share the same verification path.
class DevUpdateAction extends StatefulWidget {
  const DevUpdateAction({super.key, this.updates = const DevUpdateService()});
  final DevUpdateService updates;
  @override
  State<DevUpdateAction> createState() => _DevUpdateActionState();
}

class _DevUpdateActionState extends State<DevUpdateAction> {
  bool busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(silent: true));
  }

  Future<void> _check({bool silent = false}) async {
    if (!mounted || busy || !widget.updates.supported) return;
    var reportError = !silent;
    setState(() => busy = true);
    try {
      final release = await widget.updates.check();
      if (!mounted) return;
      if (release == null) {
        if (!silent)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('التطبيق محدّث بالفعل')));
        return;
      }
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تحديث تجريبي متاح'),
          content: Text(
            'الإصدار ${release.versionName} (${release.versionCode})\n${release.notes}\n'
            'سيتم تنزيل نسخة موقعة والتحقق من بصمتها. أكمل حفظ عملك قبل التثبيت. يُثبَّت التحديث فوق التطبيق الحالي للاحتفاظ ببياناته.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('لاحقًا'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تنزيل وتحديث'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      reportError = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جار تنزيل التحديث والتحقق منه…')),
      );
      await widget.updates.downloadAndInstall(release);
    } catch (error) {
      if (mounted && reportError)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
            content: Text(error is FormatException
                ? 'تعذر التحديث: ${error.message}'
                : error is PlatformException
                    ? 'تعذّر فتح مثبّت أندرويد. تحقق من إذن تثبيت التحديث.'
                    : error is IOException
                        ? 'تعذّر إكمال التنزيل. تحقق من الاتصال ثم أعد المحاولة.'
                        : 'تعذّر التحديث. أعد المحاولة لاحقًا.')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'التحقق من تحديثات التطبيق',
        icon: Icon(busy ? Icons.hourglass_top : Icons.system_update_alt),
        onPressed: busy ? null : () => _check(),
      );
}
