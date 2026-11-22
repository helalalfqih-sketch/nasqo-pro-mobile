import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../models/erp_models.dart';
import '../services/posting_receipt.dart';
import '../state/erp_controller.dart';
import 'hybrid_protocol.dart';
import 'react_reports.dart';

typedef Json = Map<String, Object?>;

/// Adapts the packaged React protocol to the same native operations as the
/// Flutter forms. Every successful financial reply follows the SQLite commit.
class ReactWorkspace {
  ReactWorkspace(
    this.controller, {
    required this.allowWrites,
    this.onLegacyRecovery,
  });
  final void Function()? onLegacyRecovery;
  final ErpController controller;
  final bool allowWrites;
  static const workspaceId = 'local-erp-workspace';
  Future<void> _pending = Future.value();

  Future<String> handle(String raw) {
    final result = _pending.then((_) => _handle(raw));
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<String> _handle(String raw) async {
    var id = 'unknown';
    String? action;
    try {
      final body = jsonDecode(raw);
      if (body is Map && body['requestId'] is String) id = body['requestId'];
      final request = HybridRequestEnvelope.parse(body);
      action = request.action;
      if (action == 'getSnapshot' && !controller.dbReady) {
        await controller.initDatabase();
      }
      if (!controller.dbReady) {
        throw const HybridBridgeException(
          'SERVICE_UNAVAILABLE',
          'قاعدة البيانات المحلية غير جاهزة.',
        );
      }
      final owner = request.payload['workspaceId'];
      if (owner != null && owner != workspaceId) {
        throw const HybridBridgeException(
          'UNAUTHORIZED_ACTION',
          'مساحة عمل غير صالحة.',
        );
      }
      final result = await _dispatch(request);
      return HybridResponseEnvelope.success(
        requestId: id,
        action: action,
        data: result,
      ).toJsonString();
    } catch (error) {
      final issue = switch (error) {
        HybridBridgeException e => e,
        SaleValidationException e => HybridBridgeException(
            'VALIDATION_ERROR',
            e.message,
          ),
        FormatException e => HybridBridgeException(
            'VALIDATION_ERROR',
            e.message,
          ),
        _ => const HybridBridgeException(
            'SERVICE_UNAVAILABLE',
            'تعذر إتمام العملية المحلية. راجع السجل قبل إعادة الحفظ.',
          ),
      };
      return HybridResponseEnvelope.failure(
        requestId: id,
        action: action,
        error: issue,
      ).toJsonString();
    }
  }

  Future<Object?> _dispatch(HybridRequestEnvelope request) async {
    final payload = request.payload;
    final data = payload['payload'] is Map
        ? Json.from(payload['payload'] as Map)
        : payload;
    switch (request.action) {
      case 'saveWorkspaceSettings':
        if (!allowWrites ||
            !controller.hasActionPermission(ErpActionPermission.settings)) {
          throw const HybridBridgeException(
              'UNAUTHORIZED_ACTION', 'صلاحية تعديل الإعدادات غير متاحة.');
        }
        final settings = Json.from(payload['updates'] as Map);
        await controller.saveWorkspaceSettings(
            name: _string(settings, 'companyName', controller.companyName),
            currency: _currency(settings['defaultCurrency']),
            provider: _string(
                settings, 'whatsappProvider', controller.messageProvider),
            phone: _string(settings, 'whatsappPhone', controller.messagePhone),
            instant: settings['whatsappInstantEnabled'] as bool? ??
                controller.instantMessages);
        return {'snapshot': await snapshot()};
      case 'getSnapshot':
        return snapshot();
      case 'getInventoryMovementsReport':
      case 'getCashboxesReport':
        final options =
            Map<String, Object?>.from(payload['options'] as Map? ?? {});
        final code = options['currency'];
        final currency = code == null || code == '' || code == 'الكل'
            ? null
            : _currency(code);
        return request.action == 'getCashboxesReport'
            ? reactCashboxReport(controller, options, currency)
            : reactInventoryReport(controller, options, currency);
      case 'getInvoiceDetail':
        final entry = controller.ledger
            .where((e) => e.id == payload['entryId'])
            .firstOrNull;
        if (entry == null) throw const FormatException('المستند غير موجود.');
        return {'entry': _entry(entry), 'lines': _lines(entry.id)};
      case 'getProductPriceStats':
        final prices = controller.saleLines
            .where((e) => e.itemId == payload['itemId'])
            .map((e) => e.unitPrice)
            .toList();
        final sorted = [...prices]..sort();
        return {
          'minPrice': sorted.firstOrNull ?? 0,
          'maxPrice': sorted.lastOrNull ?? 0,
          'lastPrice': prices.lastOrNull ?? 0,
          'txCount': prices.length,
        };
      case 'saveUiPreferences':
        final prefs = await _savePreferences(
          Json.from(payload['preferences'] as Map),
        );
        return {'preferences': prefs};
      case 'changeCurrency':
        final currency = _currency(payload['currency']).label;
        await _savePreferences({'activeCurrency': currency});
        return {'currency': currency, 'snapshot': await snapshot()};
      case 'openLegacyRecovery':
        if (onLegacyRecovery == null)
          throw const FormatException('الواجهة الاحتياطية غير متاحة.');
        onLegacyRecovery!();
        return {'handled': true};
      case 'openInvoice':
      case 'openVoucher':
      case 'openAccountStatement':
      case 'goBack':
      case 'navigate':
      case 'showMessage':
        return {'handled': true};
    }
    if (!kHybridFinancialMutationCommands.contains(request.action)) {
      throw HybridBridgeException(
        'SERVICE_UNAVAILABLE',
        'الخدمة المحلية غير متاحة: ${request.action}',
      );
    }
    if (!allowWrites) {
      throw const HybridBridgeException(
        'UNAUTHORIZED_ACTION',
        'الكتابة المالية معطلة في هذا الإصدار.',
      );
    }
    final key = request.idempotencyKey!;
    if (key.length > 256) throw const FormatException('مفتاح الحفظ طويل جدًا.');
    final fingerprint = computeCanonicalRequestHash(request.action, payload);
    final receipt = BridgeReceipt(
      sha256.convert(utf8.encode(key)).toString(),
      fingerprint,
    );
    String recordType;
    switch (request.action) {
      case 'saveAccount':
        recordType = 'account';
        _permit(
          ErpPermissionModule.accounts,
          payload['accountId'] == null ? ErpCrudAction.add : ErpCrudAction.edit,
        );
      case 'saveWarehouse':
        recordType = 'warehouse';
        _permit(
          ErpPermissionModule.warehouses,
          payload['warehouseId'] == null
              ? ErpCrudAction.add
              : ErpCrudAction.edit,
        );
      case 'updateInventoryItem':
        recordType = 'item';
        _permit(ErpPermissionModule.items, ErpCrudAction.edit);
      case 'createInventoryItem':
        recordType = 'item';
        _permit(ErpPermissionModule.items, ErpCrudAction.add);
      case 'createLedgerEntry':
        recordType = 'entry';
        final permission = switch (data['kind']) {
          'invoice' => ErpActionPermission.newInvoice,
          'transfer' => ErpActionPermission.newTransfer,
          'simple-entry' => ErpActionPermission.dailyJournalEntry,
          'currency' => ErpActionPermission.currencyExchangeVoucher,
          'voucher' => ErpActionPermission.newVoucher,
          _ => throw const FormatException('نوع المستند غير مدعوم هنا.'),
        };
        if (!controller.hasActionPermission(permission)) {
          throw const HybridBridgeException(
            'UNAUTHORIZED_ACTION',
            'صلاحية الترحيل غير متاحة.',
          );
        }
      default:
        throw HybridBridgeException(
          'SERVICE_UNAVAILABLE',
          'هذه العملية غير مدعومة في قاعدة البيانات المحلية: ${request.action}',
        );
    }
    String? entityId = await controller.database.bridgeResult(receipt);
    final replayed = entityId != null;
    if (!replayed) {
      switch (request.action) {
        case 'saveAccount':
          await controller.saveAccountRows(
            [
              (
                name: _string(data, 'name'),
                phone: _string(data, 'phone'),
                opening: _num(data, 'openingBalance'),
              ),
            ],
            category: AccountCategory.values.byName(
              _string(data, 'category', 'purchases'),
            ),
            currency: _currency(data['currency']),
            direction: _direction(data['openingDirection'] ?? 'credit'),
            note: _string(data, 'note'),
            creditLimit: _num(data, 'creditLimit'),
            cash: data['isCashAccount'] == true,
            editId: payload['accountId'] as String?,
            bridgeReceipt: receipt,
          );
        case 'saveWarehouse':
          await controller.saveWarehouse(
            id: payload['warehouseId'] as String?,
            name: _string(data, 'name'),
            details: _string(data, 'details'),
            isDefault: data['isDefault'] == true,
            bridgeReceipt: receipt,
          );
        case 'updateInventoryItem':
          final changes = Json.from(payload['updates'] as Map);
          final item = controller.inventory
              .where((i) => i.id == payload['itemId'])
              .firstOrNull;
          if (item == null) throw const FormatException('الصنف غير موجود.');
          if (changes['warehouseId'] != null &&
              changes['warehouseId'] != item.warehouseId) {
            throw const FormatException(
              'استخدم تحويل المخزون لتغيير المستودع.',
            );
          }
          await controller.updateCatalogItem(
            item.id,
            name: _string(changes, 'name', item.name),
            sku: _string(changes, 'sku', item.sku),
            unit: _string(changes, 'unit', item.unit),
            quantity: _num(changes, 'quantity', item.quantity),
            avgCost: _num(changes, 'avgCost', item.avgCost),
            threshold: _num(changes, 'minThreshold', item.minThreshold),
            bridgeReceipt: receipt,
          );
        case 'createInventoryItem':
          await controller.receiveStock(
            quantity: _num(data, 'quantity'),
            name: _string(data, 'name'),
            sku: _string(data, 'sku'),
            unit: _string(data, 'unit', 'حبة'),
            warehouseId: _warehouse(data).id,
            avgCost: _num(data, 'avgCost'),
            threshold: _num(data, 'minThreshold', 0),
            bridgeReceipt: receipt,
          );
        case 'createLedgerEntry':
          await _post(data, receipt);
      }
      entityId = await controller.database.bridgeResult(receipt);
    }
    final snap = await snapshot();
    final keyInSnapshot = {
      'entry': 'ledger',
      'item': 'inventory',
      'warehouse': 'warehouses',
      'account': 'accounts',
    }[recordType]!;
    final record = (snap[keyInSnapshot] as List)
        .whereType<Map>()
        .where((r) => r['id'] == entityId)
        .firstOrNull;
    if (record == null) {
      throw const FormatException('تعذر العثور على نتيجة الحفظ الأصلية.');
    }
    return {
      recordType: record,
      'snapshot': snap,
      'postingReceipt': {'replayed': replayed, 'idempotencyKey': key},
    };
  }

  Future<Json> _savePreferences(Json prefs) async {
    final db = await controller.database.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'erp_state',
        where: 'stateKey = ?',
        whereArgs: ['react_ui_preferences'],
      );
      final saved = rows.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(rows.single['payloadJson'] as String)
              as Map<String, dynamic>;
      saved.addAll(prefs);
      await txn.insert(
          'erp_state',
          {
            'stateKey': 'react_ui_preferences',
            'payloadJson': jsonEncode(saved),
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      return saved;
    });
  }

