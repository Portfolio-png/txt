import 'package:flutter/material.dart';

class PPFilterToolbar extends StatelessWidget {
  const PPFilterToolbar({
    super.key,
    required this.selectedFilters,
    required this.filterOptions,
    required this.selectedCount,
    required this.onFilterChanged,
    required this.onSortPressed,
    required this.onClearSelection,
    required this.isMobile,
    required this.sortAscending,
  });

  final Map<String, String> selectedFilters;
  final Map<String, List<String>> filterOptions;
  final int selectedCount;
  final void Function(String name, String value) onFilterChanged;
  final VoidCallback onSortPressed;
  final VoidCallback onClearSelection;
  final bool isMobile;
  final bool sortAscending;

  @override
  Widget build(BuildContext context) {
    final filterEntries = filterOptions.entries.toList();
    final filterRow = isMobile
        ? Wrap(
            spacing: 8,
            runSpacing: 8,
            children: filterEntries
                .map(
                  (entry) => _ToolbarFilterDropdown(
                    label: entry.key,
                    value: selectedFilters[entry.key] ?? entry.value.first,
                    options: entry.value,
                    onChanged: (next) {
                      if (next != null) {
                        onFilterChanged(entry.key, next);
                      }
                    },
                  ),
                )
                .toList(),
          )
        : _JoinedFilterBar(
            items: filterEntries
                .map(
                  (entry) => _JoinedFilterItem(
                    label: entry.key,
                    value: selectedFilters[entry.key] ?? entry.value.first,
                    options: entry.value,
                    showLeadingFilterIcon: entry.key == 'Party',
                    onChanged: (next) {
                      if (next != null) {
                        onFilterChanged(entry.key, next);
                      }
                    },
                  ),
                )
                .toList(),
          );

    final actionButtons = Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        _TextActionButton(
          label: 'Tertiary Button',
          variant: _ActionVariant.tertiary,
          onPressed: () {},
        ),
        _TextActionButton(
          label: 'Tertiary Button',
          variant: _ActionVariant.tertiaryActive,
          onPressed: () {},
        ),
        _TextActionButton(
          label: '+ Primary Button',
          variant: _ActionVariant.primary,
          onPressed: () {},
        ),
      ],
    );

    final controls = isMobile
        ? Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.end,
            children: [
              _SelectedAndControls(
                selectedCount: selectedCount,
                sortAscending: sortAscending,
                onClearSelection: onClearSelection,
                onSortPressed: onSortPressed,
              ),
            ],
          )
        : _SelectedAndControls(
            selectedCount: selectedCount,
            sortAscending: sortAscending,
            onClearSelection: onClearSelection,
            onSortPressed: onSortPressed,
          );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Heading',
            style: TextStyle(
              fontSize: 20,
              color: Color(0xFF3C3C3C),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          actionButtons,
          const SizedBox(height: 12),
          filterRow,
          const SizedBox(height: 8),
          controls,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final targetFilterWidth = maxWidth >= 1280
            ? 562.0
            : (maxWidth * 0.62).clamp(420.0, 562.0);
        final stackRows = maxWidth < 1200;

        if (stackRows) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Heading',
                    style: TextStyle(
                      fontSize: 20,
                      color: Color(0xFF3C3C3C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  actionButtons,
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(width: targetFilterWidth, child: filterRow),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: controls),
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                const Text(
                  'Heading',
                  style: TextStyle(
                    fontSize: 20,
                    color: Color(0xFF3C3C3C),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                actionButtons,
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(width: targetFilterWidth, child: filterRow),
                const Spacer(),
                controls,
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEDEDED),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF4F4F4F)),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF4F4F4F),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedAndControls extends StatelessWidget {
  const _SelectedAndControls({
    required this.selectedCount,
    required this.sortAscending,
    required this.onClearSelection,
    required this.onSortPressed,
  });

  final int selectedCount;
  final bool sortAscending;
  final VoidCallback onClearSelection;
  final VoidCallback onSortPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$selectedCount Selected',
          style: const TextStyle(fontSize: 11, color: Color(0xFF5E5E5E)),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: 'Clear selection',
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onClearSelection,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFFEDEDED),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.close,
                size: 19,
                color: Color(0xFF444444),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _ControlChip(
          label: 'Newest',
          icon: sortAscending ? Icons.arrow_downward : Icons.arrow_upward,
          onTap: onSortPressed,
        ),
        const SizedBox(width: 10),
        _ControlChip(label: 'Filters', icon: Icons.filter_list, onTap: () {}),
      ],
    );
  }
}

class _JoinedFilterBar extends StatelessWidget {
  const _JoinedFilterBar({required this.items});

  final List<_JoinedFilterItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        border: Border.all(color: const Color(0xFFCBCBCB)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Expanded(child: items[i]),
            if (i != items.length - 1)
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: Color(0xFFCBCBCB),
              ),
          ],
        ],
      ),
    );
  }
}

