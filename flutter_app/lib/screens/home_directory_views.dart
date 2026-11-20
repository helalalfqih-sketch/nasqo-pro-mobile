import 'package:flutter/material.dart';
import '../state/erp_controller.dart';
import 'home_account_views.dart';

String _searchText(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  return input
      .split('')
      .map((c) {
        if (arabic.contains(c)) return arabic.indexOf(c).toString();
        if (persian.contains(c)) return persian.indexOf(c).toString();
        return c;
      })
      .join()
      .trim()
      .toLowerCase();
}

/// Body-only local account directory. The owning route provides its Scaffold.
class HomeChartOfAccountsView extends StatefulWidget {
  const HomeChartOfAccountsView({super.key, required this.controller});
  final ErpController controller;
  @override
  State<HomeChartOfAccountsView> createState() =>
      _HomeChartOfAccountsViewState();
}

class _HomeChartOfAccountsViewState extends State<HomeChartOfAccountsView> {
  String _query = '';
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final accounts = widget.controller.accounts
                .where((account) =>
                    _searchText('${account.codeNumber} ${account.name}')
                        .contains(_searchText(_query)))
                .toList()
              ..sort((a, b) {
                final code = a.codeNumber.compareTo(b.codeNumber);
                return code != 0 ? code : a.name.compareTo(b.name);
              });
            return ListView(
              key: const ValueKey('home-chart-directory'),
              padding: const EdgeInsets.all(16),
              children: [
                Text('دليل الحسابات',
                    style: Theme.of(context).textTheme.headlineSmall),
                const Text('دليل محلي للقراءة فقط؛ اضغط الحساب لعرض كشفه'),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('chart-account-search'),
                  decoration: const InputDecoration(
                      labelText: 'بحث بالرمز أو اسم الحساب',
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 12),
                if (accounts.isEmpty)
                  Text(widget.controller.accounts.isEmpty
                      ? 'لا توجد حسابات محلية'
                      : 'لا توجد حسابات مطابقة'),
                for (final account in accounts)
                  Card(
                      child: ListTile(
                    key: ValueKey('chart-account-${account.id}'),
                    title: Text(account.name),
                    subtitle: Text(
                        'الرمز: ${account.codeNumber}\nالتصنيف: ${account.category.label}\nالعملة: ${account.currency.label}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => HomeAccountStatementView(
                          controller: widget.controller,
                          accountId: account.id,
                          initialCurrency: account.currency),
                    )),
                  )),
              ],
            );
          },
        ),
      );
}

/// Legacy deleted ledger headers only; no restore, purge or cancellation API.
/// Body-only: host inside a Scaffold for standard navigation and material UI.
class HomeTrashView extends StatelessWidget {
  const HomeTrashView({super.key, required this.controller});
  final ErpController controller;
  Future<void> _apply(BuildContext context,String id,int number,bool purge) async {
    if(purge) {
      final confirm=await showDialog<bool>(context:context,builder:(dialog)=>AlertDialog(
        title:Text('حذف القيد رقم $number نهائيًا؟'),content:const Text('ستُحذف بنود القيد من قاعدة الهاتف.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(dialog,false),child:const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(dialog,true),child:const Text('حذف نهائي'))]));
      if(confirm!=true || !context.mounted) return;
    }
    try {
      await controller.resolveTrash(id,purge:purge);
      if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(purge?'تم حذف القيد':'تمت استعادة العملية')));
    } catch(error){if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(error.toString())));}
  }
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final deleted = controller.ledger
                .where((entry) => entry.deleted)
                .toList()
              ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
            return ListView(
              key: const ValueKey('home-legacy-trash'),
              padding: const EdgeInsets.all(16),
              children: [
                Text('المحذوفات القديمة',
                    style: Theme.of(context).textTheme.headlineSmall),
                const Text(
                    'اختر قيدًا لاستعادته إلى الدفتر أو حذفه نهائيًا.'),
                const SizedBox(height: 12),
                if (deleted.isEmpty) const Text('لا توجد قيود محذوفة قديمة'),
                for (final entry in deleted)
                  Card(
                      child: Padding(
                    key: ValueKey('legacy-deleted-${entry.id}'),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.accountName,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(
                              '${entry.typeLabel} · رقم القيد: ${entry.entryNumber}'),
                          Text('التاريخ: ${entry.entryDate}'),
                          Text(
                              'المبلغ: ${entry.amount} ${entry.currency.label}'),
                          if (entry.documentNumber.isNotEmpty)
                            Text('المستند: ${entry.documentNumber}'),
                          Wrap(children:[TextButton(onPressed:()=>_apply(context,entry.id,entry.entryNumber,false),child:const Text('استعادة')),
                            TextButton(onPressed:()=>_apply(context,entry.id,entry.entryNumber,true),child:const Text('حذف نهائي'))]),
                        ]),
                  )),
              ],
            );
          },
        ),
      );
}
