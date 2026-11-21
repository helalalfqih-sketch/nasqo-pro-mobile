import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/home_account_views.dart';
import '../models/erp_models.dart';
import '../screens/account_tools.dart';
import '../screens/home_warehouse_view.dart';
import '../screens/workspace_views.dart';
import '../services/android_csv_writer.dart';
import '../services/account_amounts.dart';
import '../services/local_sales_csv.dart';
import '../state/erp_controller.dart';
import 'home_presentation.dart';

class HybridHomeView extends StatefulWidget {
  const HybridHomeView(
      {super.key,
      required this.controller,
      required this.openModule,
      required this.showNative});
  final ErpController controller;
  final Future<void> Function(String, {AccountRecord? account}) openModule;
  final VoidCallback showNative;
  @override
  State<HybridHomeView> createState() => HybridHomeState();
}

class HybridHomeState extends State<HybridHomeView> {
  late final view = HomePresentation(widget.controller);
  MethodChannel? _channel;
  bool _ready = false, _editing = false, _overlay = false, _failed = false;
  bool _opening = false;
  late bool _dark;
  Timer? _startup;
  Future<void> _pending = Future.value();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dark = Theme.of(context).brightness == Brightness.dark;
    _refresh();
  }

  void _error() {
    _startup?.cancel();
    if (mounted && !_failed) setState(() => _failed = true);
  }

  Future<void> _attach(int id) async {
    final channel = MethodChannel('nasqo/home/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'intent' ||
          call.arguments is! String ||
          !mounted ||
          _failed) {
        return;
      }
      final msg = view.parse(call.arguments as String);
      if (msg == null) return;
      switch (msg['action']) {
        case 'ready':
          if (!_ready) {
            _ready = true;
            _refresh();
          }
        case 'paint':
          _startup?.cancel();
          await channel.invokeMethod<void>('paint');
        case 'editing':
          if (_editing != msg['active']) {
            setState(() => _editing = msg['active'] as bool);
          }
        case 'overlay':
          if (_overlay != msg['active']) {
            setState(() => _overlay = msg['active'] as bool);
          }
        case 'currency':
        case 'scroll':
        case 'layout':
          _pending = _pending.then((_) async {
            await view.savePreference(msg);
            if (msg['action'] == 'currency') _refresh();
          }).catchError((Object error) {
            _error();
          });
        case 'tile':
        case 'navigate':
          if (_opening || ModalRoute.of(context)?.isCurrent != true) return;
          _opening = true;
          try {
            final id = msg['id'] as String;
            final route = msg['action'] == 'tile' ? homeDestinations[id]! : id;
            await widget.openModule(route);
            if (mounted &&
                (route == 'measurements' || route == 'measurement-new')) {
              await view.loadMeasurementCount();
              _refresh();
            }
          } finally {
            _opening = false;
          }
        case 'browse':
          view.directory.open(msg['screen'] as String);
          _refresh();
        case 'members':
        case 'group':
          await _pending;
          if (!mounted ||
              _failed ||
              ModalRoute.of(context)?.isCurrent != true) {
            return;
          }
          final id = msg['id'] as int?;
          final category = id == null
              ? AccountCategory.values.byName(msg['category'])
              : view.categoryFor(id);
          view.directory.open('suppliers',
              groupId: category == null ? id : null,
              accountCategory: category,
              initialCurrency: id == null ? null : view.selection(id));
          _refresh();
        case 'filter':
          view.directory.period = msg['period'] as String;
          view.directory.currency = msg['currency'] as String;
          _refresh();
        case 'account':
        case 'directoryExport':
        case 'warehouse':
          if (_opening || ModalRoute.of(context)?.isCurrent != true) return;
          _opening = true;
          try {
            if (msg['action'] == 'directoryExport') {
              await _export(msg);
            } else if (msg['action'] == 'warehouse') {
              await _warehouseAction(msg);
            } else {
              await _accountAction(msg);
            }
            _refresh();
          } finally {
            _opening = false;
          }
        case 'haptic':
          await HapticFeedback.selectionClick();
      }
    });
    try {
      await view.load();
      if (!mounted) return;
      _startup = Timer(const Duration(seconds: 15), _error);
      await channel.invokeMethod<void>('start');
    } catch (_) {
      _error();
    }
  }

  Future<void> _export(Map<String, dynamic> msg) async {
    try {
      if (msg['format'] == 'pdf-print') {
        await _channel?.invokeMethod<void>('printDirectory');
        return;
      }
      final rows = view.directory.exportRows(msg['onlyCurrency'] as bool);
      if (msg['format'] == 'excel') {
        String cell(String value) => '"${value.replaceAll('"', '""')}"';
        final lines = [
          for (final r in rows)
            [
              for (final (index, value) in r.indexed)
                cell(index == 1 ? LocalSalesCsv.safeText(value) : value)
            ].join(',')
        ].join('\r\n');
        final saved = await const AndroidCsvWriter().saveToChosenFile(
            Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode(lines)]),
            'nasqo-accounts.csv');
        if (saved && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم حفظ ملف الحسابات CSV')));
        }
      } else {
        final totals = <String, double>{};
        for (final r in rows.skip(1)) {
          totals.update(r[2], (v) => v + double.parse(r[5]),
              ifAbsent: () => double.parse(r[5]));
        }
        final summary = [
          widget.controller.companyName,
          'ملخص أرصدة الحسابات',
          for (final e in totals.entries)
            '${e.value.toStringAsFixed(2)} ${e.key}'
        ].join('\n');
        await _channel
            ?.invokeMethod<void>('contact', {'op': 'message', 'text': summary});
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذّر إكمال التصدير على هذا الجهاز')));
      }
    }
  }

  Future<void> _warehouseAction(Map<String, dynamic> msg) async {
    final c = widget.controller;
    final w = c.warehouses.where((w) => w.id == msg['id']).firstOrNull;
    if (msg['op'] == 'create' || msg['op'] == 'edit') {
      await showWarehouseEditor(context, c, w);
    } else if (w != null) {
      final items = msg['op'] == 'items';
      await Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (_) => Scaffold(
                  appBar: AppBar(
                      title: Text(
                          '${items ? "أصناف المخزن" : "حركة المخزون"}: ${w.name}')),
                  body: items
                      ? InventoryCatalogScreen(controller: c, warehouseId: w.id)
                      : StockMovementScreen(
                          controller: c, warehouseId: w.id))));
    }
  }

  Future<void> _accountAction(Map<String, dynamic> msg) async {
    final a = view.directory.account(msg['id']);
    if (a == null) return;
    final op = msg['op'];
    final selected = CurrencyCode.values
        .where((c) => c.label == view.directory.currency)
        .firstOrNull;
    final cur = view.directory.screen == 'suppliers'
        ? selected ?? a.currency
        : a.currency;
    if (op == 'statement' || op == 'edit') {
      await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => op == 'edit'
              ? Scaffold(
                  appBar: AppBar(title: Text('تعديل ${a.name}')),
                  body:
                      AccountEditor(controller: widget.controller, account: a))
              : HomeAccountStatementView(
                  controller: widget.controller,
                  accountId: a.id,
                  initialCurrency: cur)));
    } else if (op == 'contact' || op == 'whatsapp' || op == 'message') {
      final amount = accountAmountsByCurrency(widget.controller, [a],
          period: view.directory.period)[(a.id, cur)];
      final net = (amount?.credit ?? 0) - (amount?.debit ?? 0);
      final side = net < 0
          ? 'عليه'
          : net > 0
              ? 'له'
              : 'متزن';
      final message =
          'رصيد ${a.name}: ${net.abs().toStringAsFixed(2)} ${cur.label} ($side)';
      try {
        await _channel?.invokeMethod<void>(
            'contact', {'op': op, 'phone': a.phone, 'text': message});
      } on PlatformException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تعذّر فتح تطبيق التواصل على هذا الجهاز')));
        }
      }
    } else {
      const routes = {
        'invoice': 'invoice',
        'return': 'sales-return-drafts',
        'quote': 'quote-new',
        'order': 'order-new',
        'voucher': 'post-voucher',
        'transfer': 'post-transfer',
        'journal': 'post-journal',
        'exchange': 'post-exchange'
      };
      await widget.openModule(routes[op]!, account: a);
    }
  }

  void _refresh() {
    if (_ready && !_failed && mounted) {
      _channel
          ?.invokeMethod<void>('present', jsonEncode(view.snapshot(_dark)))
          .catchError((Object error) {
        _error();
      });
    }
  }

  @override
  void dispose() {
    _startup?.cancel();
    widget.controller.removeListener(_refresh);
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('تعذّر فتح الرئيسية الهجينة على هذا الجهاز.'),
        TextButton(
            onPressed: widget.showNative,
            child: const Text('فتح الرئيسية الأصلية')),
      ]));
    }
    return PopScope(
        canPop: !_editing && !_overlay,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && (_editing || _overlay)) {
            _channel?.invokeMethod<void>('endEdit');
          }
        },
        child: AndroidView(
            viewType: 'nasqo/offline-home',
            layoutDirection: TextDirection.rtl,
            onPlatformViewCreated: _attach));
  }
}
