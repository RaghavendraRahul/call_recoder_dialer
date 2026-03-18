import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'bouncing_button.dart';

class IncomingCallOverlay extends StatelessWidget {
  final String callerName;
  final String phoneNumber;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  const IncomingCallOverlay({
    super.key,
    required this.callerName,
    required this.phoneNumber,
    required this.onAnswer,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background with vibrant premium gradient or themed surface
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? null : Theme.of(context).scaffoldBackgroundColor,
              gradient: Theme.of(context).brightness == Brightness.dark
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF0F172A), // Deep Slate
                        Color(0xFF020617), // Midnight Blue
                        Color(0xFF1E1B4B), // Deep Indigo
                      ],
                      stops: [0.0, 0.6, 1.0],
                    )
                  : null,
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
            child: Container(color: Colors.black.withValues(alpha: 0.3)),
          ),

          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 1),

                // Caller Info
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    // Pulsing Avatar that feels alive
                    const _PulsingAvatar(),
                    const SizedBox(height: 35),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        callerName,
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.0,
                          height: 1.1,
                          fontFamily: 'Inter',
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      phoneNumber,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.85) ?? Colors.black87,
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 36),
                    
                    // Glassmorphic status pill
                    ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white.withValues(alpha: 0.15)
                                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.ring_volume,
                                color: Colors.greenAccent.shade400,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'INCOMING CALL',
                                style: TextStyle(
                                  color: Colors.greenAccent.shade100,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const Spacer(flex: 2),

                // Swipe-to-answer hint or simple buttons
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 60,
                    left: 32,
                    right: 32,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _DeclineButton(onDecline: onDecline),
                      _AcceptButton(onAnswer: onAnswer),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeclineButton extends StatelessWidget {
  final VoidCallback onDecline;

  const _DeclineButton({required this.onDecline});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BouncingButton(
          onTap: () {
            HapticFeedback.heavyImpact();
            onDecline();
          },
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(
                alpha: 0.2,
              ), // Semi-transparent red
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.call_end,
              color: Colors.redAccent,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          "Decline",
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _AcceptButton extends StatefulWidget {
  final VoidCallback onAnswer;

  const _AcceptButton({required this.onAnswer});

  @override
  State<_AcceptButton> createState() => _AcceptButtonState();
}

class _AcceptButtonState extends State<_AcceptButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BouncingButton(
          onTap: () {
            HapticFeedback.heavyImpact();
            widget.onAnswer();
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ripple effect
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Container(
                    width: 72 + (_controller.value * 20),
                    height: 72 + (_controller.value * 20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.greenAccent.withValues(
                          alpha: 0.5 * (1.0 - _controller.value),
                        ),
                        width: 2,
                      ),
                    ),
                  );
                },
              ),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.green, // Solid green
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.call, color: Colors.white, size: 32),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          "Accept",
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PulsingAvatar extends StatefulWidget {
  const _PulsingAvatar();

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated rings
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: List.generate(3, (index) {
                  final delay = index * 0.3;
                  final value = (_controller.value + delay) % 1.0;
                  return Opacity(
                    opacity: (1.0 - value) * 0.5,
                    child: Transform.scale(
                      scale: 1.0 + (value * 0.5),
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),

          // Avatar Image/Icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[800],
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: const Icon(Icons.person, size: 64, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
