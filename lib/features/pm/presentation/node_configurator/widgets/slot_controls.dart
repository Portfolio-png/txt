import 'package:flutter/material.dart';

import '../domain/node_blueprint.dart';

/// A one-line reading of a slot's state, tinted by [SlotTone].
class SlotChip extends StatelessWidget {
  const SlotChip({
    super.key,
    required this.icon,
    required this.label,
    required this.tone,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final SlotTone tone;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final style = styleForTone(tone);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 12 : 14, color: style.foreground),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: style.foreground,
                fontSize: dense ? 11 : 12,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SlotModeOption<T> {
  const SlotModeOption({
    required this.value,
    required this.label,
    required this.blurb,
    required this.icon,
    required this.tone,
  });

  final T value;
  final String label;

  /// Shown on hover and, for the selected option, as the slot's one caption
  /// line. Never rendered four times at once.
  final String blurb;
  final IconData icon;
  final SlotTone tone;
}

/// A row of mode pills with a single caption underneath.
///
/// The modes need explaining — "None" and "At run time" both leave the field
/// blank and mean opposite things — but explaining all of them at once buries
/// the screen in prose. So only the selected mode speaks, and [caption] lets
/// the parent make that line say something concrete about the current pairing
/// rather than repeating the generic blurb.
class SlotModeSelector<T> extends StatelessWidget {
  const SlotModeSelector({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.caption,
    this.captionTone,
  });

  final List<SlotModeOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? caption;
  final SlotTone? captionTone;

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );
    final line = caption ?? selected.blurb;
    final tone = captionTone ?? selected.tone;
    final style = styleForTone(tone);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in options)
              _ModePill<T>(
                key: ValueKey('slot_mode_${option.value}'),
                option: option,
                selected: option.value == value,
                onTap: () => onChanged(option.value),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(selected.icon, size: 13, color: style.foreground),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                line,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: style.foreground,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModePill<T> extends StatelessWidget {
  const _ModePill({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SlotModeOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = styleForTone(option.tone);

    return Tooltip(
      message: option.blurb,
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? style.background : const Color(0xFFFDFDFF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? style.foreground : const Color(0xFFE6E8F4),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  option.icon,
                  size: 14,
                  color: selected
                      ? style.foreground
                      : const Color(0xFF9AA0B2),
                ),
                const SizedBox(width: 6),
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? style.foreground
                        : const Color(0xFF6C7386),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pickable asset. Incompatible options stay visible but locked with the
/// reason attached — a die vanishing from the picker teaches nothing.
class AssetChoice {
  const AssetChoice({
    required this.id,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    this.disabledReason,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool enabled;
  final String? disabledReason;
}

class AssetChoicePicker extends StatelessWidget {
  const AssetChoicePicker({
    super.key,
    required this.choices,
    required this.selectedId,
    required this.onChanged,
    required this.emptyLabel,
  });

  final List<AssetChoice> choices;
  final String? selectedId;
  final ValueChanged<String> onChanged;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (choices.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFDEDEE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF6D6D8)),
        ),
        child: Text(
          emptyLabel,
          style: const TextStyle(fontSize: 12, color: Color(0xFFC62828)),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final choice in choices)
          _AssetChip(
            choice: choice,
            selected: choice.id == selectedId,
            onTap: choice.enabled ? () => onChanged(choice.id) : null,
          ),
      ],
    );
  }
}

class _AssetChip extends StatelessWidget {
  const _AssetChip({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final AssetChoice choice;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = !choice.enabled;
    final background = disabled
        ? const Color(0xFFF6F7FB)
        : selected
        ? const Color(0xFFF1EEFF)
        : const Color(0xFFFDFDFF);
    final borderColor = disabled
        ? const Color(0xFFE6E8F4)
        : selected
        ? const Color(0xFF4740B7)
        : const Color(0xFFE6E8F4);
    final titleColor = disabled
        ? const Color(0xFF9AA0B2)
        : selected
        ? const Color(0xFF4740B7)
        : const Color(0xFF303646);

    final chip = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (disabled) ...[
              const Icon(Icons.lock_outline, size: 12, color: Color(0xFF9AA0B2)),
              const SizedBox(width: 5),
            ] else if (selected) ...[
              const Icon(Icons.check, size: 12, color: Color(0xFF4740B7)),
              const SizedBox(width: 5),
            ],
            Text(
              choice.title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: titleColor,
                height: 1.15,
              ),
            ),
            if (choice.subtitle.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                choice.subtitle,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.15,
                  color: disabled
                      ? const Color(0xFFB0B5C4)
                      : const Color(0xFF9AA0B2),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (disabled && choice.disabledReason != null) {
      return Tooltip(message: choice.disabledReason!, child: chip);
    }
    return chip;
  }
}
