import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../data/rivet_repository.dart';
import '../data/spring_repository.dart';
import '../domain/rivet.dart';
import '../domain/spring.dart';
import 'rivet_form_dialog.dart';
import 'spring_form_dialog.dart';

/// What the item editor is editing: the plain item, or one of the raw-material
/// forms. Owner, 2026-11-25: "give two checks for Rivet and Spring, or is it
/// item, so you can switch between them".
enum ItemKind {
  item('Item', Icons.inventory_2_outlined),
  rivet('Rivet', Icons.push_pin_outlined),
  spring('Spring', Icons.waves_outlined);

  const ItemKind(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The item editor with a rail down its left: Item, Rivet, Spring.
///
/// - A rivet (an item in Raw Materials › Rivets) opens on **Rivet**, a spring
///   (Raw Materials › Springs) on **Spring** — each its drawing form; Item
///   stays one click away for the photo, CAD and sets.
/// - Any other existing item opens on Item, and Rivet and Spring are drawn
///   disabled with why: a socket is not made a rivet by a click.
/// - A new item may be any of the three.
///
/// Both forms stay mounted once opened, so switching back and forth keeps
/// what was typed. No LayoutBuilder here: the item editor below holds a
/// reorderable list with tooltips, which crashes under one
/// (ReorderableList + LayoutBuilder trap) — the rail-or-row choice reads the
/// screen width instead.
class ItemKindSwitcher extends StatefulWidget {
  const ItemKindSwitcher({
    super.key,
    required this.itemEditor,
    required this.itemId,
    required this.isRivet,
    required this.onRivetSaved,
    required this.onClose,
    this.isSpring = false,
    this.onSpringSaved,
  });

  /// The plain item editor, as it was before the rail.
  final Widget itemEditor;

  /// Null for a new item.
  final int? itemId;

  /// Whether the existing item is filed under Raw Materials › Rivets.
  final bool isRivet;
  final ValueChanged<RivetDefinition> onRivetSaved;
  final VoidCallback onClose;

  /// Whether the existing item is filed under Raw Materials › Springs.
  final bool isSpring;
  final ValueChanged<SpringDefinition>? onSpringSaved;

  @override
  State<ItemKindSwitcher> createState() => _ItemKindSwitcherState();
}

class _ItemKindSwitcherState extends State<ItemKindSwitcher> {
  late ItemKind _kind = widget.isRivet
      ? ItemKind.rivet
      : widget.isSpring
      ? ItemKind.spring
      : ItemKind.item;
  final Set<ItemKind> _opened = <ItemKind>{};
  Future<RivetDefinition?>? _rivet;
  Future<SpringDefinition?>? _spring;

  bool get _isNew => widget.itemId == null;

  /// Why a kind cannot be picked, or null when it can.
  String? _blocked(ItemKind kind) {
    switch (kind) {
      case ItemKind.item:
        return null;
      case ItemKind.rivet:
        if (_isNew || widget.isRivet) return null;
        return 'Only an item in Raw Materials › Rivets is a rivet.';
      case ItemKind.spring:
        if (_isNew || widget.isSpring) return null;
        return 'Only an item in Raw Materials › Springs is a spring.';
    }
  }

  void _springSaved(SpringDefinition saved) =>
      (widget.onSpringSaved ?? (_) => widget.onClose())(saved);

  Widget _springForm() {
    if (_isNew) {
      return SpringFormDialog(onSaved: _springSaved, onCancel: widget.onClose);
    }
    _spring ??= widget.itemId == null
        ? Future<SpringDefinition?>.value(null)
        : context.read<SpringRepository>().get(widget.itemId!);
    return FutureBuilder<SpringDefinition?>(
      future: _spring,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Surface(
            child: SizedBox(
              height: 320,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return _Surface(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not open the spring: ${snapshot.error}',
                style: const TextStyle(
                  fontSize: 14,
                  color: SoftErpTheme.dangerText,
                ),
              ),
            ),
          );
        }
        return SpringFormDialog(
          spring: snapshot.data,
          // Filed under Springs from the item form, with no spec yet: saving
          // gives this item its spec rather than making another spring.
          attachToItemId: snapshot.data == null ? widget.itemId : null,
          onSaved: _springSaved,
          onCancel: widget.onClose,
        );
      },
    );
  }

