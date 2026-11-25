import 'package:flutter/material.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../domain/spring.dart';

/// How a raw material's name is put together: its blocks in order, each
/// joined to the one before by a space, X, + or -, and the blocks not in the
/// name offered to add (owner, 2026-11-25: "give naming format to rearrange
/// name with 'x' '+' '-' symbols").
///
/// The item editor's Naming Format, made for a built name: blocks move with
/// ← and → (and the keyboard), a separator is picked between each pair, × takes
/// a block out, + puts one in. [onChanged] gets the whole new order.
class NamingFormatEditor extends StatelessWidget {
  const NamingFormatEditor({
    super.key,
    required this.tokens,
    required this.blocks,
    required this.labelOf,
    required this.onChanged,
    this.onReset,
  });

  /// The name's blocks, in order.
  final List<NameToken> tokens;

  /// Every block the name may hold.
  final List<String> blocks;
  final String Function(String block) labelOf;
  final ValueChanged<List<NameToken>> onChanged;

  /// Back to the default order; null hides the button.
  final VoidCallback? onReset;

  void _move(int from, int to) {
    final next = List<NameToken>.of(tokens);
    final token = next.removeAt(from);
    next.insert(to, token);
    onChanged(next);
  }

  void _setSep(int index, NameSeparator sep) {
    final next = List<NameToken>.of(tokens);
    next[index] = next[index].withSep(sep);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final inName = {for (final t in tokens) t.block};
    final available = [
      for (final b in blocks)
        if (!inName.contains(b)) b,
    ];
    final row = <Widget>[];
    for (var i = 0; i < tokens.length; i += 1) {
      if (i > 0) {
        row.add(
          _SeparatorPicker(
            key: ValueKey<String>('name-sep-${tokens[i].block}'),
            value: tokens[i].sep,
            onChanged: (sep) => _setSep(i, sep),
          ),
        );
      }
      row.add(
        _BlockChip(
          key: ValueKey<String>('name-token-${tokens[i].block}'),
          block: tokens[i].block,
          label: labelOf(tokens[i].block),
          onLeft: i == 0 ? null : () => _move(i, i - 1),
          onRight: i == tokens.length - 1 ? null : () => _move(i, i + 1),
          // The name keeps at least one block.
          onRemove: tokens.length <= 1
              ? null
              : () => onChanged([...tokens]..removeAt(i)),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Naming Format',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
              ),
              if (onReset != null)
                TextButton(
                  key: const ValueKey<String>('name-reset'),
                  onPressed: onReset,
                  child: const Text('Reset', style: TextStyle(fontSize: 14)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'The name’s blocks in order. Move them with ← →, pick what joins two '
            'blocks (space, X, + or -), × takes one out.',
            style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: SoftErpTheme.sectionSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: row,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Available Blocks (click + to include):',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: SoftErpTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (available.isEmpty)
            const Text(
              'Every block is in the name.',
              style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final block in available)
                  ActionChip(
                    key: ValueKey<String>('name-add-$block'),
                    avatar: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      labelOf(block),
                      style: const TextStyle(fontSize: 14),
                    ),
                    onPressed: () => onChanged([...tokens, NameToken(block)]),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BlockChip extends StatelessWidget {
  const _BlockChip({
    super.key,
    required this.block,
    required this.label,
    required this.onLeft,
    required this.onRight,
    required this.onRemove,
  });

  final String block;
  final String label;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    Widget icon(String key, IconData data, String tip, VoidCallback? onTap) =>
        IconButton(
          key: ValueKey<String>('name-$key-$block'),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          padding: EdgeInsets.zero,
          iconSize: 18,
          onPressed: onTap,
          icon: Icon(data),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: SoftErpTheme.accentSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SoftErpTheme.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          icon('left', Icons.chevron_left_rounded, 'Move earlier', onLeft),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          icon('right', Icons.chevron_right_rounded, 'Move later', onRight),
          icon('remove', Icons.close_rounded, 'Take out of the name', onRemove),
        ],
      ),
    );
  }
}

/// The joiner between two blocks: space, X, + or -.
class _SeparatorPicker extends StatelessWidget {
  const _SeparatorPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final NameSeparator value;
  final ValueChanged<NameSeparator> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<NameSeparator>(
      tooltip: 'What joins these two blocks',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => <PopupMenuEntry<NameSeparator>>[
        for (final sep in NameSeparator.values)
          PopupMenuItem<NameSeparator>(
            key: ValueKey<String>('name-sep-option-${sep.name}'),
            value: sep,
            child: Text(sep.label, style: const TextStyle(fontSize: 14)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: SoftErpTheme.cardSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Text(
          value == NameSeparator.space ? '␣' : value.label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: SoftErpTheme.accentDark,
          ),
        ),
      ),
    );
  }
}
