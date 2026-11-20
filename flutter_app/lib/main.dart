import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/dashboard_screen.dart';
import 'screens/account_tools.dart';
import 'screens/account_groups_view.dart';
import 'screens/purchase_invoice_view.dart';
import 'screens/stock_scanner_view.dart';
import 'screens/home_navigation.dart';
import 'screens/local_report_detail.dart';
import 'screens/local_entry_view.dart';
import 'screens/customer_list_sheet.dart';
import 'screens/invoice_form_sheet.dart';
import 'screens/nasqo_web_drawer.dart';
import 'screens/nasqo_brand_mark.dart';
import 'screens/erp_hub_screen.dart';
import 'screens/finance_screen.dart';
import 'screens/hr_screen.dart';
import 'screens/manufacturing_screen.dart';
import 'screens/pos_crm_screen.dart';
import 'screens/procurement_screen.dart';
import 'screens/workspace_views.dart';
import 'screens/local_backup_workspace_view.dart';
import 'screens/local_db_startup_view.dart';
import 'screens/home_lookup_views.dart';
import 'screens/home_account_views.dart';
import 'screens/home_warehouse_view.dart';
import 'screens/home_summary_views.dart';
import 'screens/sale_tax_register_view.dart';
import 'screens/home_sales_register_view.dart';
import 'screens/nonposting_document_views.dart';
import 'screens/home_directory_views.dart';
import 'models/nonposting_document.dart';
import 'models/sales_return_draft.dart';
import 'models/erp_models.dart';
import 'models/voucher_draft.dart';
import 'screens/voucher_draft_views.dart';
import 'screens/cash_transfer_draft_views.dart';
import 'screens/simple_journal_draft_views.dart';
import 'screens/fx_draft_views.dart';
import 'screens/sales_return_views.dart';
import 'screens/customer_measurement_views.dart';
import 'screens/cash_supplier_statement_view.dart';
import 'services/customer_measurement_repository.dart';
import 'state/erp_controller.dart';

void main() {
  runApp(const NasqoProErpApp());
}

class NasqoProErpApp extends StatefulWidget {
  const NasqoProErpApp({super.key, this.controller});

  /// When provided (for example, by a test), the caller owns its lifecycle.
  final ErpController? controller;

  @override
  State<NasqoProErpApp> createState() => _NasqoProErpAppState();
}

class _NasqoProErpAppState extends State<NasqoProErpApp> {
  ErpController? _ownedController;

  ErpController get _controller =>
      widget.controller ?? (_ownedController ??= ErpController());

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final colorScheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF4338CA),
          primary: _controller.isDarkMode ? const Color(0xFFB9B4FF) : const Color(0xFF4338CA),
          secondary: const Color(0xFF0891B2),
          brightness:
              _controller.isDarkMode ? Brightness.dark : Brightness.light,
        );

        return MaterialApp(
          title: 'نسقو برو ERP',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: colorScheme,
            scaffoldBackgroundColor: _controller.isDarkMode ? null : const Color(0xFFF5F7FF),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF4338CA),
              foregroundColor: Colors.white,
              centerTitle: false,
            ),
          ),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: _controller.requiresLocalDatabase && !_controller.dbReady
                ? LocalDbStartupView(
                    diagnosticCode: _controller.localDatabaseDiagnostic,
                    retry: _controller.initDatabase,
                  )
                : NasqoMainShell(controller: _controller),
          ),
        );
      },
    );
  }
}

class NasqoMainShell extends StatefulWidget {
  const NasqoMainShell({super.key, required this.controller});
  final ErpController controller;

  @override
  State<NasqoMainShell> createState() => _NasqoMainShellState();
}

class _NasqoMainShellState extends State<NasqoMainShell> {
  final _shellKey = GlobalKey<ScaffoldState>();
  final _homeScroll = ScrollController();
  String? _activeModule;

  @override
  void dispose() {
    _homeScroll.dispose();
    super.dispose();
  }

  Future<void> _quickActions() async {
    final route = await showHomeQuickActions(context);
    if (!mounted || route == null) return;
    if (route == 'invoice') {
      _openInvoice();
    } else {
      _openModulePage(route);
    }
  }

  Widget _documents(NonpostingDocumentType type, {bool createOnOpen = false}) {
    final controller = widget.controller;
    return NonpostingDocumentsView(
      type: type,
      createOnOpen: createOnOpen,
      initialCurrency: controller.defaultCurrency,
      loadDocuments: () => controller.loadNonpostingDocuments(type),
      loadDocument: (id) => controller.loadNonpostingDocument(type, id),
      saveDocument: controller.saveNonpostingDocument,
    );
  }

