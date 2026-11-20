import 'erp_models.dart';

class ErpWorkspaceSnapshot {
  const ErpWorkspaceSnapshot({this.employees = const [],
    this.leaveRequests = const [],
    this.deals = const [],
    this.purchaseOrders = const [],
    this.boms = const [],
    this.productionOrders = const [],
    this.costCenters = const []});
  final List<ErpEmployeeProfile> employees;
  final List<ErpLeaveRequest> leaveRequests;
  final List<ErpDealRecord> deals;
  final List<ErpPurchaseOrder> purchaseOrders;
  final List<ErpBomRecipe> boms;
  final List<ErpProductionOrder> productionOrders;
  final List<ErpCostCenter> costCenters;

  factory ErpWorkspaceSnapshot.fromJson(Map<String, dynamic> data) {
    List<T> read<T>(String key, T Function(Map<String, dynamic>) decode) =>
      ((data[key] ?? const []) as List).map((row) => decode(row as Map<String, dynamic>)).toList();
    return ErpWorkspaceSnapshot(
      employees: read('employees', ErpEmployeeProfile.fromJson),
      leaveRequests: read('leaveRequests', ErpLeaveRequest.fromJson),
      deals: read('deals', ErpDealRecord.fromJson),
      purchaseOrders: read('purchaseOrders', ErpPurchaseOrder.fromJson),
      boms: read('boms', ErpBomRecipe.fromJson),
      productionOrders: read('productionOrders', ErpProductionOrder.fromJson),
      costCenters: read('costCenters', ErpCostCenter.fromJson),
    );
  }

  Map<String, Object?> toJson() => {
    'employees': employees.map((r) => r.toJson()).toList(),
    'leaveRequests': leaveRequests.map((r) => r.toJson()).toList(),
    'deals': deals.map((r) => r.toJson()).toList(),
    'purchaseOrders': purchaseOrders.map((r) => r.toJson()).toList(),
    'boms': boms.map((r) => r.toJson()).toList(),
    'productionOrders': productionOrders.map((r) => r.toJson()).toList(),
    'costCenters': costCenters.map((r) => r.toJson()).toList(),
  };
}
