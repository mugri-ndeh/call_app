import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:injectable/injectable.dart';

typedef IncomingCallHandler = void Function(CallInvite invite);

class CallInvite {
  const CallInvite({
    required this.callId,
    required this.callerId,
    required this.calleeId,
    this.callerName,
    this.offer,
  });

  final String callId;
  final String callerId;
  final String calleeId;
  final String? callerName;
  final Map<String, dynamic>? offer;

  factory CallInvite.fromMap(Map<String, dynamic> data) {
    return CallInvite(
      callId: data['callId'] as String? ?? '',
      callerId: data['callerId'] as String? ?? '',
      calleeId: data['calleeId'] as String? ?? '',
      callerName: data['callerName'] as String?,
      offer: (data['offer'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'callerId': callerId,
      'calleeId': calleeId,
      if (callerName != null) 'callerName': callerName,
      if (offer != null) 'offer': offer,
    };
  }
}

@singleton
class SignallingService {
  SignallingService._();

  static final SignallingService instance = SignallingService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingCallsSub;
  StreamSubscription<String>? _tokenSub;

  String? _userId;

  String? get userId => _userId;

  Future<void> init({
    required String userID,
    IncomingCallHandler? onIncomingCall,
  }) async {
    _userId = userID;
    await registerUser(userID);
    await _incomingCallsSub?.cancel();

    _incomingCallsSub = _firestore
        .collection('calls')
        .where('calleeId', isEqualTo: userID)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen(
          (snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.removed) {
                continue;
              }
              final data = change.doc.data();
              if (data == null) {
                continue;
              }
              onIncomingCall?.call(
                CallInvite.fromMap({...data, 'callId': change.doc.id}),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            log(
              'Incoming call listener failed',
              error: error,
              stackTrace: stackTrace,
            );
          },
        );
  }

  Future<void> registerUser(String userID) async {
    final token = await FirebaseMessaging.instance.getToken();
    await _firestore.collection('users').doc(userID).set({
      'id': userID,
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _tokenSub?.cancel();
    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _firestore.collection('users').doc(userID).set({
        'fcmToken': newToken,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<String> createCall({
    required String callerId,
    required String calleeId,
    required RTCSessionDescription offer,
  }) async {
    final callRef = _firestore.collection('calls').doc();
    final callee = await _firestore.collection('users').doc(calleeId).get();
    final calleeToken = callee.data()?['fcmToken'];

    final payload = {
      'callId': callRef.id,
      'callerId': callerId,
      'calleeId': calleeId,
      'callerName': callerId,
      'type': 'incoming_call',
    };

    await callRef.set({
      'callerId': callerId,
      'calleeId': calleeId,
      'callerName': callerId,
      'status': 'ringing',
      'type': 'video',
      'offer': offer.toMap(),
      'answer': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('notification_requests').add({
      'toUserId': calleeId,
      'toFcmToken': calleeToken,
      'type': 'incoming_call',
      'title': 'Incoming call',
      'body': '$callerId is calling',
      'data': payload,
      'createdAt': FieldValue.serverTimestamp(),
      'sentAt': null,
    });

    return callRef.id;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchCall(String callId) {
    return _firestore.collection('calls').doc(callId).snapshots();
  }

  Future<Map<String, dynamic>?> getCall(String callId) async {
    final snapshot = await _firestore.collection('calls').doc(callId).get();
    return snapshot.data();
  }

  Future<void> answerCall({
    required String callId,
    required RTCSessionDescription answer,
  }) {
    return _firestore.collection('calls').doc(callId).set({
      'answer': answer.toMap(),
      'status': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> declineCall(String callId) {
    return _setCallStatus(callId, 'declined');
  }

  Future<void> endCall(String callId) {
    return _setCallStatus(callId, 'ended');
  }

  Future<void> _setCallStatus(String callId, String status) {
    return _firestore.collection('calls').doc(callId).set({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> addIceCandidate({
    required String callId,
    required bool fromCaller,
    required RTCIceCandidate candidate,
  }) {
    final collection = fromCaller ? 'callerCandidates' : 'calleeCandidates';
    return _firestore
        .collection('calls')
        .doc(callId)
        .collection(collection)
        .add(candidate.toMap());
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchIceCandidates({
    required String callId,
    required bool fromCaller,
  }) {
    final collection = fromCaller ? 'callerCandidates' : 'calleeCandidates';
    return _firestore
        .collection('calls')
        .doc(callId)
        .collection(collection)
        .snapshots();
  }

  Future<void> dispose() async {
    await _incomingCallsSub?.cancel();
    await _tokenSub?.cancel();
  }
}
