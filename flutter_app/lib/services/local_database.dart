import 'cash_sale_settlement.dart';
import 'dart:convert';
import 'voucher_draft_repository.dart';
import 'cash_transfer_draft_repository.dart';
import 'simple_journal_draft_repository.dart';
import 'fx_draft_repository.dart';
import '../models/sale_tax_register.dart';
import '../models/sale_facts.dart';
import '../models/invoice_print_snapshot.dart';
import '../models/sales_return_draft.dart';
import '../models/nonposting_document.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/erp_models.dart';

/// Raised without raw data when persisted settings are structurally invalid.
class InvalidLocalSettings implements Exception {
  const InvalidLocalSettings();
}

class LocalDbSnapshot {
  const LocalDbSnapshot({
    required this.accounts,
    required this.ledger,
    required this.warehouses,
    required this.inventory,
    this.saleLines = const [],
    this.companyName,
    this.isDarkMode,
    this.nextEntryNumber,
    this.erpData,
  });

  final List<AccountRecord> accounts;
  final List<LedgerEntryRecord> ledger;
  final List<WarehouseRecord> warehouses;
  final List<InventoryItemRecord> inventory;
  final List<SavedSaleLine> saleLines;
  final String? companyName;
  final bool? isDarkMode;
  final int? nextEntryNumber;
  final Map<String, dynamic>? erpData;
}

class LocalDatabase {
  LocalDatabase._()
      : _factory = null,
        _path = null;

  /// Uses the production schema in a separate file, such as an isolated test DB.
  LocalDatabase.withFactory(DatabaseFactory factory, String path)
      : _factory = factory,
        _path = path;

  static final LocalDatabase instance = LocalDatabase._();

  static const String dbName = 'nasqo_pro_erp.db';
  static const int dbVersion = 9;

  Database? _db;
  Future<Database>? _opening;
  final DatabaseFactory? _factory;
  final String? _path;

  Future<Database> get database {
    final opened = _db;
    if (opened != null) return Future.value(opened);
    return _opening ??= _open().whenComplete(() {
      _opening = null;
    });
  }

  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final fullPath = _path ?? p.join(await factory.getDatabasesPath(), dbName);
    _db = await factory.openDatabase(
      fullPath,
      options: OpenDatabaseOptions(
          version: dbVersion,
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) await _createSaleLines(db);
            if (oldVersion < 3) await _createNonpostingDocuments(db);
            if (oldVersion < 4) await _createReturnDrafts(db);
            if (oldVersion < 5) await _createSaleFacts(db);
            if (oldVersion < 6) await VoucherDraftRepository.createSchema(db);
            if (oldVersion < 7) {
              await CashTransferDraftRepository.createSchema(db);
            }
            if (oldVersion < 8) {
              await SimpleJournalDraftRepository.createSchema(db);
            }
            if (oldVersion < 9) {
              await FxDraftRepository.createSchema(db);
            }
          },
          onCreate: (db, version) async {
            await db.execute('''
          CREATE TABLE accounts (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            phone TEXT NOT NULL,
            creditLimit REAL NOT NULL,
            currency TEXT NOT NULL,
            isCashAccount INTEGER NOT NULL,
            note TEXT NOT NULL,
            openingBalance REAL NOT NULL,
            openingDirection TEXT NOT NULL,
            codeNumber INTEGER NOT NULL
          )
        ''');

            await db.execute('''
          CREATE TABLE ledger_entries (
            id TEXT PRIMARY KEY,
            accountId TEXT NOT NULL,
            accountName TEXT NOT NULL,
            kind TEXT NOT NULL,
            typeLabel TEXT NOT NULL,
            payment TEXT NOT NULL,
            direction TEXT NOT NULL,
            amount REAL NOT NULL,
            currency TEXT NOT NULL,
            exchangeRate REAL NOT NULL,
            details TEXT NOT NULL,
            documentNumber TEXT NOT NULL,
            warehouseId TEXT NOT NULL,
            warehouseName TEXT NOT NULL,
            expenseCategory TEXT NOT NULL,
            entryNumber INTEGER NOT NULL,
            deleted INTEGER NOT NULL,
            entryDate TEXT NOT NULL
          )
        ''');

            await db.execute('''
          CREATE TABLE warehouses (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            details TEXT NOT NULL,
            isDefault INTEGER NOT NULL
          )
        ''');

            await db.execute('''
          CREATE TABLE inventory_items (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            unit TEXT NOT NULL,
            quantity REAL NOT NULL,
            avgCost REAL NOT NULL,
            warehouseId TEXT NOT NULL,
            minThreshold REAL NOT NULL,
            sku TEXT NOT NULL
          )
        ''');

            await db.execute('''
          CREATE TABLE erp_state (
            stateKey TEXT PRIMARY KEY,
            payloadJson TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');
            await _createSaleLines(db);
            await _createNonpostingDocuments(db);
            await _createReturnDrafts(db);
            await _createSaleFacts(db);
            await VoucherDraftRepository.createSchema(db);
            await CashTransferDraftRepository.createSchema(db);
            await SimpleJournalDraftRepository.createSchema(db);
            await FxDraftRepository.createSchema(db);
          }),
    );
    return _db!;
  }

  Future<void> _createSaleFacts(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS sale_facts (
      entryId TEXT PRIMARY KEY, currency TEXT NOT NULL, preTaxTotal REAL NOT NULL,
      taxEnabled INTEGER NOT NULL, appliedTaxRate REAL NOT NULL,
      taxAmount REAL NOT NULL, finalTotal REAL NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS sale_line_cost_facts (
      entryId TEXT NOT NULL, position INTEGER NOT NULL, stockAverageCost REAL,
      PRIMARY KEY(entryId, position))''');
  }

