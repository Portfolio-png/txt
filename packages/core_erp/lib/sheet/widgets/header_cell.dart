import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../column_def.dart';
import '../sheet_def.dart';
import '../sheet_metrics.dart';
import '../sheet_controller.dart';

class HeaderCell extends StatefulWidget {
  const HeaderCell({
    super.key,
    required this.column,
    required this.sheetDef,
    required this.controller,
    required this.width,
    this.metrics = SheetMetrics.fallback,
  });

  final ColumnDef column;
  final SheetDef sheetDef;
  final SheetController controller;
  final double width;
  final SheetMetrics metrics;

  @override
  State<HeaderCell> createState() => _HeaderCellState();
}

class _HeaderCellState extends State<HeaderCell> {
  bool _hovered = false;

  /// True while the column menu is open. Opening it lays a barrier over the
  /// header, which ends the hover; the button, shown only on hover, was then
  /// unmounted under its own menu and PopupMenuButton dropped the pick — the
  /// group card's Edit menu had the same fault.
  bool _menuOpen = false;

  void _setMenuOpen(bool open) {
    if (mounted && _menuOpen != open) setState(() => _menuOpen = open);
  }
  bool _isEditingName = false;
  late final TextEditingController _nameController;
  final FocusNode _focusNode = FocusNode();

