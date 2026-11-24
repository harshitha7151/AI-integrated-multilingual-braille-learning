import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// A flat, focusable action row for buttonless accessible interaction.
///
/// The surface deliberately does not expose button semantics. TalkBack users
/// can activate it with the standard tap action or the named custom action,
/// touch users can tap the full row, and keyboard/switch users can press Enter
/// or Space while it has focus.
class AccessibleActionSurface extends StatefulWidget {
  final String semanticsLabel;
  final String actionLabel;
  final String? semanticsHint;
  final VoidCallback? onActivate;
  final Widget child;
  final bool? selected;
  final bool? toggled;
  final bool inMutuallyExclusiveGroup;
  final EdgeInsetsGeometry padding;
  final bool showDivider;

  const AccessibleActionSurface({
    super.key,
    required this.semanticsLabel,
    required this.actionLabel,
    required this.onActivate,
    required this.child,
    this.semanticsHint,
    this.selected,
    this.toggled,
    this.inMutuallyExclusiveGroup = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.showDivider = true,
  });

  @override
  State<AccessibleActionSurface> createState() =>
      _AccessibleActionSurfaceState();
}

class _AccessibleActionSurfaceState extends State<AccessibleActionSurface> {
  bool _focused = false;

  bool get _enabled => widget.onActivate != null;

  void _activate() {
    if (_enabled) widget.onActivate!();
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.outlineVariant;
    final selectedColor = Theme.of(
      context,
    ).colorScheme.primaryContainer.withValues(alpha: 0.42);
    final focusedColor = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);

    return FocusableActionDetector(
      enabled: _enabled,
      onShowFocusHighlight: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: Semantics(
        container: true,
        focusable: true,
        enabled: _enabled,
        selected: widget.selected,
        toggled: widget.toggled,
        inMutuallyExclusiveGroup: widget.inMutuallyExclusiveGroup,
        label: widget.semanticsLabel,
        hint: widget.semanticsHint,
        onTap: _enabled ? _activate : null,
        customSemanticsActions: _enabled
            ? <CustomSemanticsAction, VoidCallback>{
                CustomSemanticsAction(label: widget.actionLabel): _activate,
              }
            : const <CustomSemanticsAction, VoidCallback>{},
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: _enabled ? _activate : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: widget.padding,
              decoration: BoxDecoration(
                color: widget.selected == true
                    ? selectedColor
                    : _focused
                    ? focusedColor
                    : Colors.transparent,
                border: widget.showDivider
                    ? Border(bottom: BorderSide(color: divider))
                    : null,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
