import 'package:flutter/material.dart';
import '../models/customer_measurement.dart';
import '../services/customer_measurement_repository.dart';
import '../state/erp_controller.dart';

class CustomerMeasurementsView extends StatefulWidget {
  const CustomerMeasurementsView({
    super.key,
    required this.controller,
  });

  final ErpController controller;

  @override
  State<CustomerMeasurementsView> createState() =>
      _CustomerMeasurementsViewState();
}

class _CustomerMeasurementsViewState extends State<CustomerMeasurementsView> {
  late final CustomerMeasurementRepository _repo;
  List<CustomerMeasurement> _measurements = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _repo = CustomerMeasurementRepository(widget.controller.database);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _repo.loadAll();
    if (mounted) {
      setState(() {
        _measurements = items;
        _loading = false;
      });
    }
  }

  void _openForm([CustomerMeasurement? existing]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomerMeasurementFormSheet(
        repository: _repo,
        initial: existing,
        onSaved: _load,
      ),
    );
  }

  Future<void> _delete(CustomerMeasurement item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المقاس'),
          content: Text('هل أنت متأكد من حذف مقاس ${item.customerName}؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && item.id != null) {
      await _repo.delete(item.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _measurements.where((m) {
      final text = '${m.customerName} ${m.phone} ${m.itemType} ${m.notes}'
          .toLowerCase();
      return text.contains(_query.toLowerCase());
    }).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('التمييز والمقاسات'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'إضافة مقاس جديد',
              onPressed: () => _openForm(),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF0B5CA8),
          foregroundColor: Colors.white,
          tooltip: 'مقاس جديد',
          onPressed: () => _openForm(),
          child: const Icon(Icons.add),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'بحث في المقاسات والعملاء',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onChanged: (val) => setState(() => _query = val),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.straighten,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              const Text(
                                'لا توجد مقاسات مسجلة بعد',
                                style:
                                    TextStyle(fontSize: 14, color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text('تسجيل مقاس جديد'),
                                onPressed: () => _openForm(),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            return _MeasurementCard(
                              item: item,
                              onEdit: () => _openForm(item),
                              onDelete: () => _delete(item),
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

class _MeasurementCard extends StatelessWidget {
  const _MeasurementCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final CustomerMeasurement item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF0B5CA8), width: 1.5),
      ),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF0B5CA8).withValues(alpha: 0.1),
                  child: const Icon(Icons.straighten,
                      color: Color(0xFF0B5CA8), size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.customerName,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${item.itemType}${item.phone.isNotEmpty ? " • ${item.phone}" : ""}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 19),
                  tooltip: 'تعديل',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 19, color: Colors.red),
                  tooltip: 'حذف',
                  onPressed: onDelete,
                ),
              ],
            ),
            const Divider(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip('الطول', item.length),
                _chip('الكتف', item.shoulder),
                _chip('الكم', item.sleeve),
                _chip('الصدر', item.chest),
                _chip('الرقبة', item.neck),
                _chip('الخصر', item.waist),
              ],
            ),
            if (item.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Text(
                  'ملاحظات التفصيل: ${item.notes}',
                  style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, double val) {
    if (val <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0B5CA8).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: const Color(0xFF0B5CA8).withValues(alpha: 0.2)),
      ),
      child: Text(
        '$label: ${val.toStringAsFixed(1)}',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF073B68),
        ),
      ),
    );
  }
}

class CustomerMeasurementFormSheet extends StatefulWidget {
  const CustomerMeasurementFormSheet({
    super.key,
    required this.repository,
    this.initial,
    required this.onSaved,
  });

  final CustomerMeasurementRepository repository;
  final CustomerMeasurement? initial;
  final VoidCallback onSaved;

  @override
  State<CustomerMeasurementFormSheet> createState() =>
      _CustomerMeasurementFormSheetState();
}

class _CustomerMeasurementFormSheetState
    extends State<CustomerMeasurementFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _itemTypeController;
  late TextEditingController _lengthController;
  late TextEditingController _shoulderController;
  late TextEditingController _sleeveController;
  late TextEditingController _chestController;
  late TextEditingController _neckController;
  late TextEditingController _waistController;
  late TextEditingController _notesController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _nameController = TextEditingController(text: init?.customerName ?? '');
    _phoneController = TextEditingController(text: init?.phone ?? '');
    _itemTypeController =
        TextEditingController(text: init?.itemType ?? 'ثوب رجالي');
    _lengthController = TextEditingController(
        text: init?.length == null || init!.length == 0
            ? ''
            : init.length.toString());
    _shoulderController = TextEditingController(
        text: init?.shoulder == null || init!.shoulder == 0
            ? ''
            : init.shoulder.toString());
    _sleeveController = TextEditingController(
        text: init?.sleeve == null || init!.sleeve == 0
            ? ''
            : init.sleeve.toString());
    _chestController = TextEditingController(
        text: init?.chest == null || init!.chest == 0
            ? ''
            : init.chest.toString());
    _neckController = TextEditingController(
        text: init?.neck == null || init!.neck == 0
            ? ''
            : init.neck.toString());
    _waistController = TextEditingController(
        text: init?.waist == null || init!.waist == 0
            ? ''
            : init.waist.toString());
    _notesController = TextEditingController(text: init?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _itemTypeController.dispose();
    _lengthController.dispose();
    _shoulderController.dispose();
    _sleeveController.dispose();
    _chestController.dispose();
    _neckController.dispose();
    _waistController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final item = CustomerMeasurement(
      id: widget.initial?.id,
      customerName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      date: widget.initial?.date ??
          DateTime.now().toIso8601String().substring(0, 10),
      itemType: _itemTypeController.text.trim().isEmpty
          ? 'ثوب رجالي'
          : _itemTypeController.text.trim(),
      length: double.tryParse(_lengthController.text.trim()) ?? 0.0,
      shoulder: double.tryParse(_shoulderController.text.trim()) ?? 0.0,
      sleeve: double.tryParse(_sleeveController.text.trim()) ?? 0.0,
      chest: double.tryParse(_chestController.text.trim()) ?? 0.0,
      neck: double.tryParse(_neckController.text.trim()) ?? 0.0,
      waist: double.tryParse(_waistController.text.trim()) ?? 0.0,
      notes: _notesController.text.trim(),
    );

    await widget.repository.save(item);
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 16,
          left: 16,
          right: 16,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.initial == null
                          ? 'تسجيل مقاس عميل جديد'
                          : 'تعديل مقاس العميل',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم العميل *',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty
                      ? 'يرجى إدخال اسم العميل'
                      : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _itemTypeController,
                        decoration: const InputDecoration(
                          labelText: 'نوع الملبس/الصنف',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'القياسات والأبعاد (سم):',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF073B68)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _numField(_lengthController, 'الطول الكلي')),
                    const SizedBox(width: 8),
                    Expanded(child: _numField(_shoulderController, 'الكتف')),
                    const SizedBox(width: 8),
                    Expanded(child: _numField(_sleeveController, 'الكم')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _numField(_chestController, 'الصدر')),
                    const SizedBox(width: 8),
                    Expanded(child: _numField(_neckController, 'الرقبة')),
                    const SizedBox(width: 8),
                    Expanded(child: _numField(_waistController, 'الخصر')),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات التمييز والتفصيل والطلب',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'جاري الحفظ...' : 'حفظ المقاس'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0B5CA8),
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _numField(TextEditingController ctrl, String label) {
    return TextFormField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