  void _permit(ErpPermissionModule module, ErpCrudAction action) {
    if (!controller.hasModulePermission(module, action)) {
      throw const HybridBridgeException(
        'UNAUTHORIZED_ACTION',
        'لا تتوفر صلاحية هذه العملية.',
      );
    }
  }

  static String _string(Json d, String k, [String fallback = '']) =>
      (d[k] as String?)?.trim() ?? fallback;
  static double _num(Json d, String k, [double fallback = 0]) {
    final n = d[k];
    if (n == null) return fallback;
    final parsed = n is num ? n.toDouble() : double.tryParse(n.toString());
    if (parsed == null || !parsed.isFinite) {
      throw const FormatException('قيمة عددية غير صالحة.');
    }
    return parsed;
  }

  CurrencyCode _currency(Object? raw) => raw == null
      ? controller.defaultCurrency
      : CurrencyCode.values.firstWhere(
          (e) => e.name == raw || e.label == raw,
          orElse: () => throw const FormatException('عملة غير مدعومة.'),
        );
  EntryDirection _direction(Object? raw) => EntryDirection.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => throw const FormatException('اتجاه القيد غير صالح.'),
      );
  WarehouseRecord _warehouse(Json d) {
    final id = _string(d, 'warehouseId');
    final w = controller.warehouses
        .where((e) => id.isEmpty ? e.isDefault : e.id == id)
        .firstOrNull;
    if (w == null) throw const FormatException('اختر مستودعًا صالحًا.');
    return w;
  }

  Future<void> _post(Json d, BridgeReceipt receipt) async {
    final account =
        controller.accounts.where((e) => e.id == d['accountId']).firstOrNull;
    if (account == null) throw const FormatException('اختر حسابًا صالحًا.');
    final direction = _direction(d['direction']);
    final payment = PaymentMethod.values.byName(_string(d, 'payment'));
    final currency = _currency(d['currency']);
    final reference = _string(d, 'documentNumber');
    final boxes = controller.accounts.where((a) => a.isCashAccount).toList()
      ..sort((a, b) => a.codeNumber.compareTo(b.codeNumber));
    String? cashbox;
    if (d['cashboxId'] != null && d['cashboxId'] != 0 && d['cashboxId'] != '') {
      final box = boxes
          .where(
            (b) =>
                b.codeNumber.toString() == d['cashboxId'].toString() ||
                b.id == d['cashboxId'],
          )
          .firstOrNull;
      if (box == null) throw const FormatException('الصندوق النقدي غير موجود.');
      cashbox = box.id;
    }
    if (d['kind'] == 'invoice') {
      final warehouse = _warehouse(d);
      final rawLines = (d['lines'] as List?) ?? [];
      final rows = <InvoiceItemRow>[];
      for (final raw in rawLines) {
        final line = Json.from(raw as Map);
        final item = controller.inventory
            .where(
              (e) =>
                  e.id == line['inventoryItemId'] &&
                  e.warehouseId == warehouse.id,
            )
            .firstOrNull;
        if (item == null) {
          throw const FormatException('اختر صنفًا من المستودع المحدد.');
        }
        final units = _num(line, 'unitNum', 1);
        if (units != 1 || _num(line, 'bonus') != 0) {
          throw const FormatException(
            'اختر الوحدة الأساسية دون كمية مجانية لهذا الصنف.',
          );
        }
        rows.add(
          InvoiceItemRow(
            id: '${rows.length}',
            itemId: item.id,
            productName: item.name,
            quantity: _num(line, 'quantity'),
            unitPrice: _num(line, 'price'),
            discount: _num(line, 'discount'),
            roundLineTotal: true,
          ),
        );
      }
      final amount = _num(d, 'amount');
      if (rows.isNotEmpty &&
          (rows.fold<double>(0, (n, r) => n + r.lineTotal) - amount).abs() >
              0.01) {
        throw const FormatException('مجموع البنود لا يطابق مبلغ الفاتورة.');
      }
      final free = rows.isEmpty ? amount : null;
      final date = d['entryDate'] == null
          ? null
          : DateTime.parse(d['entryDate'] as String);
      if (direction == EntryDirection.credit) {
        if (currency != account.currency) {
          throw const FormatException('عملة الشراء لا تطابق عملة المورد.');
        }
        await controller.postPurchaseInvoice(
          accountId: account.id,
          warehouseId: warehouse.id,
          payment: payment,
          rows: rows,
          reference: reference,
          exchangeRate: _num(d, 'exchangeRate', 1),
          invoiceDate: date,
          freeAmount: free,
          cashboxAccountId: cashbox,
          requestId: receipt.key,
          bridgeReceipt: receipt,
        );
      } else {
        if (currency != controller.defaultCurrency) {
          throw const FormatException('عملة البيع لا تطابق العملة الافتراضية.');
        }
        await controller.submitSalesInvoice(
          accountId: account.id,
          customerName: account.name,
          warehouse: warehouse,
          payment: payment,
          includeVat: false,
          rows: rows,
          freeAmount: free,
          invoiceDate: date,
          requestId: receipt.key,
          documentNumber: reference,
          memo: _string(d, 'details'),
          cashboxAccountId: cashbox,
          bridgeReceipt: receipt,
        );
      }
    } else {
      final kind = switch (d['kind']) {
        'voucher' => LedgerKind.voucher,
        'simple-entry' => LedgerKind.simpleEntry,
        'transfer' => LedgerKind.transfer,
        'currency' => LedgerKind.currency,
        _ => throw const FormatException(
            'استخدم النموذج الأصلي لنوع المستند المحدد.',
          ),
      };
      await controller.postLocalEntry(
        accountId: account.id,
        kind: kind,
        counterpartId: d['counterpartAccountId'] as String?,
        cashboxAccountId: cashbox,
        requestId: receipt.key,
        documentNumber: reference,
        direction: direction,
        payment: payment,
        amount: _num(d, 'amount'),
        currency: currency,
        exchangeRate: _num(d, 'exchangeRate', 1),
        fromCurrency:
            d['fromCurrency'] == null ? null : _currency(d['fromCurrency']),
        note: _string(d, 'details'),
        expenseCategory: _string(d, 'expenseCategory'),
        bridgeReceipt: receipt,
      );
    }
  }

  List<Json> _lines(String id) => [
        for (final l in controller.saleLines.where((l) => l.entryId == id))
          {
            'lineKind': l.itemId.isEmpty ? 'free' : 'item',
            'inventoryItemId': l.itemId,
            'itemName': l.itemName,
            'unit': l.unit,
            'unitNum': 1,
            'quantity': l.quantity,
            'price': l.unitPrice,
            'total': l.quantity * l.unitPrice,
          },
      ];
  Json _entry(LedgerEntryRecord l) =>
      _ledgerToHybridJson(l, lines: _lines(l.id));

  Future<Json> snapshot() async {
    final db = await controller.database.database;
    final rows = await db.query(
      'erp_state',
      columns: ['payloadJson'],
      where: 'stateKey = ?',
      whereArgs: ['react_ui_preferences'],
    );
    final prefs = rows.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(rows.single['payloadJson'] as String)
            as Map<String, dynamic>;
    final boxes = controller.accounts.where((a) => a.isCashAccount).toList()
      ..sort((a, b) => a.codeNumber.compareTo(b.codeNumber));
    final archive = controller.restoredGroups;
    final hasDirectory = archive != null && archive.groups.isNotEmpty;
    final categories = controller.accounts.map((a) => a.category).toSet();
    return {
      'workspaceId': workspaceId,
      'userEmail': 'offline@nasqo.local',
      'workspace': {
        'id': workspaceId,
        'ownerId': workspaceId,
        'companyName': controller.companyName,
        'defaultCurrency': controller.defaultCurrency.label,
        'whatsappProvider': controller.messageProvider,
        'whatsappPhone': controller.messagePhone,
        'whatsappInstantEnabled': controller.instantMessages,
      },
      'currencies': [
        for (final c in CurrencyCode.values)
          {
            'id': c.index + 1,
            'code': c.label,
            'name': c.label,
            'symbol': c.label,
            'ratePrimary': 1.0,
            'rateSecondary': 1.0,
            ...controller.currencyDetails(c),
          },
      ],
      'accountGroups': [
        if (hasDirectory)
          for (final group in archive.groups)
            {
              'id': group.id,
              'name': group.name,
              'legacyId': group.number,
              'category': archive.groupCategories[group.id] ?? 'shop',
              'currencyCode': _groupCurrency(archive.groupCurrencies[group.id]),
              'sortOrder': group.order,
              'hasBill': true,
              'isEmployee': archive.groupCategories[group.id] == 'employees',
            }
        else
          for (final category in AccountCategory.values.where(
            categories.contains,
          ))
            {
              'id': category.index + 1,
              'name': category.label,
              'category': category.name,
              'currencyCode': controller.defaultCurrency.label,
              'sortOrder': category.index + 1,
              'hasBill': true,
              'isEmployee': category == AccountCategory.employees,
            },
      ],
      'cashboxes': [
        for (final a in boxes)
          {
            'id': a.codeNumber,
            'name': a.name,
            'details': a.note,
            'currencyCode': a.currency.label,
            'state': 1,
            'boxType': 0,
            'sortOrder': a.codeNumber,
            'isActive': true,
          },
      ],
      'accounts': [
        for (final a in controller.accounts)
          _accountToHybridJson(
            a,
            groupId:
                hasDirectory ? archive.membership[a.id] : a.category.index + 1,
          ),
      ],
      'warehouses': [
        for (final (i, w) in controller.warehouses.indexed)
          _warehouseToHybridJson(w, i + 1),
      ],
      'ledger': controller.ledger.map(_entry).toList(),
      'inventory': controller.inventory.map(_inventoryToHybridJson).toList(),
      'uiPreferences': {
        'themeMode': controller.isDarkMode ? 'dark' : 'light',
        ...prefs,
      },
      'activeCurrency':
          prefs['activeCurrency'] ?? controller.defaultCurrency.label,
      'capabilities': {
        'offlineReady': true,
        'printingSupported': false,
        'pdfExportSupported': false,
        'filePickerSupported': false,
        'googleDriveConfigured': false,
        'whatsappShareSupported': false,
        'readOnlyFinancial': !allowWrites,
      },
    };
  }

  String _groupCurrency(String? value) =>
      CurrencyCode.values
          .where(
            (c) =>
                c.name.toUpperCase() == value?.toUpperCase() ||
                c.label == value,
          )
          .firstOrNull
          ?.label ??
      controller.defaultCurrency.label;

  Map<String, Object?> _accountToHybridJson(AccountRecord a, {int? groupId}) =>
      <String, Object?>{
        'id': a.id,
        'ownerId': workspaceId,
        if (groupId != null) 'groupId': groupId,
        'name': a.name,
        'category': a.category.name,
        'phone': a.phone,
        'creditLimit': a.creditLimit,
        'currency': a.currency.label,
        'isCashAccount': a.isCashAccount,
        'accountImage': '1',
        'sortOrder': a.codeNumber,
        'settlement': false,
        'documentNumberRequired': false,
        'messageMethod': 'sms',
        'sendMode': 'never',
        'note': a.note,
        'openingBalance': a.openingBalance,
        'openingDirection': a.openingDirection.name,
        'codeNumber': a.codeNumber,
      };

  Map<String, Object?> _ledgerToHybridJson(
    LedgerEntryRecord l, {
    List<Map<String, Object?>> lines = const [],
  }) =>
      <String, Object?>{
        'id': l.id,
        'ownerId': workspaceId,
        'accountId': l.accountId,
        'accountName': l.accountName,
        'counterpartAccountId': '',
        'counterpartAccountName': '',
        'kind': _ledgerKindToHybrid(l.kind),
        'typeLabel': l.typeLabel,
        'payment': l.payment.name,
        'direction': l.direction.name,
        'amount': l.amount,
        'currency': l.currency.label,
        'exchangeRate': l.exchangeRate,
        'details': l.details,
        'documentNumber': l.documentNumber,
        'warehouseId': l.warehouseId,
        'warehouseName': l.warehouseName,
        'invoiceContent': lines.isNotEmpty ? 'items' : 'none',
        'entryNumber': l.entryNumber,
        'deleted': l.deleted,
        'entryDate': l.entryDate,
        if (l.expenseCategory.isNotEmpty) 'expenseCategory': l.expenseCategory,
        'sourceOrigin': 'native',
        'lineCount': lines.length,
        if (lines.isNotEmpty) 'lines': lines,
        'createdAtMs':
            DateTime.tryParse(l.entryDate)?.millisecondsSinceEpoch ?? 0,
      };

  Map<String, Object?> _warehouseToHybridJson(WarehouseRecord w, int code) =>
      <String, Object?>{
        'id': w.id,
        'ownerId': workspaceId,
        'name': w.name,
        'details': w.details,
        'isDefault': w.isDefault,
        'codeNumber': code,
      };

  Map<String, Object?> _inventoryToHybridJson(InventoryItemRecord i) =>
      <String, Object?>{
        'id': i.id,
        'ownerId': workspaceId,
        'name': i.name,
        'unit': i.unit,
        'quantity': i.quantity,
        'avgCost': i.avgCost,
        'minThreshold': i.minThreshold,
        'sku': i.sku,
        'currencyCode': controller.defaultCurrency.label,
        'isActive': true,
        'warehouseId': i.warehouseId,
        'quantityUnverified': false,
      };

  static String _ledgerKindToHybrid(LedgerKind kind) {
    return switch (kind) {
      LedgerKind.returnEntry => 'return',
      LedgerKind.simpleEntry => 'simple-entry',
      _ => kind.name,
    };
  }
}
