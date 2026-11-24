import 'package:flutter/material.dart';

/// Two-finger horizontal navigation and a distinct three-finger horizontal
/// language-cycle gesture. Callers disable it during accessible navigation;
/// the separately mounted Braille keyboard is outside this detector.
class TwoFingerNavigationDetector extends StatefulWidget {
  final bool enabled;
  final ValueChanged<int> onSwipe;
  final VoidCallback? onLanguageSwipe;
  final ValueChanged<int>? onVerticalSwipe;
  final Widget child;

  const TwoFingerNavigationDetector({
    super.key,
    required this.enabled,
    required this.onSwipe,
    this.onLanguageSwipe,
    this.onVerticalSwipe,
    required this.child,
  });

  @override
  State<TwoFingerNavigationDetector> createState() =>
      _TwoFingerNavigationDetectorState();
}

class _TwoFingerNavigationDetectorState
    extends State<TwoFingerNavigationDetector> {
  final Map<int, Offset> _starts = {};
  final Map<int, Offset> _positions = {};
  int _direction = 0;
  int _verticalDirection = 0;
  bool _languageGesture = false;

  void _down(PointerDownEvent event) {
    if (!widget.enabled) return;
    _starts[event.pointer] = event.localPosition;
    _positions[event.pointer] = event.localPosition;
    if (_positions.length > 3) _reset();
  }

  void _move(PointerMoveEvent event) {
    if (!_positions.containsKey(event.pointer)) return;
    _positions[event.pointer] = event.localPosition;
    if (_positions.length == 3) {
      final movements = _positions.keys.map((id) => _positions[id]! - _starts[id]!).toList();
      final sameDirection = movements.every((move) => move.dx.sign == movements.first.dx.sign);
      if (sameDirection && movements.every((move) => move.dy.abs() < 70 && move.dx.abs() > 130)) {
        _languageGesture = true;
      }
      return;
    }
    if (_positions.length != 2) return;
    final ids = _positions.keys.toList();
    final first = _positions[ids[0]]! - _starts[ids[0]]!;
    final second = _positions[ids[1]]! - _starts[ids[1]]!;
    if (first.dx.abs() < 90 && second.dx.abs() < 90 &&
        first.dy.sign == second.dy.sign &&
        first.dy.abs() > 110 && second.dy.abs() > 110) {
      _verticalDirection = first.dy < 0 ? 1 : -1;
    } else if (first.dx.sign == second.dx.sign &&
        first.dy.abs() < 90 &&
        second.dy.abs() < 90 &&
        first.dx.abs() > 100 &&
        second.dx.abs() > 100) {
      _direction = first.dx < 0 ? 1 : -1;
    }
  }

  void _end(PointerEvent event) {
    _positions.remove(event.pointer);
    _starts.remove(event.pointer);
    if (_positions.isNotEmpty) return;
    final direction = _direction;
    final verticalDirection = _verticalDirection;
    final languageGesture = _languageGesture;
    _reset();
    if (widget.enabled && languageGesture) {
      widget.onLanguageSwipe?.call();
    } else if (widget.enabled && direction != 0) {
      widget.onSwipe(direction);
    } else if (widget.enabled && verticalDirection != 0) {
      widget.onVerticalSwipe?.call(verticalDirection);
    }
  }

  void _reset() {
    _starts.clear();
    _positions.clear();
    _direction = 0;
    _verticalDirection = 0;
    _languageGesture = false;
  }

  @override
  void didUpdateWidget(TwoFingerNavigationDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _reset();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _end,
    onPointerCancel: _end,
    child: widget.child,
  );
}
