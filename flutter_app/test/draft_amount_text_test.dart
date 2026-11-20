import 'package:flutter_test/flutter_test.dart';
import 'package:nasqo_pro_erp/models/draft_amount_text.dart';

void main() {
  test('decimal draft editing does not round or lose existing small amounts',
      () {
    expect(draftAmountText(null), '');
    expect(draftAmountText(1e-7), '0.0000001');
    expect(draftAmountText(2.34e-10), '0.000000000234');
    for (final value in [0.15, 1e-7, 2.34e-10, 5e-324, 1e22, 123.45]) {
      final text = draftAmountText(value);
      expect(text, matches(r'^\d+(\.\d+)?$'));
      expect(double.parse(text), value);
    }
  });
}