  Future<void> _appendSaleFacts(DatabaseExecutor db, SaleFacts facts) async {
    bool close(double a, double b) => (a - b).abs() <= 1e-7;
    final amounts = [
      facts.preTaxTotal,
      facts.appliedTaxRate,
      facts.taxAmount,
      facts.finalTotal
    ];
    if (facts.entryId.isEmpty ||
        amounts.any((v) => !v.isFinite || v < 0) ||
        facts.appliedTaxRate > 1 ||
        (!facts.taxEnabled &&
            (facts.appliedTaxRate != 0 || facts.taxAmount != 0)) ||
        !close(facts.preTaxTotal + facts.taxAmount, facts.finalTotal)) {
      throw ArgumentError('حقائق الفاتورة غير صالحة');
    }
    final rawTax = facts.preTaxTotal * (facts.appliedTaxRate * 100);
    if (!rawTax.isFinite ||
        rawTax > 9007199254740991 ||
        !close(rawTax.roundToDouble() / 100, facts.taxAmount)) {
      throw ArgumentError('ضريبة الفاتورة لا تطابق الأساس والمعدل');
    }
    final headers = await db
        .query('ledger_entries', where: 'id = ?', whereArgs: [facts.entryId]);
    if (headers.length != 1) throw StateError('رأس الفاتورة غير موجود');
    final header = headers.single;
    if (header['kind'] != 'invoice' ||
        header['direction'] != 'debit' ||
        header['deleted'] != 0 ||
        !isEligibleSalesReturnSource(_ledgerFromMap(header)) ||
        header['currency'] != facts.currency.name ||
        !close((header['amount'] as num).toDouble(), facts.finalTotal)) {
      throw StateError('حقائق الفاتورة لا تطابق رأس المبيعات');
    }
    final lines = await db.query('sale_lines',
        where: 'entryId = ?', whereArgs: [facts.entryId], orderBy: 'position');
    final positions = <int>{};
    for (final cost in facts.lineCosts) {
      if (!positions.add(cost.position) ||
          cost.position < 0 ||
          (cost.stockAverageCost != null &&
              (!cost.stockAverageCost!.isFinite ||
                  cost.stockAverageCost! < 0))) {
        throw ArgumentError('تكلفة أو موضع بند غير صالح');
      }
    }
    var subtotal = 0.0;
    for (final line in lines) {
      final qty = (line['quantity'] as num).toDouble();
      final price = (line['unitPrice'] as num).toDouble();
      if (!qty.isFinite ||
          qty <= 0 ||
          !price.isFinite ||
          price < 0 ||
          !positions.contains(line['position'])) {
        throw StateError('بنود الفاتورة لا تطابق حقائقها');
      }
      subtotal += qty * price;
    }
    if (lines.isEmpty ||
        lines.length != positions.length ||
        !subtotal.isFinite ||
        !close(subtotal, facts.preTaxTotal)) {
      throw StateError('أساس الفاتورة أو مواضع البنود غير متطابقة');
    }
    // Default INSERT aborts on duplicate: immutable facts cannot be replaced.
    await db.insert('sale_facts', {
      'entryId': facts.entryId,
      'currency': facts.currency.name,
      'preTaxTotal': facts.preTaxTotal,
      'taxEnabled': facts.taxEnabled ? 1 : 0,
      'appliedTaxRate': facts.appliedTaxRate,
      'taxAmount': facts.taxAmount,
      'finalTotal': facts.finalTotal
    });
    for (final cost in facts.lineCosts) {
      await db.insert('sale_line_cost_facts', {
        'entryId': facts.entryId,
        'position': cost.position,
        'stockAverageCost': cost.stockAverageCost
      });
    }
  }

  /// Transactionally reads a consistent local snapshot; makes no data writes.
  /// Missing or mismatched facts are unknown, not inferred zero-tax sales.
  Future<SaleTaxRegister> loadSaleTaxRegister(
      {String? from, String? through}) async {
    bool iso(String text) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return false;
      final d = DateTime.tryParse(text);
      return d != null && d.toIso8601String().substring(0, 10) == text;
    }

    if ((from != null && !iso(from)) ||
        (through != null && !iso(through)) ||
        (from != null && through != null && from.compareTo(through) > 0)) {
      throw ArgumentError('الفترة غير صالحة؛ استخدم YYYY-MM-DD ومن <= إلى');
    }
    bool close(double a, double b) =>
        a.isFinite && b.isFinite && (a - b).abs() <= 1e-7;
    double? number(Object? value) {
      if (value is! num || !value.isFinite || value < 0) return null;
      return value.toDouble();
    }

