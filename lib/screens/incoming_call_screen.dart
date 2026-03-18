import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/incoming_call_overlay.dart';
import '../services/native_call_service.dart';
import '../services/call_state_service.dart';

class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Prevent back button
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent, // Important for overlay effect
        body: Consumer<CallStateService>(
          builder: (context, callStateService, child) {
            // Safety check: if call ended, pop this screen
            if (callStateService.callState != CallState.ringing) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted && Navigator.canPop(context)) {
                  Navigator.of(context).pop();
                }
              });
              return const SizedBox.shrink();
            }

            final callerName = callStateService.callerName ?? 'Unknown';
            final phoneNumber = callStateService.phoneNumber ?? 'Unknown';

            return IncomingCallOverlay(
              callerName: callerName,
              phoneNumber: phoneNumber,
              onAnswer: () async {
                await NativeCallService().answerCall();
                // Screen will be popped or replaced by active call screen via state change
              },
              onDecline: () async {
                await NativeCallService().rejectCall();
              },
            );
          },
        ),
      ),
    );
  }
}