  Future<List<SalesReturnSource>> _salesReturnSources() async {
    final controller = widget.controller;
    await controller.initDatabase();
    final linesByEntry = <String, List<SavedSaleLine>>{};
    for (final line in controller.saleLines) {
      (linesByEntry[line.entryId] ??= []).add(line);
    }
    return [
      for (final entry in controller.ledger)
        if (isEligibleSalesReturnSource(entry) &&
            linesByEntry.containsKey(entry.id))
          SalesReturnSource(entry: entry, lines: linesByEntry[entry.id]!),
    ];
  }

  Widget _voucherDrafts(VoucherDraftType type) => VoucherDraftsView(
        type: type,
        loadDrafts: () => widget.controller.loadVoucherDrafts(type),
        loadDraft: widget.controller.loadVoucherDraft,
        loadAccounts: widget.controller.loadVoucherAccounts,
        saveDraft: widget.controller.saveVoucherDraft,
        initialCurrency: widget.controller.defaultCurrency,
      );

  void _openModulePage(String moduleId) {
    if (moduleId == 'measurement-new') {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => CustomerMeasurementFormSheet(
          repository:
              CustomerMeasurementRepository(widget.controller.database),
          onSaved: () {},
        ),
      );
      return;
    }
    if (_activeModule == moduleId) return;
    final category = AccountCategory.values.where((c) => moduleId == 'group-${c.name}').firstOrNull;
    final (title, Widget page) = switch (moduleId) {
      _ when category != null => (category.label, HomeAccountsView(
        controller: widget.controller, category: category, onOpenModule: _openModulePage)),
      'measurements' => (
          'التمييز والمقاسات',
          CustomerMeasurementsView(controller: widget.controller),
        ),
      'cash-statement' => (
          'كشف حساب المورد النقدي',
          CashSupplierStatementView(
            controller: widget.controller,
            account: widget.controller.accounts.firstWhere(
              (a) => a.isCashAccount || a.category == AccountCategory.purchases,
              orElse: () => widget.controller.accounts.isNotEmpty
                  ? widget.controller.accounts.first
                  : const AccountRecord(
                      id: 'cash-supp-default',
                      name: 'المورد النقدي العام',
                      category: AccountCategory.purchases,
                      phone: '',
                      creditLimit: 0,
                      currency: CurrencyCode.sar,
                      isCashAccount: true,
                      note: '',
                      openingBalance: 0,
                      openingDirection: EntryDirection.debit,
                      codeNumber: 101,
                    ),
            ),
            onOpenModule: _openModulePage,
          ),
        ),
      'vouchers' => (
          'مسودات السندات',
          ListView(padding: const EdgeInsets.all(16), children: [
            const Text('مسودات محلية لا تحرّك الصندوق ولا ترحّل إلى الحسابات.'),
            ListTile(
              key: const ValueKey('open-receipt-drafts'),
              title: const Text('مسودات سند قبض'),
              onTap: () => _openModulePage('receipt-drafts'),
            ),
            ListTile(
              key: const ValueKey('open-payment-drafts'),
              title: const Text('مسودات سند صرف'),
              onTap: () => _openModulePage('payment-drafts'),
            ),
          ]),
        ),
      'receipt-drafts' => (
          'مسودات سند قبض',
          _voucherDrafts(VoucherDraftType.receipt)
        ),
      'payment-drafts' => (
          'مسودات سند صرف',
          _voucherDrafts(VoucherDraftType.payment)
        ),
      'cash-transfer-drafts' => (
          'مسودات التحويل الداخلي',
          CashTransferDraftsView(
            loadDrafts: widget.controller.loadCashTransferDrafts,
            loadDraft: widget.controller.loadCashTransferDraft,
            loadAccounts: widget.controller.loadVoucherAccounts,
            saveDraft: widget.controller.saveCashTransferDraft,
            initialCurrency: widget.controller.defaultCurrency,
          ),
        ),
      'simple-journal-drafts' => (
          'مسودات القيد البسيط',
          SimpleJournalDraftsView(
            loadDrafts: widget.controller.loadSimpleJournalDrafts,
            loadDraft: widget.controller.loadSimpleJournalDraft,
            loadAccounts: widget.controller.loadVoucherAccounts,
            saveDraft: widget.controller.saveSimpleJournalDraft,
            initialCurrency: widget.controller.defaultCurrency,
          ),
        ),
      'fx-drafts' => (
          'مسودات صرف العملات',
          FxDraftsView(
            loadDrafts: widget.controller.loadFxDrafts,
            loadDraft: widget.controller.loadFxDraft,
            loadAccounts: widget.controller.loadVoucherAccounts,
            saveDraft: widget.controller.saveFxDraft,
          ),
        ),
      'purchase-register' => ('سجل فواتير المشتريات',PurchasesRegister(controller:widget.controller,
          openNew:()=>_openModulePage('purchase-new'))),
      'purchase-new' => ('فاتورة مشتريات جديدة',PurchaseInvoiceView(controller:widget.controller)),
      'group-directory' => ('إدارة مجموعات الحسابات',AccountGroupsView(controller:widget.controller)),
      'account-new' => ('إضافة حساب',AccountEditor(controller:widget.controller)),
      'account-import' => ('استيراد الحسابات',AccountImportView(controller:widget.controller)),
      'message-settings' => ('إعدادات إشعارات واتساب',MessageSettingsView(controller:widget.controller)),
      'accounts' => (
          'جميع الحسابات',
          ListView(
            padding: const EdgeInsets.all(12),
            children: [GroupBalancesPanel(controller: widget.controller)],
          )
        ),
      'quotes' || 'quote-new' => (
          'عروض الأسعار',
          _documents(NonpostingDocumentType.quote,
              createOnOpen: moduleId == 'quote-new'),
        ),
      'orders' || 'order-new' => (
          'طلبيات البيع',
          _documents(NonpostingDocumentType.order,
              createOnOpen: moduleId == 'order-new'),
        ),
      'sales-return-drafts' => (
          'مسودات مرتجع المبيعات',
          SalesReturnDraftsView(
            loadDrafts: widget.controller.loadSalesReturnDrafts,
            loadDraft: widget.controller.loadSalesReturnDraft,
            loadSales: _salesReturnSources,
            loadFacts: widget.controller.loadOriginalSaleFacts,
            saveDraft: widget.controller.saveSalesReturnDraft,
            postDraft: widget.controller.postSalesReturn,
          )
        ),
      'chart-accounts' => (
          'دليل الحسابات',
          HomeChartOfAccountsView(controller: widget.controller),
        ),
      'trash' => (
          'سلة المحذوفات',
          HomeTrashView(controller: widget.controller),
        ),
      'post-voucher' || 'post-exchange' || 'post-journal' || 'post-transfer' => ('عملية جديدة', LocalEntryView(
        controller: widget.controller, kind: switch (moduleId) { 'post-exchange' => LedgerKind.currency, 'post-journal' => LedgerKind.simpleEntry, 'post-transfer' => LedgerKind.transfer, _ => LedgerKind.voucher },
        openDrafts: () => _openModulePage(switch (moduleId) { 'post-exchange' => 'fx-drafts', 'post-journal' => 'simple-journal-drafts', 'post-transfer' => 'cash-transfer-drafts', _ => 'vouchers' }))),
      'notifications' => ('التنبيهات', LocalAlertsView(controller: widget.controller, open: _openModulePage)),
      'report-trial' || 'report-profit' || 'report-movement' || 'report-closing' || 'report-category' || 'report-stock' || 'report-expiry' || 'report-services' => (
          LocalReport.values.byName(moduleId.substring(7)).title,
          LocalReportDetail(controller:widget.controller,report:LocalReport.values.byName(moduleId.substring(7)))),
      'reports' => ('التقارير', HomeReportsView(onOpenModule: _openModulePage)),
      'qr-scanner' || 'item-new' => ('الأصناف', StockScannerView(
        controller: widget.controller, createOnOpen: moduleId == 'item-new')),
      'quick-search' => (
          'البحث السريع',
          HomeQuickSearchScreen(controller: widget.controller)
        ),
      'daily-movement' => (
          'الحركة اليومية',
          DailyMovementScreen(controller: widget.controller)
        ),
      'cashboxes' => (
          'صناديق النقدية',
          HomeCashboxesView(controller: widget.controller)
        ),
      'account-statement' => (
          'كشف حساب',
          HomeAccountsView(controller: widget.controller, category: null, onOpenModule: _openModulePage)
        ),
      'warehouses' => (
          'المخازن',
          HomeWarehouseView(controller: widget.controller)
        ),
      'currencies' => (
          'دليل العملات',
          HomeCurrencyDirectoryView(controller: widget.controller)
        ),
      'sales-register' => (
          'سجل فواتير المبيعات',
          HomeSalesRegisterView(controller: widget.controller),
        ),
      'sales-overview' => (
          'ملخص المبيعات',
          HomeSalesOverviewView(controller: widget.controller)
        ),
      'settings' => (
          'الإعدادات',
          WorkspaceSettingsScreen(
            controller: widget.controller,
            openLocalBackups: () => _openModulePage('local-backups'),
          )
        ),
      'local-backups' => (
          'النسخ المحلية واختبار الاستعادة',
          LocalBackupWorkspaceView(
            onRestored: (message) {
              Navigator.of(context).popUntil((route) => route.isFirst);
              if (_homeScroll.hasClients) _homeScroll.jumpTo(0);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            },
            restoreWeb: widget.controller.restoreWebBackup,
            restoreLocal: widget.controller.restoreLocalBackup,
            importLocal: widget.controller.importLocalBackup,
            exportLocal: widget.controller.exportLocalBackup,
            loadBackups: widget.controller.loadLocalBackups,
            createBackup: widget.controller.createLocalBackup,
            verifyBackup: widget.controller.verifyLocalBackup,
            testRestore: widget.controller.testLocalBackupRestore,
          )
        ),
      'inventory' => (
          'الأصناف',
          InventoryCatalogScreen(controller: widget.controller)
        ),
      'stock-movement' => (
          'حركة المخازن',
          StockMovementScreen(controller: widget.controller)
        ),
      'finance' => (
          'القوائم المالية والأستاذ العام',
          FinanceScreen(
            controller: widget.controller,
            openRecordedSalesTax: () => _openModulePage('recorded-sales-tax'),
          )
        ),
      'recorded-sales-tax' => (
          'الضريبة الموثقة على المبيعات المحلية',
          SaleTaxRegisterView(
              loadRegister: widget.controller.loadSaleTaxRegister),
        ),
      'crm' => (
          'المبيعات ونقطة البيع',
          PosCrmScreen(controller: widget.controller)
        ),
      'hr' => (
          'الموارد البشرية والرواتب',
          HrScreen(controller: widget.controller)
        ),
      'procurement' => (
          'المشتريات وسلسلة التوريد',
          ProcurementScreen(controller: widget.controller)
        ),
      'manufacturing' => (
          'التصنيع ومراكز التكلفة',
          ManufacturingScreen(controller: widget.controller)
        ),
      _ => (
          'مركز الـ ERP',
          ErpHubScreen(
            controller: widget.controller,
            onOpenModule: _openModulePage,
          )
        ),
    };

