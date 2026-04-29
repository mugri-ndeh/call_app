import 'dart:async';
import 'dart:developer';

import 'package:call_app/features/call/presentation/pages/call_screen.dart';
import 'package:call_app/firebase_options.dart';
import 'package:call_app/utils/signalling/signalling_utils.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationUtils.showIncomingCallFromData(message.data);
}

class NotificationUtils {
  NotificationUtils._();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static StreamSubscription<CallEvent?>? _callKitSub;
  static final Set<String> _shownCallIds = <String>{};

  static Future<void> initialize({
    required String userId,
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    _navigatorKey = navigatorKey;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await SignallingService.instance.registerUser(userId);

    await _callKitSub?.cancel();
    _callKitSub = FlutterCallkitIncoming.onEvent.listen(_handleCallKitEvent);

    FirebaseMessaging.onMessage.listen((message) async {
      await showIncomingCallFromData(message.data);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _openCallFromData(message.data);
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _openCallFromData(initialMessage.data);
    }
  }

  static Future<void> showIncomingCallFromData(
    Map<String, dynamic> data,
  ) async {
    if (data['type'] != 'incoming_call') {
      return;
    }

    final invite = CallInvite.fromMap(data);
    if (invite.callId.isEmpty) {
      return;
    }

    await showIncomingCall(invite);
  }

  static Future<void> showIncomingCall(CallInvite invite) async {
    if (!_shownCallIds.add(invite.callId)) {
      return;
    }

    final callKitParams = CallKitParams(
      id: invite.callId,
      nameCaller: invite.callerName ?? invite.callerId,
      appName: 'Call App',
      handle: invite.callerId,
      type: 1,
      textAccept: 'Accept',
      textDecline: 'Decline',
      duration: 30000,
      extra: invite.toMap(),
      headers: invite.toMap(),
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
      callingNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Calling...',
        callbackText: 'Hang up',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Incoming Call',
        missedCallNotificationChannelName: 'Missed Call',
        isShowCallID: true,
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
  }

  static Future<void> _handleCallKitEvent(CallEvent? event) async {
    if (event == null) {
      return;
    }

    final data = _extractCallData(event.body);
    final callId = data['callId'] as String? ?? data['id'] as String? ?? '';

    switch (event.event) {
      case Event.actionCallAccept:
        _openCallFromData(data);
        break;
      case Event.actionCallDecline:
      case Event.actionCallEnded:
      case Event.actionCallTimeout:
        if (callId.isNotEmpty) {
          await SignallingService.instance.declineCall(callId);
        }
        break;
      default:
        break;
    }
  }

  static Map<String, dynamic> _extractCallData(dynamic body) {
    if (body is! Map) {
      return {};
    }
    final map = body.cast<String, dynamic>();
    final extra = map['extra'];
    if (extra is Map) {
      return extra.cast<String, dynamic>();
    }
    final headers = map['headers'];
    if (headers is Map) {
      return headers.cast<String, dynamic>();
    }
    return map;
  }

  static void _openCallFromData(Map<String, dynamic> data) {
    if (data['type'] != 'incoming_call' && data['callId'] == null) {
      return;
    }

    final invite = CallInvite.fromMap(data);
    if (invite.callId.isEmpty) {
      return;
    }

    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      log('Navigator is not ready for incoming call ${invite.callId}');
      return;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: invite.callId,
          callerId: invite.callerId,
          calleeId: invite.calleeId,
          isCaller: false,
          offer: invite.offer,
        ),
      ),
    );
  }
}
