import 'package:flutter/material.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';

class DropdownOption<T> {
  const DropdownOption({
    required this.value,
    required this.label,
    this.subtitle,
  });

  final T value;
  final String label;
  final String? subtitle;
}

/// A mobile-friendly dropdown selector widget that opens a Modal Bottom Sheet
/// without automatically focusing the keyboard or opening the software keyboard
/// on page load. The search field only receives focus when explicitly tapped.
class DropdownSelector<T> extends StatelessWidget {
  const DropdownSelector({
    super.key,
    required this.options,
    required this.onChanged,
    this.selectedValue,
    this.label,
    this.hintText = 'Select option',
    this.enableSearch = true,
  });

  final List<DropdownOption<T>> options;
  final T? selectedValue;
  final ValueChanged<T> onChanged;
  final String? label;
  final String hintText;
  final bool enableSearch;

  String _selectedLabel() {
    if (selectedValue == null) return hintText;
    final match = options.where((o) => o.value == selectedValue).firstOrNull;
    return match?.label ?? hintText;
  }

  void _showSelectorSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _DropdownSheetContent<T>(
        options: options,
        selectedValue: selectedValue,
        onSelected: (val) {
          Navigator.of(sheetContext).pop();
          onChanged(val);
        },
        title: label ?? hintText,
        enableSearch: enableSearch,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedValue != null;
    return InkWell(
      onTap: () => _showSelectorSheet(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (label != null) ...[
                    Text(
                      label!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: SoftErpTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    _selectedLabel(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: hasSelection ? FontWeight.w600 : FontWeight.normal,
                      color: hasSelection ? SoftErpTheme.textPrimary : SoftErpTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: SoftErpTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _DropdownSheetContent<T> extends StatefulWidget {
  const _DropdownSheetContent({
    required this.options,
    required this.onSelected,
    required this.title,
    this.selectedValue,
    this.enableSearch = true,
  });

  final List<DropdownOption<T>> options;
  final T? selectedValue;
  final ValueChanged<T> onSelected;
  final String title;
  final bool enableSearch;

  @override
  State<_DropdownSheetContent<T>> createState() => _DropdownSheetContentState<T>();
}

class _DropdownSheetContentState<T> extends State<_DropdownSheetContent<T>> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.options.where((o) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return o.label.toLowerCase().contains(q) ||
          (o.subtitle?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            if (widget.enableSearch && widget.options.length > 5) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                focusNode: _focusNode, // DOES NOT auto-focus on open
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (q) => setState(() => _query = q.trim()),
              ),
            ],
            const SizedBox(height: 12),
            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No options found',
                          style: TextStyle(color: SoftErpTheme.textSecondary),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final opt = filtered[index];
                        final isSelected = opt.value == widget.selectedValue;
                        return ListTile(
                          title: Text(
                            opt.label,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? SoftErpTheme.accent : SoftErpTheme.textPrimary,
                            ),
                          ),
                          subtitle: opt.subtitle != null ? Text(opt.subtitle!) : null,
                          trailing: isSelected
                              ? const Icon(Icons.check, color: SoftErpTheme.accent)
                              : null,
                          onTap: () => widget.onSelected(opt.value),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
