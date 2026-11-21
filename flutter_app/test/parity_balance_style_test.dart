import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/screens/dashboard_screen.dart';
import 'package:nasqo_pro_erp/services/web_backup.dart';
import 'package:nasqo_pro_erp/state/erp_controller.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('restored balances follow CSS sign and color (dark=$dark)', (tester) async {
      final c = ErpController(autoInitDb: false);
      addTearDown(c.dispose);
      c.accounts.clear();
      c.ledger.clear();
      c.restoredGroups = RestoredGroups.fromJson({
        'accountGroups': [
          {'id': 31, 'name': 'مجموعة اختبار'},
        ],
        'accounts': [
          {'id': 'qa', 'groupId': 31},
        ],
      });
      c.accounts.add(const AccountRecord(id:'qa', name:'حساب اختبار',
          category:AccountCategory.clients, openingBalance:1250.5,
          openingDirection:EntryDirection.credit));
      await tester.pumpWidget(MaterialApp(theme: dark ? ThemeData.dark() : ThemeData.light(),
        home: Directionality(textDirection:TextDirection.rtl,
          child:Scaffold(body: GroupBalancesPanel(controller:c)))));
      final amount = tester.widget<Text>(find.text('1,250.5-'));
      expect(amount.textDirection, TextDirection.ltr);
      expect(amount.style?.color, dark ? const Color(0xfffb7185) : const Color(0xff9f1239));
      expect(c.accounts.single.openingBalance, 1250.5);
    });
  }
}
