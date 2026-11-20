enum CurrencyCode {
  sar('ريال'),
  usd('دولار'),
  eur('يورو'),
  currency2('عملة 2');

  const CurrencyCode(this.label);
  final String label;
}

enum AccountCategory {
  purchases('المشتريات والموردون'),
  sales('المبيعات'),
  clients('العملاء'),
  employees('الموظفون'),
  transfers('الحوالات والصناديق'),
  shop('المحل والمصروفات');

  const AccountCategory(this.label);
  final String label;
}

enum LedgerKind {
  voucher,
  invoice,
  returnEntry,
  quote,
  order,
  transfer,
  currency,
  simpleEntry,
  opening,
}

enum PaymentMethod {
  cash('نقدي'),
  credit('آجل'),
  balance('رصيد');

  const PaymentMethod(this.label);
  final String label;
}

enum EntryDirection { debit, credit }

enum ErpDealStage {
  lead('فرصة جديدة', 25),
  proposal('عرض سعر', 50),
  negotiation('تفاوض', 75),
  won('صفقة مغلقة (ربح)', 100),
  lost('مغلقة (خسارة)', 0);

  const ErpDealStage(this.label, this.defaultProbability);
  final String label;
  final int defaultProbability;
}

enum PurchaseOrderStatus {
  draft('مسودة'),
  approved('معتمد'),
  received('مستلم');

  const PurchaseOrderStatus(this.label);
  final String label;
}

enum ProductionOrderStatus {
  planned('مخطط'),
  inProgress('قيد التصنيع'),
  completed('مكتمل');

  const ProductionOrderStatus(this.label);
  final String label;
}

enum AttendanceStatus {
  present('حاضر'),
  leave('إجازة'),
  absent('غائب');

  const AttendanceStatus(this.label);
  final String label;
}

enum LeaveStatus {
  pending('قيد المراجعة'),
  approved('معتمدة'),
  rejected('مرفوضة');

  const LeaveStatus(this.label);
  final String label;
}

class AccountRecord {
  const AccountRecord({
    required this.id,
    required this.name,
    required this.category,
    this.phone = '',
    this.creditLimit = 50000,
    this.currency = CurrencyCode.sar,
    this.isCashAccount = false,
    this.note = '',
    this.openingBalance = 0,
    this.openingDirection = EntryDirection.credit,
    this.codeNumber = 1,
  });

  final String id;
  final String name;
  final AccountCategory category;
  final String phone;
  final double creditLimit;
  final CurrencyCode currency;
  final bool isCashAccount;
  final String note;
  final double openingBalance;
  final EntryDirection openingDirection;
  final int codeNumber;
}

class LedgerEntryRecord {
  const LedgerEntryRecord({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.kind,
    required this.typeLabel,
    required this.payment,
    required this.direction,
    required this.amount,
    this.currency = CurrencyCode.sar,
    this.exchangeRate = 1.0,
    this.details = '',
    this.documentNumber = '',
    this.warehouseId = 'wh_1',
    this.warehouseName = 'المخزن الرئيسي',
    this.expenseCategory = '',
    required this.entryNumber,
    this.deleted = false,
    required this.entryDate,
  });

  final String id;
  final String accountId;
  final String accountName;
  final LedgerKind kind;
  final String typeLabel;
  final PaymentMethod payment;
  final EntryDirection direction;
  final double amount;
  final CurrencyCode currency;
  final double exchangeRate;
  final String details;
  final String documentNumber;
  final String warehouseId;
  final String warehouseName;
  final String expenseCategory;
  final int entryNumber;
  final bool deleted;
  final String entryDate;
}

class WarehouseRecord {
  const WarehouseRecord({
    required this.id,
    required this.name,
    this.details = '',
    this.isDefault = false,
  });

  final String id;
  final String name;
  final String details;
  final bool isDefault;
}

class InventoryItemRecord {
  const InventoryItemRecord({
    required this.id,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.avgCost,
    this.warehouseId = 'wh_1',
    this.minThreshold = 25,
    this.sku = '',
  });

  final String id;
  final String name;
  final String unit;
  final double quantity;
  final double avgCost;
  final String warehouseId;
  final double minThreshold;
  final String sku;

