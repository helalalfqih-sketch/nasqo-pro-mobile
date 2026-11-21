import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import '../services/website_restore_trial.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../services/web_backup.dart';
import '../services/website_backup_file.dart';
import 'nasqo_brand_mark.dart';

import '../services/local_backup_files.dart';
import '../services/legacy_backup_inspection.dart';
import 'web_auxiliary_views.dart';

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

  Uint8List? _selectedBytes;
  String? _fileName, _importMessage;
  Map<String, Object?> _report = {};
  LegacyBackupInspection? _inspection;
  WebBackup? _converted;
  bool _verified = false;
  final _testedLocal = <String>{};

  Future<void> _importStep(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _importMessage = null;
    });
    try {
      await operation();
    } on FormatException catch (e) {
      _importMessage = e.message.toString();
      _report['issue'] = _importMessage;
    } catch (_) {
      _importMessage = 'تعذّرت قراءة الملف أو إكمال العملية. راجع نتيجة الفحص.';
      _report['issue'] = _importMessage;
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _restoring = null;
        });
    }
  }

  Future<void> _importWeb() => _importStep(() async {
        final file = await openFile();
        if (file == null || !mounted) return;
        _selectedBytes = null;
        _inspection = null;
        _converted = null;
        _verified = false;
        _fileName = file.name;
        _report = {'file': file.name, 'bytes': await file.length()};
        final buffer = BytesBuilder(copy: false);
        const limit = LocalBackupFiles.maxBackupBytes;
        if (await file.length() > limit)
          throw const FormatException('تجاوز حجم الملف 16 ميبيبايت.');
        await for (final chunk in file.openRead()) {
          if (buffer.length + chunk.length > limit)
            throw const FormatException('تجاوز حجم الملف الحد المدعوم.');
          buffer.add(chunk);
        }
        final original = buffer.takeBytes();
        _report['sha256'] = sha256.convert(original).toString();
        final bytes = await unpackWebsiteBackup(original, limit);
        final sqlite = bytes.length >= 16 &&
            String.fromCharCodes(bytes.take(16)) == 'SQLite format 3\x00';
        _report['format'] = sqlite ? 'SQLite' : 'JSON';
        _inspection = await inspectLegacyBackup(bytes);
        if (_inspection != null) {
          _report['inspection'] = _inspection!.toJson();
          _importMessage = _inspection!.arabicSummary;
        }
        _selectedBytes = bytes;
      });

  Future<void> _convert() => _importStep(() async {
        _converted = null;
        _verified = false;
        _report.remove('trial');
        _report.remove('issue');
        final audit = _inspection;
        if (audit != null &&
            (!audit.integrityOk || audit.issues.values.any((n) => n > 0))) {
          throw const FormatException(
              'توقف التحويل. راجع المراجع والحقول المفقودة في تقرير الفحص.');
        }
        final raw = await readWebsiteBackup(
            _selectedBytes!, LocalBackupFiles.maxBackupBytes);
        final root = jsonDecode(raw);
        if (root is Map) {
          _report['dataFormat'] = root['format'];
          _report['version'] = root['version'];
        }
        if (root is Map &&
            root['format'] == 'nasqo-local-qa-json-v1' &&
            widget.importLocal != null) {
          final local = await widget.importLocal!(raw);
          _files = [local, ..._files.where((f) => f.id != local.id)];
          _selectedBytes = null;
          _importMessage = 'تم فحص نسخة الهاتف وإضافتها إلى النسخ المحلية.';
          return;
        }
        final backup = WebBackup.parse(raw);
        _converted = backup;
        _report['converted'] = {
          'accounts': backup.accounts.length,
          'movements': backup.ledger.length,
          'invoiceLines': backup.lines.length,
          'warehouses': backup.warehouses.length,
          'items': backup.inventory.length
        };
        _importMessage =
            'اكتمل التحويل. الحسابات: ${backup.accounts.length}، الحركات: ${backup.ledger.length}، الأصناف: ${backup.inventory.length}.';
      });

  Future<void> _trial() => _importStep(() async {
        _verified = false;
        _report['trial'] = await testWebsiteRestore(_converted!);
        _verified = true;
        _importMessage =
            'تطابقت السجلات بعد إغلاق قاعدة الاختبار وإعادة فتحها.';
      });

  Future<void> _applyWeb() => _importStep(() async {
        if (!_verified || _converted == null) return;
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('استبدال بيانات الهاتف؟'),
                    content: Text(
                        'الملف: $_fileName\nالمنشأة: ${_converted!.company}\nسيحتفظ التطبيق بنسخة قابلة للرجوع من بياناتك الحالية قبل الاستعادة.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('إلغاء')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('استبدال واستعادة'))
                    ]));
        if (confirmed != true || !mounted) return;
        setState(() => _restoring = _fileName);
        await widget.restoreWeb!(_converted!);
        _verified = false;
        _report['restored'] = true;
        _importMessage = 'تمت استعادة $_fileName.';
        widget.onRestored?.call(_importMessage!);
      });

  Future<void> _saveReport() => _importStep(() async {
        final saved =
            await const MethodChannel('com.indexesstore.nasqo_qa/csv_export')
                .invokeMethod<bool>('saveReport', {
          'suggestedName': 'nasqo-inspection.json',
          'bytes': Uint8List.fromList(
              utf8.encode(const JsonEncoder.withIndent('  ').convert(_report)))
        });
        if (saved == true) _importMessage = 'تم حفظ تقرير الفحص.';
      });

  Future<void> _restoreLocal(LocalBackupFile file) =>
      _run('جارٍ تجهيز الاستعادة…', () async {
        final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('استعادة هذه النسخة إلى الهاتف؟'),
                    content: Text(
                        'ستُستبدل بيانات مساحة العمل بالنسخة ${file.id}. سيتم الاحتفاظ بنسخة من البيانات الحالية.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('إلغاء')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('استبدال واستعادة'))
                    ]));
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
            if (restore) _testedLocal.add(file.id);
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
          child: Stack(children: [
            Scaffold(
              appBar: AppBar(
                  toolbarHeight:
                      MediaQuery.textScalerOf(context).scale(24) * 2 + 16,
                  title: Text('النسخ المحلية واختبار التعافي',
                      maxLines: 2,
                      softWrap: true,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontSize: 18))),
              body: ListView(padding: const EdgeInsets.all(16), children: [
                if (widget.restoreWeb != null)
                  FilledButton.icon(
                      onPressed: _busy ? null : _importWeb,
                      icon: const Icon(Icons.file_open),
                      label: const Text(
                          'استيراد نسخة الموقع أو الهاتف (\u2066.back\u2069 أو \u2066.json\u2069)')),
                if (_fileName != null)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(_fileName!,
                                    textDirection: TextDirection.ltr),
                                Text('حجم الملف: ${_report["bytes"]} بايت'),
                                if (_report['format'] != null)
                                  Text('نوع النسخة: ${_report["format"]}'),
                                if (_report['version'] != null)
                                  Text('إصدار البيانات: ${_report["version"]}'),
                                if (_report['sha256'] != null)
                                  SelectableText(_report['sha256'] as String,
                                      textDirection: TextDirection.ltr),
                                if (_inspection != null)
                                  Text(_inspection!.arabicSummary),
                                if (_importMessage != null &&
                                    _importMessage !=
                                        _inspection?.arabicSummary)
                                  Text(_importMessage!),
                                OutlinedButton(
                                    onPressed: _busy || _selectedBytes == null
                                        ? null
                                        : _convert,
                                    child: const Text('اختبار التحويل')),
                                OutlinedButton(
                                    onPressed: _busy || _converted == null
                                        ? null
                                        : _trial,
                                    child: const Text(
                                        'اختبار استعادة الملف في قاعدة معزولة')),
                                FilledButton(
                                    onPressed:
                                        _busy || !_verified ? null : _applyWeb,
                                    child: const Text('استعادة البيانات')),
                                TextButton(
                                    onPressed: _busy ? null : _saveReport,
                                    child: const Text('حفظ تقرير الفحص')),
                              ]))),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('معلومات النسخ الاحتياطية',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        const Text(
                            'تُحفظ النسخ المحلية داخل التطبيق دون تشفير. استخدم «حفظ في ملف» '
                            'للاحتفاظ بنسخة خارج الهاتف.',
                            softWrap: true),
                        const SizedBox(height: 12),
                        const Text(
                            'اختبار الاستعادة يعمل في قاعدة مؤقتة منفصلة، '
                            'ولا يستبدل بياناتك الحالية.',
                            softWrap: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                      onPressed: _busy ? null : _create,
                      icon: const Icon(Icons.add),
                      label: const Text('إنشاء نسخة محلية')),
                  OutlinedButton.icon(
                      onPressed: _busy ? null : _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('تحديث القائمة')),
                  OutlinedButton.icon(
                      key: const ValueKey('backup-open-name-modal'),
                      onPressed: _busy
                          ? null
                          : () => showBackupNameModal(
                                context,
                                onSaveLocal: (_) async => _create(),
                              ),
                      icon: const Icon(Icons.drive_file_rename_outline),
                      label: const Text('تسمية نسخة احتياطية')),
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
                                  color:
                                      Theme.of(context).colorScheme.error)))),
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
                                    textDirection: TextDirection.ltr,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
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
                                      child:
                                          const Text('اختبار استعادة معزولة')),
                                  if (widget.exportLocal != null)
                                    OutlinedButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _run(
                                                'جارٍ تصدير النسخة…',
                                                () async => await widget
                                                        .exportLocal!(file.id)
                                                    ? 'تم حفظ النسخة في الملف المحدد.'
                                                    : 'أُلغي التصدير.'),
                                        child: const Text('حفظ في ملف')),
                                  if (widget.restoreLocal != null)
                                    OutlinedButton(
                                        onPressed: _busy ||
                                                !_testedLocal.contains(file.id)
                                            ? null
                                            : () => _restoreLocal(file),
                                        child:
                                            const Text('استعادة إلى الهاتف')),
                                ]),
                              ]))),
              ]),
            ),
            if (_restoring != null)
              Positioned.fill(
                  child: ColoredBox(
                      color: const Color(0xE6101224),
                      child: Center(
                          child: Material(
                              color: Colors.transparent,
                              child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              SizedBox.square(
                                                  dimension: 84,
                                                  child:
                                                      CircularProgressIndicator(
                                                          color: Color(
                                                              0xFF22BEEB))),
                                              NasqoBrandMark(size: 64)
                                            ]),
                                        const SizedBox(height: 20),
                                        Text(
                                            'جارٍ استعادة $_restoring وتجهيز النظام…',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold))
                                      ])))))),
          ]),
        ),
      );
}
