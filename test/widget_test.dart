import 'package:call_app/utils/signalling/signalling_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CallInvite maps Firestore and FCM payload data', () {
    final invite = CallInvite.fromMap({
      'callId': 'call-1',
      'callerId': '111111',
      'calleeId': '222222',
      'callerName': '111111',
    });

    expect(invite.callId, 'call-1');
    expect(invite.callerId, '111111');
    expect(invite.calleeId, '222222');
    expect(invite.toMap()['callerName'], '111111');
  });
}
