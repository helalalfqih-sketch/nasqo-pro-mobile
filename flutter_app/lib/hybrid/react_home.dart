import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../state/erp_controller.dart';
import 'react_workspace.dart';

// Only QA builds explicitly selecting both flags get the React financial UI.
// Neither choice is tied to Flutter's debug/release build mode. Without these
// flags existing non-QA builds keep their original presentation and permissions.
const reactHomeEnabled =
    bool.fromEnvironment('NASQO_QA_REACT_PRIMARY', defaultValue: false);
const reactHomeAllowWrites = reactHomeEnabled &&
    bool.fromEnvironment('NASQO_QA_REACT_ALLOW_WRITES', defaultValue: false);

class ReactHome extends StatefulWidget {
  const ReactHome(
      {super.key, required this.controller, required this.onLegacy});
  final ErpController controller;
  final VoidCallback onLegacy;
  @override
  State<ReactHome> createState() => _ReactHomeState();
}

class _ReactHomeState extends State<ReactHome> {
  late final _workspace =
      ReactWorkspace(widget.controller, allowWrites: reactHomeAllowWrites,
          confirmRestore: _confirmWebsiteRestore);
  MethodChannel? _channel;
  bool _failed = false;
  Future<void> _attach(int id) async {
    final channel = MethodChannel('nasqo/home/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'reactRequest' && call.arguments is String) {
        final raw = call.arguments as String;
        final response = await _workspace.handle(raw);
        // Reload the same React tree from the newly committed native SQLite.
        if (mounted) {
          final reply = jsonDecode(response);
          if (reply is Map && reply['ok'] == true &&
              reply['action'] == 'restoreWorkspace' &&
              reply['data'] is Map &&
              (reply['data'] as Map)['restored'] == true) {
            await channel.invokeMethod<void>('present', jsonEncode({
              'protocolVersion': '1.0.0',
              'kind': 'event',
              'event': 'snapshotUpdated',
              'payload': (reply['data'] as Map)['snapshot'],
              'timestampMs': DateTime.now().millisecondsSinceEpoch,
            }));
          }
        }
        // React owns all screen navigation. Only a deliberate Back at the
        // React route-stack root may offer the separate legacy QA fallback.
        if (mounted) {
          try {
            final message = jsonDecode(raw);
            if (message is Map &&
                message['kind'] == 'request' &&
                message['action'] == 'goBack' &&
                message['payload'] is Map &&
                (message['payload'] as Map)['stackDepth'] == 1) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) unawaited(_chooseHome());
              });
            }
          } on FormatException {
            // ReactWorkspace has already rejected malformed bridge messages.
          }
        }
        return response;
      }
      return null;
    });
    try {
      await channel.invokeMethod<void>('start');
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<bool> _confirmWebsiteRestore(Map<String, Object?> preview) async {
    if (!mounted || preview['restorable'] != true) return false;
    final counts = preview['counts'] as Map? ?? const {};
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد استعادة بيانات الويب'),
        content: Text(
          'الملف: ${preview['fileName']}\n'
          'الحسابات: ${counts['accounts'] ?? 0} • المجموعات: ${counts['groups'] ?? 0}\n'
          'العملات: ${counts['currencies'] ?? 0} • الفواتير: ${counts['invoices'] ?? 0}\n'
          'السندات: ${counts['vouchers'] ?? 0} • المخازن: ${counts['warehouses'] ?? 0}\n'
          'الأصناف: ${counts['items'] ?? 0}\n\n'
          'سيُحفظ ملف رجوع مستقل أولًا، ولن يبدأ الاستبدال إلا بعد التأكيد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('أوافق على الاستعادة')),
        ],
      ),
    );
    return approved == true;
  }

  Future<void> _backInsideReact() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      // The React FlowStack handles navigation, open dialogs, and keyboards.
      // It reports goBack only when its own route stack is at the root.
      await channel.invokeMethod<void>(
          'present',
          jsonEncode({
            'protocolVersion': '1.0.0',
            'kind': 'event',
            'event': 'backPressed',
            'payload': <String, Object?>{},
            'timestampMs': DateTime.now().millisecondsSinceEpoch,
          }));
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _chooseHome() async {
    final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('وضع استرداد QA'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('متابعة React')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('فتح الواجهة القديمة يدويًا')),
              ],
            ));
    if (leave == true && mounted) widget.onLegacy();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _workspace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_backInsideReact());
      },
      child: Scaffold(
          body: SafeArea(
              child: _failed
                  ? Center(
                      child: TextButton(
                          onPressed: widget.onLegacy,
                          child: const Text(
                              'تعذر فتح React. يمكنك اختيار واجهة الاسترداد القديمة')))
                  : AndroidView(
                      viewType: 'nasqo/offline-home',
                      layoutDirection: TextDirection.rtl,
                      creationParams: const {'reactWorkspace': true},
                      creationParamsCodec: const StandardMessageCodec(),
                      onPlatformViewCreated: _attach))));
}
