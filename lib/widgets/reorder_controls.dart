import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

const moveUpAction = CustomSemanticsAction(label: 'Yukarı taşı');
const moveDownAction = CustomSemanticsAction(label: 'Aşağı taşı');

/// A ReorderableListView row with ways to move it besides dragging: "Yukarı/Aşağı taşı" screen-reader
/// actions on the row itself (the drag handle is hidden from them) — pair with [ReorderControls].
class ReorderableRow extends StatelessWidget {
  final int index;
  final int count;

  /// -1 = up, 1 = down.
  final ValueChanged<int> onMove;
  final Widget child;

  const ReorderableRow({
    super.key,
    required this.index,
    required this.count,
    required this.onMove,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    customSemanticsActions: {
      if (index > 0) moveUpAction: () => onMove(-1),
      if (index < count - 1) moveDownAction: () => onMove(1),
    },
    child: child,
  );
}

/// Row trailing: visible "Taşı" menu (Yukarı / Aşağı taşı) + 48 dp drag handle (decorative for screen
/// readers, which use [ReorderableRow] actions instead).
class ReorderControls extends StatelessWidget {
  final int index;
  final int count;
  final ValueChanged<int> onMove;
  final Key? menuKey;

  const ReorderControls({super.key, required this.index, required this.count, required this.onMove, this.menuKey});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PopupMenuButton<int>(
        key: menuKey,
        tooltip: 'Taşı',
        enabled: count > 1,
        icon: const Icon(Icons.swap_vert_rounded),
        onSelected: onMove,
        itemBuilder: (_) => [
          if (index > 0) const PopupMenuItem(value: -1, child: Text('Yukarı taşı')),
          if (index < count - 1) const PopupMenuItem(value: 1, child: Text('Aşağı taşı')),
        ],
      ),
      ExcludeSemantics(
        child: ReorderableDragStartListener(
          index: index,
          child: const SizedBox(width: 48, height: 48, child: Icon(Icons.drag_handle_rounded)),
        ),
      ),
    ],
  );
}