    final previousModule = _activeModule;
    _activeModule = moduleId;
    Navigator.of(context)
        .push<void>(
      MaterialPageRoute(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: category != null || const {
            'post-journal', 'post-transfer', 'post-voucher', 'post-exchange', 'qr-scanner', 'item-new', 'account-statement', 'cashboxes',
            'warehouses',
            'currencies',
            'sales-overview',
            'recorded-sales-tax',
            'sales-register',
            'quotes',
            'quote-new',
            'orders',
            'order-new',
            'sales-return-drafts',
            'receipt-drafts',
            'payment-drafts',
            'cash-transfer-drafts',
            'simple-journal-drafts',
            'fx-drafts',
            'local-backups',
            'measurements',
            'cash-statement',
          }.contains(moduleId)
              ? page
              : Scaffold(
                  appBar: AppBar(title: Text(title)),
                  body: ListenableBuilder(
                    listenable: widget.controller,
                    builder: (_, __) => page,
                  ),
                ),
        ),
      ),
    )
        .whenComplete(() {
      if (_activeModule == moduleId) _activeModule = previousModule;
    });
  }

  void _openFromDrawer(String moduleId) {
    _shellKey.currentState?.closeDrawer();
    if (moduleId != 'home') _openModulePage(moduleId);
  }

  void _openInvoice() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      builder: (_) => InvoiceFormSheet(controller: widget.controller),
    );
  }

  void _openCustomers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomerListSheet(
        controller: widget.controller,
        onSelectCustomer: (_) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF4338CA);
    const navy = Color(0xFF312E81);
    final unread=workspaceAlerts(widget.controller).where((a)=>!widget.controller.readAlerts.contains(a.id)).length;
    return Scaffold(
      key: _shellKey,
      appBar: AppBar(
        titleSpacing: 0,
        leadingWidth: 48,
        toolbarHeight: 52,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [blue, navy],
            ),
          ),
        ),
        leading: IconButton(
          key: const ValueKey('home-open-drawer'),
          tooltip: 'فتح القائمة',
          onPressed: () => _shellKey.currentState?.openDrawer(),
          icon: const Icon(Icons.menu),
        ),
        title: Row(children: [
          PopupMenuButton<String>(
            tooltip: 'خيارات',
            onSelected: (action) => action == 'local-backups'
                ? _openModulePage('local-backups')
                : widget.controller.toggleTheme(),
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'local-backups',
                child: Text('النسخ المحلية واختبار الاستعادة'),
              ),
              PopupMenuItem<String>(
                enabled: false,
                child: Text('تفريغ القاعدة · غير متاح'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(value: 'theme', child: Text('تبديل المظهر')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              child: Text('خيارات', style: TextStyle(fontSize: 14)),
            ),
          ),
          const SizedBox(width: 5),
          const NasqoBrandMark(size: 26),
          const SizedBox(width: 5),
          Flexible(
            child: Text(widget.controller.companyName == 'نسقو برو ERP' ? 'نسقو برو' : widget.controller.companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ]),
        actions: [
          SizedBox(width:34,child:IconButton(tooltip:'إعدادات واتساب',iconSize:19,padding:EdgeInsets.zero,
            onPressed:()=>_openModulePage('message-settings'),icon:const Icon(Icons.chat_outlined))),
          SizedBox(width: 34, child: IconButton(
            tooltip: 'سلة المحذوفات', iconSize: 19, padding: EdgeInsets.zero,
            onPressed: () => _openModulePage('trash'), icon: const Icon(Icons.delete_outline))),
          SizedBox(
            width: 34,
            child: IconButton(
              icon: const Icon(Icons.search, size: 19),
              tooltip: 'البحث العام',
              padding: EdgeInsets.zero,
              onPressed: () => _openModulePage('quick-search'),
            ),
          ),
          SizedBox(width: 34, child: IconButton(tooltip: 'التنبيهات', iconSize: 19,
            padding: EdgeInsets.zero, onPressed: () => _openModulePage('notifications'),
            icon: Badge(isLabelVisible:unread>0,label:Text(unread>99?'99+':'$unread'),child:const Icon(Icons.notifications_none)))),
          PopupMenuButton<String>(
            tooltip: 'إضافة',
            icon: const Icon(Icons.add),
            onSelected: (route) => switch (route) {
              'invoice' => _openInvoice(),
              'customer' => _openCustomers(),
              _ => _openModulePage(route),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'account-new', child: Text('إضافة حساب جديد')),
              PopupMenuItem(
                  value: 'post-voucher', child: Text('سند جديد')),
              PopupMenuItem(
                  value: 'post-transfer', child: Text('حوالة جديدة')),
              PopupMenuItem(
                  value: 'invoice', child: Text('فاتورة مبيعات جديدة')),
              PopupMenuItem(value:'purchase-new',child:Text('فاتورة مشتريات جديدة')),
              PopupMenuItem(
                  value: 'sales-return-drafts', child: Text('مردود مبيعات جديد')),
              PopupMenuItem(
                  value: 'quote-new', child: Text('عرض سعر جديد')),
              PopupMenuItem(
                  value: 'order-new', child: Text('طلبية بيع جديدة')),
              PopupMenuItem(
                  value: 'post-journal', child: Text('قيد بسيط جديد')),
              PopupMenuItem(
                  value: 'item-new', child: Text('إضافة صنف للمخزن')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: HomeNavigation(
        onHome: () {
          if (_homeScroll.hasClients) {
            _homeScroll.animateTo(0, duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
          }
        },
        onServices: () => _openModulePage('hub'),
        onQuickActions: _quickActions,
        onReports: () => _openModulePage('reports'),
        onProfile: () => _openModulePage('settings'),
      ),
      drawer: NasqoWebDrawer(
        companyName: widget.controller.companyName,
        onOpen: _openFromDrawer,
      ),
      body: DashboardScreen(
        scrollController: _homeScroll,
        controller: widget.controller,
        onOpenModule: _openModulePage,
      ),
    );
  }
}
