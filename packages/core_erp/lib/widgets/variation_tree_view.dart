import 'package:flutter/material.dart';
import 'package:paper/features/items/domain/item_definition.dart';

typedef VariationNode = ItemVariationNodeDefinition;

class VariationTreeView extends StatefulWidget {
  const VariationTreeView({
    super.key,
    required this.roots,
    required this.onLeafSelected,
    this.selectedNodeIds = const <String>{},
    this.enabled = true,
    this.maxHeight = 400,
  });

  final List<VariationNode> roots;
  final void Function(VariationNode leaf, List<String> pathNodeIds)
  onLeafSelected;
  final Set<String> selectedNodeIds;
  final bool enabled;
  final double maxHeight;

  @override
  State<VariationTreeView> createState() => _VariationTreeViewState();
}

class _VariationTreeViewState extends State<VariationTreeView> {
  final Set<String> _expandedNodeIds = <String>{};
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  Set<String>? _internalSelectedNodeIds;

  Set<String> get _effectiveSelectedNodeIds =>
      _internalSelectedNodeIds ?? widget.selectedNodeIds;

  @override
  void initState() {
    super.initState();
    _syncInitialExpansion();
  }

  @override
  void didUpdateWidget(covariant VariationTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roots != widget.roots) {
      _syncInitialExpansion(resetDeeperExpansions: false);
    }
    if (widget.selectedNodeIds.length != oldWidget.selectedNodeIds.length ||
        !widget.selectedNodeIds.containsAll(oldWidget.selectedNodeIds)) {
      _internalSelectedNodeIds = null;
    }
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  void _syncInitialExpansion({bool resetDeeperExpansions = true}) {
    final activeRoots = _filterArchived(widget.roots);
    final rootIds = activeRoots
        .where((node) => node.kind == ItemVariationNodeKind.property)
        .map(_nodeId)
        .toSet();
    if (resetDeeperExpansions) {
      _expandedNodeIds
        ..clear()
        ..addAll(rootIds);
      return;
    }
    _expandedNodeIds.addAll(rootIds);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeRoots = _filterArchived(widget.roots);
    final selectedPathIds = _selectedPathIds(
      activeRoots,
      _effectiveSelectedNodeIds,
    );
    final hasSelection = selectedPathIds.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Scrollbar(
          controller: _verticalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _verticalController,
            padding: const EdgeInsets.all(12),
            child: Scrollbar(
              controller: _horizontalController,
              thumbVisibility: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth == double.infinity
                            ? 0
                            : constraints.maxWidth,
                      ),
                      child: activeRoots.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'No variation options available',
                                style: theme.textTheme.bodyMedium,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: activeRoots
                                  .map(
                                    (node) => _buildNode(
                                      context,
                                      node: node,
                                      depth: 0,
                                      valuePath: const <String>[],
                                      pathNodeIds: const <String>[],
                                      selectedPathIds: selectedPathIds,
                                      hasSelection: hasSelection,
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNode(
    BuildContext context, {
    required VariationNode node,
    required int depth,
    required List<String> valuePath,
    required List<String> pathNodeIds,
    required Set<String> selectedPathIds,
    required bool hasSelection,
  }) {
    final theme = Theme.of(context);
    final activeChildren = _filterArchived(node.children);
    final currentNodeId = _nodeId(node);
    final currentPathIds = _collectPathNodeIds(pathNodeIds, node);
    final currentValuePath = node.kind == ItemVariationNodeKind.value
        ? <String>[...valuePath, node.name.trim()]
        : valuePath;
    final isExpandable = activeChildren.isNotEmpty;
    final isLeaf = _isLeafValue(node, activeChildren);
    final isSelected = _effectiveSelectedNodeIds.contains(currentNodeId);
    final isOnSelectedPath = _isNodeOnSelectedPath(
      currentNodeId,
      selectedPathIds,
    );
    final containsSelectedLeaf = _subtreeContainsLeaf(
      node,
      _effectiveSelectedNodeIds,
    );
    final isRelatedToSelection =
        !hasSelection || isOnSelectedPath || containsSelectedLeaf;
    final rowColor = isOnSelectedPath
        ? theme.colorScheme.primary.withValues(alpha: isSelected ? 0.18 : 0.10)
        : Colors.transparent;
    final iconColor = isOnSelectedPath
        ? theme.colorScheme.primary
        : theme.iconTheme.color;
    final label = isLeaf
        ? _displayLabelForLeaf(node, currentValuePath)
        : node.name;
    final labelStyle =
        (node.kind == ItemVariationNodeKind.property
                ? theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )
                : theme.textTheme.bodyMedium)
            ?.copyWith(color: widget.enabled ? null : theme.disabledColor);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: isRelatedToSelection ? 1 : 0.45,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: depth * 20.0),
            child: Material(
              color: rowColor,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: !widget.enabled
                    ? null
                    : isLeaf
                    ? () => _handleNodeTap(node, currentPathIds)
                    : isExpandable
                    ? () => _toggleExpanded(currentNodeId)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        child: isExpandable
                            ? Icon(
                                _expandedNodeIds.contains(currentNodeId)
                                    ? Icons.expand_more
                                    : Icons.chevron_right,
                                size: 18,
                                color: iconColor,
                              )
                            : const SizedBox.shrink(),
                      ),
                      Icon(
                        node.kind == ItemVariationNodeKind.property
                            ? Icons.tune
                            : Icons.circle,
                        size: node.kind == ItemVariationNodeKind.property
                            ? 18
                            : 10,
                        color: iconColor,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          style: labelStyle,
                          overflow: TextOverflow.visible,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isExpandable && _expandedNodeIds.contains(currentNodeId))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: activeChildren
                  .map(
                    (child) => _buildNode(
                      context,
                      node: child,
                      depth: depth + 1,
                      valuePath: currentValuePath,
                      pathNodeIds: currentPathIds,
                      selectedPathIds: selectedPathIds,
                      hasSelection: hasSelection,
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }

  void _toggleExpanded(String nodeId) {
    setState(() {
      if (_expandedNodeIds.contains(nodeId)) {
        _expandedNodeIds.remove(nodeId);
      } else {
        _expandedNodeIds.add(nodeId);
      }
    });
  }

  void _handleNodeTap(VariationNode leaf, List<String> pathNodeIds) {
    setState(() {
      _internalSelectedNodeIds = pathNodeIds.toSet();
      _expandedNodeIds.addAll(pathNodeIds);
    });
    widget.onLeafSelected(leaf, pathNodeIds);
  }

  List<VariationNode> _filterArchived(List<VariationNode> nodes) {
    return nodes.where((node) => !node.isArchived).toList(growable: false);
  }

  bool _isLeafValue(VariationNode node, [List<VariationNode>? activeChildren]) {
    final visibleChildren = activeChildren ?? _filterArchived(node.children);
    return node.kind == ItemVariationNodeKind.value && visibleChildren.isEmpty;
  }

  bool _isNodeOnSelectedPath(String nodeId, Set<String> selectedPathIds) {
    return selectedPathIds.contains(nodeId);
  }

  String _displayLabelForLeaf(VariationNode node, List<String> valuePath) {
    final explicit = node.displayName.trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }
    return _generatePathLabel(valuePath);
  }

  String _generatePathLabel(List<String> valuePath) {
    final values = valuePath
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return values.join(' | ');
  }

  List<String> _collectPathNodeIds(List<String> existing, VariationNode node) {
    return <String>[...existing, _nodeId(node)];
  }

  Set<String> _selectedPathIds(
    List<VariationNode> roots,
    Set<String> selectedNodeIds,
  ) {
    if (selectedNodeIds.isEmpty) {
      return <String>{};
    }
    final allPaths = <String>{};
    for (final root in roots) {
      for (final selectedId in selectedNodeIds) {
        final path = _findPathNodeIds(root, selectedId, const <String>[]);
        if (path.isNotEmpty) {
          allPaths.addAll(path);
          break;
        }
      }
    }
    return allPaths;
  }

  List<String> _findPathNodeIds(
    VariationNode node,
    String selectedLeafId,
    List<String> currentPath,
  ) {
    final nextPath = _collectPathNodeIds(currentPath, node);
    if (_nodeId(node) == selectedLeafId) {
      return nextPath;
    }
    for (final child in _filterArchived(node.children)) {
      final path = _findPathNodeIds(child, selectedLeafId, nextPath);
      if (path.isNotEmpty) {
        return path;
      }
    }
    return const <String>[];
  }

  bool _subtreeContainsLeaf(VariationNode node, Set<String> selectedNodeIds) {
    if (selectedNodeIds.isEmpty) {
      return false;
    }
    if (selectedNodeIds.contains(_nodeId(node))) {
      return true;
    }
    for (final child in _filterArchived(node.children)) {
      if (_subtreeContainsLeaf(child, selectedNodeIds)) {
        return true;
      }
    }
    return false;
  }

  String _nodeId(VariationNode node) => node.id.toString();
}

// Example usage:
// VariationTreeView(
//   roots: item.variationTree,
//   selectedLeafId: selectedLeafId,
//   onLeafSelected: (leaf, pathNodeIds) {
//     debugPrint('Selected: ${leaf.displayName} -> $pathNodeIds');
//   },
// )
