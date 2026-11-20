import 'package:flutter/material.dart';

import '../services/local_backup_files.dart';

class LocalBackupWorkspaceView extends StatefulWidget {
  const LocalBackupWorkspaceView(
      {super.key,
      required this.loadBackups,
      required this.createBackup,
      required this.verifyBackup,
      required this.testRestore});
  final Future<List<LocalBackupFile>> Function() loadBackups;
  final Future<LocalBackupFile> Function() createBackup;
  final Future<LocalBackupCheck> Function(String id) verifyBackup;

  /// Must restore only to a disposable isolated database, never the live database.
  final Future<LocalBackupCheck> Function(String id) testRestore;
  @override
  State<LocalBackupWorkspaceView> createState() =>
      _LocalBackupWorkspaceViewState();
}

class _LocalBackupWorkspaceViewState extends State<LocalBackupWorkspaceView> {
  List<LocalBackupFile> _files = [];
  bool _busy = false;
  String? _status;
  String? _error;
  LocalBackupCheck? _result;
  @override
  void initState() {
    super.initState();
    _run('جارٍ قراءة النسخ المحلية…', () async {
      _files = await widget.loadBackups();
      return 'اكتملت قراءة قائمة النسخ.';
    });
  }

  Future<void> _run(String waiting, Future<String> Function() operation) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _status = waiting;
      _error = null;
      _result = null;
    });
    try {
      final message = await operation();
      if (mounted) {
        setState(() {
          _status = message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = null;
          _error =
              'تعذر إكمال العملية. لم تُستبدل قاعدة البيانات الحالية. يمكنك إعادة المحاولة.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _refresh() => _run('جارٍ تحديث القائمة…', () async {
        final files = await widget.loadBackups();
        if (mounted) {
          _files = files;
        }
        return 'تم تحديث قائمة النسخ.';
      });

  void _create() => _run('جارٍ إنشاء نسخة داخل التطبيق…', () async {
        final file = await widget.createBackup();
        if (mounted) {
          _files = [file, ..._files.where((f) => f.id != file.id)];
        }
        return 'تم إنشاء نسخة محلية داخل التطبيق. لم تُختبر استعادتها بعد.';
      });

  void _check(LocalBackupFile file, {required bool restore}) => _run(
        restore
            ? 'جارٍ اختبار الاستعادة في قاعدة مؤقتة معزولة…'
            : 'جارٍ التحقق من سلامة النسخة…',
        () async {
          final result = await (restore
              ? widget.testRestore(file.id)
              : widget.verifyBackup(file.id));
          if (mounted) {
            _result = result;
          }
          return restore
              ? 'نجح اختبار الاستعادة المعزولة للنسخة: ${file.id}. لم تُستبدل البيانات الحالية.'
              : 'نجح التحقق من سلامة النسخة: ${file.id}. هذا ليس اختبار استعادة.';
        },
      );

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: PopScope(
          canPop: !_busy,
          child: Scaffold(
            appBar: AppBar(title: const Text('النسخ المحلية واختبار التعافي')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              const Text(
                  'نسخ محلية خاصة داخل مساحة التطبيق فقط، غير مشفرة وليست نسخاً خارجية. حذف التطبيق أو فقد الجهاز قد يفقد هذه النسخ أيضاً. لا توجد هنا مشاركة أو حذف أو استبدال للبيانات الحالية.'),
              const SizedBox(height: 12),
              const Text(
                  'التحقق يفحص سلامة النسخة. اختبار الاستعادة يقرأها في قاعدة مؤقتة معزولة، ولا يُعد استعادة فعلية أو ضماناً شاملاً للتعافي.'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.add),
                    label: const Text('إنشاء نسخة محلية')),
                OutlinedButton.icon(
                    onPressed: _busy ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('تحديث القائمة')),
              ]),
              if (_busy)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(
                        semanticsLabel: 'عملية محلية قيد التنفيذ')),
              if (_status != null)
                Semantics(
                    liveRegion: true,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(_status!))),
              if (_error != null)
                Semantics(
                    liveRegion: true,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)))),
              if (_result != null)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('بصمة سلامة النسخة'),
                              SelectableText(_result!.checksum,
                                  textDirection: TextDirection.ltr),
                              Text(
                                  'عدد الجداول التي فُحصت: ${_result!.tableCounts.length}'),
                              Text(
                                  'عدد الصفوف التي فُحصت: ${_result!.tableCounts.values.fold<int>(0, (a, b) => a + b)}'),
                            ]))),
              if (_files.isEmpty && !_busy)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'لا توجد نسخ محلية معروضة. حدّث القائمة أو أنشئ نسخة صراحةً.')),
              for (final file in _files)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(file.id,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text(
                                  'تاريخ النسخة: ${file.modifiedAt.toLocal().toIso8601String().split('.').first}'),
                              Text('حجم النسخة: ${file.bytes} بايت'),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _check(file, restore: false),
                                    child: const Text('التحقق من السلامة')),
                                OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _check(file, restore: true),
                                    child: const Text('اختبار استعادة معزولة')),
                              ]),
                            ]))),
            ]),
          ),
        ),
      );
}
