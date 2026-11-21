import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../state/erp_controller.dart';

class RolesPermissionsScreen extends StatefulWidget {
  const RolesPermissionsScreen({
    super.key,
    required this.controller,
  });

  final ErpController controller;

  @override
  State<RolesPermissionsScreen> createState() => _RolesPermissionsScreenState();
}

class _RolesPermissionsScreenState extends State<RolesPermissionsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String? _editingRoleId;
  bool _isCreatingNew = false;
  String _sectionFilter = 'all'; // 'all' | 'modules' | 'actions'
  String _searchQuery = '';

  late Map<ErpPermissionModule, ErpModuleCrudFlags> _draftModules;
  late Set<ErpActionPermission> _draftActions;

  @override
  void initState() {
    super.initState();
    _loadFromRole(widget.controller.activeRole);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadFromRole(ErpRoleRecord role) {
    _isCreatingNew = false;
    _editingRoleId = role.id;
    _nameController.text = role.name;
    _draftModules = {
      for (final m in ErpPermissionModule.values) m: role.flagsFor(m),
    };
    _draftActions = Set<ErpActionPermission>.from(role.actionPermissions);
  }

  void _startNewRole() {
    setState(() {
      _isCreatingNew = true;
      _editingRoleId = null;
      _nameController.clear();
      _draftModules = {
        for (final m in ErpPermissionModule.values)
          m: const ErpModuleCrudFlags.none(),
      };
      _draftActions = <ErpActionPermission>{};
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('أدخل اسم الدور الجديد وحدد الصلاحيات ثم اضغط حفظ.'),
      ),
    );
  }

  void _setAllPermissions(bool enabled) {
    setState(() {
      _draftModules = {
        for (final m in ErpPermissionModule.values)
          m: enabled
              ? const ErpModuleCrudFlags.all()
              : const ErpModuleCrudFlags.none(),
      };
      _draftActions = enabled
          ? Set<ErpActionPermission>.from(ErpActionPermission.values)
          : <ErpActionPermission>{};
    });
  }

  void _toggleModuleAction(ErpPermissionModule module, ErpCrudAction action) {
    setState(() {
      final current = _draftModules[module] ?? const ErpModuleCrudFlags.none();
      _draftModules[module] = current.withAction(action, !current[action]);
    });
  }

  void _toggleAllForModule(ErpPermissionModule module) {
    setState(() {
      final current = _draftModules[module] ?? const ErpModuleCrudFlags.none();
      _draftModules[module] = current.allEnabled
          ? const ErpModuleCrudFlags.none()
          : const ErpModuleCrudFlags.all();
    });
  }

  void _toggleActionPermission(ErpActionPermission permission) {
    setState(() {
      if (_draftActions.contains(permission)) {
        _draftActions.remove(permission);
      } else {
        _draftActions.add(permission);
      }
    });
  }

  Future<void> _saveCurrentRole({required bool asUpdate}) async {
    try {
      final targetId = _isCreatingNew ? null : _editingRoleId;
      final saved = await widget.controller.saveRole(
        id: targetId,
        name: _nameController.text,
        modulePermissions: _draftModules,
        actionPermissions: _draftActions,
      );
      if (!mounted) return;
      setState(() {
        _loadFromRole(saved);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            asUpdate && targetId != null
                ? 'تم تعديل صلاحيات الدور «${saved.name}» بنجاح.'
                : 'تم حفظ الدور «${saved.name}» وتفعيله بنجاح.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final msg = error is FormatException
          ? error.message
          : error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  Future<void> _deleteCurrentRole() async {
    if (_isCreatingNew || _editingRoleId == null) {
      setState(() {
        _loadFromRole(widget.controller.activeRole);
      });
      return;
    }
    try {
      final deletedName = _nameController.text.trim();
      await widget.controller.deleteRole(_editingRoleId!);
      if (!mounted) return;
      setState(() {
        _loadFromRole(widget.controller.activeRole);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حذف الدور «$deletedName».')),
      );
    } catch (error) {
      if (!mounted) return;
      final msg = error is FormatException
          ? error.message
          : error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  int get _draftGrantedCount {
    var count = _draftActions.length;
    for (final m in ErpPermissionModule.values) {
      count += (_draftModules[m] ?? const ErpModuleCrudFlags.none()).enabledCount;
    }
    return count;
  }

  IconData _moduleIcon(ErpPermissionModule module) => switch (module) {
        ErpPermissionModule.currencies => Icons.currency_exchange,
        ErpPermissionModule.cashboxes => Icons.account_balance_wallet_outlined,
        ErpPermissionModule.accounts => Icons.account_tree_outlined,
        ErpPermissionModule.warehouses => Icons.warehouse_outlined,
        ErpPermissionModule.vouchers => Icons.receipt_outlined,
        ErpPermissionModule.users => Icons.manage_accounts_outlined,
        ErpPermissionModule.rolesAndPermissions =>
          Icons.admin_panel_settings_outlined,
        ErpPermissionModule.items => Icons.inventory_2_outlined,
        ErpPermissionModule.quotesAndOrders => Icons.request_quote_outlined,
        ErpPermissionModule.cashFunds => Icons.savings_outlined,
        ErpPermissionModule.warehouseTransfers => Icons.swap_horiz_outlined,
      };

  IconData _actionIcon(ErpActionPermission action) => switch (action) {
        ErpActionPermission.newVoucher => Icons.note_add_outlined,
        ErpActionPermission.newInvoice => Icons.post_add_outlined,
        ErpActionPermission.dailyJournalEntry => Icons.menu_book_outlined,
        ErpActionPermission.quickSearch => Icons.manage_search_outlined,
        ErpActionPermission.accountStatement => Icons.fact_check_outlined,
        ErpActionPermission.messages => Icons.chat_outlined,
        ErpActionPermission.currencyExchangeVoucher =>
          Icons.swap_horizontal_circle_outlined,
        ErpActionPermission.editInvoice => Icons.edit_note_outlined,
        ErpActionPermission.newTransfer => Icons.send_outlined,
        ErpActionPermission.backup => Icons.backup_outlined,
        ErpActionPermission.restoreBackup => Icons.restore_outlined,
        ErpActionPermission.exportToApp => Icons.ios_share_outlined,
        ErpActionPermission.importFromApp => Icons.file_download_outlined,
        ErpActionPermission.dailyMovement => Icons.today_outlined,
        ErpActionPermission.activationOptions => Icons.verified_user_outlined,
        ErpActionPermission.settings => Icons.settings_outlined,
        ErpActionPermission.newReturn => Icons.assignment_return_outlined,
        ErpActionPermission.editTransfer => Icons.published_with_changes_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final roles = widget.controller.roles;
    final q = _searchQuery.trim();

    final visibleModules = ErpPermissionModule.values
        .where((m) => q.isEmpty || m.label.contains(q))
        .toList();
    final visibleActions = ErpActionPermission.values
        .where((a) => q.isEmpty || a.label.contains(q))
        .toList();

    final showModules = _sectionFilter == 'all' || _sectionFilter == 'modules';
    final showActions = _sectionFilter == 'all' || _sectionFilter == 'actions';

    return SingleChildScrollView(
      key: const ValueKey('roles-permissions-scroll'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        // 1. Mobile Header Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF07365D), Color(0xFF0B5CA8)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.admin_panel_settings,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isCreatingNew
                          ? 'الأدوار والصلاحيات · إنشاء دور جديد'
                          : 'الأدوار والصلاحيات · ${widget.controller.activeRole.name}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_draftGrantedCount / ${ErpRoleRecord.maxTotalPermissions}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'إدارة صلاحيات الأقسام الأساسية (إضافة، تعديل، حذف، عرض) والصلاحيات الإجرائية مع الحفظ المباشر في SQLite.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. Role Selector & Role Name Card
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'الأدوار المحفوظة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final role in roles)
                      ChoiceChip(
                        key: ValueKey('role-chip-${role.id}'),
                        label: Text(
                          '${role.name} (${role.totalGrantedPermissions})',
                        ),
                        selected: !_isCreatingNew && _editingRoleId == role.id,
                        onSelected: (_) async {
                          await widget.controller.setActiveRole(role.id);
                          if (!mounted) return;
                          setState(() {
                            _loadFromRole(role);
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('role-name-input'),
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'اسم الدور',
                    hintText: 'مثال: محاسب فرع، أمين مستودع، مشرف مبيعات',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 4 primary actions matching reference semantics: جديد / حفظ / تعديل / حذف
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('role-action-new'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF39A16),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _startNewRole,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('جديد'),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('role-action-save'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0B5CA8),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _saveCurrentRole(asUpdate: false),
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('حفظ'),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('role-action-edit'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF169B62),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _saveCurrentRole(asUpdate: true),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('تعديل'),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('role-action-delete'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD84949),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _deleteCurrentRole,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('حذف'),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'تحديد سريع للصلاحيات:',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          key: const ValueKey('role-select-all'),
                          onPressed: () => _setAllPermissions(true),
                          child: const Text('تحديد الكل'),
                        ),
                        OutlinedButton(
                          key: const ValueKey('role-clear-all'),
                          onPressed: () => _setAllPermissions(false),
                          child: const Text('إلغاء الكل'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 3. Mobile Search & Section Switcher
        TextField(
          key: const ValueKey('role-permission-search'),
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: 'بحث في الأقسام أو الصلاحيات...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('role-filter-all'),
              label: const Text('الكل (29)'),
              selected: _sectionFilter == 'all',
              onSelected: (_) => setState(() => _sectionFilter = 'all'),
            ),
            ChoiceChip(
              key: const ValueKey('role-filter-modules'),
              label: const Text('صلاحيات الأقسام (11)'),
              selected: _sectionFilter == 'modules',
              onSelected: (_) => setState(() => _sectionFilter = 'modules'),
            ),
            ChoiceChip(
              key: const ValueKey('role-filter-actions'),
              label: const Text('صلاحيات أخرى (18)'),
              selected: _sectionFilter == 'actions',
              onSelected: (_) => setState(() => _sectionFilter = 'actions'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 4. Module CRUD Permissions (11 Modules x 4 CRUD flags)
        if (showModules) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF39A16).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFF39A16).withValues(alpha: 0.4),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.grid_view_rounded,
                    size: 18, color: Color(0xFFD98200)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الصلاحيات الأساسية للأقسام (إضافة · تعديل · حذف · عرض)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final module in visibleModules) _buildModuleCard(context, module),
          const SizedBox(height: 12),
        ],

        // 5. Other Action Permissions (18 checkboxes)
        if (showActions) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.fact_check_outlined,
                    size: 18, color: colors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'صلاحيات أخرى (العمليات والإجراءات السريعة)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  '${_draftActions.length} / ${ErpActionPermission.values.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < visibleActions.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  CheckboxListTile(
                    key: ValueKey('action-perm-${visibleActions[i].name}'),
                    dense: true,
                    secondary: Icon(
                      _actionIcon(visibleActions[i]),
                      color: _draftActions.contains(visibleActions[i])
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    title: Text(
                      visibleActions[i].label,
                      style: TextStyle(
                        fontWeight: _draftActions.contains(visibleActions[i])
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    value: _draftActions.contains(visibleActions[i]),
                    onChanged: (_) =>
                        _toggleActionPermission(visibleActions[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
      ),
    );
  }

  Widget _buildModuleCard(BuildContext context, ErpPermissionModule module) {
    final colors = Theme.of(context).colorScheme;
    final flags = _draftModules[module] ?? const ErpModuleCrudFlags.none();

    return Card(
      key: ValueKey('module-card-${module.name}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      const Color(0xFF0B5CA8).withValues(alpha: 0.12),
                  foregroundColor: const Color(0xFF0B5CA8),
                  child: Icon(_moduleIcon(module), size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    module.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: ValueKey('module-all-${module.name}'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => _toggleAllForModule(module),
                  icon: Icon(
                    flags.allEnabled
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 18,
                  ),
                  label: Text('${flags.enabledCount}/4'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in ErpCrudAction.values)
                  FilterChip(
                    key: ValueKey('perm-${module.name}-${action.name}'),
                    label: Text(action.label),
                    selected: flags[action],
                    selectedColor:
                        const Color(0xFFF39A16).withValues(alpha: 0.22),
                    checkmarkColor: const Color(0xFFB46900),
                    side: BorderSide(
                      color: flags[action]
                          ? const Color(0xFFF39A16)
                          : colors.outlineVariant,
                    ),
                    onSelected: (_) => _toggleModuleAction(module, action),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
