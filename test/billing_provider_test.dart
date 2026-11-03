import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/providers/billing_provider.dart';

void main() {
  test('appAccountTokenForUid returns a deterministic StoreKit UUID', () {
    final token = appAccountTokenForUid('uid-a');

    expect(token, appAccountTokenForUid('uid-a'));
    expect(token, isNot(appAccountTokenForUid('uid-b')));
    expect(
      token,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}
