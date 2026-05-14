import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HelpBalloon extends StatelessWidget {
  final Widget child;
  final String message;
  final bool isEnabled;
  final Alignment balloonAlignment;

  const HelpBalloon({
    super.key,
    required this.child,
    required this.message,
    required this.isEnabled,
    this.balloonAlignment = Alignment.topRight,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (isEnabled) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.amber, size: 40),
                        const SizedBox(height: 16),
                        Text(message,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(fontSize: 14)),
                      ],
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Entendido"))
                    ],
                  ),
                );
              },
            ),
          ),
          Positioned(
            left: balloonAlignment == Alignment.topLeft ? -4 : null,
            right: balloonAlignment == Alignment.topRight ? -4 : null,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.amber,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: const Icon(Icons.help, size: 8, color: Colors.black),
            ),
          ),
        ],
      ],
    );
  }
}