  InventoryItemRecord copyWith({
    double? quantity,
    double? avgCost,
  }) {
    return InventoryItemRecord(
      id: id,
      name: name,
      unit: unit,
      quantity: quantity ?? this.quantity,
      avgCost: avgCost ?? this.avgCost,
      warehouseId: warehouseId,
      minThreshold: minThreshold,
      sku: sku,
    );
  }
}

class InvoiceItemRow {
  InvoiceItemRow({
    required this.id,
    this.itemId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0,
  });

  final String id;
  String? itemId;
  String productName;
  double quantity;
  double unitPrice;

  double discount;
  bool get validDiscount => discount.isFinite && discount >= 0;
  double get lineTotal {
    final gross = quantity * unitPrice;
    if (discount == 0 || !gross.isFinite || !validDiscount) return gross;
    final cents = (gross - discount).clamp(0.0, double.infinity) * 100;
    return cents.isFinite ? cents.roundToDouble() / 100 : double.infinity;
  }
  double get netUnitPrice => discount == 0 ? unitPrice : lineTotal / quantity;
  String get discountNote => 'سعر الوحدة: $unitPrice، خصم السطر: $discount، الصافي: $lineTotal';
}

/// Durable sale line. Old ledger headers have no synthetic backfilled lines.
class SavedSaleLine {
  const SavedSaleLine({
    required this.entryId,
    required this.position,
    required this.itemId,
    required this.itemName,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
  });

  final String entryId;
  final int position;
  final String itemId;
  final String itemName;
  final String unit;
  final double quantity;
  final double unitPrice;

  static bool sameQuantity(double a, double b) {
    if (a == b) return true;
    if (a <= 0 || b <= 0) return false;
    return (a - b).abs() <= 1e-15 * (a > b ? a : b);
  }

  /// Allocate the difference of cumulative amounts so splitting a return
  /// cannot create or lose a cent. Preserve the exact original final total.
  static double returnedValue(double originalQuantity, double price,
      double alreadyReturned, double nextQuantity) {
    double cumulative(double qty) {
      final amount = qty * price;
      if (sameQuantity(originalQuantity, qty)) return originalQuantity * price;
      final rounded = (amount * 100).roundToDouble() / 100;
      return rounded.clamp(0.0, originalQuantity * price).toDouble();
    }
    return cumulative(alreadyReturned + nextQuantity) - cumulative(alreadyReturned);
  }
}

class SaleValidationException implements Exception {
  const SaleValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ErpEmployeeProfile {
  factory ErpEmployeeProfile.fromJson(Map<String, dynamic> data) => ErpEmployeeProfile(
    id: data['id'] as String,
    name: data['name'] as String,
    roleTitle: data['roleTitle'] as String,
    department: data['department'] as String,
    basicSalary: (data['basicSalary'] as num).toDouble(),
    allowances: (data['allowances'] as num).toDouble(),
    deductions: (data['deductions'] as num).toDouble(),
    status: data['status'] as String,
    hireDate: data['hireDate'] as String,
    leaveBalanceDays: data['leaveBalanceDays'] as int,
    attendanceToday: AttendanceStatus.values.byName(data['attendanceToday'] as String),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'roleTitle': roleTitle,
    'department': department,
    'basicSalary': basicSalary,
    'allowances': allowances,
    'deductions': deductions,
    'status': status,
    'hireDate': hireDate,
    'leaveBalanceDays': leaveBalanceDays,
    'attendanceToday': attendanceToday.name,
  };

  const ErpEmployeeProfile({
    required this.id,
    required this.name,
    required this.roleTitle,
    required this.department,
    required this.basicSalary,
    required this.allowances,
    required this.deductions,
    this.status = 'active',
    required this.hireDate,
    this.leaveBalanceDays = 21,
    this.attendanceToday = AttendanceStatus.present,
  });

  final String id;
  final String name;
  final String roleTitle;
  final String department;
  final double basicSalary;
  final double allowances;
  final double deductions;
  final String status;
  final String hireDate;
  final int leaveBalanceDays;
  final AttendanceStatus attendanceToday;

  double get netSalary =>
      (basicSalary + allowances - deductions).clamp(0, double.infinity);

  ErpEmployeeProfile copyWith({
    int? leaveBalanceDays,
    AttendanceStatus? attendanceToday,
  }) {
    return ErpEmployeeProfile(
      id: id,
      name: name,
      roleTitle: roleTitle,
      department: department,
      basicSalary: basicSalary,
      allowances: allowances,
      deductions: deductions,
      status: status,
      hireDate: hireDate,
      leaveBalanceDays: leaveBalanceDays ?? this.leaveBalanceDays,
      attendanceToday: attendanceToday ?? this.attendanceToday,
    );
  }
}

class ErpLeaveRequest {
  factory ErpLeaveRequest.fromJson(Map<String, dynamic> data) => ErpLeaveRequest(
    id: data['id'] as String,
    employeeId: data['employeeId'] as String,
    employeeName: data['employeeName'] as String,
    leaveType: data['leaveType'] as String,
    startDate: data['startDate'] as String,
    days: data['days'] as int,
    status: LeaveStatus.values.byName(data['status'] as String),
    note: data['note'] as String,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'employeeId': employeeId,
    'employeeName': employeeName,
    'leaveType': leaveType,
    'startDate': startDate,
    'days': days,
    'status': status.name,
    'note': note,
  };

