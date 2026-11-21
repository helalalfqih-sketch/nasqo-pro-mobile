import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/erp_models.dart';
import '../state/erp_controller.dart';

/// A read-only local document. The platform view can request output for this
/// route only. It cannot select a record, change a draft or post a transaction.
class HybridDocumentView extends StatefulWidget {
  const HybridDocumentView({super.key, required this.controller,
    required this.accountId, required this.entryId, required this.nativePreview});
  final ErpController controller;
  final String accountId, entryId;
  final Widget Function(LedgerEntryRecord entry) nativePreview;

  @override
  State<HybridDocumentView> createState() => _HybridDocumentState();
}

class _HybridDocumentState extends State<HybridDocumentView> {
  MethodChannel? _channel;
  Timer? _startup;
  LedgerEntryRecord? _entry;
  Map<String, Object?>? _document;
  bool _ready = false, _failed = false, _busy = false, _dark = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dark = Theme.of(context).brightness == Brightness.dark;
    if (_ready) unawaited(_present());
  }

  void _fail() {
    _startup?.cancel();
    if (mounted && !_failed) setState(() => _failed = true);
  }

  Future<void> _present() async {
    if (!_ready || !mounted || _failed || _document == null) return;
    try {
      await _channel?.invokeMethod<void>('present', jsonEncode({
        ..._document!, 'dark': _dark, 'busy': _busy,
      }));
    } on PlatformException {
      _fail();
    }
  }

  Future<void> _attach(int id) async {
    final channel = MethodChannel('nasqo/home/$id');
    _channel = channel;
    try {
      final doc = await widget.controller.database.readStatementDocument(widget.accountId, widget.entryId);
      if (!mounted) return;
      final entry = doc.entry;
      _entry = entry;
      _document = {
        'screen': 'document', 'company': widget.controller.companyName,
        'generatedAt': DateTime.now().toIso8601String(),
        'entry': {'id': entry.id, 'entryNumber': entry.entryNumber,
          'documentNumber': entry.documentNumber, 'entryDate': entry.entryDate,
          'accountName': entry.accountName, 'warehouseName': entry.warehouseName,
          'typeLabel': entry.typeLabel, 'details': entry.details,
          'amount': entry.amount, 'currency': entry.currency.label, 'lineCount': doc.lines.length},
        'lines': [for (final line in doc.lines) {
          'id': line.position, 'itemName': line.itemName, 'unit': line.unit,
          'quantity': line.quantity, 'price': line.unitPrice, 'total': line.quantity * line.unitPrice,
        }],
      };
      channel.setMethodCallHandler(_intent);
      _startup = Timer(const Duration(seconds: 15), _fail);
      await channel.invokeMethod<void>('start');
    } catch (_) {
      _fail();
    }
  }

  Future<void> _intent(MethodCall call) async {
    if (!mounted || _failed || call.method != 'intent') return;
    final raw = call.arguments;
    if (raw is! String || raw.length > 96) return;
    Object? msg;
    try { msg = jsonDecode(raw); } on FormatException { return; }
    if (msg is! Map<String, dynamic>) return;
    if (msg.length == 1 && msg['action'] == 'ready') {
      _ready = true;
      await _present();
    } else if (msg.length == 1 && msg['action'] == 'documentPaint') {
      _startup?.cancel();
    } else if (_ready && ModalRoute.of(context)?.isCurrent == true) {
      if (msg.length == 1 && msg['action'] == 'documentClose') {
        Navigator.of(context).pop();
      } else if (msg.length == 2 && msg['action'] == 'documentOutput' &&
          const {'print', 'pdf'}.contains(msg['op']) && !_busy) {
        _busy = true;
        await _present();
        try {
          await _channel?.invokeMethod<void>('printDocument');
        } on PlatformException {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تعذّر فتح مربع طباعة Android.')));
          }
        } finally {
          _busy = false;
          await _present();
        }
      }
    }
  }

  @override
  void dispose() {
    _startup?.cancel();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      final entry = _entry;
      if (entry != null) return widget.nativePreview(entry);
      return Scaffold(appBar: AppBar(title: const Text('معاينة المستند')),
          body: const Center(child: Text('تعذّر قراءة المستند من الحساب المحدد.')));
    }
    return Scaffold(body: SafeArea(child: AndroidView(viewType: 'nasqo/offline-home',
        layoutDirection: TextDirection.rtl, onPlatformViewCreated: _attach)));
  }
}
