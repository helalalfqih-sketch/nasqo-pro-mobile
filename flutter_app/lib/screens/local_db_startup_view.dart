import 'package:flutter/material.dart';

/// A non-destructive local database startup gate. Never displays raw errors.
class LocalDbStartupView extends StatefulWidget {
  const LocalDbStartupView(
      {super.key, required this.diagnosticCode, required this.retry});
  final String? diagnosticCode;
  final Future<void> Function() retry;
  @override
  State<LocalDbStartupView> createState() => _LocalDbStartupViewState();
}

class _LocalDbStartupViewState extends State<LocalDbStartupView> {
  bool _retrying = false;
  bool _retryFailed = false;
  static const _descriptions = <String, String>{
    'DB-DRIVER': 'تعذر تشغيل مكوّن قاعدة البيانات المحلية.',
    'DB-SETTINGS': 'تعذر تجهيز إعدادات قاعدة البيانات المحلية.',
    'DB-SCHEMA': 'تعذر تجهيز بنية قاعدة البيانات المحلية أو تحديثها.',
    'DB-LOCKED':
        'قاعدة البيانات المحلية مشغولة حالياً. انتظر قليلاً ثم أعد المحاولة.',
    'DB-SPACE':
        'تعذر توفير مساحة كافية لقاعدة البيانات. تحقق من مساحة الجهاز دون حذف بيانات التطبيق.',
    'DB-DAMAGED':
        'تعذر التحقق من سلامة قاعدة البيانات المحلية. حافظ على بيانات التطبيق واطلب المساعدة إذا استمرت المشكلة.',
    'DB-OPEN': 'تعذر فتح قاعدة البيانات المحلية.',
  };

  @override
  void didUpdateWidget(covariant LocalDbStartupView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diagnosticCode != widget.diagnosticCode) {
      _retryFailed = false;
    }
  }

  Future<void> _retry() async {
    if (_retrying || (widget.diagnosticCode == null && !_retryFailed)) {
      return;
    }
    setState(() {
      _retrying = true;
      _retryFailed = false;
    });
    try {
      await widget.retry();
    } catch (_) {
      if (mounted) {
        setState(() {
          _retryFailed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _retrying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading =
        _retrying || (widget.diagnosticCode == null && !_retryFailed);
    final supplied = widget.diagnosticCode;
    final code = _descriptions.containsKey(supplied) ? supplied! : 'DB-OPEN';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: !loading,
        child: Scaffold(
          appBar: AppBar(
              title: const Text('تجهيز قاعدة البيانات المحلية'),
              automaticallyImplyLeading: false),
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(24), children: [
            const Icon(Icons.storage,
                size: 48, semanticLabel: 'قاعدة البيانات المحلية'),
            const SizedBox(height: 24),
            if (loading) ...[
              const Center(
                  child: CircularProgressIndicator(
                      semanticsLabel: 'جارٍ تجهيز قاعدة البيانات')),
              const SizedBox(height: 20),
              Semantics(
                  liveRegion: true,
                  child: const Text(
                      'جارٍ تجهيز قاعدة البيانات المحلية. انتظر اكتمال التجهيز قبل إنشاء فاتورة.')),
            ] else ...[
              Semantics(
                  liveRegion: true,
                  child: Text(_descriptions[code]!,
                      style: Theme.of(context).textTheme.titleMedium)),
              const SizedBox(height: 12),
              Text('رمز التشخيص: $code'),
              const SizedBox(height: 12),
              const Text(
                  'إنشاء الفواتير متوقف مؤقتاً حتى تصبح قاعدة البيانات جاهزة.'),
              const SizedBox(height: 20),
              FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة بأمان')),
            ],
            const SizedBox(height: 24),
            const Text(
                'لا تحذف التطبيق أو بياناته، ولا تُعد تثبيته لحل المشكلة، حتى لا تفقد سجلاتك المحلية. إعادة المحاولة لا تطلب حذف البيانات أو تصفيرها.'),
          ])),
        ),
      ),
    );
  }
}