  const ErpLeaveRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.leaveType,
    required this.startDate,
    required this.days,
    this.status = LeaveStatus.pending,
    this.note = '',
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final String leaveType;
  final String startDate;
  final int days;
  final LeaveStatus status;
  final String note;

  ErpLeaveRequest copyWith({LeaveStatus? status}) {
    return ErpLeaveRequest(
      id: id,
      employeeId: employeeId,
      employeeName: employeeName,
      leaveType: leaveType,
      startDate: startDate,
      days: days,
      status: status ?? this.status,
      note: note,
    );
  }
}

class ErpDealRecord {
  factory ErpDealRecord.fromJson(Map<String, dynamic> data) => ErpDealRecord(
    id: data['id'] as String,
    title: data['title'] as String,
    clientAccountId: data['clientAccountId'] as String,
    clientName: data['clientName'] as String,
    value: (data['value'] as num).toDouble(),
    currency: CurrencyCode.values.firstWhere((c) => c.name == data['currency'] || c.label == data['currency'] || c.name.toUpperCase() == data['currency']),
    stage: ErpDealStage.values.byName(data['stage'] as String),
    probability: data['probability'] as int,
    expectedCloseDate: data['expectedCloseDate'] as String,
    assignedTo: data['assignedTo'] as String,
    convertedInvoiceEntryId: data['convertedInvoiceEntryId'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'clientAccountId': clientAccountId,
    'clientName': clientName,
    'value': value,
    'currency': currency.name,
    'stage': stage.name,
    'probability': probability,
    'expectedCloseDate': expectedCloseDate,
    'assignedTo': assignedTo,
    'convertedInvoiceEntryId': convertedInvoiceEntryId,
  };

  const ErpDealRecord({
    required this.id,
    required this.title,
    required this.clientAccountId,
    required this.clientName,
    required this.value,
    this.currency = CurrencyCode.sar,
    this.stage = ErpDealStage.lead,
    this.probability = 25,
    required this.expectedCloseDate,
    required this.assignedTo,
    this.convertedInvoiceEntryId,
  });

  final String id;
  final String title;
  final String clientAccountId;
  final String clientName;
  final double value;
  final CurrencyCode currency;
  final ErpDealStage stage;
  final int probability;
  final String expectedCloseDate;
  final String assignedTo;
  final String? convertedInvoiceEntryId;

  ErpDealRecord copyWith({
    ErpDealStage? stage,
    int? probability,
    String? convertedInvoiceEntryId,
  }) {
    return ErpDealRecord(
      id: id,
      title: title,
      clientAccountId: clientAccountId,
      clientName: clientName,
      value: value,
      currency: currency,
      stage: stage ?? this.stage,
      probability: probability ?? this.probability,
      expectedCloseDate: expectedCloseDate,
      assignedTo: assignedTo,
      convertedInvoiceEntryId:
          convertedInvoiceEntryId ?? this.convertedInvoiceEntryId,
    );
  }
}

class ErpPurchaseOrderLine {
  factory ErpPurchaseOrderLine.fromJson(Map<String, dynamic> data) => ErpPurchaseOrderLine(
    inventoryItemId: data['inventoryItemId'] as String?,
    itemName: data['itemName'] as String,
    unit: data['unit'] as String,
    quantity: (data['quantity'] as num).toDouble(),
    unitCost: (data['unitCost'] as num).toDouble(),
  );