class _JoinedFilterItem extends StatelessWidget {
  const _JoinedFilterItem({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.showLeadingFilterIcon,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final bool showLeadingFilterIcon;

  @override
  Widget build(BuildContext context) {
    return _JoinedSegmentSelector(
      label: label,
      value: value,
      options: options,
      onChanged: onChanged,
      showLeadingFilterIcon: showLeadingFilterIcon,
    );
  }
}

class _JoinedSegmentSelector extends StatefulWidget {
  const _JoinedSegmentSelector({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.showLeadingFilterIcon,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final bool showLeadingFilterIcon;

  @override
  State<_JoinedSegmentSelector> createState() => _JoinedSegmentSelectorState();
}

class _JoinedSegmentSelectorState extends State<_JoinedSegmentSelector> {
  bool _open = false;

  Future<void> _openMenu() async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) {
      return;
    }

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final rect = Rect.fromPoints(topLeft, bottomRight);
    final menuWidth = box.size.width;

    setState(() => _open = true);
    final selected = await showMenu<String>(
      context: context,
      color: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(rect.left, rect.bottom + 4, menuWidth, 0),
        Offset.zero & overlay.size,
      ),
      items: widget.options
          .map(
            (option) => PopupMenuItem<String>(
              value: option,
              height: 34,
              child: SizedBox(
                width: menuWidth - 32,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: const Color(0xFF2F3744),
                          fontWeight: option == widget.value
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (option == widget.value)
                      const Icon(
                        Icons.check,
                        size: 14,
                        color: Color(0xFF6049E3),
                      ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );

    if (!mounted) {
      return;
    }
    setState(() => _open = false);
    if (selected != null) {
      widget.onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _openMenu,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              if (widget.showLeadingFilterIcon) ...[
                const Icon(
                  Icons.filter_alt_outlined,
                  size: 12,
                  color: Color(0xFF2F3744),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  '${widget.label}: ${widget.value}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF2F3744),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: const Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: Color(0xFF5E5E5E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarFilterDropdown extends StatelessWidget {
  const _ToolbarFilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: _AnimatedFilterSelector(
          text: '$label: $value',
          selectedValue: value,
          options: options,
          label: label,
          onChanged: onChanged,
          textStyle: const TextStyle(fontSize: 11, color: Color(0xFF5E5E5E)),
          compact: false,
        ),
      ),
    );
  }
}

class _AnimatedFilterSelector extends StatefulWidget {
  const _AnimatedFilterSelector({
    required this.text,
    required this.selectedValue,
    required this.options,
    required this.label,
    required this.onChanged,
    required this.textStyle,
    required this.compact,
  });

  final String text;
  final String selectedValue;
  final List<String> options;
  final String label;
  final ValueChanged<String?> onChanged;
  final TextStyle textStyle;
  final bool compact;

  @override
  State<_AnimatedFilterSelector> createState() =>
      _AnimatedFilterSelectorState();
}

class _AnimatedFilterSelectorState extends State<_AnimatedFilterSelector> {
  bool _open = false;

  Future<void> _openAnchoredMenu() async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) {
      return;
    }

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final rect = Rect.fromPoints(topLeft, bottomRight);

    setState(() => _open = true);
    final selected = await showMenu<String>(
      context: context,
      color: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(rect.left, rect.bottom + 6, rect.width, 0),
        Offset.zero & overlay.size,
      ),
      items: widget.options
          .map(
            (option) => PopupMenuItem<String>(
              value: option,
              height: 38,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      option,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: widget.compact ? 13 : 11,
                        color: const Color(0xFF2F3744),
                        fontWeight: option == widget.selectedValue
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (option == widget.selectedValue)
                    const Icon(Icons.check, size: 14, color: Color(0xFF6049E3)),
                ],
              ),
            ),
          )
          .toList(),
    );
    if (!mounted) {
      return;
    }
    setState(() => _open = false);
    if (selected != null) {
      widget.onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _openAnchoredMenu,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: widget.textStyle,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: widget.compact ? 20 : 16,
                  color: const Color(0xFF5E5E5E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ActionVariant { tertiary, tertiaryActive, primary }

class _TextActionButton extends StatelessWidget {
  const _TextActionButton({
    required this.label,
    required this.variant,
    required this.onPressed,
  });

  final String label;
  final _ActionVariant variant;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isPrimary = variant == _ActionVariant.primary;
    final isActiveTertiary = variant == _ActionVariant.tertiaryActive;

    return SizedBox(
      width: 176,
      height: 38,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: isPrimary ? const Color(0xFF6049E3) : Colors.white,
          foregroundColor: isPrimary
              ? Colors.white
              : isActiveTertiary
              ? const Color(0xFF6049E3)
              : const Color(0xFF5E5E5E),
          side: BorderSide(
            color: isPrimary
                ? const Color(0xFF6049E3)
                : isActiveTertiary
                ? const Color(0xFF8E7EF5)
                : const Color(0xFFDCDCDC),
            width: isActiveTertiary ? 2 : 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
