import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/erp_models.dart';
import '../state/erp_controller.dart';

String _normalize(String text) => text.trim().toLowerCase()
    .replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ـ', '');

double _number(String text) {
  var value = text.trim().replaceAll('٫', '.').replaceAll('٬', '');
  for (var i = 0; i < 10; i++) {
    value = value.replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i').replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
  }
  return double.tryParse(value) ?? double.nan;
}

Map<String, String> _fields(String raw) {
  if (raw.startsWith('{')) {
    try {
      final data = jsonDecode(raw);
      if (data is Map) {
        return {for (final e in data.entries)
          if (e.value is String || e.value is num)
            e.key.toString().toLowerCase(): e.value.toString().trim()};
      }
    } on FormatException { /* Try a plain code below. */ }
  }
  if (raw.contains('=') && (raw.contains(';') || raw.contains('\n'))) {
    final fields = <String, String>{};
    for (final pair in raw.split(RegExp('[;\n]'))) {
      final index = pair.indexOf('=');
      if (index > 0) fields[pair.substring(0, index).trim().toLowerCase()] = pair.substring(index + 1).trim();
    }
    return fields;
  }
  final key = raw.replaceFirst(RegExp(r'^(sku:|item:|product:)', caseSensitive: false), '').trim();
  return {RegExp(r'^[a-zA-Z0-9_-]{3,32}$').hasMatch(key) ? 'sku' : 'name': key};
}

class StockScannerView extends StatefulWidget {
  const StockScannerView({super.key, required this.controller, this.createOnOpen = false});
  final ErpController controller;
  final bool createOnOpen;
  @override
  State<StockScannerView> createState() => _StockScannerState();
}

class _StockScannerState extends State<StockScannerView> {
  final _code = TextEditingController();
  final _name = TextEditingController(), _sku = TextEditingController(), _unit = TextEditingController();
  final _qty = TextEditingController(), _cost = TextEditingController(), _threshold = TextEditingController();
  late final _scanner = MobileScannerController();
  List<InventoryItemRecord> _matches = [];
  String? _selectedId, _warehouse, _message;
  bool _camera = false, _busy = false, _searched = false;

  @override
  void initState() {
    super.initState();
    final stores = widget.controller.warehouses;
    _warehouse = stores.where((w) => w.isDefault).firstOrNull?.id ?? stores.firstOrNull?.id;
    _unit.text = 'حبة';
    _qty.text = '10';
    _cost.text = '0';
    _threshold.text = '25';
    _searched = widget.createOnOpen;
  }

  @override
  void dispose() {
    for (final field in [_code, _name, _sku, _unit, _qty, _cost, _threshold]) { field.dispose(); }
    _scanner.dispose();
    super.dispose();
  }

  void _lookup(String raw) {
    if (_busy || raw.trim().isEmpty) return;
    final fields = _fields(raw.trim());
    final key = _normalize(fields['sku'] ?? fields['code'] ?? fields['name'] ?? fields['id'] ?? raw);
    if (key.isEmpty) return;
    final stock = widget.controller.inventory;
    var matches = stock.where((i) => _normalize(i.id) == key || _normalize(i.sku) == key).toList();
    if (matches.isEmpty) {
      final name = _normalize(fields['name'] ?? key);
      if (name.isNotEmpty) matches = stock.where((i) => _normalize(i.name).contains(name)).toList();
    }
    setState(() {
      _camera = false;
      _searched = true;
      _message = null;
      _matches = matches;
      _selectedId = matches.length == 1 ? matches.single.id : null;
      _code.text = raw.trim();
      _name.text = fields['name'] ?? '';
      _sku.text = fields['sku'] ?? fields['code'] ?? '';
      _unit.text = fields['unit'] ?? 'حبة';
      _qty.text = matches.isEmpty ? fields['quantity'] ?? fields['qty'] ?? '10' : '1';
      _cost.text = fields['avgcost'] ?? fields['cost'] ?? fields['price'] ?? '0';
      _threshold.text = fields['minthreshold'] ?? fields['min'] ?? '25';
    });
  }

