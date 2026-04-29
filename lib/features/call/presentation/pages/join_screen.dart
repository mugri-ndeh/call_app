import 'package:call_app/utils/notification/notification_utils.dart';
import 'package:flutter/material.dart';

import '../../../../utils/signalling/signalling_utils.dart';
import 'call_screen.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.selfCallerId});

  final String selfCallerId;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final remoteCallerIdTextEditingController = TextEditingController();
  final Set<String> _shownIncomingCallIds = {};
  CallInvite? incomingCall;

  @override
  void initState() {
    super.initState();
    SignallingService.instance.init(
      userID: widget.selfCallerId,
      onIncomingCall: (invite) {
        if (!mounted || _shownIncomingCallIds.contains(invite.callId)) {
          return;
        }
        _shownIncomingCallIds.add(invite.callId);
        setState(() => incomingCall = invite);
        NotificationUtils.showIncomingCall(invite);
      },
    );
  }

  Future<void> _declineCall(CallInvite invite) async {
    await SignallingService.instance.declineCall(invite.callId);
    if (mounted) {
      setState(() => incomingCall = null);
    }
  }

  void _openCall({
    required String callerId,
    required String calleeId,
    required bool isCaller,
    String? callId,
    Map<String, dynamic>? offer,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: callId,
          callerId: callerId,
          calleeId: calleeId,
          isCaller: isCaller,
          offer: offer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(centerTitle: true, title: const Text('P2P Call App')),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextField(
                      controller: TextEditingController(
                        text: widget.selfCallerId,
                      ),
                      readOnly: true,
                      textAlign: TextAlign.center,
                      enableInteractiveSelection: false,
                      decoration: const InputDecoration(
                        labelText: 'Your Caller ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: remoteCallerIdTextEditingController,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'Remote Caller ID',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      icon: const Icon(Icons.video_call),
                      label: const Text('Invite'),
                      onPressed: () {
                        final calleeId = remoteCallerIdTextEditingController
                            .text
                            .trim();
                        if (calleeId.isEmpty) {
                          return;
                        }
                        _openCall(
                          callerId: widget.selfCallerId,
                          calleeId: calleeId,
                          isCaller: true,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (incomingCall != null)
              Align(
                alignment: Alignment.topCenter,
                child: Material(
                  elevation: 4,
                  child: ListTile(
                    title: Text(
                      'Incoming call from ${incomingCall!.callerName ?? incomingCall!.callerId}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.call_end),
                          color: Colors.redAccent,
                          onPressed: () => _declineCall(incomingCall!),
                        ),
                        IconButton(
                          icon: const Icon(Icons.call),
                          color: Colors.green,
                          onPressed: () {
                            final invite = incomingCall!;
                            setState(() => incomingCall = null);
                            _openCall(
                              callId: invite.callId,
                              callerId: invite.callerId,
                              calleeId: widget.selfCallerId,
                              isCaller: false,
                              offer: invite.offer,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    remoteCallerIdTextEditingController.dispose();
    super.dispose();
  }
}
