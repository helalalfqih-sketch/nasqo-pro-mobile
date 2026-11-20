import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../services/web_backup.dart';
import '../services/website_backup_file.dart';
import 'nasqo_brand_mark.dart';

import '../services/local_backup_files.dart';

class LocalBackupWorkspaceView extends StatefulWidget {
  const LocalBackupWorkspaceView(
      {super.key,
      required this.loadBackups,
      required this.createBackup,
      this.restoreWeb,
      this.onRestored,
      this.importLocal,
      this.exportLocal,
      this.restoreLocal,
      required this.verifyBackup,
      required this.testRestore});
  final Future<LocalBackupFile> Function(String)? importLocal;
  final Future<bool> Function(String)? exportLocal;
  final Future<void> Function(WebBackup)? restoreWeb;
  final ValueChanged<String>? onRestored;
  final Future<void> Function(String id)? restoreLocal;
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
  String? _restoring;
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
          _restoring = null;
        });
      }
    }
  }

  Future<void> _importWeb() => _run('جارٍ قراءة ملف النسخة…', () async {
    final file = await openFile();
    if (file == null) return 'أُلغي اختيار الملف.';
    if (!mounted) return '';
    setState(() => _restoring = file.name);
    final buffer = BytesBuilder(copy: false);
    const limit = LocalBackupFiles.maxBackupBytes;
    if (await file.length() > limit) return 'الحد الأقصى للنسخة 16 ميبيبايت.';
    await for (final chunk in file.openRead()) {
      if (buffer.length + chunk.length > limit) return 'الملف أكبر من الحد المدعوم.';
      buffer.add(chunk);
    }
    final WebBackup backup;
    try {
      final raw = await readWebsiteBackup(buffer.takeBytes(), limit);
      final root = jsonDecode(raw);
      if (root is Map && root['format'] == 'nasqo-local-qa-json-v1' && widget.importLocal != null) {
        final file = await widget.importLocal!(raw);
        if (mounted) _files = [file, ..._files];
        return 'تم التحقق من نسخة الهاتف وإضافتها للقائمة. اضغط «استعادة إلى الهاتف» لتطبيقها.';
      }
      backup = WebBackup.parse(raw);
    } on FormatException catch (error) {
      return 'تعذرت قراءة النسخة: ${error.message}';
    } on Object {
      return 'بنية سجلات الملف غير متوافقة مع تطبيق الهاتف.';
    }
    if (!mounted) return '';
    setState(() => _restoring = null);
    final confirmed = await showDialog<bool>(context: context, builder: (context) =>
      AlertDialog(title: const Text('استبدال بيانات الهاتف؟'),
        content: SingleChildScrollView(child: Text(
          '${backup.company}\nالحسابات: ${backup.accounts.length} • القيود: ${backup.ledger.length}\n'
          'المستودعات: ${backup.warehouses.length} • الأصناف: ${backup.inventory.length}\n'
          'ستُستبدل السجلات والمسودات الحالية. تُستخدم الحقول المدعومة في هذه الأقسام وبنود الفواتير وسجلات وحدات ERP المتوافقة. '
          'تُستعاد المجموعات المدعومة. قد تتضمن النسخة بيانات إضافية مثل جداول الإدارة وحقول الضرائب والخصومات لا يدعمها هذا المسار.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('استبدال واستعادة')),
        ]));
    if (confirmed != true || !mounted) return 'أُلغيت الاستعادة.';
    setState(() => _restoring = file.name);
    await widget.restoreWeb!(backup);
    final message = 'تمت استعادة ${file.name} • المجموعات: ${backup.groupData.groups.length} • الحسابات: ${backup.accounts.length} • الحركات: ${backup.ledger.length} • الأصناف: ${backup.inventory.length}';
    if (mounted) widget.onRestored?.call(message);
    return message;
  });

  Future<void> _restoreLocal(LocalBackupFile file) => _run('جارٍ تجهيز الاستعادة…', () async {
    final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('استعادة هذه النسخة إلى الهاتف؟'),
      content: Text('ستُستبدل بيانات مساحة العمل بالنسخة ${file.id}. سيتم الاحتفاظ بنسخة من البيانات الحالية.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('استبدال واستعادة'))]));
    if (confirm != true) return 'أُلغيت الاستعادة.';
    setState(() => _restoring = file.id);
    await widget.restoreLocal!(file.id);
    return 'اكتملت الاستعادة إلى قاعدة الهاتف.';
  });

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
          child: Stack(children:[Scaffold(
            appBar: AppBar(title: const Text('النسخ المحلية واختبار التعافي')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              if (widget.restoreWeb != null)
                FilledButton.icon(onPressed: _busy ? null : _importWeb,
                  icon: const Icon(Icons.file_open),
                  label: const Text('استيراد نسخة الموقع أو الهاتف (.back أو .json)')),
              const Text(
                  'تُحفظ النسخ داخل التطبيق دون تشفير. اختر «حفظ في ملف» للاحتفاظ بالنسخة خارج التطبيق. اختبار النسخة المحلية يجري في قاعدة منفصلة.'),
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
                                if (widget.exportLocal != null) OutlinedButton(onPressed: _busy ? null : () =>
                                  _run('جارٍ تصدير النسخة…', () async => await widget.exportLocal!(file.id)
                                    ? 'تم حفظ النسخة في الملف المحدد.' : 'أُلغي التصدير.'), child: const Text('حفظ في ملف')),
                                if (widget.restoreLocal != null) OutlinedButton(onPressed: _busy ? null : () => _restoreLocal(file), child: const Text('استعادة إلى الهاتف')),
                              ]),
                            ]))),
            ]),
          ),
          if (_restoring != null) Positioned.fill(child: ColoredBox(
            color:const Color(0xE6101224),child: Center(child: Material(color:Colors.transparent,
            child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,
              children:[const Stack(alignment:Alignment.center,children:[
                SizedBox.square(dimension:84,child:CircularProgressIndicator(color:Color(0xFF22BEEB))),
                NasqoBrandMark(size:64)]),
                const SizedBox(height:20),Text('جارٍ استعادة $_restoring وتجهيز النظام…',
                  textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold))
              ])))))),
          ]),
        ),
      );
}
