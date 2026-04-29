import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../features/auth/data/models/user.dart';

Future<void> showCall(
  User caller,
  String callId,
  Map<String, dynamic> callParams,
) async {
  CallKitParams callKitParams = CallKitParams(
    id: callId,
    nameCaller: caller.name,
    appName: 'Buzme',
    avatar: 'https://i.pravatar.cc/100',
    handle: '0123456789',
    type: 0,
    textAccept: 'Accept',
    textDecline: 'Decline',

    missedCallNotification: NotificationParams(
      showNotification: true,
      isShowCallback: true,
      subtitle: 'Missed call',
      callbackText: 'Call back',
    ),
    callingNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: true,
      subtitle: 'Calling...',
      callbackText: 'Hang Up',
    ),
    duration: 30000,
    extra: caller.toMap(),
    headers: callParams,
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      logoUrl: 'https://i.pravatar.cc/100',
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#0955fa',
      backgroundUrl: 'https://i.pravatar.cc/500',
      actionColor: '#4CAF50',
      textColor: '#ffffff',
      incomingCallNotificationChannelName: "Incoming Call",
      missedCallNotificationChannelName: "Missed Call",
      isShowCallID: false,
    ),
    ios: IOSParams(
      iconName: 'CallKitLogo',
      handleType: 'generic',
      supportsVideo: true,
      maximumCallGroups: 2,
      maximumCallsPerCallGroup: 1,
      audioSessionMode: 'default',
      audioSessionActive: true,
      audioSessionPreferredSampleRate: 44100.0,
      audioSessionPreferredIOBufferDuration: 0.005,
      supportsDTMF: true,
      supportsHolding: true,
      supportsGrouping: false,
      supportsUngrouping: false,
      ringtonePath: 'system_ringtone_default',
    ),
  );
  await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
}

Future<void> showMissedCall(User caller, String callId) async {
  CallKitParams params = CallKitParams(
    id: callId,
    nameCaller: caller.name,
    handle: '0123456789',
    type: 1,
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: true,
      subtitle: 'Missed call',
      callbackText: 'Call back',
    ),
    android: const AndroidParams(
      isCustomNotification: true,
      isShowCallID: true,
    ),
    extra: <String, dynamic>{'userId': caller.id},
  );
  await FlutterCallkitIncoming.showMissCallNotification(params);
}