  Future<RivetDefinition?> _loadRivet() {
    final id = widget.itemId;
    if (id == null) return Future<RivetDefinition?>.value(null);
    return context.read<RivetRepository>().get(id);
  }

  Widget _rivetForm() {
    if (_isNew) {
      return RivetFormDialog(
        onSaved: widget.onRivetSaved,
        onCancel: widget.onClose,
      );
    }
    _rivet ??= _loadRivet();
    return FutureBuilder<RivetDefinition?>(
      future: _rivet,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Surface(
            child: SizedBox(
              height: 320,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return _Surface(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not open the rivet: ${snapshot.error}',
                style: const TextStyle(
                  fontSize: 14,
                  color: SoftErpTheme.dangerText,
                ),
              ),
            ),
          );
        }
        return RivetFormDialog(
          rivet: snapshot.data,
          // Filed under Rivets from the item form, with no spec yet: saving
          // gives this item its spec rather than making another rivet.
          attachToItemId: snapshot.data == null ? widget.itemId : null,
          onSaved: widget.onRivetSaved,
          onCancel: widget.onClose,
        );
      },
    );
  }

  Widget _content(ItemKind kind) {
    switch (kind) {
      case ItemKind.item:
        return widget.itemEditor;
      case ItemKind.rivet:
        return _rivetForm();
      case ItemKind.spring:
        return _springForm();
    }
  }

  @override
  Widget build(BuildContext context) {
    _opened.add(_kind);
    final narrow = MediaQuery.of(context).size.width < 980;
    final content = Stack(
      children: <Widget>[
        for (final kind in ItemKind.values)
          if (_opened.contains(kind))
            Visibility(
              key: ValueKey<String>('item-kind-body-${kind.name}'),
              visible: kind == _kind,
              maintainState: true,
              child: _content(kind),
            ),
      ],
    );
    final rail = _Rail(
      selected: _kind,
      blocked: _blocked,
      horizontal: narrow,
      onPick: (kind) => setState(() => _kind = kind),
    );
    if (narrow) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          rail,
          const SizedBox(height: 10),
          Flexible(child: content),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        rail,
        const SizedBox(width: 12),
        Expanded(child: content),
      ],
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.selected,
    required this.blocked,
    required this.horizontal,
    required this.onPick,
  });

  final ItemKind selected;
  final String? Function(ItemKind kind) blocked;
  final bool horizontal;
  final ValueChanged<ItemKind> onPick;

  @override
  Widget build(BuildContext context) {
    final entries = <Widget>[
      for (final kind in ItemKind.values)
        _RailEntry(
          kind: kind,
          selected: kind == selected,
          reason: blocked(kind),
          horizontal: horizontal,
          onTap: () => onPick(kind),
        ),
    ];
    return _Surface(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: horizontal
            ? Row(
                children: <Widget>[for (final e in entries) Expanded(child: e)],
              )
            : SizedBox(
                width: 150,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(8, 4, 8, 10),
                      child: Text(
                        'EDITING',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                    ),
                    for (final e in entries) ...<Widget>[
                      e,
                      const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _RailEntry extends StatelessWidget {
  const _RailEntry({
    required this.kind,
    required this.selected,
    required this.reason,
    required this.horizontal,
    required this.onTap,
  });

  final ItemKind kind;
  final bool selected;

  /// Why it cannot be picked; null when it can. Drawn disabled, never hidden.
  final String? reason;
  final bool horizontal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = reason == null;
    final color = selected
        ? Colors.white
        : enabled
        ? SoftErpTheme.textPrimary
        : SoftErpTheme.textMuted;
    final tile = Material(
      color: selected ? SoftErpTheme.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey<String>('item-kind-${kind.name}'),
        borderRadius: BorderRadius.circular(12),
        onTap: enabled && !selected ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: horizontal
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: <Widget>[
              Icon(kind.icon, size: 20, color: color),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  kind.label,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      selected: selected,
      enabled: enabled,
      button: true,
      child: enabled ? tile : Tooltip(message: reason!, child: tile),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: child,
    );
  }
}