  Map<String, Object?> toJson() => {
    'inventoryItemId': inventoryItemId,
    'itemName': itemName,
    'unit': unit,
    'quantity': quantity,
    'unitCost': unitCost,
  };

  const ErpPurchaseOrderLine({
    this.inventoryItemId,
    required this.itemName,
    required this.unit,
    required this.quantity,
    required this.unitCost,
  });

  final String? inventoryItemId;
  final String itemName;
  final String unit;
  final double quantity;
  final double unitCost;
}

class ErpPurchaseOrder {
  factory ErpPurchaseOrder.fromJson(Map<String, dynamic> data) => ErpPurchaseOrder(
    id: data['id'] as String,
    poNumber: data['poNumber'] as String,
    supplierAccountId: data['supplierAccountId'] as String,
    supplierName: data['supplierName'] as String,
    warehouseId: data['warehouseId'] as String,
    warehouseName: data['warehouseName'] as String,
    currency: CurrencyCode.values.firstWhere((c) => c.name == data['currency'] || c.label == data['currency'] || c.name.toUpperCase() == data['currency']),
    orderDate: data['orderDate'] as String,
    expectedDate: data['expectedDate'] as String,
    status: PurchaseOrderStatus.values.byName(data['status'] as String),
    lines: (data['lines'] as List).map((e) => ErpPurchaseOrderLine.fromJson(e as Map<String, dynamic>)).toList(),
    notes: data['notes'] as String,
    postedLedgerEntryId: data['postedLedgerEntryId'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'poNumber': poNumber,
    'supplierAccountId': supplierAccountId,
    'supplierName': supplierName,
    'warehouseId': warehouseId,
    'warehouseName': warehouseName,
    'currency': currency.name,
    'orderDate': orderDate,
    'expectedDate': expectedDate,
    'status': status.name,
    'lines': lines.map((v) => v.toJson()).toList(),
    'notes': notes,
    'postedLedgerEntryId': postedLedgerEntryId,
  };

  const ErpPurchaseOrder({
    required this.id,
    required this.poNumber,
    required this.supplierAccountId,
    required this.supplierName,
    required this.warehouseId,
    required this.warehouseName,
    this.currency = CurrencyCode.sar,
    required this.orderDate,
    required this.expectedDate,
    this.status = PurchaseOrderStatus.draft,
    required this.lines,
    this.notes = '',
    this.postedLedgerEntryId,
  });

  final String id;
  final String poNumber;
  final String supplierAccountId;
  final String supplierName;
  final String warehouseId;
  final String warehouseName;
  final CurrencyCode currency;
  final String orderDate;
  final String expectedDate;
  final PurchaseOrderStatus status;
  final List<ErpPurchaseOrderLine> lines;
  final String notes;
  final String? postedLedgerEntryId;

  ErpPurchaseOrder copyWith({
    PurchaseOrderStatus? status,
    String? postedLedgerEntryId,
  }) {
    return ErpPurchaseOrder(
      id: id,
      poNumber: poNumber,
      supplierAccountId: supplierAccountId,
      supplierName: supplierName,
      warehouseId: warehouseId,
      warehouseName: warehouseName,
      currency: currency,
      orderDate: orderDate,
      expectedDate: expectedDate,
      status: status ?? this.status,
      lines: lines,
      notes: notes,
      postedLedgerEntryId: postedLedgerEntryId ?? this.postedLedgerEntryId,
    );
  }
}

class ErpBomComponent {
  factory ErpBomComponent.fromJson(Map<String, dynamic> data) => ErpBomComponent(
    inventoryItemId: data['inventoryItemId'] as String,
    itemName: data['itemName'] as String,
    unit: data['unit'] as String,
    quantityPerUnit: (data['quantityPerUnit'] as num).toDouble(),
  );

  Map<String, Object?> toJson() => {
    'inventoryItemId': inventoryItemId,
    'itemName': itemName,
    'unit': unit,
    'quantityPerUnit': quantityPerUnit,
  };

  const ErpBomComponent({
    required this.inventoryItemId,
    required this.itemName,
    required this.unit,
    required this.quantityPerUnit,
  });

