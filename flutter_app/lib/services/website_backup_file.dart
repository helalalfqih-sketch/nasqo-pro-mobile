import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

/// Decode supported website file contents without opening the live database.
Future<String> readWebsiteBackup(Uint8List input, int limit) async {
  var bytes = input;
  if (bytes.length >= 2 && bytes[0] == 31 && bytes[1] == 139) {
    final output = BytesBuilder(copy: false);
    await for (final block in gzip.decoder.bind(Stream.value(bytes))) {
      if (output.length + block.length > limit) {
        throw const FormatException('النسخة بعد فك الضغط أكبر من الحد المدعوم.');
      }
      output.add(block);
    }
    bytes = output.takeBytes();
  }
  if (!ascii.decode(bytes.take(16).toList(),allowInvalid:true).startsWith('SQLite format 3\x00')) {
    return utf8.decode(bytes);
  }
  final directory = await Directory.systemTemp.createTemp('nasqo-import-');
  try {
    final file = await File('${directory.path}/source.db').writeAsBytes(bytes);
    final db = await openDatabase(file.path,readOnly:true,singleInstance:false);
    try {
      final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name']).toSet();
      if (!tables.containsAll({'workspaces','accounts','account_groups','ledger_entries','inventory_items','warehouses'})) {
        // Recognize older website SQLite layouts without writing to the phone.
        // Importing these directly would lose relationships and accounting fields.
        if (tables.containsAll({'customers', 'products', 'stores', 'cboxes', 'trans_details'})) {
          throw const FormatException(
            'هذه نسخة SQLite قديمة من الموقع. الملف لم يتلف، لكن بنية '
            'جداوله تختلف عن قاعدة الهاتف. لم تُستبدل أي بيانات. '
            'احتفظ بالملف الأصلي؛ يلزم تحويل معزول مع مطابقة '
            'الحسابات والمخزون والفواتير قبل الاستعادة.');
        }
        throw const FormatException(
          'بنية SQLite غير مدعومة في هذا الإصدار. لم تُستبدل '
          'بيانات الهاتف. استخدم تصدير JSON الموحد من الموقع، '
          'أو احتفظ بالملف لفحص التوافق.');
      }
      final integrity = await db.rawQuery('PRAGMA quick_check(1)');
      if (integrity.length != 1 || integrity.single.values.single != 'ok') {
        throw const FormatException('لم يجتز ملف SQLite فحص السلامة.');
      }
      final workspaces = await db.query('workspaces',limit:2);
      if (workspaces.length != 1) throw const FormatException('يجب أن تتضمن النسخة منشأة واحدة.');
      final ws = workspaces.single;
      Future<List<Map<String,dynamic>>> rows(String table) async {
        final records = await db.query(table,where:'workspace_id = ?',whereArgs:[ws['id']]);
        return [for (final row in records) {
          for (final field in row.entries)
            field.key.replaceAllMapped(RegExp(r'_([a-z])'),(m)=>m[1]!.toUpperCase()):
                const {'is_default','is_cash_account','deleted','quantity_unverified','settled_on_receipt'}.contains(field.key)
                  ? field.value == 1 : field.value
        }];
      }
      final ledger = await rows('ledger_entries');
      final lines = <Object?,List<Map<String,dynamic>>>{};
      if (tables.contains('invoice_lines')) {
        for (final line in await rows('invoice_lines')) {
          (lines[line['entryId']] ??= []).add(line);
        }
      }
      for (final entry in ledger) { entry['lines'] = lines[entry['id']] ?? []; }
      final modules = <String,dynamic>{};
      const moduleTables = {
        'employees':'erp_employees','leaveRequests':'erp_leave_requests',
        'deals':'erp_deals','purchaseOrders':'erp_purchase_orders','boms':'erp_boms',
        'productionOrders':'erp_production_orders','costCenters':'erp_cost_centers'
      };
      for (final module in moduleTables.entries) {
        if (!tables.contains(module.value)) continue;
        final records = await rows(module.value);
        for (final record in records) {
          for (final field in ['lines','components','linkedCategories']) {
            final encoded = record.remove('${field}Json');
            if (encoded is String) record[field] = jsonDecode(encoded);
          }
        }
        modules[module.key] = records;
      }
      return jsonEncode({
        'format':'nasqo-unified-sqlite-export-v2','version':2,
        'erpData':modules,'workspace':{'companyName':ws['company_name']},'accountGroups':await rows('account_groups'),
        'accounts':await rows('accounts'),'warehouses':await rows('warehouses'),
        'ledger':ledger,'inventory':await rows('inventory_items'),
        if(tables.contains('stock_transfers')) 'stockTransfers':await rows('stock_transfers'),
        if(tables.contains('stock_transfer_lines')) 'stockTransferLines':await rows('stock_transfer_lines')
      });
    } finally { await db.close(); }
  } finally { await directory.delete(recursive:true); }
}
