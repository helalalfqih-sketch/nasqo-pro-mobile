import '../services/website_restore_trial.dart';
import 'dart:async';
import '../services/account_csv.dart';
import '../services/cash_sale_settlement.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/erp_models.dart';
import '../models/erp_workspace_snapshot.dart';
import '../models/invoice_print_snapshot.dart';
import '../models/nonposting_document.dart';
import '../models/sales_return_draft.dart';
import '../models/sale_facts.dart';
import '../models/voucher_draft.dart';
import '../models/cash_transfer_draft.dart';
import '../models/simple_journal_draft.dart';
import '../models/fx_draft.dart';
import '../models/sale_tax_register.dart';
import '../services/accounting_engine.dart';
import '../services/local_database.dart';
import '../services/local_backup_service.dart';
import '../services/web_backup.dart';
import '../services/local_backup_files.dart';
import '../services/voucher_draft_repository.dart';
import '../services/cash_transfer_draft_repository.dart';
import '../services/simple_journal_draft_repository.dart';
import '../services/fx_draft_repository.dart';

class ErpController extends ChangeNotifier {
  ErpController({bool autoInitDb = true, LocalDatabase? localDatabase})
      : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _usesPersistentStore = autoInitDb || localDatabase != null {
    _seedInitialData();
    if (autoInitDb) {
      unawaited(initDatabase());
    }
  }

  final LocalDatabase _localDatabase;
  LocalDatabase get database => _localDatabase;
  LocalDatabase get localDatabase => _localDatabase;
  final bool _usesPersistentStore;
  Future<void>? _startingDatabase;
  Future<void> _writeTail = Future<void>.value();
  bool _salesPosting = false;
  bool _resetting = false;
  bool _editingWorkspace = false;
  bool _disposed = false;