  /// The key listener's own node — held, not made in build, where a new one
  /// per rebuild (one per keystroke while typing) was never disposed.
  final FocusNode _keyListenerNode = FocusNode(skipTraversal: true);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.column.label);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        widget.controller.focusCell(widget.column.id, isHeader: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant HeaderCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.column.label != widget.column.label && !_isEditingName) {
      _nameController.text = widget.column.label;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    _keyListenerNode.dispose();
    super.dispose();
  }

  void _commitName() {
    setState(() => _isEditingName = false);
    if (_nameController.text.trim().isNotEmpty) {
      widget.controller.renameColumn(
        widget.column.id,
        _nameController.text.trim(),
      );
    } else {
      _nameController.text = widget.column.label;
    }
  }

  void _cancelName() {
    setState(() => _isEditingName = false);
    _nameController.text = widget.column.label;
  }

  @override
  Widget build(BuildContext context) {
    final isFocused =
        widget.controller.focusedColumnId == widget.column.id &&
        widget.controller.isHeaderFocused;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        width: widget.width,
        height: widget.metrics.headerHeight,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: SoftErpTheme.shellSurface,
          border: Border(
            right: const BorderSide(color: SoftErpTheme.border),
            bottom: const BorderSide(color: SoftErpTheme.borderStrong, width: 1.5),
            top: isFocused
                ? const BorderSide(color: SoftErpTheme.accent, width: 2)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            // Column Name (editable inline)
            Expanded(
              child: _isEditingName
                  ? KeyboardListener(
                      focusNode: _keyListenerNode,
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.escape) {
                          _cancelName();
                        }
                      },
                      child: TextField(
                        controller: _nameController,
                        focusNode: _focusNode,
                        autofocus: true,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: SoftErpTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _commitName(),
                        onTapOutside: (_) => _commitName(),
                      ),
                    )
                  : InkWell(
                      onDoubleTap: widget.column.isDefault
                          ? null
                          : () => setState(() => _isEditingName = true),
                      onTap: () {
                        widget.controller.focusCell(
                          widget.column.id,
                          isHeader: true,
                        );
                      },
                      child: Tooltip(
                        // Without this a truncated name was unrecoverable: the
                        // only other way to read it was to double-click into the
                        // rename field.
                        message: widget.column.label,
                        waitDuration: const Duration(milliseconds: 400),
                        child: Text(
                          widget.column.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: widget.metrics.labelFontSize,
                            fontWeight: FontWeight.w700,
                            color: widget.column.isDefault
                                ? SoftErpTheme.textPrimary
                                : SoftErpTheme.textPrimary,
                          ),
                        ),
                      ),
                    ),
            ),

            // The kind badge and the parent icon used to sit here, inline with
            // the label, and between them took 40-63px of a column as narrow as
            // 125px — on Part Code the badge alone was nearly the whole label
            // budget. Neither is urgent while reading a sheet: the badge now
            // shows on hover, and hierarchy is in the sidebar's COLUMN TREE and
            // in the menu that sets it.
            if (_hovered && !widget.column.isStamp) _buildKindTag(),

            // Reserved 16px on every header forever; now it earns its place only
            // when the pointer is on the column or the column is focused.
            if (!widget.column.isStamp && (_hovered || isFocused || _menuOpen))
              _buildMoreMenu(context),
          ],
        ),
      ),
    );
  }

  Widget _buildParentIcon(BuildContext context) {
    if (widget.column.isGroup || widget.column.isStamp) {
      return const SizedBox(width: 14);
    }

    final isDependent = widget.column.parentId != null;
    return Tooltip(
      message: isDependent
          ? 'Sits under ${widget.sheetDef.getColumn(widget.column.parentId!)?.label}. Click to reparent.'
          : 'Primary Group. Click to reparent.',
      child: InkWell(
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
        onTap: () => _showReparentMenu(context),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            isDependent
                ? Icons.subdirectory_arrow_right_rounded
                : Icons.crop_square_rounded,
            size: 14,
            color: isDependent
                ? SoftErpTheme.infoText
                : SoftErpTheme.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildKindTag() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: SoftErpTheme.border,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.column.kindTag,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SoftErpTheme.textSecondary,
            ),
          ),
          if (widget.column.isDefault)
            const Text(
              '*',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.dangerText,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMoreMenu(BuildContext context) {
    final (canLeft, _) = widget.sheetDef.canMoveLeft(widget.column.id);
    final (canRight, _) = widget.sheetDef.canMoveRight(widget.column.id);
    final (canRem, _) = widget.sheetDef.canRemove(widget.column.id);

    return SizedBox(
      width: 16,
      height: 26,
      child: PopupMenuButton<String>(
        tooltip: 'Column options',
        padding: EdgeInsets.zero,
        iconSize: 13,
        icon: const Icon(
          Icons.more_vert_rounded,
          size: 13,
          color: SoftErpTheme.textMuted,
        ),
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: 'rename',
            enabled: !widget.column.isDefault,
            child: const Text('Rename column', style: TextStyle(fontSize: 14)),
          ),
          PopupMenuItem(
            value: 'reparent',
            enabled: !widget.column.isGroup && !widget.column.isStamp,
            child: const Text(
              'Change parent...',
              style: TextStyle(fontSize: 14),
            ),
          ),
          PopupMenuItem(
            value: 'move_left',
            enabled: canLeft,
            child: const Text('Move left', style: TextStyle(fontSize: 14)),
          ),
          PopupMenuItem(
            value: 'move_right',
            enabled: canRight,
            child: const Text('Move right', style: TextStyle(fontSize: 14)),
          ),
          if (widget.controller.canEditOptions?.call(widget.column) ?? false)
            const PopupMenuItem(
              value: 'options',
              child: Text('Edit options…', style: TextStyle(fontSize: 14)),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'remove',
            enabled: canRem,
            child: const Text(
              'Remove column',
              style: TextStyle(fontSize: 14, color: SoftErpTheme.dangerText),
            ),
          ),
        ],
        onOpened: () => _setMenuOpen(true),
        onCanceled: () => _setMenuOpen(false),
        onSelected: (val) {
          _setMenuOpen(false);
          switch (val) {
            case 'rename':
              setState(() => _isEditingName = true);
              break;
            case 'reparent':
              _showReparentMenu(context);
              break;
            case 'move_left':
              widget.controller.moveColumn(widget.column.id, -1);
              break;
            case 'move_right':
              widget.controller.moveColumn(widget.column.id, 1);
              break;
            case 'options':
              widget.controller.onEditOptions?.call(widget.column);
              break;
            case 'remove':
              widget.controller.requestRemoveColumn(widget.column.id);
              break;
          }
        },
      ),
    );
  }

  void _showReparentMenu(BuildContext context) {
    final candidateParents = widget.sheetDef.columns
        .where(
          (c) =>
              c.kind == ColumnKind.list && c.position < widget.column.position,
        )
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Reparent "${widget.column.label}"',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select a parent list column to its left, or set as Primary Group:',
              style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            ListTile(
              dense: true,
              leading: const Icon(Icons.crop_square_rounded, size: 18),
              title: const Text(
                'Primary Group (Root)',
                style: TextStyle(fontSize: 14),
              ),
              selected: widget.column.parentId == null,
              onTap: () {
                Navigator.of(ctx).pop();
                widget.controller.reparentColumn(widget.column.id, null);
              },
            ),
            ...candidateParents.map(
              (p) => ListTile(
                dense: true,
                leading: const Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 18,
                  color: SoftErpTheme.accent,
                ),
                title: Text(
                  '${p.label} (Col ${p.position + 1})',
                  style: const TextStyle(fontSize: 14),
                ),
                selected: widget.column.parentId == p.id,
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.controller.reparentColumn(widget.column.id, p.id);
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