  final String inventoryItemId;
  final String itemName;
  final String unit;
  final double quantityPerUnit;
}

class ErpBomRecipe {
  factory ErpBomRecipe.fromJson(Map<String, dynamic> data) => ErpBomRecipe(
    id: data['id'] as String,
    name: data['name'] as String,
    finishedItemId: data['finishedItemId'] as String,
    finishedItemName: data['finishedItemName'] as String,
    finishedUnit: data['finishedUnit'] as String,
    components: (data['components'] as List).map((e) => ErpBomComponent.fromJson(e as Map<String, dynamic>)).toList(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'finishedItemId': finishedItemId,
    'finishedItemName': finishedItemName,
    'finishedUnit': finishedUnit,
    'components': components.map((v) => v.toJson()).toList(),
  };

  const ErpBomRecipe({
    required this.id,
    required this.name,
    required this.finishedItemId,
    required this.finishedItemName,
    required this.finishedUnit,
    required this.components,
  });

  final String id;
  final String name;
  final String finishedItemId;
  final String finishedItemName;
  final String finishedUnit;
  final List<ErpBomComponent> components;
}

class ErpProductionOrder {
  factory ErpProductionOrder.fromJson(Map<String, dynamic> data) => ErpProductionOrder(
    id: data['id'] as String,
    orderNumber: data['orderNumber'] as String,
    bomId: data['bomId'] as String,
    bomName: data['bomName'] as String,
    finishedItemId: data['finishedItemId'] as String,
    finishedItemName: data['finishedItemName'] as String,
    quantityToProduce: (data['quantityToProduce'] as num).toDouble(),
    warehouseId: data['warehouseId'] as String,
    status: ProductionOrderStatus.values.byName(data['status'] == 'in-progress' ? 'inProgress' : data['status'] as String),
    createdDate: data['createdDate'] as String,
    completedDate: data['completedDate'] as String?,
    costCenterId: data['costCenterId'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'orderNumber': orderNumber,
    'bomId': bomId,
    'bomName': bomName,
    'finishedItemId': finishedItemId,
    'finishedItemName': finishedItemName,
    'quantityToProduce': quantityToProduce,
    'warehouseId': warehouseId,
    'status': status.name,
    'createdDate': createdDate,
    'completedDate': completedDate,
    'costCenterId': costCenterId,
  };

  const ErpProductionOrder({
    required this.id,
    required this.orderNumber,
    required this.bomId,
    required this.bomName,
    required this.finishedItemId,
    required this.finishedItemName,
    required this.quantityToProduce,
    required this.warehouseId,
    this.status = ProductionOrderStatus.planned,
    required this.createdDate,
    this.completedDate,
    this.costCenterId,
  });

  final String id;
  final String orderNumber;
  final String bomId;
  final String bomName;
  final String finishedItemId;
  final String finishedItemName;
  final double quantityToProduce;
  final String warehouseId;
  final ProductionOrderStatus status;
  final String createdDate;
  final String? completedDate;
  final String? costCenterId;

  ErpProductionOrder copyWith({
    ProductionOrderStatus? status,
    String? completedDate,
  }) {
    return ErpProductionOrder(
      id: id,
      orderNumber: orderNumber,
      bomId: bomId,
      bomName: bomName,
      finishedItemId: finishedItemId,
      finishedItemName: finishedItemName,
      quantityToProduce: quantityToProduce,
      warehouseId: warehouseId,
      status: status ?? this.status,
      createdDate: createdDate,
      completedDate: completedDate ?? this.completedDate,
      costCenterId: costCenterId,
    );
  }
}

class ErpCostCenter {
  factory ErpCostCenter.fromJson(Map<String, dynamic> data) => ErpCostCenter(
    id: data['id'] as String,
    code: data['code'] as String,
    name: data['name'] as String,
    managerName: data['managerName'] as String,
    budget: (data['budget'] as num).toDouble(),
    extraPostedSpend: ((data['extraPostedSpend'] as num?) ?? 0).toDouble(),
    linkedCategories: List<String>.from(data['linkedCategories'] as List),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'managerName': managerName,
    'budget': budget,
    'extraPostedSpend': extraPostedSpend,
    'linkedCategories': linkedCategories,
  };

  const ErpCostCenter({
    required this.id,
    required this.code,
    required this.name,
    required this.managerName,
    required this.budget,
    this.extraPostedSpend = 0,
    this.linkedCategories = const [],
  });

  final String id;
  final String code;
  final String name;
  final String managerName;
  final double budget;
  final double extraPostedSpend;
  final List<String> linkedCategories;
}