  Future<void> _image() async {
    final file = await openFile(acceptedTypeGroups: [const XTypeGroup(label: 'صورة', mimeTypes: ['image/*'])]);
    if (file == null || !mounted) return;
    try {
      final result = await _scanner.analyzeImage(file.path);
      if (!mounted) return;
      final code = result?.barcodes.firstOrNull?.rawValue;
      if (code != null && code.isNotEmpty) {
        _lookup(code);
      } else {
        setState(() => _message = 'لم يظهر رمز قابل للقراءة في الصورة.');
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'تعذرت قراءة الصورة. يمكنك إدخال الرمز يدويًا.');
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      await widget.controller.receiveStock(existingId: _selectedId, quantity: _number(_qty.text),
        name: _name.text, sku: _sku.text, unit: _unit.text, avgCost: _number(_cost.text),
        threshold: _number(_threshold.text), warehouseId: _warehouse ?? '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المخزون')));
      Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _message = error is SaleValidationException ? error.message : 'تعذر حفظ المخزون.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String label, TextEditingController controller, {bool number = false}) =>
    TextField(controller: controller, enabled: !_busy,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(labelText: label));

  @override
  Widget build(BuildContext context) {
    final item = _matches.where((i) => i.id == _selectedId).firstOrNull;
    String warehouseName(String id) => widget.controller.warehouses.where((w) => w.id == id).firstOrNull?.name ?? id;
    return Scaffold(appBar: AppBar(title: Text(widget.createOnOpen ? 'إضافة صنف للمخزن' : 'ماسح QR للمخزون والأصناف')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        if (!widget.createOnOpen) ...[
          if (_camera) SizedBox(height: 210, child: MobileScanner(
            onDetect: (capture) {
              final raw = capture.barcodes.firstOrNull?.rawValue;
              if (mounted && _camera && raw != null) _lookup(raw);
            })),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: _busy ? null : () => setState(() => _camera = !_camera),
              icon: const Icon(Icons.camera_alt_outlined), label: Text(_camera ? 'إيقاف الكاميرا' : 'تشغيل الكاميرا')),
            OutlinedButton.icon(onPressed: _busy || _camera ? null : _image, icon: const Icon(Icons.image_outlined), label: const Text('رفع صورة QR')),
          ]),
          TextField(controller: _code, enabled: !_busy, onSubmitted: _lookup,
            onChanged: (_) => setState(() { _searched = false; _message = null; }),
            decoration: InputDecoration(labelText: 'رمز الصنف أو اسمه', suffixIcon: IconButton(
              tooltip: 'بحث', icon: const Icon(Icons.search), onPressed: _busy ? null : () => _lookup(_code.text)))),
        ],
        if (_searched) ...[
          if (_matches.length > 1) DropdownButtonFormField<String>(value: _selectedId, isExpanded: true,
            decoration: const InputDecoration(labelText: 'اختر الصنف والمستودع'),
            items: [for (final i in _matches) DropdownMenuItem(value: i.id, child: Text('${i.name} · ${warehouseName(i.warehouseId)}'))],
            onChanged: _busy ? null : (id) => setState(() => _selectedId = id)),
          if (item != null) ListTile(title: Text(item.name),
            subtitle: Text('${warehouseName(item.warehouseId)} · الرصيد الحالي: ${item.quantity} ${item.unit}\nمتوسط التكلفة: ${item.avgCost} · حد التنبيه: ${item.minThreshold}')),
          if (_matches.isEmpty) ...[
            _field('اسم الصنف', _name), _field('رمز الصنف', _sku), _field('الوحدة', _unit),
            DropdownButtonFormField<String>(value: _warehouse, isExpanded: true,
              decoration: const InputDecoration(labelText: 'المستودع'),
              items: [for (final w in widget.controller.warehouses) DropdownMenuItem(value: w.id, child: Text(w.name))],
              onChanged: _busy ? null : (id) => setState(() => _warehouse = id)),
            _field('متوسط التكلفة', _cost, number: true), _field('حد التنبيه', _threshold, number: true),
          ],
          if (_matches.isEmpty || item != null) ...[
            _field(_matches.isEmpty ? 'الكمية الافتتاحية' : 'الكمية المضافة', _qty, number: true),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _save,
              child: Text(_matches.isEmpty ? 'إضافة الصنف إلى المخزون' : 'توريد للمخزون')),
          ],
        ],
        if (_message != null) Text(_message!, semanticsLabel: _message),
      ])));
  }
}
