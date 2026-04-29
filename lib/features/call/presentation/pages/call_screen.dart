import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../utils/signalling/signalling_utils.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    this.callId,
    this.offer,
    required this.callerId,
    required this.calleeId,
    required this.isCaller,
  });

  final String? callId;
  final String callerId;
  final String calleeId;
  final bool isCaller;
  final Map<String, dynamic>? offer;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _signallingService = SignallingService.instance;
  final _localRTCVideoRenderer = RTCVideoRenderer();
  final _remoteRTCVideoRenderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _pendingCandidates = [];
  final Set<String> _seenRemoteCandidateIds = {};

  MediaStream? _localStream;
  RTCPeerConnection? _rtcPeerConnection;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _candidateSub;

  String? _callId;
  bool isAudioOn = true;
  bool isVideoOn = true;
  bool isFrontCameraSelected = true;
  bool _remoteDescriptionSet = false;
  bool _isEnding = false;
  bool _hasSignalledEnd = false;

  @override
  void initState() {
    super.initState();
    _callId = widget.callId;
    _setupPeerConnection();
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  Future<void> _setupPeerConnection() async {
    await _localRTCVideoRenderer.initialize();
    await _remoteRTCVideoRenderer.initialize();

    _rtcPeerConnection = await createPeerConnection({
      'iceServers': [
        {
          'urls': [
            'stun:stun1.l.google.com:19302',
            'stun:stun2.l.google.com:19302',
          ],
        },
      ],
    });

    _rtcPeerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteRTCVideoRenderer.srcObject = event.streams.first;
        setState(() {});
      }
    };

    _rtcPeerConnection!.onIceCandidate = (candidate) {
      final callId = _callId;
      if (callId == null) {
        _pendingCandidates.add(candidate);
        return;
      }
      _signallingService.addIceCandidate(
        callId: callId,
        fromCaller: widget.isCaller,
        candidate: candidate,
      );
    };

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': isAudioOn,
      'video': isVideoOn
          ? {'facingMode': isFrontCameraSelected ? 'user' : 'environment'}
          : false,
    });

    for (final track in _localStream!.getTracks()) {
      await _rtcPeerConnection!.addTrack(track, _localStream!);
    }

    _localRTCVideoRenderer.srcObject = _localStream;
    setState(() {});

    if (widget.isCaller) {
      await _startOutgoingCall();
    } else {
      await _answerIncomingCall();
    }
  }

  Future<void> _startOutgoingCall() async {
    final offer = await _rtcPeerConnection!.createOffer();
    await _rtcPeerConnection!.setLocalDescription(offer);

    final callId = await _signallingService.createCall(
      callerId: widget.callerId,
      calleeId: widget.calleeId,
      offer: offer,
    );

    _callId = callId;
    await _flushPendingCandidates();
    _watchRemoteCandidates(fromCaller: false);

    _callSub = _signallingService.watchCall(callId).listen((snapshot) async {
      final data = snapshot.data();
      if (data == null) {
        return;
      }

      final status = data['status'];
      if (status == 'declined' || status == 'ended') {
        _closeCall(pop: true);
        return;
      }

      final answer = (data['answer'] as Map?)?.cast<String, dynamic>();
      if (answer != null && !_remoteDescriptionSet) {
        await _rtcPeerConnection!.setRemoteDescription(
          RTCSessionDescription(
            answer['sdp'] as String?,
            answer['type'] as String?,
          ),
        );
        _remoteDescriptionSet = true;
      }
    });
  }

  Future<void> _answerIncomingCall() async {
    final callId = _callId;
    if (callId == null) {
      throw StateError('Incoming calls require an existing callId.');
    }

    final callData = await _signallingService.getCall(callId);
    final offer =
        widget.offer ?? (callData?['offer'] as Map?)?.cast<String, dynamic>();
    if (offer == null) {
      throw StateError('Incoming call $callId has no offer.');
    }

    _watchRemoteCandidates(fromCaller: true);

    await _rtcPeerConnection!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String?, offer['type'] as String?),
    );
    _remoteDescriptionSet = true;

    final answer = await _rtcPeerConnection!.createAnswer();
    await _rtcPeerConnection!.setLocalDescription(answer);
    await _signallingService.answerCall(callId: callId, answer: answer);
    await _flushPendingCandidates();

    _callSub = _signallingService.watchCall(callId).listen((snapshot) {
      final status = snapshot.data()?['status'];
      if (status == 'declined' || status == 'ended') {
        _closeCall(pop: true);
      }
    });
  }

  void _watchRemoteCandidates({required bool fromCaller}) {
    final callId = _callId;
    if (callId == null) {
      return;
    }

    _candidateSub = _signallingService
        .watchIceCandidates(callId: callId, fromCaller: fromCaller)
        .listen(
          (snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.removed ||
                  _seenRemoteCandidateIds.contains(change.doc.id)) {
                continue;
              }
              _seenRemoteCandidateIds.add(change.doc.id);
              final data = change.doc.data();
              if (data == null) {
                continue;
              }
              _rtcPeerConnection?.addCandidate(
                RTCIceCandidate(
                  data['candidate'] as String?,
                  data['sdpMid'] as String?,
                  data['sdpMLineIndex'] as int?,
                ),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            log(
              'Candidate listener failed',
              error: error,
              stackTrace: stackTrace,
            );
          },
        );
  }

  Future<void> _flushPendingCandidates() async {
    final callId = _callId;
    if (callId == null || _pendingCandidates.isEmpty) {
      return;
    }

    final candidates = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final candidate in candidates) {
      await _signallingService.addIceCandidate(
        callId: callId,
        fromCaller: widget.isCaller,
        candidate: candidate,
      );
    }
  }

  Future<void> _leaveCall() async {
    await _signalCallEnded();
    _closeCall(pop: true);
  }

  Future<void> _signalCallEnded() async {
    if (_hasSignalledEnd) {
      return;
    }
    _hasSignalledEnd = true;

    final callId = _callId;
    if (callId != null) {
      await _signallingService.endCall(callId);
      await FlutterCallkitIncoming.endCall(callId);
    }
  }

  void _toggleMic() {
    isAudioOn = !isAudioOn;
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = isAudioOn;
    }
    setState(() {});
  }

  void _toggleCamera() {
    isVideoOn = !isVideoOn;
    for (final track
        in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = isVideoOn;
    }
    setState(() {});
  }

  void _switchCamera() {
    isFrontCameraSelected = !isFrontCameraSelected;
    for (final track
        in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      // ignore: deprecated_member_use
      track.switchCamera();
    }
    setState(() {});
  }

  void _closeCall({required bool pop}) {
    if (_isEnding) {
      return;
    }
    _isEnding = true;
    _callSub?.cancel();
    _candidateSub?.cancel();
    _localStream?.getTracks().forEach((track) => track.stop());
    _rtcPeerConnection?.close();
    if (pop && mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _signalCallEnded();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: Text(widget.isCaller ? 'Calling ${widget.calleeId}' : 'Call'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Colors.black,
                      child: RTCVideoView(
                        _remoteRTCVideoRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          height: 160,
                          width: 120,
                          child: ColoredBox(
                            color: Colors.black54,
                            child: RTCVideoView(
                              _localRTCVideoRenderer,
                              mirror: isFrontCameraSelected,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      icon: Icon(isAudioOn ? Icons.mic : Icons.mic_off),
                      onPressed: _toggleMic,
                    ),
                    IconButton.filled(
                      icon: const Icon(Icons.call_end),
                      iconSize: 30,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _leaveCall,
                    ),
                    IconButton(
                      icon: const Icon(Icons.cameraswitch),
                      onPressed: _switchCamera,
                    ),
                    IconButton(
                      icon: Icon(
                        isVideoOn ? Icons.videocam : Icons.videocam_off,
                      ),
                      onPressed: _toggleCamera,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _closeCall(pop: false);
    _localRTCVideoRenderer.dispose();
    _remoteRTCVideoRenderer.dispose();
    _localStream?.dispose();
    _rtcPeerConnection?.dispose();
    super.dispose();
  }
}