    final db = await database;
    return db.transaction((txn) async {
      final headers = await txn.query('ledger_entries',
          where:
              "deleted = 0 AND ((kind = ? AND direction = ? AND typeLabel IN (?, ?)) OR (kind = 'returnEntry' AND direction = 'credit' AND EXISTS (SELECT 1 FROM erp_state WHERE stateKey = 'return_detail/' || ledger_entries.id)))",
          whereArgs: ['invoice', 'debit', 'ف.مبيعات نقدية', 'ف.مبيعات آجل'],
          orderBy: 'entryDate DESC, entryNumber DESC, id');
      final result = <SaleTaxRegisterRow>[];
      final known = <CurrencyCode, int>{}, unknown = <CurrencyCode, int>{};
      final net = <CurrencyCode, double>{},
          tax = <CurrencyCode, double>{},
          total = <CurrencyCode, double>{};
      var invalidHeaders = 0;
      for (final h in headers) {
        final date = h['entryDate'];
        final currency = CurrencyCode.values
            .where((c) => c.name == h['currency'])
            .firstOrNull;
        if (date is! String || !iso(date) || currency == null) {
          invalidHeaders++;
          continue;
        }
        if ((from != null && date.compareTo(from) < 0) ||
            (through != null && date.compareTo(through) > 0)) {
          continue;
        }
        known.putIfAbsent(currency, () => 0);
        unknown.putIfAbsent(currency, () => 0);
        net.putIfAbsent(currency, () => 0);
        tax.putIfAbsent(currency, () => 0);
        total.putIfAbsent(currency, () => 0);
        void unavailable() {
          unknown[currency] = unknown[currency]! + 1;
        }

        if (h['kind'] == 'returnEntry') {
          final detail = (await txn.query('erp_state', where: 'stateKey = ?',
              whereArgs: ['return_detail/${h['id']}'])).single;
          final data = jsonDecode(detail['payloadJson'] as String) as Map<String,dynamic>;
          final n = number(data['net']), t = number(data['tax']), v = number(data['total']);
          final original = await _readSaleFacts(txn, data['sourceEntryId'] as String);
          if (n == null || t == null || v == null || original == null ||
              !close(n+t,v) || h['amount'] != v) {
            unavailable();
            continue;
          }
          known[currency] = known[currency]! + 1;
          net[currency] = net[currency]! - n;
          tax[currency] = tax[currency]! - t;
          total[currency] = total[currency]! - v;
          result.add(SaleTaxRegisterRow(entryId:h['id'] as String,
              entryNumber:h['entryNumber'] as int, documentNumber:h['documentNumber'] as String,
              date:date,accountName:h['accountName'] as String,currency:currency,
              preTaxTotal:-n,taxAmount:-t,finalTotal:-v,taxEnabled:original.taxEnabled,
              appliedTaxRate:original.appliedTaxRate));
          continue;
        }
        final fRows = await txn
            .query('sale_facts', where: 'entryId = ?', whereArgs: [h['id']]);
        if (fRows.length != 1) {
          unavailable();
          continue;
        }
        final f = fRows.single;
        final n = number(f['preTaxTotal']),
            t = number(f['taxAmount']),
            v = number(f['finalTotal']),
            rate = number(f['appliedTaxRate']);
        final headerAmount = number(h['amount']);
        if (n == null ||
            t == null ||
            v == null ||
            rate == null ||
            rate > 1 ||
            headerAmount == null ||
            f['currency'] != currency.name ||
            ![0, 1].contains(f['taxEnabled']) ||
            (f['taxEnabled'] == 0 && (t != 0 || rate != 0)) ||
            (n == 0 && t != 0) ||
            !close(n + t, v) ||
            !close(headerAmount, v)) {
          unavailable();
          continue;
        }
        // The committed tax amount is the source of truth. Do not recalculate
        // via rate (e.g. a documented .06 boundary must remain .06).
        final lines = await txn.query('sale_lines',
            where: 'entryId = ?', whereArgs: [h['id']], orderBy: 'position');
        final costs = await txn.query('sale_line_cost_facts',
            where: 'entryId = ?', whereArgs: [h['id']]);
        final costPositions = costs.map((c) => c['position']).toSet();
        var lineNet = 0.0;
        var validLines = lines.isNotEmpty &&
            lines.length == costs.length &&
            costPositions.length == costs.length;
        for (final l in lines) {
          final q = number(l['quantity']), p = number(l['unitPrice']);
          if (q == null ||
              q == 0 ||
              p == null ||
              !costPositions.contains(l['position']) ||
              l['position'] is! int ||
              (l['position'] as int) < 0) {
            validLines = false;
            break;
          }
          lineNet += q * p;
        }
        if (!validLines ||
            !close(lineNet, n) ||
            ![net[currency]! + n, tax[currency]! + t, total[currency]! + v]
                .every((a) => a.isFinite)) {
          unavailable();
          continue;
        }
        known[currency] = known[currency]! + 1;
        net[currency] = net[currency]! + n;
        tax[currency] = tax[currency]! + t;
        total[currency] = total[currency]! + v;
        result.add(SaleTaxRegisterRow(
            entryId: h['id'] as String,
            entryNumber: h['entryNumber'] as int,
            documentNumber: h['documentNumber'] as String,
            date: date,
            accountName: h['accountName'] as String,
            currency: currency,
            preTaxTotal: n,
            taxAmount: t,
            finalTotal: v,
            taxEnabled: f['taxEnabled'] == 1,
            appliedTaxRate: rate));
      }
      return SaleTaxRegister(
          from: from,
          through: through,
          rows: result,
          invalidHeaderCount: invalidHeaders,
          currencies: [
            for (final c in CurrencyCode.values)
              if (known.containsKey(c))
                SaleTaxCurrencySummary(
                    currency: c,
                    knownCount: known[c]!,
                    unknownCount: unknown[c]!,
                    preTaxTotal: net[c]!,
                    taxAmount: tax[c]!,
                    finalTotal: total[c]!)
          ]);
    });
  }

  Future<SaleFacts?> getSaleFacts(String entryId) async {
    final db = await database;
    return db.transaction((txn) => _readSaleFacts(txn, entryId));
  }

  Future<InvoicePrintSnapshot> loadInvoiceForPrint(String entryId) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn
          .query('ledger_entries', where: 'id = ?', whereArgs: [entryId]);
      if (rows.isEmpty) throw StateError('Saved invoice unavailable.');
      final lines = await txn.query('sale_lines',
          where: 'entryId = ?',
          whereArgs: [entryId],
          orderBy: 'position',
          limit: 217);
      if (lines.length > 216) throw StateError('Invoice page limit.');
      return InvoicePrintSnapshot(_ledgerFromMap(rows.single),
          lines.map(_savedSaleLineFromMap), await _readSaleFacts(txn, entryId));
    }, exclusive: false);
  }

  SavedSaleLine _savedSaleLineFromMap(Map<String, Object?> row) =>
      SavedSaleLine(
          entryId: row['entryId'] as String,
          position: row['position'] as int,
          itemId: row['itemId'] as String,
          itemName: row['itemName'] as String,
          unit: row['unit'] as String,
          quantity: (row['quantity'] as num).toDouble(),
          unitPrice: (row['unitPrice'] as num).toDouble());

  Future<SaleFacts?> _readSaleFacts(
      DatabaseExecutor txn, String entryId) async {
    final rows = await txn
        .query('sale_facts', where: 'entryId = ?', whereArgs: [entryId]);
    if (rows.isEmpty) return null;
    final row = rows.single;
    final costs = await txn.query('sale_line_cost_facts',
        where: 'entryId = ?', whereArgs: [entryId], orderBy: 'position');
    return SaleFacts(
        entryId: entryId,
        currency: CurrencyCode.values.byName(row['currency'] as String),
        preTaxTotal: (row['preTaxTotal'] as num).toDouble(),
        taxEnabled: row['taxEnabled'] == 1,
        appliedTaxRate: (row['appliedTaxRate'] as num).toDouble(),
        taxAmount: (row['taxAmount'] as num).toDouble(),
        finalTotal: (row['finalTotal'] as num).toDouble(),
        lineCosts: costs
            .map((c) => SaleLineCostFact(
                position: c['position'] as int,
                stockAverageCost: (c['stockAverageCost'] as num?)?.toDouble()))
            .toList());
  }

  Future<void> _createReturnDrafts(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS sales_return_drafts (
      id INTEGER PRIMARY KEY AUTOINCREMENT, revision INTEGER NOT NULL,
      sourceEntryId TEXT NOT NULL, date TEXT NOT NULL, reason TEXT NOT NULL,
      accountId TEXT NOT NULL, accountName TEXT NOT NULL,
      warehouseId TEXT NOT NULL, currency TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS sales_return_draft_lines (
      draftId INTEGER NOT NULL, position INTEGER NOT NULL,
      itemId TEXT NOT NULL, itemName TEXT NOT NULL, unit TEXT NOT NULL,
      quantity REAL NOT NULL CHECK(quantity > 0), sourceQuantity REAL NOT NULL,
      unitPrice REAL NOT NULL CHECK(unitPrice >= 0),
      PRIMARY KEY(draftId, position))''');
  }

  Future<SalesReturnDraft> saveSalesReturnDraft(
      {int? id,
      int revision = 0,
      required String sourceEntryId,
      required String date,
      required String reason,
      required List<SalesReturnSelection> selections}) async {
    final parsed = DateTime.tryParse(date);
    final picks = List<SalesReturnSelection>.of(selections);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date ||
        reason.trim().isEmpty ||
        picks.isEmpty ||
        (id == null ? revision != 0 : id <= 0 || revision < 1)) {
      throw ArgumentError('بيانات مسودة المرتجع غير صالحة');
    }
    final positions = <int>{};
    for (final pick in picks) {
      if (!positions.add(pick.position) ||
          !pick.quantity.isFinite ||
          pick.quantity <= 0) {
        throw ArgumentError('بند مكرر أو كمية غير صالحة');
      }
    }
    final db = await database;
    return db.transaction((txn) async {
      final sources = await txn
          .query('ledger_entries', where: 'id = ?', whereArgs: [sourceEntryId]);
      if (sources.length != 1) throw StateError('فاتورة الأصل غير موجودة');
      final source = sources.single;
      // Strict allowlist for sales actually emitted by the local invoice flow.
      if (source['kind'] != 'invoice' ||
          source['direction'] != 'debit' ||
          !isEligibleSalesReturnSource(_ledgerFromMap(source))) {
        throw StateError('الأصل ليس فاتورة مبيعات حديثة فعالة');
      }
      final currency = CurrencyCode.values.byName(source['currency'] as String);
      final sourceLines = await txn.query('sale_lines',
          where: 'entryId = ?', whereArgs: [sourceEntryId]);
      final byPosition = {
        for (final row in sourceLines) row['position'] as int: row
      };
      final lines = <SalesReturnDraftLine>[];
      for (final pick in picks) {
        final line = byPosition[pick.position];
        if (line == null) throw StateError('البند لا ينتمي إلى فاتورة الأصل');
        final qty = (line['quantity'] as num).toDouble();
        final price = (line['unitPrice'] as num).toDouble();
        if (!qty.isFinite ||
            qty <= 0 ||
            pick.quantity > qty ||
            !price.isFinite ||
            price < 0 ||
            !(pick.quantity * price).isFinite) {
          throw ArgumentError('الكمية تتجاوز الأصل أو بيانات الأصل غير صالحة');
        }
        lines.add(SalesReturnDraftLine(
            position: pick.position,
            itemId: line['itemId'] as String,
            itemName: line['itemName'] as String,
            unit: line['unit'] as String,
            quantity: pick.quantity,
            sourceQuantity: qty,
            unitPrice: price));
      }
      if (!lines.fold<double>(0, (sum, line) => sum + line.total).isFinite) {
        throw ArgumentError('إجمالي غير صالح');
      }
      final values = <String, Object?>{
        'revision': revision + 1,
        'sourceEntryId': sourceEntryId,
        'date': date,
        'reason': reason.trim(),
        'accountId': source['accountId'],
        'accountName': source['accountName'],
        'warehouseId': source['warehouseId'],
        'currency': currency.name
      };
      final int savedId;
      if (id == null) {
        savedId = await txn.insert('sales_return_drafts', values);
      } else {
        savedId = id;
        final count = await txn.update('sales_return_drafts', values,
            where: 'id = ? AND revision = ? AND sourceEntryId = ?',
            whereArgs: [id, revision, sourceEntryId]);
        if (count != 1) throw StateError('المسودة تغيرت أو لا تنتمي إلى الأصل');
        await txn.delete('sales_return_draft_lines',
            where: 'draftId = ?', whereArgs: [id]);
      }
      for (final line in lines) {
        await txn.insert('sales_return_draft_lines', {
          'draftId': savedId,
          'position': line.position,
          'itemId': line.itemId,
          'itemName': line.itemName,
          'unit': line.unit,
          'quantity': line.quantity,
          'sourceQuantity': line.sourceQuantity,
          'unitPrice': line.unitPrice
        });
      }
      return SalesReturnDraft(
          id: savedId,
          revision: revision + 1,
          sourceEntryId: sourceEntryId,
          date: date,
          reason: reason.trim(),
          accountId: source['accountId'] as String,
          accountName: source['accountName'] as String,
          warehouseId: source['warehouseId'] as String,
          currency: currency,
          lines: lines);
    });
  }

  Future<int> postReturnDraft(int id, int revision) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query('sales_return_drafts',
          where: 'id = ? AND revision = ?', whereArgs: [id, revision]);
      if (rows.length != 1) throw StateError('تغيرت المسودة أو سبق ترحيلها.');
      final draft = await _readReturnDraft(txn, rows.single);
      final headers = await txn.query('ledger_entries',
          where: 'id = ?', whereArgs: [draft.sourceEntryId]);
      if (headers.isEmpty) throw StateError('الفاتورة الأصلية غير موجودة.');
      final source = _ledgerFromMap(headers.single);
      final facts = await _readSaleFacts(txn, source.id);
      if (!isEligibleSalesReturnSource(source) || facts == null ||
          source.accountId != draft.accountId || source.currency != draft.currency ||
          source.warehouseId != draft.warehouseId || facts.preTaxTotal <= 0 ||
          (facts.finalTotal - source.amount).abs() > 0.005 || draft.lines.isEmpty) {
        throw StateError('تعذر التحقق من بيانات الفاتورة وضريبتها الأصلية.');
      }
      final sourceLines = await txn.query('sale_lines',
          where: 'entryId = ?', whereArgs: [source.id]);
      final byPosition = {for (final line in sourceLines) line['position']: line};
      final stateKey = 'sale_returns/${source.id}';
      final states = await txn.query('erp_state', where: 'stateKey = ?', whereArgs: [stateKey]);
      final prior = states.isEmpty ? <String,dynamic>{} :
          jsonDecode(states.single['payloadJson'] as String) as Map<String,dynamic>;
      final quantities = Map<String,dynamic>.from(prior['quantities'] ?? {});
      final previousNet = (prior['net'] as num?)?.toDouble() ?? 0;
      final previousTax = (prior['tax'] as num?)?.toDouble() ?? 0;
      var net = previousNet;
      for (final line in draft.lines) {
        final original = byPosition[line.position];
        final key = line.position.toString();
        final total = ((quantities[key] as num?) ?? 0) + line.quantity;
        if (original == null || original['itemId'] != line.itemId ||
            original['unitPrice'] != line.unitPrice || line.quantity <= 0 ||
            total > (original['quantity'] as num) + 1e-9) {
          throw StateError('تجاوزت كمية المرتجع المتبقي في الفاتورة.');
        }
        quantities[key] = total;
        net += line.quantity * line.unitPrice;
        final changed = await txn.rawUpdate(
            'UPDATE inventory_items SET quantity = quantity + ? WHERE id = ? AND warehouseId = ?',
            [line.quantity, line.itemId, source.warehouseId]);
        if (changed != 1) throw StateError('الصنف غير موجود في المستودع الأصلي.');
      }
      double money(double number) => (number * 100).round() / 100;
      if (!net.isFinite || net > facts.preTaxTotal + 1e-7) throw StateError('تجاوز المرتجع أصل الفاتورة.');
      final tax = money(facts.taxAmount * net / facts.preTaxTotal);
      final returnedNet = net - previousNet;
      final returnedTax = money(tax - previousTax);
      final amount = returnedNet + returnedTax;
      final settings = (await txn.query('erp_state', where: 'stateKey = ?', whereArgs: ['settings'])).single;
      final config = jsonDecode(settings['payloadJson'] as String) as Map<String,dynamic>;
      final highest = Sqflite.firstIntValue(await txn.rawQuery('SELECT MAX(entryNumber) FROM ledger_entries')) ?? 0;
      final last = config['nextEntryNumber'] as int;
      final number = (last > highest ? last : highest) + 1;
      final entry = LedgerEntryRecord(id: 'local-return-$number', accountId: source.accountId,
          accountName: source.accountName, kind: LedgerKind.returnEntry, typeLabel: 'مرتجع مبيعات',
          payment: source.payment, direction: EntryDirection.credit, amount: amount,
          currency: source.currency, exchangeRate: source.exchangeRate,
          details: draft.reason, documentNumber: source.documentNumber,
          warehouseId: source.warehouseId, warehouseName: source.warehouseName,
          entryNumber: number, entryDate: draft.date);
      await txn.insert('ledger_entries', _ledgerToMap(entry));
      if (source.payment == PaymentMethod.cash) {
        final receipts = await txn.query('ledger_entries', where: 'id = ?',
            whereArgs: ['${source.id}/cashbox']);
        if (receipts.isNotEmpty) {
          final receipt = _ledgerFromMap(receipts.single);
          if (!isCashSaleSettlement(receipt) || receipt.deleted ||
              receipt.payment != PaymentMethod.cash || receipt.currency != source.currency ||
              receipt.amount != source.amount || receipt.entryNumber != source.entryNumber ||
              receipt.direction != EntryDirection.debit) {
            throw StateError('تعذرت مطابقة حركة الصندوق بالفاتورة الأصلية.');
          }
          for (final movement in cashSaleSettlement(entry,
              cashboxId: receipt.accountId, cashboxName: receipt.accountName)) {
            await txn.insert('ledger_entries', _ledgerToMap(movement));
          }
        }
      }
      for (final line in draft.lines) {
        await txn.insert('sale_lines', {'entryId':entry.id,'position':line.position,
          'itemId':line.itemId,'itemName':line.itemName,'unit':line.unit,
          'quantity':line.quantity,'unitPrice':line.unitPrice});
      }
      final now = DateTime.now().toIso8601String();
      await txn.insert('erp_state', {'stateKey':stateKey,
        'payloadJson':jsonEncode({'quantities':quantities,'net':net,'tax':tax}),
        'updatedAt':now}, conflictAlgorithm:ConflictAlgorithm.replace);
      await txn.insert('erp_state', {'stateKey':'return_detail/${entry.id}',
        'payloadJson':jsonEncode({'sourceEntryId':source.id,'net':returnedNet,
          'tax':returnedTax,'total':amount}), 'updatedAt':now});
      config['nextEntryNumber'] = number;
      await txn.update('erp_state', {'payloadJson':jsonEncode(config),'updatedAt':now},
          where:'stateKey = ?', whereArgs:['settings']);
      await txn.delete('sales_return_draft_lines',where:'draftId = ?',whereArgs:[id]);
      await txn.delete('sales_return_drafts',where:'id = ?',whereArgs:[id]);
      return number;
    });
  }

  Future<SalesReturnDraft> _readReturnDraft(
      DatabaseExecutor db, Map<String, Object?> row) async {
    final lines = await db.query('sales_return_draft_lines',
        where: 'draftId = ?', whereArgs: [row['id']], orderBy: 'position');
    return SalesReturnDraft(
        id: row['id'] as int,
        revision: row['revision'] as int,
        sourceEntryId: row['sourceEntryId'] as String,
        date: row['date'] as String,
        reason: row['reason'] as String,
        accountId: row['accountId'] as String,
        accountName: row['accountName'] as String,
        warehouseId: row['warehouseId'] as String,
        currency: CurrencyCode.values.byName(row['currency'] as String),
        lines: lines
            .map((l) => SalesReturnDraftLine(
                position: l['position'] as int,
                itemId: l['itemId'] as String,
                itemName: l['itemName'] as String,
                unit: l['unit'] as String,
                quantity: (l['quantity'] as num).toDouble(),
                sourceQuantity: (l['sourceQuantity'] as num).toDouble(),
                unitPrice: (l['unitPrice'] as num).toDouble()))
            .toList());
  }

  Future<SalesReturnDraft?> getSalesReturnDraft(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn
          .query('sales_return_drafts', where: 'id = ?', whereArgs: [id]);
      return rows.isEmpty ? null : await _readReturnDraft(txn, rows.single);
    });
  }

  Future<List<SalesReturnDraft>> listSalesReturnDrafts() async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query('sales_return_drafts', orderBy: 'id DESC');
      final result = <SalesReturnDraft>[];
      for (final row in rows) {
        result.add(await _readReturnDraft(txn, row));
      }
      return result;
    });
  }

  Future<void> _createNonpostingDocuments(DatabaseExecutor db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS nonposting_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL CHECK(type IN ('quote', 'order')),
        revision INTEGER NOT NULL,
        date TEXT NOT NULL, currency TEXT NOT NULL,
        customerName TEXT NOT NULL, accountId TEXT NOT NULL, notes TEXT NOT NULL
      )
    """);
    await db.execute("""
      CREATE TABLE IF NOT EXISTS nonposting_lines (
        documentId INTEGER NOT NULL, position INTEGER NOT NULL,
        itemId TEXT NOT NULL, description TEXT NOT NULL,
        quantity REAL NOT NULL CHECK(quantity > 0),
        unitPrice REAL NOT NULL CHECK(unitPrice >= 0),
        PRIMARY KEY(documentId, position),
        FOREIGN KEY(documentId) REFERENCES nonposting_documents(id)
      )
    """);
  }

  /// Resolves only after the transaction commits. Existing documents require
  /// their current revision, preventing lost edits and cross-type replacement.
  Future<NonpostingDocument> saveNonpostingDocument(
      NonpostingDocument doc) async {
    doc.validate();
    final db = await database;
    return db.transaction((txn) async {
      final values = <String, Object?>{
        'type': doc.type.name,
        'revision': doc.revision + 1,
        'date': doc.date,
        'currency': doc.currency.name,
        'customerName': doc.customerName,
        'accountId': doc.accountId,
        'notes': doc.notes,
      };
      final int id;
      if (doc.id == null) {
        id = await txn.insert('nonposting_documents', values);
      } else {
        id = doc.id!;
        final changed = await txn.update('nonposting_documents', values,
            where: 'id = ? AND type = ? AND revision = ?',
            whereArgs: [id, doc.type.name, doc.revision]);
        if (changed != 1) {
          throw StateError('المستند غير موجود أو تغير؛ أعد تحميله');
        }
        await txn.delete('nonposting_lines',
            where: 'documentId = ?', whereArgs: [id]);
      }
      for (var i = 0; i < doc.lines.length; i++) {
        final line = doc.lines[i];
        await txn.insert('nonposting_lines', {
          'documentId': id,
          'position': i,
          'itemId': line.itemId,
          'description': line.description,
          'quantity': line.quantity,
          'unitPrice': line.unitPrice,
        });
      }
      return NonpostingDocument(
          id: id,
          revision: doc.revision + 1,
          type: doc.type,
          date: doc.date,
          currency: doc.currency,
          customerName: doc.customerName,
          accountId: doc.accountId,
          notes: doc.notes,
          lines: doc.lines);
    });
  }

  Future<NonpostingDocument> _readNonposting(
      DatabaseExecutor db, Map<String, Object?> row) async {
    final lines = await db.query('nonposting_lines',
        where: 'documentId = ?',
        whereArgs: [row['id']],
        orderBy: 'position ASC');
    return NonpostingDocument(
        id: row['id'] as int,
        revision: row['revision'] as int,
        type: NonpostingDocumentType.values.byName(row['type'] as String),
        date: row['date'] as String,
        currency: CurrencyCode.values.byName(row['currency'] as String),
        customerName: row['customerName'] as String,
        accountId: row['accountId'] as String,
        notes: row['notes'] as String,
        lines: lines
            .map((l) => NonpostingLine(
                itemId: l['itemId'] as String,
                description: l['description'] as String,
                quantity: (l['quantity'] as num).toDouble(),
                unitPrice: (l['unitPrice'] as num).toDouble()))
            .toList());
  }

  Future<List<NonpostingDocument>> listNonpostingDocuments(
      NonpostingDocumentType type) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query('nonposting_documents',
          where: 'type = ?',
          whereArgs: [type.name],
          orderBy: 'date DESC, id DESC');
      final result = <NonpostingDocument>[];
      for (final row in rows) {
        result.add(await _readNonposting(txn, row));
      }
      return result;
    });
  }

  Future<NonpostingDocument?> getNonpostingDocument(
      NonpostingDocumentType type, int id) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query('nonposting_documents',
          where: 'id = ? AND type = ?', whereArgs: [id, type.name]);
      return rows.isEmpty ? null : await _readNonposting(txn, rows.single);
    });
  }

  Future<void> _createSaleLines(DatabaseExecutor db) => db.execute('''
    CREATE TABLE sale_lines (
      entryId TEXT NOT NULL,
      position INTEGER NOT NULL,
      itemId TEXT NOT NULL,
      itemName TEXT NOT NULL,
      unit TEXT NOT NULL,
      quantity REAL NOT NULL,
      unitPrice REAL NOT NULL,
      PRIMARY KEY (entryId, position)
    )
  ''');

  Future<void> close() async {
    final opening = _opening;
    if (opening != null) {
      try {
        await opening;
      } catch (_) {
        // No connection exists after a failed open.
      }
    }
    await _db?.close();
    _db = null;
  }

  /// An empty chart of accounts does NOT mean a database is fresh. A ledger,
  /// draft, preference or sequence can exist before accounts have been imported.
  Future<bool> hasSeededData() async {
    final db = await database;
    const tables = [
      'accounts',
      'ledger_entries',
      'inventory_items',
      'warehouses',
      'sale_lines',
      'erp_state',
      'nonposting_documents',
      'nonposting_lines',
      'sales_return_drafts',
      'sales_return_draft_lines',
      'sale_facts',
      'sale_line_cost_facts',
      'voucher_drafts',
      'cash_transfer_drafts',
      'simple_journal_drafts',
      'fx_drafts',
      'sqlite_sequence',
    ];
    final clauses =
        tables.map((t) => 'EXISTS(SELECT 1 FROM "$t")').join(' OR ');
    final result = await db.rawQuery('SELECT ($clauses) AS has_rows');
    return (Sqflite.firstIntValue(result) ?? 0) != 0;
  }

  /// Reads committed invoice headers without loading unrelated tables.
  Future<List<LedgerEntryRecord>> loadCommittedLedger() async {
    final db = await database;
    final rows = await db.query('ledger_entries', orderBy: 'entryNumber DESC');
    return List.unmodifiable(rows.map(_ledgerFromMap));
  }

  Future<LocalDbSnapshot> loadSnapshot() async {
    final db = await database;
    final accRows = await db.query('accounts', orderBy: 'codeNumber ASC');
    final ledRows =
        await db.query('ledger_entries', orderBy: 'entryNumber DESC');
    final whRows = await db.query('warehouses');
    final invRows = await db.query('inventory_items');
    final lineRows = await db.query('sale_lines', orderBy: 'entryId, position');
    final metaRows = await db
        .query('erp_state', where: 'stateKey = ?', whereArgs: ['settings']);

    String? companyName;
    bool? isDarkMode;
    int? nextEntryNumber;
    if (metaRows.isNotEmpty) {
      try {
        final decoded = jsonDecode(metaRows.first['payloadJson'] as String);
        if (decoded is! Map<String, dynamic>) {
          throw const InvalidLocalSettings();
        }
        final company = decoded['companyName'];
        final dark = decoded['isDarkMode'];
        final next = decoded['nextEntryNumber'];
        if ((company != null && company is! String) ||
            (dark != null && dark is! bool) ||
            (next != null &&
                (next is! num ||
                    !next.isFinite ||
                    next < 0 ||
                    next > 9007199254740991 ||
                    next != next.truncate()))) {
          throw const InvalidLocalSettings();
        }
        companyName = company as String?;
        isDarkMode = dark as bool?;
        nextEntryNumber = (next as num?)?.toInt();
      } on FormatException {
        throw const InvalidLocalSettings();
      }
    }

    final modules = await db.query('erp_state', where: 'stateKey = ?', whereArgs: ['erp_modules']);
    Map<String, dynamic>? erpData;
    if (modules.isNotEmpty) {
      erpData = jsonDecode(modules.single['payloadJson'] as String) as Map<String, dynamic>;
    } else {
      // Earlier restores kept the web export while clearing the mobile ERP lists.
      final archived = await db.query('erp_state', columns: ['stateKey'],
        where: 'stateKey = ?', whereArgs: ['original_web_export']);
      if (archived.isNotEmpty) erpData = {};
    }
    return LocalDbSnapshot(
      erpData: erpData,
      accounts: accRows.map(_accountFromMap).toList(),
      ledger: ledRows.map(_ledgerFromMap).toList(),
      warehouses: whRows.map(_warehouseFromMap).toList(),
      inventory: invRows.map(_inventoryFromMap).toList(),
      saleLines: lineRows.map(_savedSaleLineFromMap).toList(),
      companyName: companyName,
      isDarkMode: isDarkMode,
      nextEntryNumber: nextEntryNumber,
    );
  }

  Future<Map<String,dynamic>?> readOriginalWebExport() async {
    final rows = await (await database).query('erp_state',columns:['payloadJson'],
        where:'stateKey = ?',whereArgs:['original_web_export']);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.single['payloadJson'] as String) as Map<String,dynamic>;
  }

  Future<void> saveSnapshot({
    required List<AccountRecord> accounts,
    required List<LedgerEntryRecord> ledger,
    required List<WarehouseRecord> warehouses,
    required List<InventoryItemRecord> inventory,
    required List<SavedSaleLine> saleLines,
    required String companyName,
    required bool isDarkMode,
    required int nextEntryNumber,
    SaleFacts? appendedSaleFacts,
    String? restoredWebExport,
    Map<String, Object?>? erpData,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      if (restoredWebExport != null) {
        await _clearTables(txn);
        await txn.insert('erp_state', {
          'stateKey': 'original_web_export',
          'payloadJson': restoredWebExport,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
      await txn.delete('accounts');
      for (final a in accounts) {
        await txn.insert('accounts', _accountToMap(a),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.delete('ledger_entries');
      for (final l in ledger) {
        await txn.insert('ledger_entries', _ledgerToMap(l),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.delete('warehouses');
      for (final w in warehouses) {
        await txn.insert('warehouses', _warehouseToMap(w),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.delete('inventory_items');
      for (final i in inventory) {
        await txn.insert('inventory_items', _inventoryToMap(i),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.delete('sale_lines');
      for (final line in saleLines) {
        await txn.insert('sale_lines', {
          'entryId': line.entryId,
          'position': line.position,
          'itemId': line.itemId,
          'itemName': line.itemName,
          'unit': line.unit,
          'quantity': line.quantity,
          'unitPrice': line.unitPrice,
        });
      }

      if (erpData != null) {
        await txn.insert('erp_state', {
          'stateKey': 'erp_modules', 'payloadJson': jsonEncode(erpData),
          'updatedAt': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (appendedSaleFacts != null) {
        await _appendSaleFacts(txn, appendedSaleFacts);
      }

      await txn.insert(
        'erp_state',
        {
          'stateKey': 'settings',
          'payloadJson': jsonEncode({
            'companyName': companyName,
            'isDarkMode': isDarkMode,
            'nextEntryNumber': nextEntryNumber,
          }),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<Map<String, int>> getTableCounts() async {
    final db = await database;
    final acc = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM accounts')) ??
        0;
    final led = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM ledger_entries')) ??
        0;
    final wh = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM warehouses')) ??
        0;
    final inv = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM inventory_items')) ??
        0;
    return {
      'accounts': acc,
      'ledger': led,
      'warehouses': wh,
      'inventory': inv,
    };
  }

  Future<LedgerEntryRecord?> resolveDeletedEntry(String id,{required bool purge}) async {
    final db=await database;
    return db.transaction((txn) async {
      final rows=await txn.query('ledger_entries',where:'id = ? AND deleted = 1',whereArgs:[id]);
      if(rows.length!=1) throw StateError('تغيّرت حالة القيد. أعد فتح المحذوفات.');
      if(!purge) {
        await txn.update('ledger_entries',{'deleted':0},where:'id = ?',whereArgs:[id]);
        return _ledgerFromMap({...rows.single,'deleted':0});
      }
      final drafts=await txn.query('sales_return_drafts',columns:['id'],where:'sourceEntryId = ?',whereArgs:[id],limit:1);
      final posted=await txn.query('erp_state',columns:['stateKey'],
        where:'stateKey IN (?,?)',whereArgs:['sale_returns/$id','return_detail/$id'],limit:1);
      final linked = await txn.query('ledger_entries', columns: ['id'],
        where: "id IN (?, ?) OR id || '/cashbox' = ? OR id || '/settlement' = ?",
        whereArgs: ['$id/cashbox', '$id/settlement', id, id], limit: 1);
      if (linked.isNotEmpty) throw StateError('القيد مرتبط بتسوية نقدية.');
      if(drafts.isNotEmpty || posted.isNotEmpty) throw StateError('القيد مرتبط بمرتجع محفوظ.');
      for(final table in ['sale_line_cost_facts','sale_facts','sale_lines']) {
        await txn.delete(table,where:'entryId = ?',whereArgs:[id]);
      }
      await txn.delete('ledger_entries',where:'id = ? AND deleted = 1',whereArgs:[id]);
      return null;
    });
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.transaction(_clearTables);
  }

  Future<void> _clearTables(DatabaseExecutor txn) async {
      if ((await txn.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='customer_measurements'")).isNotEmpty) {
        await txn.delete('customer_measurements');
      }
      await txn.delete('accounts');
      await txn.delete('ledger_entries');
      await txn.delete('warehouses');
      await txn.delete('inventory_items');
      await txn.delete('erp_state');
      await txn.delete('sale_lines');
      await txn.delete('nonposting_lines');
      await txn.delete('nonposting_documents');
      await txn.delete('sales_return_draft_lines');
      await txn.delete('sales_return_drafts');
      await txn.delete('sale_line_cost_facts');
      await txn.delete('sale_facts');
      await VoucherDraftRepository.clearDrafts(txn);
      await CashTransferDraftRepository.clearDrafts(txn);
      await SimpleJournalDraftRepository.clearDrafts(txn);
      await FxDraftRepository.clearDrafts(txn);

  }

  Map<String, Object?> _accountToMap(AccountRecord a) => {
        'id': a.id,
        'name': a.name,
        'category': a.category.name,
        'phone': a.phone,
        'creditLimit': a.creditLimit,
        'currency': a.currency.name,
        'isCashAccount': a.isCashAccount ? 1 : 0,
        'note': a.note,
        'openingBalance': a.openingBalance,
        'openingDirection': a.openingDirection.name,
        'codeNumber': a.codeNumber,
      };

  AccountRecord _accountFromMap(Map<String, Object?> m) => AccountRecord(
        id: m['id'] as String,
        name: m['name'] as String,
        category: AccountCategory.values.firstWhere(
          (e) => e.name == m['category'],
          orElse: () => AccountCategory.clients,
        ),
        phone: (m['phone'] as String?) ?? '',
        creditLimit: (m['creditLimit'] as num?)?.toDouble() ?? 50000,
        currency: CurrencyCode.values.firstWhere(
          (e) => e.name == m['currency'],
          orElse: () => CurrencyCode.sar,
        ),
        isCashAccount: (m['isCashAccount'] as int? ?? 0) == 1,
        note: (m['note'] as String?) ?? '',
        openingBalance: (m['openingBalance'] as num?)?.toDouble() ?? 0,
        openingDirection: EntryDirection.values.firstWhere(
          (e) => e.name == m['openingDirection'],
          orElse: () => EntryDirection.credit,
        ),
        codeNumber: (m['codeNumber'] as int?) ?? 1,
      );

  Map<String, Object?> _ledgerToMap(LedgerEntryRecord l) => {
        'id': l.id,
        'accountId': l.accountId,
        'accountName': l.accountName,
        'kind': l.kind.name,
        'typeLabel': l.typeLabel,
        'payment': l.payment.name,
        'direction': l.direction.name,
        'amount': l.amount,
        'currency': l.currency.name,
        'exchangeRate': l.exchangeRate,
        'details': l.details,
        'documentNumber': l.documentNumber,
        'warehouseId': l.warehouseId,
        'warehouseName': l.warehouseName,
        'expenseCategory': l.expenseCategory,
        'entryNumber': l.entryNumber,
        'deleted': l.deleted ? 1 : 0,
        'entryDate': l.entryDate,
      };

  LedgerEntryRecord _ledgerFromMap(Map<String, Object?> m) => LedgerEntryRecord(
        id: m['id'] as String,
        accountId: m['accountId'] as String,
        accountName: m['accountName'] as String,
        kind: LedgerKind.values.firstWhere(
          (e) => e.name == m['kind'],
          orElse: () => LedgerKind.invoice,
        ),
        typeLabel: m['typeLabel'] as String,
        payment: PaymentMethod.values.firstWhere(
          (e) => e.name == m['payment'],
          orElse: () => PaymentMethod.cash,
        ),
        direction: EntryDirection.values.firstWhere(
          (e) => e.name == m['direction'],
          orElse: () => EntryDirection.debit,
        ),
        amount: (m['amount'] as num).toDouble(),
        currency: CurrencyCode.values.firstWhere(
          (e) => e.name == m['currency'],
          orElse: () => CurrencyCode.sar,
        ),
        exchangeRate: (m['exchangeRate'] as num?)?.toDouble() ?? 1.0,
        details: (m['details'] as String?) ?? '',
        documentNumber: (m['documentNumber'] as String?) ?? '',
        warehouseId: (m['warehouseId'] as String?) ?? 'wh_1',
        warehouseName: (m['warehouseName'] as String?) ?? 'المخزن الرئيسي',
        expenseCategory: (m['expenseCategory'] as String?) ?? '',
        entryNumber: (m['entryNumber'] as int?) ?? 1,
        deleted: (m['deleted'] as int? ?? 0) == 1,
        entryDate: (m['entryDate'] as String?) ?? '',
      );

  Map<String, Object?> _warehouseToMap(WarehouseRecord w) => {
        'id': w.id,
        'name': w.name,
        'details': w.details,
        'isDefault': w.isDefault ? 1 : 0,
      };

  WarehouseRecord _warehouseFromMap(Map<String, Object?> m) => WarehouseRecord(
        id: m['id'] as String,
        name: m['name'] as String,
        details: (m['details'] as String?) ?? '',
        isDefault: (m['isDefault'] as int? ?? 0) == 1,
      );

  Map<String, Object?> _inventoryToMap(InventoryItemRecord i) => {
        'id': i.id,
        'name': i.name,
        'unit': i.unit,
        'quantity': i.quantity,
        'avgCost': i.avgCost,
        'warehouseId': i.warehouseId,
        'minThreshold': i.minThreshold,
        'sku': i.sku,
      };

  InventoryItemRecord _inventoryFromMap(Map<String, Object?> m) =>
      InventoryItemRecord(
        id: m['id'] as String,
        name: m['name'] as String,
        unit: m['unit'] as String,
        quantity: (m['quantity'] as num).toDouble(),
        avgCost: (m['avgCost'] as num).toDouble(),
        warehouseId: (m['warehouseId'] as String?) ?? 'wh_1',
        minThreshold: (m['minThreshold'] as num?)?.toDouble() ?? 25,
        sku: (m['sku'] as String?) ?? '',
      );
}
