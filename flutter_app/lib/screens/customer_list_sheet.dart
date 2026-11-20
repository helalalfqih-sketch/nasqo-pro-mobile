import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../state/erp_controller.dart';

class CustomerListSheet extends StatefulWidget {
  const CustomerListSheet({
    super.key,
    required this.controller,
    required this.onSelectCustomer,
    this.allowAdd = true,
  });

  final ErpController controller;
  final ValueChanged<AccountRecord> onSelectCustomer;
  final bool allowAdd;

  @override
  State<CustomerListSheet> createState() => _CustomerListSheetState();
}

class _CustomerListSheetState extends State<CustomerListSheet> {
  String _search = '';
  bool _addingNew = false;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clients =
        widget.controller.accounts.where((acc) {
          final isClientType =
              acc.category == AccountCategory.clients ||
              acc.category == AccountCategory.sales ||
              acc.category == AccountCategory.purchases;
          if (!isClientType) return false;
          if (_search.trim().isEmpty) return true;
          final q = _search.trim().toLowerCase();
          return acc.name.toLowerCase().contains(q) || acc.phone.contains(q);
        }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'إدارة العملاء (CustomerList)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'ابحث عن عميل...',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.allowAdd)
                  FilledButton.icon(
                    onPressed: () => setState(() => _addingNew = !_addingNew),
                    icon: Icon(
                      _addingNew ? Icons.close : Icons.person_add,
                      size: 16,
                    ),
                    label: Text(_addingNew ? 'إلغاء' : 'جديد'),
                  ),
              ],
            ),
            if (widget.allowAdd && _addingNew) ...[
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'اسم العميل',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم الجوال',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () {
                          final name = _nameCtrl.text.trim();
                          if (name.isEmpty) return;
                          final created = widget.controller.addCustomer(
                            name: name,
                            phone: _phoneCtrl.text.trim(),
                          );
                          _nameCtrl.clear();
                          _phoneCtrl.clear();
                          setState(() => _addingNew = false);
                          widget.onSelectCustomer(created);
                          Navigator.pop(context);
                        },
                        child: const Text('حفظ واختيار العميل'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: clients.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final client = clients[index];
                  return ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF0B5CA8),
                      foregroundColor: Colors.white,
                      child: Icon(Icons.person, size: 18),
                    ),
                    title: Text(
                      client.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      client.phone.isEmpty
                          ? client.category.label
                          : client.phone,
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () {
                        widget.onSelectCustomer(client);
                        Navigator.pop(context);
                      },
                      child: const Text('اختيار'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