  void _requireAvailableMutation() {
    if (_salesPosting || _resetting || _editingWorkspace) {
      throw const SaleValidationException(
          'توجد عملية حفظ جارية؛ انتظر اكتمالها.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  RestoredGroups? restoredGroups;
  String companyName = 'نسقو برو ERP';
  Set<String> readAlerts={}, dismissedAlerts={};
  void _loadAlertState(dynamic state) {
    readAlerts=state is Map && state['read'] is List ? (state['read'] as List).whereType<String>().toSet() : {};
    dismissedAlerts=state is Map && state['dismissed'] is List ? (state['dismissed'] as List).whereType<String>().toSet() : {};
  }
  Future<void> updateAlerts(Iterable<String> ids,{bool dismiss=false}) async {
    _requireAvailableMutation();_editingWorkspace=true;
    try {
      if(_usesPersistentStore) {
        await initDatabase();
        if(!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final read={...readAlerts,...ids}, hidden={...dismissedAlerts,if(dismiss)...ids};
      if(_usesPersistentStore) await _saveCurrentSnapshot(nextModuleData:{..._workspaceModuleData,
        'alertState':{'read':read.toList(),'dismissed':hidden.toList()}});
      readAlerts=read;dismissedAlerts=hidden;
      if(!_disposed) notifyListeners();
    } finally {_editingWorkspace=false;}
  }

  Map<String,dynamic>? groupDirectory;

  void _applyGroupDirectory(Map<String,dynamic>? data) {
    groupDirectory=data;
    if(data==null) return;
    final target=restoredGroups ??= RestoredGroups.fromJson({});
    final updated=RestoredGroups.fromJson(data);
    target.groupCategories..clear()..addAll(updated.groupCategories);
    target.groupCurrencies..clear()..addAll(updated.groupCurrencies);
    target.groups..clear()..addAll(updated.groups);
    target.membership..clear()..addAll(updated.membership);
  }

  Future<void> saveGroup({int? id, required String name, required AccountCategory category,
      required CurrencyCode currency, required Set<String> members}) async {
    _requireAvailableMutation(); _editingWorkspace=true;
    try {
      if(_usesPersistentStore) {
        await initDatabase();
        if(!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final archive=restoredGroups;
      final existing=archive?.groups??[];
      final membership=<String,int>{...?archive?.membership};
      final definitions=<Map<String,dynamic>>[];
      final hints={for(final g in (groupDirectory?['accountGroups'] as List? ?? [])) g['id']:g};
      for(final g in existing) {
        final member=accounts.where((a)=>membership[a.id]==g.id).firstOrNull;
        definitions.add({'id':g.id,'legacyId':g.number,'sortOrder':g.order,'name':g.name,
          'category':hints[g.id]?['category'] ?? archive?.groupCategories[g.id] ?? member?.category.name ?? 'shop',
          'currencyCode':hints[g.id]?['currencyCode'] ?? archive?.groupCurrencies[g.id] ?? member?.currency.name ?? defaultCurrency.name});
      }
      if(existing.isEmpty) {
        for(final cat in AccountCategory.values) {
          final groupId=cat.index+1;
          definitions.add({'id':groupId,'legacyId':groupId,'sortOrder':groupId,'name':cat.label,
              'category':cat.name,'currencyCode':defaultCurrency.name});
          for(final a in accounts.where((a)=>a.category==cat)) {membership[a.id]=groupId;}
        }
      }
      final label=name.trim();
      if(label.isEmpty || definitions.any((g)=>g['id']!=id && g['name']==label)) {
        throw const FormatException('أدخل اسم مجموعة غير مكرر.');
      }
      final index=definitions.indexWhere((g)=>g['id']==id);
      if(id!=null && index<0) throw StateError('المجموعة غير موجودة.');
      final nextId=id ?? definitions.fold<int>(0,(n,g)=>n>(g['id'] as int)?n:g['id'] as int)+1;
      final nextNumber=index>=0?definitions[index]['legacyId']:definitions.fold<int>(0,(n,g)=>n>(g['legacyId'] as int)?n:g['legacyId'] as int)+1;
      final row={'id':nextId,'legacyId':nextNumber,'name':label,'sortOrder':index<0?nextNumber:definitions[index]['sortOrder'],
        'category':category.name,'currencyCode':currency.name};
      if(index<0) {definitions.add(row);} else {definitions[index]=row;}
      membership.removeWhere((account,group)=>group==nextId && !members.contains(account));
      final validIds=accounts.map((a)=>a.id).toSet();
      for(final a in members) {
        if(!validIds.contains(a)) throw StateError('أحد الحسابات غير موجود.');
        membership[a]=nextId;
      }
      final data={'accountGroups':definitions,'accounts':[for(final e in membership.entries) {'id':e.key,'groupId':e.value}]};
      if(_usesPersistentStore) await _saveCurrentSnapshot(nextModuleData:{..._workspaceModuleData,'groupDirectory':data});
      _applyGroupDirectory(data);
      if(!_disposed) notifyListeners();
    } finally { _editingWorkspace=false; }
  }

  int primaryTint=0xff4338ca, secondaryTint=0xff0891b2;
  double homeRadius=24;
  void _loadAppearance(dynamic data) {
    primaryTint=data is Map && data['primary'] is int?data['primary']:0xff4338ca;
    secondaryTint=data is Map && data['secondary'] is int?data['secondary']:0xff0891b2;
    homeRadius=data is Map && data['radius'] is num?(data['radius'] as num).clamp(0,24).toDouble():24;
  }
  Future<void> saveAppearance(int primary,int secondary,double radius) async {
    _requireAvailableMutation();_editingWorkspace=true;
    try {
      if(_usesPersistentStore) {
        await initDatabase();
        if(!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final data={'primary':primary,'secondary':secondary,'radius':radius};
      if(_usesPersistentStore) await _saveCurrentSnapshot(nextModuleData:{..._workspaceModuleData,'appearance':data});
      _loadAppearance(data);
      if(!_disposed) notifyListeners();
    } finally { _editingWorkspace=false; }
  }
  Map<String, dynamic> _currencyDetails = {};
  Map<String, dynamic> currencyDetails(CurrencyCode code) {
    final data = _currencyDetails[code.name];
    return data is Map ? Map<String, dynamic>.from(data) : {};
  }

  /// Rates are quoted in base currency for one unit of the selected currency.
  double? exchangeQuote(CurrencyCode from, CurrencyCode to, EntryDirection side) {
    if (from == to) return 1;
    final buying = side == EntryDirection.credit;
    double? quote(CurrencyCode code, bool buy) {
      if (code == defaultCurrency) return 1;
      final value = currencyDetails(code)[buy ? 'buy' : 'sell'];
      return value is num && value.isFinite && value > 0 ? value.toDouble() : null;
    }
    final source = quote(from, buying);
    final target = quote(to, !buying);
    if (source == null || target == null) return null;
    final rate = source / target;
    return rate.isFinite && rate > 0 ? rate : null;
  }

  Future<void> saveCurrencyDetails(CurrencyCode code, String symbol, String subunit,
      double buy, double sell) async {
    _requireAvailableMutation();
    _editingWorkspace = true;
    try {
      if (!buy.isFinite || !sell.isFinite || buy <= 0 || sell <= 0 ||
          (code == defaultCurrency && (buy != 1 || sell != 1))) {
        throw const SaleValidationException('تحقق من أسعار الشراء والبيع.');
      }
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final next = {..._currencyDetails, code.name: {
        'symbol': symbol.trim(), 'subunit': subunit.trim(), 'buy': buy, 'sell': sell,
      }};
      if (_usesPersistentStore) {
        await _saveCurrentSnapshot(nextModuleData: {..._workspaceModuleData, 'currencyDetails': next});
      }
      _currencyDetails = next;
      if (!_disposed) notifyListeners();
    } finally { _editingWorkspace = false; }
  }

  String messageProvider = 'nasqo';
  String messagePhone = '';
  bool instantMessages = false;

  final List<ErpRoleRecord> roles = [];
  String activeRoleId = 'role_admin';

  ErpRoleRecord get activeRole => roles.firstWhere(
        (r) => r.id == activeRoleId,
        orElse: () => roles.isNotEmpty
            ? roles.first
            : ErpRoleRecord.fullAccess(id: 'role_admin', name: 'مدير النظام'),
      );

  bool hasModulePermission(ErpPermissionModule module, ErpCrudAction action) =>
      activeRole.hasModule(module, action);

  bool hasActionPermission(ErpActionPermission action) =>
      activeRole.hasAction(action);

  static List<ErpRoleRecord> _defaultRoles() => [
        ErpRoleRecord.fullAccess(
          id: 'role_admin',
          name: 'مدير النظام',
          isSystem: true,
        ),
        ErpRoleRecord(
          id: 'role_accountant',
          name: 'محاسب',
          modulePermissions: {
            for (final m in ErpPermissionModule.values)
              m: switch (m) {
                ErpPermissionModule.currencies ||
                ErpPermissionModule.cashboxes ||
                ErpPermissionModule.accounts ||
                ErpPermissionModule.vouchers ||
                ErpPermissionModule.cashFunds =>
                  const ErpModuleCrudFlags(
                    add: true,
                    edit: true,
                    delete: false,
                    view: true,
                  ),
                ErpPermissionModule.warehouses ||
                ErpPermissionModule.items ||
                ErpPermissionModule.quotesAndOrders ||
                ErpPermissionModule.warehouseTransfers =>
                  const ErpModuleCrudFlags(view: true),
                ErpPermissionModule.users ||
                ErpPermissionModule.rolesAndPermissions =>
                  const ErpModuleCrudFlags.none(),
              },
          },
          actionPermissions: const {
            ErpActionPermission.newVoucher,
            ErpActionPermission.newInvoice,
            ErpActionPermission.dailyJournalEntry,
            ErpActionPermission.quickSearch,
            ErpActionPermission.accountStatement,
            ErpActionPermission.currencyExchangeVoucher,
            ErpActionPermission.editInvoice,
            ErpActionPermission.newTransfer,
            ErpActionPermission.dailyMovement,
            ErpActionPermission.newReturn,
            ErpActionPermission.editTransfer,
          },
        ),
        ErpRoleRecord(
          id: 'role_warehouse_sales',
          name: 'أمين مخزن ومبيعات',
          modulePermissions: {
            for (final m in ErpPermissionModule.values)
              m: switch (m) {
                ErpPermissionModule.warehouses ||
                ErpPermissionModule.items ||
                ErpPermissionModule.quotesAndOrders ||
                ErpPermissionModule.warehouseTransfers =>
                  const ErpModuleCrudFlags(
                    add: true,
                    edit: true,
                    delete: false,
                    view: true,
                  ),
                ErpPermissionModule.accounts ||
                ErpPermissionModule.currencies =>
                  const ErpModuleCrudFlags(view: true),
                _ => const ErpModuleCrudFlags.none(),
              },
          },
          actionPermissions: const {
            ErpActionPermission.newInvoice,
            ErpActionPermission.quickSearch,
            ErpActionPermission.dailyMovement,
            ErpActionPermission.newReturn,
          },
        ),
      ];

  void _loadRolesPermissions(dynamic data) {
    if (data is Map && data['roles'] is List) {
      final loaded = (data['roles'] as List)
          .whereType<Map>()
          .map((r) => ErpRoleRecord.fromJson(Map<String, dynamic>.from(r)))
          .toList();
      if (loaded.isNotEmpty) {
        roles
          ..clear()
          ..addAll(loaded);
        final savedActive = data['activeRoleId'];
        if (savedActive is String &&
            roles.any((r) => r.id == savedActive)) {
          activeRoleId = savedActive;
        } else {
          activeRoleId = roles.first.id;
        }
        return;
      }
    }
    if (roles.isEmpty) {
      roles.addAll(_defaultRoles());
      activeRoleId = roles.first.id;
    }
  }

  Future<ErpRoleRecord> saveRole({
    String? id,
    required String name,
    required Map<ErpPermissionModule, ErpModuleCrudFlags> modulePermissions,
    required Set<ErpActionPermission> actionPermissions,
  }) async {
    _requireAvailableMutation();
    _editingWorkspace = true;
    try {
      final cleanName = name.trim();
      if (cleanName.isEmpty) {
        throw const FormatException('أدخل اسم الدور قبل الحفظ.');
      }
      final duplicate = roles.any(
        (r) => r.id != id && r.name.trim() == cleanName,
      );
      if (duplicate) {
        throw const FormatException('يوجد دور آخر بنفس الاسم.');
      }
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final normalizedModules = <ErpPermissionModule, ErpModuleCrudFlags>{
        for (final m in ErpPermissionModule.values)
          m: modulePermissions[m] ?? const ErpModuleCrudFlags.none(),
      };
      final normalizedActions = Set<ErpActionPermission>.from(actionPermissions);

      final existingIdx = id == null ? -1 : roles.indexWhere((r) => r.id == id);
      late final ErpRoleRecord savedRecord;
      final nextRoles = List<ErpRoleRecord>.of(roles);
      if (existingIdx >= 0) {
        savedRecord = nextRoles[existingIdx].copyWith(
          name: cleanName,
          modulePermissions: normalizedModules,
          actionPermissions: normalizedActions,
        );
        nextRoles[existingIdx] = savedRecord;
      } else {
        final newId =
            id ?? 'role_${DateTime.now().microsecondsSinceEpoch}';
        savedRecord = ErpRoleRecord(
          id: newId,
          name: cleanName,
          modulePermissions: normalizedModules,
          actionPermissions: normalizedActions,
        );
        nextRoles.add(savedRecord);
      }
      final nextActiveId = savedRecord.id;
      final rolesPayload = {
        'activeRoleId': nextActiveId,
        'roles': nextRoles.map((r) => r.toJson()).toList(),
      };
      if (_usesPersistentStore) {
        await _saveCurrentSnapshot(
          nextModuleData: {
            ..._workspaceModuleData,
            'rolesPermissions': rolesPayload,
          },
        );
      }
      roles
        ..clear()
        ..addAll(nextRoles);
      activeRoleId = nextActiveId;
      if (!_disposed) notifyListeners();
      return savedRecord;
    } finally {
      _editingWorkspace = false;
    }
  }

  Future<void> deleteRole(String id) async {
    _requireAvailableMutation();
    _editingWorkspace = true;
    try {
      final idx = roles.indexWhere((r) => r.id == id);
      if (idx < 0) {
        throw const FormatException('الدور المطلوب حذفه غير موجود.');
      }
      if (roles[idx].isSystem) {
        throw const FormatException('لا يمكن حذف دور مدير النظام الأساسي.');
      }
      if (roles.length <= 1) {
        throw const FormatException('يجب الإبقاء على دور واحد على الأقل.');
      }
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final nextRoles = List<ErpRoleRecord>.of(roles)..removeAt(idx);
      final nextActiveId = activeRoleId == id
          ? nextRoles.first.id
          : activeRoleId;
      final rolesPayload = {
        'activeRoleId': nextActiveId,
        'roles': nextRoles.map((r) => r.toJson()).toList(),
      };
      if (_usesPersistentStore) {
        await _saveCurrentSnapshot(
          nextModuleData: {
            ..._workspaceModuleData,
            'rolesPermissions': rolesPayload,
          },
        );
      }
      roles
        ..clear()
        ..addAll(nextRoles);
      activeRoleId = nextActiveId;
      if (!_disposed) notifyListeners();
    } finally {
      _editingWorkspace = false;
    }
  }

  Future<void> setActiveRole(String id) async {
    if (!roles.any((r) => r.id == id)) return;
    _requireAvailableMutation();
    _editingWorkspace = true;
    try {
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final rolesPayload = {
        'activeRoleId': id,
        'roles': roles.map((r) => r.toJson()).toList(),
      };
      if (_usesPersistentStore) {
        await _saveCurrentSnapshot(
          nextModuleData: {
            ..._workspaceModuleData,
            'rolesPermissions': rolesPayload,
          },
        );
      }
      activeRoleId = id;
      if (!_disposed) notifyListeners();
    } finally {
      _editingWorkspace = false;
    }
  }

  Map<String,dynamic> get _workspaceModuleData => {
    ..._modules.toJson(),
    'currencyDetails': _currencyDetails,
    'appearance':{'primary':primaryTint,'secondary':secondaryTint,'radius':homeRadius},
    if(groupDirectory!=null) 'groupDirectory':groupDirectory,
    'alertState':{'read':readAlerts.toList(),'dismissed':dismissedAlerts.toList()},
    'messagePreferences':{'provider':messageProvider,'phone':messagePhone,'instant':instantMessages},
    'rolesPermissions': {
      'activeRoleId': activeRoleId,
      'roles': roles.map((r) => r.toJson()).toList(),
    },
  };
  void _loadMessagePreferences(dynamic prefs) {
    messageProvider = prefs is Map && prefs['provider']=='external' ? 'external' : 'nasqo';
    messagePhone = prefs is Map && prefs['phone'] is String ? prefs['phone'] : '';
    instantMessages = prefs is Map && prefs['instant']==true;
  }
  CurrencyCode defaultCurrency = CurrencyCode.sar;
  bool isDarkMode = false;
  bool dbReady = false;
  bool get requiresLocalDatabase => _usesPersistentStore;
  String? _localDatabaseDiagnostic;
  String? get localDatabaseDiagnostic => _localDatabaseDiagnostic;

  // Display only stable diagnostic codes; database errors may contain paths,
  // commands or private row data and must not be copied out of the app.
  String _startupCode(Object error) {
    if (error is InvalidLocalSettings) return 'DB-SETTINGS';
    if (error is MissingPluginException) return 'DB-DRIVER';
    final hint = error.toString().toLowerCase();
    if (hint.contains('downgrade') ||
        hint.contains('no such table') ||
        hint.contains('no such column') ||
        hint.contains('duplicate column') ||
        hint.contains('already exists')) {
      return 'DB-SCHEMA';
    }
    if (hint.contains('locked') || hint.contains('busy')) return 'DB-LOCKED';
    if (hint.contains('database or disk is full') ||
        hint.contains('no space') ||
        hint.contains('sqlite_full')) {
      return 'DB-SPACE';
    }
    if (hint.contains('malformed') ||
        hint.contains('not a database') ||
        hint.contains('sqlite_corrupt')) {
      return 'DB-DAMAGED';
    }
    return 'DB-OPEN';
  }

  final List<AccountRecord> accounts = [];
  final List<LedgerEntryRecord> ledger = [];
  final List<WarehouseRecord> warehouses = [];
  final List<InventoryItemRecord> inventory = [];
  final List<SavedSaleLine> saleLines = [];
  final List<ErpEmployeeProfile> employees = [];
  final List<ErpLeaveRequest> leaveRequests = [];
  final List<ErpDealRecord> deals = [];
  final List<ErpPurchaseOrder> purchaseOrders = [];
  final List<ErpBomRecipe> boms = [];
  final List<ErpProductionOrder> productionOrders = [];
  final List<ErpCostCenter> costCenters = [];

  ErpWorkspaceSnapshot get _modules => ErpWorkspaceSnapshot(
    employees: employees,
    leaveRequests: leaveRequests,
    deals: deals,
    purchaseOrders: purchaseOrders,
    boms: boms,
    productionOrders: productionOrders,
    costCenters: costCenters,
  );

  void _loadModules(ErpWorkspaceSnapshot modules) {
    employees..clear()..addAll(modules.employees);
    leaveRequests..clear()..addAll(modules.leaveRequests);
    deals..clear()..addAll(modules.deals);
    purchaseOrders..clear()..addAll(modules.purchaseOrders);
    boms..clear()..addAll(modules.boms);
    productionOrders..clear()..addAll(modules.productionOrders);
    costCenters..clear()..addAll(modules.costCenters);
  }

  int _nextEntryNumber = 1200;

  void _seedInitialData() {
    warehouses.addAll(const [
      WarehouseRecord(
        id: 'wh_1',
        name: 'المخزن الرئيسي',
        details: 'المستودع المركزي - الرياض',
        isDefault: true,
      ),
      WarehouseRecord(
        id: 'wh_2',
        name: 'مستودع الفرع التجاري',
        details: 'فرع المبيعات والتجزئة',
      ),
    ]);

    accounts.addAll(const [
      AccountRecord(
        id: 'acc_sales_1',
        name: 'مبيعات الصالة الرئيسية',
        category: AccountCategory.sales,
        codeNumber: 4001,
        openingBalance: 18500,
        openingDirection: EntryDirection.credit,
      ),
      AccountRecord(
        id: 'acc_client_1',
        name: 'عميل تجريبي ١',
        category: AccountCategory.clients,
        codeNumber: 1201,
      ),
      AccountRecord(
        id: 'acc_client_2',
        name: 'عميل تجريبي ٢',
        category: AccountCategory.clients,
        codeNumber: 1202,
      ),
      AccountRecord(
        id: 'acc_sup_1',
        name: 'مورد تجريبي ١',
        category: AccountCategory.purchases,
        codeNumber: 2101,
      ),
      AccountRecord(
        id: 'acc_cash_1',
        name: 'الصندوق الرئيسي',
        category: AccountCategory.transfers,
        isCashAccount: true,
        codeNumber: 1101,
        openingBalance: 45000,
        openingDirection: EntryDirection.debit,
      ),
      AccountRecord(
        id: 'acc_shop_1',
        name: 'مصروفات التشغيل والإيجار',
        category: AccountCategory.shop,
        codeNumber: 5101,
      ),
      AccountRecord(
        id: 'acc_emp_pool',
        name: 'مستحقات الرواتب والأجور',
        category: AccountCategory.employees,
        codeNumber: 2201,
      ),
    ]);

    inventory.addAll(const [
      InventoryItemRecord(
        id: 'inv_1',
        name: 'أرز بسمتي فاخر 10 كجم',
        unit: 'كيس',
        quantity: 80,
        avgCost: 62,
        warehouseId: 'wh_1',
        sku: 'SKU-101',
      ),
      InventoryItemRecord(
        id: 'inv_2',
        name: 'زيت زيتون بكر ممتاز 1 لتر',
        unit: 'عبوة',
        quantity: 65,
        avgCost: 34,
        warehouseId: 'wh_1',
        sku: 'SKU-102',
      ),
      InventoryItemRecord(
        id: 'inv_3',
        name: 'قهوة عربية محمصة 1 كجم',
        unit: 'علبة',
        quantity: 40,
        avgCost: 48,
        warehouseId: 'wh_1',
        sku: 'SKU-103',
      ),
      InventoryItemRecord(
        id: 'inv_4',
        name: 'سلة تموين متكاملة (منتج تام)',
        unit: 'سلة',
        quantity: 18,
        avgCost: 145,
        warehouseId: 'wh_1',
        sku: 'FG-201',
      ),
    ]);

    ledger.addAll(const [
      LedgerEntryRecord(
        id: 'led_1',
        accountId: 'acc_client_1',
        accountName: 'عميل تجريبي ١',
        kind: LedgerKind.invoice,
        typeLabel: 'ف.مبيعات آجل',
        payment: PaymentMethod.credit,
        direction: EntryDirection.debit,
        amount: 6400,
        details: 'توريد مواد غذائية متنوعة',
        documentNumber: 'INV-1001',
        entryNumber: 1001,
        entryDate: '2026-11-12',
      ),
      LedgerEntryRecord(
        id: 'led_2',
        accountId: 'acc_sup_1',
        accountName: 'مورد تجريبي ١',
        kind: LedgerKind.invoice,
        typeLabel: 'ف.مشتريات مخزنية',
        payment: PaymentMethod.credit,
        direction: EntryDirection.credit,
        amount: 4200,
        details: 'شراء أرز وزيت وقهوة للمستودع',
        documentNumber: 'PUR-1002',
        entryNumber: 1002,
        entryDate: '2026-11-13',
      ),
      LedgerEntryRecord(
        id: 'led_3',
        accountId: 'acc_shop_1',
        accountName: 'مصروفات التشغيل والإيجار',
        kind: LedgerKind.voucher,
        typeLabel: 'سند صرف مصروفات',
        payment: PaymentMethod.cash,
        direction: EntryDirection.debit,
        amount: 1800,
        details: 'إيجار ومرافق الفرع الشهري',
        expenseCategory: 'إيجار ومقر',
        entryNumber: 1003,
        entryDate: '2026-11-14',
      ),
    ]);

    employees.addAll(const [
      ErpEmployeeProfile(
        id: 'emp_1',
        name: 'موظف تجريبي ١',
        roleTitle: 'مدير العمليات والمبيعات',
        department: 'المبيعات',
        basicSalary: 7500,
        allowances: 1200,
        deductions: 250,
        hireDate: '2024-03-01',
      ),
      ErpEmployeeProfile(
        id: 'emp_2',
        name: 'موظف تجريبي ٢',
        roleTitle: 'محاسبة أولى',
        department: 'المالية',
        basicSalary: 6800,
        allowances: 900,
        deductions: 0,
        hireDate: '2024-06-15',
      ),
      ErpEmployeeProfile(
        id: 'emp_3',
        name: 'موظف تجريبي ٣',
        roleTitle: 'أمين مستودع',
        department: 'المخازن',
        basicSalary: 4800,
        allowances: 600,
        deductions: 150,
        hireDate: '2025-01-10',
      ),
    ]);

    leaveRequests.addAll(const [
      ErpLeaveRequest(
        id: 'lv_1',
        employeeId: 'emp_3',
        employeeName: 'موظف تجريبي ٣',
        leaveType: 'سنوية',
        startDate: '2026-11-20',
        days: 4,
        note: 'إجازة عائلية مجدولة',
      ),
    ]);

    deals.addAll(const [
      ErpDealRecord(
        id: 'deal_1',
        title: 'صفقة تموين تجريبية ١',
        clientAccountId: 'acc_client_1',
        clientName: 'عميل تجريبي ١',
        value: 24500,
        stage: ErpDealStage.negotiation,
        probability: 75,
        expectedCloseDate: '2026-11-25',
        assignedTo: 'موظف تجريبي ١',
      ),
      ErpDealRecord(
        id: 'deal_2',
        title: 'تجهيز سلات ضيافة للشركات',
        clientAccountId: 'acc_client_2',
        clientName: 'عميل تجريبي ٢',
        value: 14000,
        stage: ErpDealStage.proposal,
        probability: 50,
        expectedCloseDate: '2026-11-30',
        assignedTo: 'موظف تجريبي ١',
      ),
    ]);

    purchaseOrders.addAll(const [
      ErpPurchaseOrder(
        id: 'po_1',
        poNumber: 'PO-2026-101',
        supplierAccountId: 'acc_sup_1',
        supplierName: 'مورد تجريبي ١',
        warehouseId: 'wh_1',
        warehouseName: 'المخزن الرئيسي',
        orderDate: '2026-11-14',
        expectedDate: '2026-11-17',
        status: PurchaseOrderStatus.approved,
        lines: [
          ErpPurchaseOrderLine(
            inventoryItemId: 'inv_1',
            itemName: 'أرز بسمتي فاخر 10 كجم',
            unit: 'كيس',
            quantity: 20,
            unitCost: 60,
          ),
        ],
        notes: 'توريد دفعة منتصف الشهر',
      ),
    ]);

    boms.addAll(const [
      ErpBomRecipe(
        id: 'bom_1',
        name: 'تجميع سلة التموين المتكاملة',
        finishedItemId: 'inv_4',
        finishedItemName: 'سلة تموين متكاملة (منتج تام)',
        finishedUnit: 'سلة',
        components: [
          ErpBomComponent(
            inventoryItemId: 'inv_1',
            itemName: 'أرز بسمتي فاخر 10 كجم',
            unit: 'كيس',
            quantityPerUnit: 1,
          ),
          ErpBomComponent(
            inventoryItemId: 'inv_2',
            itemName: 'زيت زيتون بكر ممتاز 1 لتر',
            unit: 'عبوة',
            quantityPerUnit: 1,
          ),
          ErpBomComponent(
            inventoryItemId: 'inv_3',
            itemName: 'قهوة عربية محمصة 1 كجم',
            unit: 'علبة',
            quantityPerUnit: 1,
          ),
        ],
      ),
    ]);

    productionOrders.addAll(const [
      ErpProductionOrder(
        id: 'mfg_1',
        orderNumber: 'MFG-01',
        bomId: 'bom_1',
        bomName: 'تجميع سلة التموين المتكاملة',
        finishedItemId: 'inv_4',
        finishedItemName: 'سلة تموين متكاملة (منتج تام)',
        quantityToProduce: 5,
        warehouseId: 'wh_1',
        createdDate: '2026-11-15',
        costCenterId: 'cc_1',
      ),
    ]);

    costCenters.addAll(const [
      ErpCostCenter(
        id: 'cc_1',
        code: 'CC-100',
        name: 'مركز التشغيل والتوزيع',
        managerName: 'موظف تجريبي ١',
        budget: 40000,
        extraPostedSpend: 3500,
        linkedCategories: ['إيجار ومقر', 'شحن ونقل'],
      ),
      ErpCostCenter(
        id: 'cc_2',
        code: 'CC-200',
        name: 'مركز التصنيع والتعبئة',
        managerName: 'موظف تجريبي ٣',
        budget: 25000,
        extraPostedSpend: 1800,
        linkedCategories: ['مصروفات تشغيلية'],
      ),
    ]);
    roles
      ..clear()
      ..addAll(_defaultRoles());
    activeRoleId = roles.first.id;
  }

  Future<List<NonpostingDocument>> loadNonpostingDocuments(
    NonpostingDocumentType type,
  ) =>
      _localDatabase.listNonpostingDocuments(type);

  Future<NonpostingDocument?> loadNonpostingDocument(
    NonpostingDocumentType type,
    int id,
  ) =>
      _localDatabase.getNonpostingDocument(type, id);

  Future<NonpostingDocument> saveNonpostingDocument(
    NonpostingDocument document,
  ) =>
      _localDatabase.saveNonpostingDocument(document);

  Future<int> postSalesReturn(int id, int revision) async {
    _requireAvailableMutation();
    _editingWorkspace = true;
    try {
      await initDatabase();
      if (!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
      await _writeTail;
      final number = await _localDatabase.postReturnDraft(id, revision);
      await _loadOrCreateDatabase();
      return number;
    } finally {
      _editingWorkspace = false;
    }
  }

  Future<List<SalesReturnDraft>> loadSalesReturnDrafts() =>
      _localDatabase.listSalesReturnDrafts();

  Future<SalesReturnDraft?> loadSalesReturnDraft(int id) =>
      _localDatabase.getSalesReturnDraft(id);

  Future<SalesReturnDraft> saveSalesReturnDraft({
    int? id,
    int revision = 0,
    required String sourceEntryId,
    required String date,
    required String reason,
    required List<SalesReturnSelection> selections,
  }) =>
      _localDatabase.saveSalesReturnDraft(
        id: id,
        revision: revision,
        sourceEntryId: sourceEntryId,
        date: date,
        reason: reason,
        selections: selections,
      );

  Future<InvoicePrintSnapshot> loadInvoiceForPrint(String entryId) async {
    await initDatabase();
    if (!_usesPersistentStore) {
      return InvoicePrintSnapshot(ledger.singleWhere((e) => e.id == entryId),
          saleLines.where((line) => line.entryId == entryId), null);
    }
    if (!dbReady) {
      throw const SaleValidationException('قاعدة البيانات المحلية غير جاهزة.');
    }
    return _localDatabase.loadInvoiceForPrint(entryId);
  }

  Future<SaleFacts?> loadOriginalSaleFacts(String entryId) =>
      _localDatabase.getSaleFacts(entryId);

  Future<SaleTaxRegister> loadSaleTaxRegister(
          {String? from, String? through}) =>
      _localDatabase.loadSaleTaxRegister(from: from, through: through);

  Future<List<LedgerEntryRecord>> loadCommittedSalesForExport() async {
    await initDatabase();
    if (!_usesPersistentStore) return List.unmodifiable(ledger);
    if (!dbReady) {
      throw const SaleValidationException('قاعدة البيانات المحلية غير جاهزة.');
    }
    return _localDatabase.loadCommittedLedger();
  }

  VoucherDraftRepository get _voucherRepository =>
      VoucherDraftRepository(_localDatabase);

  Future<List<VoucherDraft>> loadVoucherDrafts(VoucherDraftType type) =>
      _voucherRepository.list(type: type);

  Future<VoucherDraft?> loadVoucherDraft(int id) => _voucherRepository.get(id);

  Future<VoucherDraft> saveVoucherDraft(VoucherDraft draft) =>
      _voucherRepository.save(draft);

  Future<List<AccountRecord>> loadVoucherAccounts() async {
    await initDatabase();
    if (_usesPersistentStore && !dbReady) {
      throw const SaleValidationException('قاعدة البيانات المحلية غير جاهزة.');
    }
    return List.unmodifiable(accounts);
  }

  CashTransferDraftRepository get _transferDrafts =>
      CashTransferDraftRepository(_localDatabase);

  Future<List<CashTransferDraft>> loadCashTransferDrafts() =>
      _transferDrafts.list();

  Future<CashTransferDraft?> loadCashTransferDraft(int id) =>
      _transferDrafts.get(id);

  Future<CashTransferDraft> saveCashTransferDraft(CashTransferDraft draft) =>
      _transferDrafts.save(draft);

  SimpleJournalDraftRepository get _journalDrafts =>
      SimpleJournalDraftRepository(_localDatabase);

  Future<List<SimpleJournalDraft>> loadSimpleJournalDrafts() =>
      _journalDrafts.list();

  Future<SimpleJournalDraft?> loadSimpleJournalDraft(int id) =>
      _journalDrafts.get(id);

  Future<SimpleJournalDraft> saveSimpleJournalDraft(SimpleJournalDraft draft) =>
      _journalDrafts.save(draft);

  FxDraftRepository get _fxDrafts => FxDraftRepository(_localDatabase);

  Future<List<FxDraft>> loadFxDrafts() => _fxDrafts.list();
  Future<FxDraft?> loadFxDraft(int id) => _fxDrafts.get(id);
  Future<FxDraft> saveFxDraft(FxDraft draft) => _fxDrafts.save(draft);

  Future<LocalBackupFiles> _openLocalBackupFiles() async {
    await initDatabase();
    if (!_usesPersistentStore || !dbReady) {
      throw StateError('قاعدة البيانات المحلية غير جاهزة للاختبار.');
    }
    return LocalBackupFiles(
      core: LocalBackupService(_localDatabase),
      privateDatabaseDirectory: () async =>
          p.dirname((await _localDatabase.database).path),
    );
  }

  Future<List<LocalBackupFile>> loadLocalBackups() async =>
      (await _openLocalBackupFiles()).loadBackups();

  Future<LocalBackupFile> importLocalBackup(String envelope) async =>
      (await _openLocalBackupFiles()).importBackup(envelope);

  Future<bool> exportLocalBackup(String id) async {
    final bytes = await (await _openLocalBackupFiles()).exportBytes(id);
    const channel = MethodChannel('com.indexesstore.nasqo_qa/csv_export');
    return await channel.invokeMethod<bool>('saveBackup', {'suggestedName': id, 'bytes': Uint8List.fromList(bytes)}) ?? false;
  }

  Future<LocalBackupFile> createLocalBackup() async =>
      (await _openLocalBackupFiles()).createBackup();

  Future<LocalBackupCheck> verifyLocalBackup(String id) async =>
      (await _openLocalBackupFiles()).verifyBackup(id);

  Future<LocalBackupCheck> testLocalBackupRestore(String id) async =>
      (await _openLocalBackupFiles()).testRestore(id);

  Future<void> initDatabase() {
    if (dbReady || !_usesPersistentStore) return Future<void>.value();
    final pending = _startingDatabase;
    if (pending != null) return pending;
    _localDatabaseDiagnostic = null;
    final attempt = _loadOrCreateDatabase().whenComplete(() {
      _startingDatabase = null;
    });
    _startingDatabase = attempt;
    if (!_disposed) notifyListeners();
    return attempt;
  }

  Future<void> _loadOrCreateDatabase() async {
    try {
      final hasData = await _localDatabase.hasSeededData();
      if (hasData) {
        final snap = await _localDatabase.loadSnapshot();
        final original = await _localDatabase.readOriginalWebExport();
        restoredGroups = original == null ? null : RestoredGroups.fromJson(original);
        _applyGroupDirectory(snap.erpData?['groupDirectory'] as Map<String,dynamic>?);
        final currencies = snap.erpData?['currencyDetails'];
        _currencyDetails = currencies is Map ? Map<String, dynamic>.from(currencies)
            : WebBackup.readCurrencyDetails(original?['currencies']);
        _loadAppearance(snap.erpData?['appearance']);
        _loadAlertState(snap.erpData?['alertState']);
        _loadMessagePreferences(snap.erpData?['messagePreferences']);
        _loadRolesPermissions(snap.erpData?['rolesPermissions']);
        if (snap.erpData != null) _loadModules(ErpWorkspaceSnapshot.fromJson(snap.erpData!));
        accounts
          ..clear()
          ..addAll(snap.accounts);
        ledger
          ..clear()
          ..addAll(snap.ledger);
        warehouses
          ..clear()
          ..addAll(snap.warehouses);
        inventory
          ..clear()
          ..addAll(snap.inventory);
        saleLines
          ..clear()
          ..addAll(snap.saleLines);
        if (snap.companyName != null && snap.companyName!.isNotEmpty) {
          companyName = snap.companyName!;
        }
        if (snap.isDarkMode != null) {
          isDarkMode = snap.isDarkMode!;
        }
        if (snap.nextEntryNumber != null &&
            snap.nextEntryNumber! > _nextEntryNumber) {
          _nextEntryNumber = snap.nextEntryNumber!;
        }
        for (final entry in snap.ledger) {
          if (entry.entryNumber > _nextEntryNumber) {
            _nextEntryNumber = entry.entryNumber;
          }
        }
      } else {
        await _saveCurrentSnapshot();
      }
      dbReady = true;
      _localDatabaseDiagnostic = null;
      if (!_disposed) notifyListeners();
    } catch (error) {
      dbReady = false;
      _localDatabaseDiagnostic = _startupCode(error);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _saveCurrentSnapshot({
    List<AccountRecord>? nextAccounts,
    Map<String,dynamic>? nextModuleData,
    String? nextCompany,
    List<WarehouseRecord>? nextWarehouses,
    List<LedgerEntryRecord>? nextLedger,
    List<InventoryItemRecord>? nextInventory,
    List<SavedSaleLine>? nextSaleLines,
    int? nextEntryNumber,
    SaleFacts? appendedSaleFacts,
  }) =>
      _localDatabase.saveSnapshot(
        accounts: List.of(nextAccounts ?? accounts),
        ledger: List.of(nextLedger ?? ledger),
        warehouses: List.of(nextWarehouses ?? warehouses),
        inventory: List.of(nextInventory ?? inventory),
        saleLines: List.of(nextSaleLines ?? saleLines),
        companyName: nextCompany ?? companyName,
        isDarkMode: isDarkMode,
        nextEntryNumber: nextEntryNumber ?? _nextEntryNumber,
        appendedSaleFacts: appendedSaleFacts,
        erpData: nextModuleData ?? _workspaceModuleData,
      );

  Future<void> _persistToDb() {
    if (!_usesPersistentStore) return Future<void>.value();
    // Capture at enqueue time; older snapshots finish before a new sale posts.
    final snapshotAccounts = List<AccountRecord>.of(accounts);
    final snapshotLedger = List<LedgerEntryRecord>.of(ledger);
    final snapshotWarehouses = List<WarehouseRecord>.of(warehouses);
    final snapshotInventory = List<InventoryItemRecord>.of(inventory);
    final snapshotSaleLines = List<SavedSaleLine>.of(saleLines);
    final snapshotCompany = companyName;
    final snapshotTheme = isDarkMode;
    final snapshotNumber = _nextEntryNumber;
    final snapshotModules = _workspaceModuleData;
    _writeTail = _writeTail.then((_) async {
      try {
        if (!dbReady && !_resetting) return;
        await _localDatabase.saveSnapshot(
          accounts: snapshotAccounts,
          ledger: snapshotLedger,
          warehouses: snapshotWarehouses,
          inventory: snapshotInventory,
          saleLines: snapshotSaleLines,
          companyName: snapshotCompany,
          isDarkMode: snapshotTheme,
          nextEntryNumber: snapshotNumber,
          erpData: snapshotModules,
        );
      } catch (_) {
        // Legacy screen behavior: it does not expose the write result.
        // The sales path below handles SQLite errors explicitly.
      }
    });
    return _writeTail;
  }

  Future<void> restoreLocalBackup(String id) async {
    _requireAvailableMutation();
    _resetting = true;
    try {
      final files = await _openLocalBackupFiles();
      await _writeTail;
      await files.createBackup();
      await files.restoreLocal(id);
      _nextEntryNumber = 0;
      _loadModules(const ErpWorkspaceSnapshot());
      await _loadOrCreateDatabase();
      if (!dbReady) throw StateError('تعذر فتح النسخة المستعادة.');
    } finally { _resetting = false; }
  }

  Future<void> restoreWebBackup(WebBackup backup) async {
    _requireAvailableMutation();
    _resetting = true;
    try {
      final files = await _openLocalBackupFiles();
      await _writeTail;
      final rollback = await files.createBackup();
      await files.testRestore(rollback.id);
      final preferences = websitePreferences(backup);
      await writeWebsiteSnapshot(_localDatabase, backup, isDarkMode);
      accounts..clear()..addAll(backup.accounts);
      ledger..clear()..addAll(backup.ledger);
      warehouses..clear()..addAll(backup.warehouses);
      inventory..clear()..addAll(backup.inventory);
      saleLines..clear()..addAll(backup.lines);
      groupDirectory=null;
      restoredGroups = backup.groupData;
      _currencyDetails = Map.of(backup.currencyDetails);
      _loadAppearance(null);
      _loadAlertState(null);
      _loadMessagePreferences(preferences);
      _loadModules(backup.modules);
      companyName = backup.company;
      _nextEntryNumber = backup.lastNumber;
      if (!_disposed) notifyListeners();
    } finally {
      _resetting = false;
    }
  }

  Future<void> resolveTrash(String id,{required bool purge}) async {
    _requireAvailableMutation();
    _editingWorkspace=true;
    try {
      await initDatabase();
      if(!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
      await _writeTail;
      final index=ledger.indexWhere((e)=>e.id==id && e.deleted);
      if(index<0) throw StateError('القيد غير موجود في المحذوفات.');
      final updated=await _localDatabase.resolveDeletedEntry(id,purge:purge);
      if(updated==null) {
        ledger.removeAt(index);
        saleLines.removeWhere((line)=>line.entryId==id);
      } else {
        ledger[index]=updated;
      }
      if(!_disposed) notifyListeners();
    } finally { _editingWorkspace=false; }
  }

  Future<void> resetLocalDatabase() async {
    _requireAvailableMutation();
    _resetting = true;
    try {
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) {
          throw const SaleValidationException(
              'قاعدة البيانات المحلية غير جاهزة.');
        }
        await _writeTail;
        await _localDatabase.clearAll();
      }
      accounts.clear();
      ledger.clear();
      warehouses.clear();
      inventory.clear();
      saleLines.clear();
      employees.clear();
      leaveRequests.clear();
      deals.clear();
      purchaseOrders.clear();
      boms.clear();
      productionOrders.clear();
      costCenters.clear();
      groupDirectory=null;
      restoredGroups = null;
      _currencyDetails = {};
      _loadAppearance(null);
      _loadAlertState(null);
      _loadMessagePreferences(null);
      _nextEntryNumber = 1200;
      _seedInitialData();
      await _persistToDb();
      if (!_disposed) notifyListeners();
    } finally {
      _resetting = false;
    }
  }

  Future<void> saveMessagePreferences(String provider,String phone,bool instant) async {
    _requireAvailableMutation();
    _editingWorkspace=true;
    try {
      if(provider!='nasqo' && provider!='external') throw ArgumentError.value(provider);
      final prefs={'provider':provider,'phone':phone.trim(),'instant':instant};
      if(_usesPersistentStore) {
        await initDatabase();
        if(!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
        await _writeTail;
        await _saveCurrentSnapshot(nextModuleData:{..._workspaceModuleData,'messagePreferences':prefs});
      }
      _loadMessagePreferences(prefs);
      if(!_disposed) notifyListeners();
    } finally { _editingWorkspace=false; }
  }

  Future<void> importAccountRows(List<ImportedAccount> rows) =>
    saveAccountRows(rows,category:AccountCategory.purchases,currency:defaultCurrency,
      direction:EntryDirection.credit);

  Future<void> saveAccountRows(List<ImportedAccount> rows,{required AccountCategory category,
      required CurrencyCode currency,required EntryDirection direction,String note='',double creditLimit=0,
      bool cash=false,String? editId}) async {
    _requireAvailableMutation();
    _editingWorkspace=true;
    try {
      if(_usesPersistentStore) {
        await initDatabase();
        if(!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      if(rows.isEmpty || (editId!=null && rows.length!=1)) throw ArgumentError('بيانات الحساب غير صالحة.');
      final next=List<AccountRecord>.of(accounts);
      final index=editId==null ? -1 : next.indexWhere((a)=>a.id==editId);
      if(editId!=null && index<0) throw StateError('الحساب غير موجود.');
      var number=next.fold<int>(0,(n,a)=>n>a.codeNumber?n:a.codeNumber);
      final prefix=DateTime.now().microsecondsSinceEpoch;
      for(final row in rows) {
        if(row.name.trim().isEmpty || row.opening<0 || !row.opening.isFinite || creditLimit<0 || !creditLimit.isFinite) {
          throw const FormatException('بيانات الحساب أو الرصيد غير صالحة.');
        }
        final code=index<0 ? ++number : next[index].codeNumber;
        final account=AccountRecord(id:editId ?? 'acc_${prefix}_$code',name:row.name.trim(),
          phone:row.phone.trim(),openingBalance:row.opening,category:category,currency:currency,
          openingDirection:direction,note:note.trim(),creditLimit:creditLimit,isCashAccount:cash,codeNumber:code);
        if(index<0) {next.add(account);} else {next[index]=account;}
      }
      if(_usesPersistentStore) await _saveCurrentSnapshot(nextAccounts:next);
      accounts..clear()..addAll(next);
      if(!_disposed) notifyListeners();
    } finally { _editingWorkspace=false; }
  }

  Future<void> renameCompany(String name) async {
    if (name.trim().isEmpty || name.trim().length > 100) {
      throw const SaleValidationException('أدخل اسم منشأة من 1 إلى 100 حرف.');
    }
    _requireAvailableMutation();
    _editingWorkspace = true;
    try {
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) throw const SaleValidationException('قاعدة البيانات غير جاهزة.');
        await _writeTail;
        await _saveCurrentSnapshot(nextCompany: name.trim());
      }
      companyName = name.trim();
      if (!_disposed) notifyListeners();
    } finally { _editingWorkspace = false; }
  }

  Future<void> setDefaultCurrency(CurrencyCode code) async {
    _requireAvailableMutation();
    _editingWorkspace = true;
    try {
      defaultCurrency = code;
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) throw const SaleValidationException('قاعدة البيانات غير جاهزة.');
        await _writeTail;
        await _saveCurrentSnapshot();
      }
      if (!_disposed) notifyListeners();
    } finally { _editingWorkspace = false; }
  }

  static const List<String> expenseCategories = [
    'مشتريات بضائع',
    'مصروفات تشغيلية',
    'شحن ونقل',
    'رواتب وأجور',
    'صيانة ومرافق',
    'تسويق ومبيعات',
    'إيجار ومقر',
    'أخرى',
  ];

  static String inferExpenseCategory(
    String description,
    String accountName, [
    AccountCategory? category,
  ]) {
    final text = '$description $accountName'.toLowerCase();
    if (text.contains('راتب') || text.contains('رواتب') || text.contains('أجر') ||
        text.contains('سلفة') || category == AccountCategory.employees) {
      return 'رواتب وأجور';
    }
    if (text.contains('شحن') || text.contains('نقل') || text.contains('توصيل') ||
        text.contains('ديزل') || text.contains('وقود')) {
      return 'شحن ونقل';
    }
    if (text.contains('إيجار') || text.contains('ايجار') || text.contains('مقر') ||
        text.contains('مستودع')) {
      return 'إيجار ومقر';
    }
    if (text.contains('كهرباء') || text.contains('ماء') || text.contains('صيانة') ||
        text.contains('إنترنت') || text.contains('انترنت')) {
      return 'صيانة ومرافق';
    }
    if (text.contains('إعلان') || text.contains('اعلان') || text.contains('تسويق') ||
        text.contains('عمولة') || category == AccountCategory.sales) {
      return 'تسويق ومبيعات';
    }
    if (text.contains('بضاعة') || text.contains('توريد') || text.contains('شراء') ||
        category == AccountCategory.purchases) {
      return 'مشتريات بضائع';
    }
    if (category == AccountCategory.shop || text.contains('مصروف') || text.contains('قرطاسية')) {
      return 'مصروفات تشغيلية';
    }
    return 'أخرى';
  }

  Future<void> moveEntryToTrash(String id) async {
    _requireAvailableMutation();
    _editingWorkspace = true;
    try {
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) throw const SaleValidationException('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final idx = ledger.indexWhere((e) => e.id == id && !e.deleted);
      if (idx < 0) throw const SaleValidationException('القيد غير موجود أو محذوف مسبقًا.');
      final nextLedger = List<LedgerEntryRecord>.of(ledger);
      nextLedger[idx] = nextLedger[idx].copyWith(deleted: true);
      final counterIdx = nextLedger.indexWhere((e) => e.id == '${id}_counter' && !e.deleted);
      if (counterIdx >= 0) {
        nextLedger[counterIdx] = nextLedger[counterIdx].copyWith(deleted: true);
      }
      if (_usesPersistentStore) {
        await _saveCurrentSnapshot(nextLedger: nextLedger);
      }
      ledger
        ..clear()
        ..addAll(nextLedger);
      if (!_disposed) notifyListeners();
    } finally { _editingWorkspace = false; }
  }

  Future<int> batchUpdateInventoryItems(
    Set<String> selectedIds, {
    String priceMode = 'keep',
    double? priceValue,
    String stockMode = 'keep',
    double? stockValue,
    double? minThreshold,
  }) async {
    _requireAvailableMutation();
    _editingWorkspace = true;
    try {
      if (selectedIds.isEmpty) {
        throw const SaleValidationException('حدد صنفًا واحدًا على الأقل للتعديل الجماعي.');
      }
      if (priceMode == 'keep' && stockMode == 'keep' && minThreshold == null) {
        throw const SaleValidationException(
            'اختر حقلًا واحدًا على الأقل للتحديث الجماعي (التكلفة أو الكمية أو حد التنبيه).');
      }
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) throw const SaleValidationException('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final next = List<InventoryItemRecord>.of(inventory);
      var updatedCount = 0;
      for (var i = 0; i < next.length; i++) {
        final item = next[i];
        if (!selectedIds.contains(item.id)) continue;
        var nextCost = item.avgCost;
        if (priceMode == 'set' && priceValue != null && priceValue.isFinite && priceValue >= 0) {
          nextCost = priceValue;
        } else if (priceMode == 'percent' && priceValue != null && priceValue.isFinite) {
          nextCost = (item.avgCost * (1 + priceValue / 100) * 100).roundToDouble() / 100;
          if (nextCost < 0) nextCost = 0;
        }
        var nextQty = item.quantity;
        if (stockMode == 'set' && stockValue != null && stockValue.isFinite && stockValue >= 0) {
          nextQty = stockValue;
        } else if (stockMode == 'delta' && stockValue != null && stockValue.isFinite) {
          nextQty = item.quantity + stockValue;
          if (nextQty < 0) nextQty = 0;
        }
        final nextThreshold = (minThreshold != null && minThreshold.isFinite && minThreshold >= 0)
            ? minThreshold
            : item.minThreshold;
        next[i] = InventoryItemRecord(
          id: item.id,
          name: item.name,
          sku: item.sku,
          unit: item.unit,
          warehouseId: item.warehouseId,
          quantity: nextQty,
          avgCost: nextCost,
          minThreshold: nextThreshold,
        );
        updatedCount++;
      }
      if (_usesPersistentStore) {
        await _saveCurrentSnapshot(nextInventory: next);
      }
      inventory
        ..clear()
        ..addAll(next);
      if (!_disposed) notifyListeners();
      return updatedCount;
    } finally { _editingWorkspace = false; }
  }

  Future<void> transferWarehouseStock({
    required String itemId,
    required String toWarehouseId,
    required double quantity,
  }) async {
    _requireAvailableMutation();
    _editingWorkspace = true;
    try {
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) throw const SaleValidationException('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final srcIdx = inventory.indexWhere((i) => i.id == itemId);
      if (srcIdx < 0) throw const SaleValidationException('الصنف غير موجود.');
      final src = inventory[srcIdx];
      if (src.warehouseId == toWarehouseId || !warehouses.any((w) => w.id == toWarehouseId)) {
        throw const SaleValidationException('اختر مستودع وجهة مختلفًا وصالحًا.');
      }
      if (!quantity.isFinite || quantity <= 0 || quantity > src.quantity) {
        throw const SaleValidationException('الكمية المحولة غير صالحة أو تتجاوز المتوفر في المستودع.');
      }
      final next = List<InventoryItemRecord>.of(inventory);
      final srcSku = src.sku.trim().toLowerCase();
      final srcName = src.name.trim().toLowerCase();
      final srcUnit = src.unit.trim().toLowerCase();

      int dstIdx = -1;
      if (srcSku.isNotEmpty) {
        final sameSkuIndices = <int>[
          for (var i = 0; i < next.length; i++)
            if (next[i].warehouseId == toWarehouseId &&
                next[i].sku.trim().toLowerCase() == srcSku)
              i,
        ];
        if (sameSkuIndices.length > 1) {
          throw const SaleValidationException('توجد سجلات مكررة لرمز الصنف في مستودع الوجهة.');
        }
        if (sameSkuIndices.length == 1) {
          final candidate = next[sameSkuIndices.single];
          if (candidate.name.trim().toLowerCase() != srcName ||
              candidate.unit.trim().toLowerCase() != srcUnit) {
            throw const SaleValidationException(
                'تعارض في اسم الصنف أو وحدة القياس لنفس الرمز في مستودع الوجهة.');
          }
          dstIdx = sameSkuIndices.single;
        } else {
          final ambiguousUnsubmittedSku = next.any((i) =>
              i.warehouseId == toWarehouseId &&
              i.sku.trim().isEmpty &&
              i.name.trim().toLowerCase() == srcName);
          if (ambiguousUnsubmittedSku) {
            throw const SaleValidationException(
                'يوجد صنف بنفس الاسم دون رمز في مستودع الوجهة؛ حدّد الرمز أولًا لمنع الالتباس.');
          }
        }
      } else {
        final sameNameIndices = <int>[
          for (var i = 0; i < next.length; i++)
            if (next[i].warehouseId == toWarehouseId &&
                next[i].name.trim().toLowerCase() == srcName)
              i,
        ];
        if (sameNameIndices.length > 1) {
          throw const SaleValidationException(
              'توجد عدة أصناف بنفس الاسم في مستودع الوجهة؛ حدّد رمز الصنف لمنع الالتباس.');
        }
        if (sameNameIndices.length == 1) {
          final candidate = next[sameNameIndices.single];
          if (candidate.sku.trim().isNotEmpty ||
              candidate.unit.trim().toLowerCase() != srcUnit) {
            throw const SaleValidationException(
                'تعارض أو التباس في رمز الصنف أو وحدة القياس في مستودع الوجهة.');
          }
          dstIdx = sameNameIndices.single;
        }
      }

      next[srcIdx] = src.copyWith(quantity: src.quantity - quantity);
      if (dstIdx >= 0) {
        final dst = next[dstIdx];
        final totalQty = dst.quantity + quantity;
        final weightedCost = totalQty > 0
            ? (dst.quantity * dst.avgCost + quantity * src.avgCost) / totalQty
            : src.avgCost;
        if (!totalQty.isFinite || !weightedCost.isFinite || totalQty == dst.quantity) {
          throw const SaleValidationException('قيمة التحويل المخزني خارج النطاق.');
        }
        next[dstIdx] = dst.copyWith(quantity: totalQty, avgCost: weightedCost);
      } else {
        next.add(InventoryItemRecord(
          id: 'item_${DateTime.now().microsecondsSinceEpoch}_${next.length}',
          name: src.name,
          sku: src.sku,
          unit: src.unit,
          warehouseId: toWarehouseId,
          quantity: quantity,
          avgCost: src.avgCost,
          minThreshold: src.minThreshold,
        ));
      }
      if (_usesPersistentStore) {
        await _saveCurrentSnapshot(nextInventory: next);
      }
      inventory
        ..clear()
        ..addAll(next);
      if (!_disposed) notifyListeners();
    } finally { _editingWorkspace = false; }
  }

  Future<void> saveWarehouse({String? id, required String name, required String details,
      required bool isDefault}) async {
    _requireAvailableMutation();
    _editingWorkspace = true;
    try {
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) throw const SaleValidationException('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      if (name.trim().isEmpty || name.trim().length > 100 ||
          warehouses.any((w) => w.id != id && w.name.trim() == name.trim())) {
        throw const SaleValidationException('أدخل اسم مخزن صالحًا وغير مكرر.');
      }
      final next = List.of(warehouses);
      final index = next.indexWhere((w) => w.id == id);
      if (id != null && index < 0) throw const SaleValidationException('المخزن غير موجود.');
      final warehouse = WarehouseRecord(id: id ?? 'wh_${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim(), details: details.trim(), isDefault: isDefault || next.isEmpty ||
          (index >= 0 && next[index].isDefault));
      if (warehouse.isDefault) {
        for (var i = 0; i < next.length; i++) {
          final w = next[i];
          if (w.isDefault) next[i] = WarehouseRecord(id: w.id, name: w.name, details: w.details);
        }
      }
      if (index < 0) { next.add(warehouse); } else { next[index] = warehouse; }
      if (_usesPersistentStore) await _saveCurrentSnapshot(nextWarehouses: next);
      warehouses..clear()..addAll(next);
      if (!_disposed) notifyListeners();
    } finally { _editingWorkspace = false; }
  }

  Future<int> postLocalEntry({
    required String accountId,
    required LedgerKind kind,
    String? counterpartId,
    String documentNumber = '',
    required EntryDirection direction,
    required PaymentMethod payment,
    required double amount,
    required CurrencyCode currency,
    CurrencyCode? fromCurrency,
    double exchangeRate = 1,
    String note = '',
    String expenseCategory = '',
  }) async {
    _requireAvailableMutation();
    _editingWorkspace = true;
    try {
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) throw const SaleValidationException('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final account = accounts.where((a) => a.id == accountId).firstOrNull;
      final exchange = kind == LedgerKind.currency;
      final paired = kind == LedgerKind.simpleEntry || kind == LedgerKind.transfer;
      final other = accounts.where((a) => a.id == counterpartId).firstOrNull;
      if (account == null || (!exchange && !paired && kind != LedgerKind.voucher) ||
          (paired && (other == null || other.id == accountId)) ||
          (kind == LedgerKind.simpleEntry && payment != PaymentMethod.balance) ||
          (kind == LedgerKind.transfer && payment != PaymentMethod.cash) ||
          !amount.isFinite || amount <= 0 ||
          !exchangeRate.isFinite || exchangeRate <= 0 ||
          (exchange && (fromCurrency == null || currency == fromCurrency)) ||
          (!exchange && exchangeRate != 1) || payment == PaymentMethod.credit) {
        throw const SaleValidationException('تحقق من الحساب والمبلغ والعملة.');
      }
      final total = amount * exchangeRate;
      if (!total.isFinite || total <= 0) throw const SaleValidationException('المبلغ خارج النطاق.');
      final nextNumber = _nextEntryNumber + 1;
      final label = switch (kind) {
        LedgerKind.currency => direction == EntryDirection.credit ? 'صرف شراء' : 'صرف بيع',
        LedgerKind.transfer => direction == EntryDirection.debit ? 'حوالة صادرة' : 'حوالة واردة',
        LedgerKind.simpleEntry => 'قيد بسيط',
        _ => direction == EntryDirection.credit ? 'له (سند)' : 'عليه (سند)',
      };
      final reference = documentNumber.trim().isEmpty && paired ? 'TX-$nextNumber' : documentNumber.trim();
      final entry = LedgerEntryRecord(
        id: 'local_${DateTime.now().microsecondsSinceEpoch}_$nextNumber',
        accountId: account.id, accountName: account.name,
        kind: kind, typeLabel: label, payment: payment, direction: direction,
        amount: total, currency: currency, exchangeRate: exchangeRate,
        details: [if (exchange) 'صرف $amount ${fromCurrency!.label} بسعر $exchangeRate إلى ${currency.label}',
          if (note.trim().isNotEmpty) note.trim(), if (!exchange && note.trim().isEmpty) label].join(' · '),
        expenseCategory: expenseCategory.trim(),
        entryNumber: nextNumber, entryDate: DateTime.now().toIso8601String().substring(0, 10),
        warehouseId: '', warehouseName: '', documentNumber: reference,
      );
      final postings = [entry];
      if (paired && other != null) {
        postings.add(LedgerEntryRecord(id: '${entry.id}_counter', accountId: other.id, accountName: other.name,
          kind: kind, typeLabel: label, payment: payment,
          direction: direction == EntryDirection.credit ? EntryDirection.debit : EntryDirection.credit,
          amount: total, currency: currency, details: entry.details, documentNumber: reference,
          entryNumber: nextNumber, entryDate: entry.entryDate, warehouseId: '', warehouseName: ''));
      }
      final nextLedger = [...postings, ...ledger];
      if (_usesPersistentStore) await _saveCurrentSnapshot(nextLedger: nextLedger, nextEntryNumber: nextNumber);
      ledger.insertAll(0, postings);
      _nextEntryNumber = nextNumber;
      if (!_disposed) notifyListeners();
      return nextNumber;
    } finally {
      _editingWorkspace = false;
    }
  }

  Future<void> updateCatalogItem(String id,{required String name,required String sku,
      required String unit,required double threshold}) async {
    _requireAvailableMutation();
    _editingWorkspace=true;
    try {
      if(_usesPersistentStore) {
        await initDatabase();
        if(!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final i=inventory.indexWhere((v)=>v.id==id);
      if(i<0 || name.trim().isEmpty || unit.trim().isEmpty || !threshold.isFinite || threshold<0) {
        throw const FormatException('تحقق من اسم الصنف والوحدة وحد التنبيه.');
      }
      final old=inventory[i], code=sku.trim();
      if(code.isNotEmpty && inventory.any((v)=>v.id!=id && v.warehouseId==old.warehouseId &&
        v.sku.toLowerCase()==code.toLowerCase())) throw StateError('الرمز مستخدم في هذا المستودع.');
      final next=List.of(inventory);
      next[i]=InventoryItemRecord(id:id,name:name.trim(),sku:code,unit:unit.trim(),warehouseId:old.warehouseId,
        quantity:old.quantity,avgCost:old.avgCost,minThreshold:threshold);
      if(_usesPersistentStore) await _saveCurrentSnapshot(nextInventory:next);
      inventory..clear()..addAll(next);
      if(!_disposed) notifyListeners();
    } finally { _editingWorkspace=false; }
  }

  Future<int> postPurchaseInvoice({required String accountId,required String warehouseId,
      required PaymentMethod payment,required List<InvoiceItemRow> rows, String reference='',double exchangeRate=1,
      double? freeAmount, String? cashboxAccountId, DateTime? invoiceDate}) async {
    _requireAvailableMutation();
    _editingWorkspace=true;
    final draftRows = [for (final row in rows) InvoiceItemRow(id:row.id, itemId:row.itemId,
        productName:row.productName, quantity:row.quantity, unitPrice:row.unitPrice, discount:row.discount,roundLineTotal:row.roundLineTotal)];
    try {
      if(_usesPersistentStore) {
        await initDatabase();
        if(!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final supplier=accounts.where((a)=>a.id==accountId && a.category==AccountCategory.purchases).firstOrNull;
      final warehouse=warehouses.where((w)=>w.id==warehouseId).firstOrNull;
      if(freeAmount!=null && (!freeAmount.isFinite || freeAmount<=0 || draftRows.isNotEmpty)) {
        throw const FormatException('تحقق من مبلغ الفاتورة الحرة.');
      }
      if(supplier==null || warehouse==null || (draftRows.isEmpty && freeAmount==null)) throw StateError('اختر المورد والمستودع وأضف بنود الفاتورة.');
      final box=accounts.where((a)=>a.id==cashboxAccountId).firstOrNull;
      if(cashboxAccountId!=null && (box==null || !box.isCashAccount || box.currency!=supplier.currency || payment!=PaymentMethod.cash)) {
        throw const FormatException('اختر صندوقًا بعملة المورد.');
      }
      if(payment!=PaymentMethod.credit && payment!=PaymentMethod.cash) throw const FormatException('طريقة دفع غير صالحة.');
      final rate=supplier.currency==defaultCurrency?1.0:exchangeRate;
      if(!rate.isFinite || rate<=0) throw const FormatException('تحقق من سعر الصرف.');
      final prefix = freeAmount == null ? 'purchase' : 'purchase_service';
      final number=_nextEntryNumber+1, id='${prefix}_${DateTime.now().microsecondsSinceEpoch}_$number';
      final stock=List.of(inventory), lines=List.of(saleLines);
      var total=freeAmount??0.0;
      if(freeAmount!=null) lines.add(SavedSaleLine(entryId:id,position:0,itemId:'',itemName:'فاتورة حرة',unit:'خدمة',quantity:1,unitPrice:freeAmount));
      for(final (pos,row) in draftRows.indexed) {
        final i=stock.indexWhere((v)=>v.id==row.itemId && v.warehouseId==warehouseId);
        if(i<0 || !row.quantity.isFinite || row.quantity<=0 || !row.unitPrice.isFinite || row.unitPrice<0 || !row.validDiscount) {
          throw const FormatException('تحقق من الأصناف والكميات والأسعار.');
        }
        final item=stock[i], quantity=item.quantity+row.quantity;
        final cost=item.quantity>0 ? (item.quantity*item.avgCost+row.lineTotal*rate)/quantity : row.netUnitPrice*rate;
        total+=row.lineTotal;
        if(!quantity.isFinite || !cost.isFinite || !total.isFinite || quantity==item.quantity) {
          throw const FormatException('قيمة البند خارج النطاق.');
        }
        stock[i]=item.copyWith(quantity:quantity,avgCost:cost);
        lines.add(SavedSaleLine(entryId:id,position:pos,itemId:item.id,itemName:item.name,
            unit:item.unit,quantity:row.quantity,unitPrice:row.netUnitPrice));
      }
      final entry=LedgerEntryRecord(id:id,accountId:accountId,accountName:supplier.name,kind:LedgerKind.invoice,
        typeLabel:payment==PaymentMethod.cash?'ف.مشتريات نقدية':'ف.مشتريات آجل',payment:payment,
        direction:EntryDirection.credit,amount:total,currency:supplier.currency,exchangeRate:rate,
        details:[if(freeAmount!=null) 'فاتورة حرة',for(final row in draftRows.where((r)=>r.discount>0)) '${row.productName} · ${row.discountNote}'].join('\n'),
        documentNumber:reference.trim().isEmpty?'PUR-$number':reference.trim(),warehouseId:warehouseId,
        warehouseName:warehouse.name,entryNumber:number,entryDate:(invoiceDate ?? DateTime.now()).toIso8601String().substring(0,10));
      final posted=[entry,if(box!=null) ...cashSaleSettlement(entry,cashboxId:box.id,cashboxName:box.name),...ledger];
      if(_usesPersistentStore) await _saveCurrentSnapshot(nextInventory:stock,nextLedger:posted,
        nextSaleLines:lines,nextEntryNumber:number);
      inventory..clear()..addAll(stock);
      ledger..clear()..addAll(posted);
      saleLines..clear()..addAll(lines);
      _nextEntryNumber=number;
      if(!_disposed) notifyListeners();
      return number;
    } finally { _editingWorkspace=false; }
  }

  Iterable<LedgerEntryRecord> get returnablePurchases => ledger.where((entry) =>
      entry.id.startsWith('purchase_') && entry.kind == LedgerKind.invoice && !entry.deleted);

  String _purchaseReturnPrefix(String sourceId) => 'purchase-return/$sourceId/';

  Map<int,double> remainingPurchaseQuantities(String sourceId) {
    final remaining = {for (final l in saleLines.where((l) => l.entryId == sourceId))
      l.position: l.quantity};
    final prefix = _purchaseReturnPrefix(sourceId);
    for (final l in saleLines.where((l) => l.entryId.startsWith(prefix))) {
      remaining.update(l.position, (q) => SavedSaleLine.sameQuantity(q,l.quantity) ? 0.0 : q - l.quantity);
    }
    return remaining;
  }

  Future<int> postPurchaseReturn({required String sourceId, required String requestId,
      required Map<int,double> quantities}) async {
    _requireAvailableMutation();
    _editingWorkspace = true;
    final requested = Map<int,double>.of(quantities);
    try {
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) throw StateError('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final source = returnablePurchases.where((e) => e.id == sourceId).firstOrNull;
      final id = '${_purchaseReturnPrefix(sourceId)}$requestId';
      if (source == null || requested.isEmpty || !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(requestId)) {
        throw const FormatException('اختر فاتورة شراء وبنودًا صالحة.');
      }
      if (ledger.any((e) => e.id == id)) throw StateError('سبق ترحيل المردود.');
      final remaining = remainingPurchaseQuantities(sourceId);
      final originals = {for (final l in saleLines.where((l) => l.entryId == sourceId)) l.position:l};
      final stock = List.of(inventory), lines = List.of(saleLines);
      var total = 0.0;
      for (final selection in requested.entries) {
        final requestedQty = selection.value, line = originals[selection.key];
        final available = remaining[selection.key] ?? 0;
        final qty = SavedSaleLine.sameQuantity(requestedQty, available) ? available : requestedQty;
        if (line == null || !requestedQty.isFinite || qty <= 0 || qty > available) {
          throw const FormatException('تجاوزت كمية المردود المتبقي في الفاتورة.');
        }
        if (line.itemId.isNotEmpty) {
          final index = stock.indexWhere((i) => i.id == line.itemId && i.warehouseId == source.warehouseId);
          if (index < 0 || (qty > stock[index].quantity && !SavedSaleLine.sameQuantity(qty,stock[index].quantity))) {
            throw const FormatException('كمية المستودع لا تكفي للمردود.');
          }
          final balance = stock[index].quantity - qty;
          stock[index] = stock[index].copyWith(quantity: balance < 0 ? 0 : balance);
        }
        final priorQuantity = line.quantity - remaining[selection.key]!;
        final value = SavedSaleLine.returnedValue(line.quantity, line.unitPrice, priorQuantity, qty);
        total += value;
        lines.add(SavedSaleLine(entryId:id,position:line.position,itemId:line.itemId,
            itemName:line.itemName,unit:line.unit,quantity:qty,unitPrice:value/qty));
      }
      if (!total.isFinite) throw const FormatException('مبلغ المردود خارج النطاق.');
      final number = _nextEntryNumber + 1;
      final entry = LedgerEntryRecord(id:id,accountId:source.accountId,accountName:source.accountName,
          kind:LedgerKind.returnEntry,typeLabel:'مردود شراء',payment:source.payment,
          direction:EntryDirection.debit,amount:total,currency:source.currency,exchangeRate:source.exchangeRate,
          documentNumber:source.documentNumber,warehouseId:source.warehouseId,warehouseName:source.warehouseName,
          entryNumber:number,entryDate:DateTime.now().toIso8601String().substring(0,10));
      final box = ledger.where((e) => e.id == '${source.id}/cashbox').firstOrNull;
      if (box != null && (box.deleted || !isCashSaleSettlement(box) || box.direction != EntryDirection.credit ||
          box.currency != source.currency || box.amount != source.amount)) {
        throw StateError('تعذر التحقق من سداد الفاتورة النقدية.');
      }
      final posted = [entry, if(box!=null) ...cashSaleSettlement(entry,cashboxId:box.accountId,cashboxName:box.accountName), ...ledger];
      if (_usesPersistentStore) await _saveCurrentSnapshot(nextInventory:stock, nextLedger:posted,
          nextSaleLines:lines, nextEntryNumber:number);
      inventory..clear()..addAll(stock);
      ledger..clear()..addAll(posted);
      saleLines..clear()..addAll(lines);
      _nextEntryNumber = number;
      if (!_disposed) notifyListeners();
      return number;
    } finally { _editingWorkspace = false; }
  }

  Future<void> receiveStock({
    String? existingId,
    required double quantity,
    String name = '',
    String sku = '',
    String unit = '',
    String warehouseId = '',
    double avgCost = 0,
    double threshold = 25,
  }) async {
    _requireAvailableMutation();
    _editingWorkspace = true;
    try {
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) throw const SaleValidationException('قاعدة البيانات غير جاهزة.');
        await _writeTail;
      }
      final next = List<InventoryItemRecord>.of(inventory);
      if (!quantity.isFinite || quantity < 0) {
        throw const SaleValidationException('أدخل كمية صالحة.');
      }
      if (existingId != null) {
        final index = next.indexWhere((item) => item.id == existingId);
        if (index < 0 || quantity <= 0) throw const SaleValidationException('تحقق من الصنف والكمية.');
        final total = next[index].quantity + quantity;
        if (!total.isFinite || total == next[index].quantity) {
          throw const SaleValidationException('الكمية خارج النطاق.');
        }
        next[index] = next[index].copyWith(quantity: total);
      } else {
        if (name.trim().isEmpty || unit.trim().isEmpty ||
            !warehouses.any((w) => w.id == warehouseId) ||
            !avgCost.isFinite || avgCost < 0 || !threshold.isFinite || threshold < 0) {
          throw const SaleValidationException('تحقق من الاسم والوحدة والمستودع والتكلفة.');
        }
        if (sku.trim().isNotEmpty && next.any((i) => i.warehouseId == warehouseId &&
            i.sku.toLowerCase() == sku.trim().toLowerCase())) {
          throw const SaleValidationException('رمز الصنف مسجل في هذا المستودع.');
        }
        next.add(InventoryItemRecord(id: 'item_${DateTime.now().microsecondsSinceEpoch}',
          name: name.trim(), sku: sku.trim(), unit: unit.trim(), warehouseId: warehouseId,
          quantity: quantity, avgCost: avgCost, minThreshold: threshold));
      }
      if (_usesPersistentStore) await _saveCurrentSnapshot(nextInventory: next);
      inventory..clear()..addAll(next);
      if (!_disposed) notifyListeners();
    } finally {
      _editingWorkspace = false;
    }
  }

  void toggleTheme() {
    _requireAvailableMutation();
    isDarkMode = !isDarkMode;
    unawaited(_persistToDb());
    notifyListeners();
  }

  AccountRecord addCustomer({
    required String name,
    String phone = '',
    String note = '',
  }) {
    _requireAvailableMutation();
    final acc = AccountRecord(
      id: 'acc_client_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      category: AccountCategory.clients,
      phone: phone.trim(),
      note: note.trim(),
      currency: defaultCurrency,
      codeNumber: 1200 + accounts.length + 1,
    );
    accounts.insert(0, acc);
    unawaited(_persistToDb());
    notifyListeners();
    return acc;
  }

  String _invoiceReferenceKey(String value) =>
      value.trim().toUpperCase().replaceAllMapped(RegExp('[٠-٩۰-۹]'), (match) {
        final code = match[0]!.codeUnitAt(0);
        return (code - (code >= 0x06f0 ? 0x06f0 : 0x0660)).toString();
      });

  Future<void> submitSalesInvoice({
    required String accountId,
    required String customerName,
    required WarehouseRecord warehouse,
    required PaymentMethod payment,
    required bool includeVat,
    required List<InvoiceItemRow> rows,
    String? cashboxAccountId,
    double? freeAmount,
    DateTime? invoiceDate,
    ValueChanged<String>? onCommitted,
    String documentNumber = '',
    String memo = '',
  }) async {
    _requireAvailableMutation();
    _salesPosting = true;
    try {
      final reference = documentNumber.trim();
      final description = memo.trim();
      if (reference.isNotEmpty &&
          (!RegExp(r'^[A-Za-z0-9ء-ي٠-٩۰-۹][A-Za-z0-9ء-ي٠-٩۰-۹._/-]{0,31}$')
                  .hasMatch(reference) ||
              reference.toUpperCase().startsWith('INV-'))) {
        throw const SaleValidationException(
            'رقم الفاتورة غير صالح. استخدم حتى 32 رمزًا من الحروف أو الأرقام أو . _ / -، وتجنب INV-.');
      }
      if (description.length > 240 ||
          RegExp(r'[\x00-\x1f\x7f-\x9f\u061c\u200e\u200f\u2028-\u202e\u2066-\u2069]')
              .hasMatch(description)) {
        throw const SaleValidationException(
            'البيان يجب أن يكون سطرًا واحدًا حتى 240 حرفًا.');
      }
      // The draft is mutable; snapshot its fields before an async boundary.
      final isFree = freeAmount != null;
      if (freeAmount != null && (rows.isNotEmpty || !freeAmount.isFinite || freeAmount <= 0)) {
        throw const SaleValidationException('أدخل مبلغًا موجبًا للفاتورة الحرة دون أصناف.');
      }
      final draftRows = [
        if (freeAmount != null) InvoiceItemRow(id:'service', itemId:'', productName:'فاتورة حرة', quantity:1, unitPrice:freeAmount),
        for (final row in rows)
          InvoiceItemRow(
            id: row.id,
            itemId: row.itemId,
            productName: row.productName,
            quantity: row.quantity,
            unitPrice: row.unitPrice,
            discount: row.discount,
            roundLineTotal: row.roundLineTotal,
          ),
      ];
      if (_usesPersistentStore) {
        await initDatabase();
        if (!dbReady) {
          throw const SaleValidationException(
              'قاعدة البيانات المحلية غير جاهزة.');
        }
        await _writeTail;
      }
      final cashbox = accounts.where((a) => a.id == cashboxAccountId).firstOrNull;
      if (cashboxAccountId != null && (payment != PaymentMethod.cash ||
          cashbox == null || !cashbox.isCashAccount || cashbox.currency != defaultCurrency)) {
        throw const SaleValidationException('اختر صندوقًا نقديًا بعملة الفاتورة.');
      }
      final referenceKey = _invoiceReferenceKey(reference);
      if (referenceKey.isNotEmpty &&
          ledger.any((entry) =>
              _invoiceReferenceKey(entry.documentNumber) == referenceKey)) {
        throw const SaleValidationException('رقم الفاتورة مستخدم بالفعل.');
      }
      if (!accounts.any((account) => account.id == accountId) ||
          !warehouses.any((store) => store.id == warehouse.id) ||
          customerName.trim().isEmpty) {
        throw const SaleValidationException('اختر حسابًا ومستودعًا صالحين.');
      }
      if (draftRows.isEmpty) {
        throw const SaleValidationException('أضف صنفًا واحدًا على الأقل.');
      }
      final indexed = {
        for (var i = 0; i < inventory.length; i++) inventory[i].id: i
      };
      final demand = <String, double>{};
      for (final row in draftRows) {
        if (isFree) continue;
        final idx = indexed[row.itemId];
        if (idx == null || inventory[idx].warehouseId != warehouse.id) {
          throw const SaleValidationException(
              'اختر أصنافًا من المستودع المحدد.');
        }
        if (!row.quantity.isFinite ||
            row.quantity <= 0 ||
            !row.unitPrice.isFinite ||
            row.unitPrice < 0 || !row.validDiscount) {
          throw const SaleValidationException('تحقق من الكمية والسعر لكل بند.');
        }
        final id = inventory[idx].id;
        demand.update(id, (qty) => qty + row.quantity,
            ifAbsent: () => row.quantity);
      }
      const tolerance = 1e-9;
      for (final entry in demand.entries) {
        final item = inventory[indexed[entry.key]!];
        if (!entry.value.isFinite ||
            !item.quantity.isFinite ||
            item.quantity < 0 ||
            entry.value - item.quantity > tolerance) {
          throw SaleValidationException('الكمية غير كافية للصنف: ${item.name}');
        }
      }

      final subtotal = draftRows.fold<double>(0, (s, r) => s + r.lineTotal);
      const existingVatPercent = 15.0;
      final taxBeforeRound = subtotal * existingVatPercent;
      if (!subtotal.isFinite ||
          (includeVat &&
              (!taxBeforeRound.isFinite ||
                  taxBeforeRound > 9007199254740991 ||
                  !(subtotal + subtotal * (existingVatPercent / 100))
                      .isFinite))) {
        throw const SaleValidationException('إجمالي الفاتورة غير صالح.');
      }
      final vatAmount = includeVat ? taxBeforeRound.roundToDouble() / 100 : 0.0;
      final grandTotal = subtotal + vatAmount;
      final stagedInventory = List<InventoryItemRecord>.of(inventory);
      for (final entry in demand.entries) {
        final idx = indexed[entry.key]!;
        final item = inventory[idx];
        final remaining = item.quantity - entry.value;
        stagedInventory[idx] =
            item.copyWith(quantity: remaining < 0 ? 0 : remaining);
      }

      final details = [
        if (description.isNotEmpty) 'بيان الفاتورة: $description',
        for (final r in draftRows.where((r) => r.discount > 0)) '${r.productName} · ${r.discountNote}',
        ...draftRows.map((r) =>
            '${r.productName} | ${r.quantity} × ${AccountingEngine.formatAmount(r.unitPrice)}'),
        if (includeVat)
          'ضريبة القيمة المضافة 15%: ${AccountingEngine.formatAmount(vatAmount)}',
      ].join('\n');

      final entryNum = _nextEntryNumber + 1;
      final prefix = isFree ? 'service-sale' : draftRows.any((r)=>r.discount>0) ? 'discount-sale' : 'led';
      final entryId = '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$entryNum';
      final postedCurrency = defaultCurrency;
      final stagedCosts = <SaleLineCostFact>[];
      final stagedLines = List<SavedSaleLine>.of(saleLines);
      for (var pos = 0; pos < draftRows.length; pos++) {
        final row = draftRows[pos];
        final item = isFree ? null : inventory[indexed[row.itemId]!];
        stagedCosts.add(SaleLineCostFact(
          position: pos,
          stockAverageCost:
              item != null && item.avgCost.isFinite && item.avgCost >= 0 ? item.avgCost : null,
        ));
        stagedLines.add(SavedSaleLine(
          entryId: entryId,
          position: pos,
          itemId: item?.id ?? '',
          itemName: item?.name ?? 'فاتورة حرة',
          unit: item?.unit ?? 'خدمة',
          quantity: row.quantity,
          unitPrice: row.netUnitPrice,
        ));
      }
      final stagedLedger = List<LedgerEntryRecord>.of(ledger);
      stagedLedger.insert(
        0,
        LedgerEntryRecord(
          id: entryId,
          accountId: accountId,
          accountName: customerName,
          kind: LedgerKind.invoice,
          typeLabel:
              payment == PaymentMethod.cash ? 'ف.مبيعات نقدية' : 'ف.مبيعات آجل',
          payment: payment,
          direction: EntryDirection.debit,
          amount: grandTotal,
          currency: postedCurrency,
          details: details,
          documentNumber: reference.isEmpty ? 'INV-$entryNum' : reference,
          warehouseId: warehouse.id,
          warehouseName: warehouse.name,
          entryNumber: entryNum,
          entryDate: (invoiceDate ?? DateTime.now()).toIso8601String().substring(0, 10),
        ),
      );
      if (cashbox != null) {
        stagedLedger.insertAll(1, cashSaleSettlement(stagedLedger.first,
            cashboxId: cashbox.id, cashboxName: cashbox.name));
      }
      if (_usesPersistentStore) {
        try {
          await _saveCurrentSnapshot(
            nextLedger: stagedLedger,
            nextInventory: stagedInventory,
            nextSaleLines: stagedLines,
            nextEntryNumber: entryNum,
            appendedSaleFacts: SaleFacts(
              entryId: entryId,
              currency: postedCurrency,
              preTaxTotal: subtotal,
              taxEnabled: includeVat,
              appliedTaxRate: includeVat ? existingVatPercent / 100 : 0,
              taxAmount: vatAmount,
              finalTotal: grandTotal,
              lineCosts: stagedCosts,
            ),
          );
        } catch (_) {
          throw const SaleValidationException(
              'تعذر تأكيد حفظ الفاتورة في SQLite. بقيت بيانات المسودة.');
        }
      }
      inventory
        ..clear()
        ..addAll(stagedInventory);
      saleLines
        ..clear()
        ..addAll(stagedLines);
      ledger
        ..clear()
        ..addAll(stagedLedger);
      _nextEntryNumber = entryNum;
      onCommitted?.call(entryId);
      if (!_disposed) notifyListeners();
    } finally {
      _salesPosting = false;
    }
  }

  void createDeal({
    required String title,
    required AccountRecord client,
    required double value,
  }) {
    _requireAvailableMutation();
    deals.insert(
      0,
      ErpDealRecord(
        id: 'deal_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        clientAccountId: client.id,
        clientName: client.name,
        value: value,
        currency: defaultCurrency,
        expectedCloseDate: DateTime.now().toIso8601String().substring(0, 10),
        assignedTo:
            employees.isNotEmpty ? employees.first.name : 'فريق المبيعات',
      ),
    );
    unawaited(_persistToDb());
    notifyListeners();
  }

  void advanceDeal(String dealId) {
    _requireAvailableMutation();
    final idx = deals.indexWhere((d) => d.id == dealId);
    if (idx < 0) return;
    final d = deals[idx];
    final next = switch (d.stage) {
      ErpDealStage.lead => ErpDealStage.proposal,
      ErpDealStage.proposal => ErpDealStage.negotiation,
      ErpDealStage.negotiation => ErpDealStage.won,
      _ => null,
    };
    if (next == null) return;
    deals[idx] = d.copyWith(stage: next, probability: next.defaultProbability);
    unawaited(_persistToDb());
    notifyListeners();
  }

  void convertDealToInvoice(String dealId) {
    _requireAvailableMutation();
    final idx = deals.indexWhere((d) => d.id == dealId);
    if (idx < 0) return;
    final deal = deals[idx];
    if (deal.convertedInvoiceEntryId != null) return;

    final entryNum = ++_nextEntryNumber;
    final entryId = 'led_${DateTime.now().millisecondsSinceEpoch}';
    ledger.insert(
      0,
      LedgerEntryRecord(
        id: entryId,
        accountId: deal.clientAccountId,
        accountName: deal.clientName,
        kind: LedgerKind.invoice,
        typeLabel: 'فاتورة مبيعات (CRM)',
        payment: PaymentMethod.credit,
        direction: EntryDirection.debit,
        amount: deal.value,
        currency: deal.currency,
        details: 'تحويل صفقة: ${deal.title}',
        documentNumber: 'CRM-$entryNum',
        entryNumber: entryNum,
        entryDate: DateTime.now().toIso8601String().substring(0, 10),
      ),
    );
    deals[idx] = deal.copyWith(
      stage: ErpDealStage.won,
      probability: 100,
      convertedInvoiceEntryId: entryId,
    );
    unawaited(_persistToDb());
    notifyListeners();
  }

  void addEmployee({
    required String name,
    required String roleTitle,
    required String department,
    required double basicSalary,
    required double allowances,
    required double deductions,
  }) {
    _requireAvailableMutation();
    employees.insert(
      0,
      ErpEmployeeProfile(
        id: 'emp_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        roleTitle: roleTitle,
        department: department,
        basicSalary: basicSalary,
        allowances: allowances,
        deductions: deductions,
        hireDate: DateTime.now().toIso8601String().substring(0, 10),
      ),
    );
    unawaited(_persistToDb());
    notifyListeners();
  }

  void postPayrollToGl() {
    _requireAvailableMutation();
    final total = AccountingEngine.computeTotalNetPayroll(employees);
    if (total <= 0) return;
    final empAcc = accounts.firstWhere(
      (a) => a.category == AccountCategory.employees,
      orElse: () => accounts.first,
    );
    final entryNum = ++_nextEntryNumber;
    ledger.insert(
      0,
      LedgerEntryRecord(
        id: 'led_${DateTime.now().millisecondsSinceEpoch}',
        accountId: empAcc.id,
        accountName: empAcc.name,
        kind: LedgerKind.voucher,
        typeLabel: 'ترحيل مسير الرواتب',
        payment: PaymentMethod.cash,
        direction: EntryDirection.debit,
        amount: total,
        details: 'مسير رواتب ${employees.length} موظفين',
        expenseCategory: 'رواتب وأجور',
        entryNumber: entryNum,
        entryDate: DateTime.now().toIso8601String().substring(0, 10),
      ),
    );
    unawaited(_persistToDb());
    notifyListeners();
  }

  void decideLeave(String leaveId, LeaveStatus status) {
    _requireAvailableMutation();
    final idx = leaveRequests.indexWhere((l) => l.id == leaveId);
    if (idx < 0 || leaveRequests[idx].status != LeaveStatus.pending) return;
    final lv = leaveRequests[idx];
    leaveRequests[idx] = lv.copyWith(status: status);
    if (status == LeaveStatus.approved) {
      final empIdx = employees.indexWhere((e) => e.id == lv.employeeId);
      if (empIdx >= 0) {
        final emp = employees[empIdx];
        employees[empIdx] = emp.copyWith(
          leaveBalanceDays: (emp.leaveBalanceDays - lv.days).clamp(0, 999),
          attendanceToday: AttendanceStatus.leave,
        );
      }
    }
    unawaited(_persistToDb());
    notifyListeners();
  }

  void createPurchaseOrder({
    required AccountRecord supplier,
    required WarehouseRecord warehouse,
    required InventoryItemRecord item,
    required double quantity,
    required double unitCost,
  }) {
    _requireAvailableMutation();
    final numCode = 101 + purchaseOrders.length;
    purchaseOrders.insert(
      0,
      ErpPurchaseOrder(
        id: 'po_${DateTime.now().millisecondsSinceEpoch}',
        poNumber: 'PO-2026-$numCode',
        supplierAccountId: supplier.id,
        supplierName: supplier.name,
        warehouseId: warehouse.id,
        warehouseName: warehouse.name,
        orderDate: DateTime.now().toIso8601String().substring(0, 10),
        expectedDate: DateTime.now().toIso8601String().substring(0, 10),
        status: PurchaseOrderStatus.approved,
        lines: [
          ErpPurchaseOrderLine(
            inventoryItemId: item.id,
            itemName: item.name,
            unit: item.unit,
            quantity: quantity,
            unitCost: unitCost,
          ),
        ],
      ),
    );
    unawaited(_persistToDb());
    notifyListeners();
  }

  void receivePurchaseOrder(String poId) {
    _requireAvailableMutation();
    final idx = purchaseOrders.indexWhere((p) => p.id == poId);
    if (idx < 0) return;
    final po = purchaseOrders[idx];
    if (po.status == PurchaseOrderStatus.received) return;

    for (final line in po.lines) {
      if (line.inventoryItemId == null) continue;
      final invIdx = inventory.indexWhere((i) => i.id == line.inventoryItemId);
      if (invIdx >= 0) {
        final item = inventory[invIdx];
        final nextCost = AccountingEngine.computeWeightedAverageCost(
          item.quantity,
          item.avgCost,
          line.quantity,
          line.unitCost,
        );
        inventory[invIdx] = item.copyWith(
          quantity: item.quantity + line.quantity,
          avgCost: nextCost,
        );
      }
    }

    final total = AccountingEngine.computePurchaseOrderTotal(po);
    final entryNum = ++_nextEntryNumber;
    final entryId = 'led_${DateTime.now().millisecondsSinceEpoch}';
    ledger.insert(
      0,
      LedgerEntryRecord(
        id: entryId,
        accountId: po.supplierAccountId,
        accountName: po.supplierName,
        kind: LedgerKind.invoice,
        typeLabel: 'ف.مشتريات (استلام PO)',
        payment: PaymentMethod.credit,
        direction: EntryDirection.credit,
        amount: total,
        details: 'استلام أمر شراء ${po.poNumber}',
        documentNumber: po.poNumber,
        warehouseId: po.warehouseId,
        warehouseName: po.warehouseName,
        entryNumber: entryNum,
        entryDate: DateTime.now().toIso8601String().substring(0, 10),
      ),
    );
    purchaseOrders[idx] = po.copyWith(
      status: PurchaseOrderStatus.received,
      postedLedgerEntryId: entryId,
    );
    unawaited(_persistToDb());
    notifyListeners();
  }

  String? completeProductionOrder(String orderId) {
    if (_salesPosting || _resetting || _editingWorkspace) {
      return 'توجد عملية حفظ جارية؛ حاول مجددًا.';
    }
    final idx = productionOrders.indexWhere((o) => o.id == orderId);
    if (idx < 0) return 'الأمر غير موجود';
    final order = productionOrders[idx];
    if (order.status == ProductionOrderStatus.completed) return null;

    final bom = boms.firstWhere((b) => b.id == order.bomId);
    for (final comp in bom.components) {
      final raw = inventory.firstWhere((i) => i.id == comp.inventoryItemId);
      final req = comp.quantityPerUnit * order.quantityToProduce;
      if (raw.quantity < req) {
        return 'نقص في الخامة: ${comp.itemName}';
      }
    }

    for (final comp in bom.components) {
      final invIdx = inventory.indexWhere((i) => i.id == comp.inventoryItemId);
      if (invIdx >= 0) {
        final raw = inventory[invIdx];
        inventory[invIdx] = raw.copyWith(
          quantity:
              raw.quantity - (comp.quantityPerUnit * order.quantityToProduce),
        );
      }
    }

    final fgIdx = inventory.indexWhere((i) => i.id == order.finishedItemId);
    if (fgIdx >= 0) {
      final fg = inventory[fgIdx];
      inventory[fgIdx] =
          fg.copyWith(quantity: fg.quantity + order.quantityToProduce);
    }

    productionOrders[idx] = order.copyWith(
      status: ProductionOrderStatus.completed,
      completedDate: DateTime.now().toIso8601String().substring(0, 10),
    );
    unawaited(_persistToDb());
    notifyListeners();
    return null;
  }
}
