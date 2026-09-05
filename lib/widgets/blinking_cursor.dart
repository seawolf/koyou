import 'package:flutter/material.dart';

/// A blinking insertion point, the height of the text it sits in.
///
/// Its job is to make a word break visible. A trailing space renders as
/// nothing, so pressing space and then starting the next syllable looks
/// identical to forgetting to press it — and `wǒài` is not `wǒ ài`. With a
/// caret in place, the space shows as a gap in front of it.
class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key, required this.height, this.color});

  /// Height of the bar, normally the font size of the text it sits in.
  final double height;

  final Color? color;

  /// Holds the caret still, for tests.
  ///
  /// A repeating animation means `pumpAndSettle` never returns, so tests switch
  /// the blink off rather than working around it. Flutter's own text fields
  /// carry the same switch, as `EditableText.debugDeterministicCursor`.
  static bool debugStatic = false;

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    duration: const Duration(milliseconds: 1100),
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    if (!BlinkingCursor.debugStatic) _blink.repeat();
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      width: 2,
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.color ?? Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(1),
      ),
    );
    if (BlinkingCursor.debugStatic) return bar;

    return AnimatedBuilder(
      animation: _blink,
      // On and off, the way a caret blinks, rather than fading in and out.
      builder: (context, child) =>
          Opacity(opacity: _blink.value < 0.5 ? 1 : 0, child: child),
      child: bar,
    );
  }
}
