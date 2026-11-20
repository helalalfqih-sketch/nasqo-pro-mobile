import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/erp_models.dart';
import 'package:nasqo_pro_erp/services/local_sales_csv.dart';

LedgerEntryRecord sale(String id,
        {String name = 'عميل',
        String doc = 'INV',
        String date = '2026-01-02',
        double amount = 1.23456789,
        CurrencyCode currency = CurrencyCode.usd,
        LedgerKind kind = LedgerKind.invoice,
        EntryDirection direction = EntryDirection.debit,
        String label = 'ف.مبيعات آجل',
        bool deleted = false}) =>
    LedgerEntryRecord(
        id: id,
        accountId: 'a',
        accountName: name,
        kind: kind,
        typeLabel: label,
        payment: PaymentMethod.credit,
        direction: direction,
        amount: amount,
        currency: currency,
        exchangeRate: 999,
        entryNumber: 1,
        entryDate: date,
        documentNumber: doc,
        deleted: deleted);
String text(LocalSalesCsvResult result) => utf8.decode(result.bytes.sublist(3));
void main() {
  test(
      'Excel UTF8 BOM CRLF, Arabic embedded newlines commas quotes, raw amount',
      () {
    final r = LocalSalesCsv.export(
        [sale('1', name: 'أحمد، شركة, "الوفاء"\nفرع\r\nثان')]);
    expect(r.bytes.take(3), [239, 187, 191]);
    expect(r.rowCount, 1);
    expect(r.byteLength, r.bytes.length);
    expect(text(r), contains('"أحمد، شركة, ""الوفاء""\nفرع\r\nثان"'));
    expect(text(r), contains('"1.23456789"\r\n'));
    expect(text(r), isNot(contains('1234.')));
    final altered = r.bytes;
    altered[0] = 0;
    expect(r.bytes[0], 239);
  });
  test('formula sigils hidden by whitespace/control/bidi/BOM are neutralized',
      () {
    for (final prefix in [
      '',
      ' \t\r\n',
      '\u0000\u0001',
      '\ufeff\u200f',
      '\u2066\u00a0'
    ]) {
      for (final sigil in ['=', '+', '-', '@']) {
        final r = LocalSalesCsv.export([
          sale('1', name: '$prefix${sigil}SUM(1,2)', doc: '$prefix${sigil}1')
        ]);
        expect(text(r), contains('"\'${sigil}SUM(1,2)"'));
        expect(text(r), contains('"\'${sigil}1"'));
      }
    }
  });
  test(
      'inclusive dates and currency, excludes nonnative/deleted/purchase/return; no mutate',
      () {
    final entries = [
      sale('before', date: '2026-01-01'),
      sale('first', doc: 'first'),
      sale('last', doc: 'last', date: '2026-01-03'),
      sale('after', date: '2026-01-04'),
      sale('sar', currency: CurrencyCode.sar),
      sale('gone', deleted: true),
      sale('purchase', direction: EntryDirection.credit),
      sale('return', kind: LedgerKind.returnEntry),
      sale('crm', label: 'CRM'),
      sale('quote', kind: LedgerKind.quote)
    ];
    final r = LocalSalesCsv.export(entries,
        from: '2026-01-02', through: '2026-01-03', currency: CurrencyCode.usd);
    expect(r.rowCount, 2);
    expect(text(r).indexOf('last'), lessThan(text(r).indexOf('first')));
    expect(entries.first.id, 'before');
    expect(LocalSalesCsv.export([sale('old-native')]).rowCount,
        1); // No invented line/tax requirement.
  });
  test(
      'all currencies remain individual labeled rows with no FX or combined total',
      () {
    final r = LocalSalesCsv.export([
      sale('usd', amount: 3),
      sale('sar', amount: 4, currency: CurrencyCode.sar)
    ]);
    expect(r.rowCount, 2);
    expect(text(r), contains('"دولار","3.0"'));
    expect(text(r), contains('"ريال","4.0"'));
  });
  test(
      'malformed date/filter or invalid eligible amount reject; zero is retained',
      () {
    for (final value in [double.nan, double.infinity, -1.0]) {
      expect(() => LocalSalesCsv.export([sale('bad', amount: value)]),
          throwsArgumentError);
    }
    for (final date in ['', '2026-02-30', '2026-1-1']) {
      expect(() => LocalSalesCsv.export([], from: date), throwsArgumentError);
      expect(() => LocalSalesCsv.export([sale('bad', date: date)]),
          throwsArgumentError);
    }
    expect(
        () =>
            LocalSalesCsv.export([], from: '2026-02-02', through: '2026-01-01'),
        throwsArgumentError);
    expect(text(LocalSalesCsv.export([sale('zero', amount: 0)])),
        contains('"0.0"'));
  });
  test('empty export is headers only, bounds fail rather than truncate', () {
    expect(LocalSalesCsv.export([]).rowCount, 0);
    expect(
        () => LocalSalesCsv.export(
            List.generate(LocalSalesCsv.maxRows + 1, (i) => sale('$i'))),
        throwsStateError);
    expect(
        () => LocalSalesCsv.export(
            [sale('large', name: 'x' * (LocalSalesCsv.maxBytes + 1))]),
        throwsStateError);
  });
}
