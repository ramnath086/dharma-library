import 'package:dharma_library/core/auth/auth_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('email validation', () {
    expect(AuthLogic.emailError(''), 'empty');
    expect(AuthLogic.emailError('   '), 'empty');
    expect(AuthLogic.emailError('not-an-email'), 'invalid');
    expect(AuthLogic.emailError('a@b'), 'invalid');
    expect(AuthLogic.emailError('reader@example.com'), isNull);
    expect(AuthLogic.isEmail('Reader@Example.com'), isTrue);
  });

  test('auth error classification', () {
    expect(AuthLogic.classifyError('AuthException: otp_expired'), 'expired');
    expect(AuthLogic.classifyError('invalid otp token'), 'code');
    expect(AuthLogic.classifyError('SocketException: failed host lookup'), 'network');
    expect(AuthLogic.classifyError('too many requests / rate limit'), 'rate');
    expect(AuthLogic.classifyError('something else'), 'generic');
  });
}
