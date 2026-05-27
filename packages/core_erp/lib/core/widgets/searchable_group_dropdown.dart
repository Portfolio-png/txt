import 'package:flutter/material.dart';

import '../../features/groups/domain/group_definition.dart';

/// A form field that opens a search-enabled overlay dialog to pick a group.
/// Replaces the default [DropdownButtonFormField] for group selection.
class SearchableGroupDropdown extends StatefulWidget {
  const SearchableGroupDropdown({
    super.key,
    required this.groups,
    required this.selectedId,
    required this.onChanged,
    this.label = 'Group',
    this.helperText,
    this.allowNull = true,
  });

  final List<GroupDefinition> groups;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  final String label;
  final String? helperText;
  final bool allowNull;

  @override
  State<SearchableGroupDropdown> createState() =>
      _SearchableGroupDropdownState();
}

class _SearchableGroupDropdownState extends State<SearchableGroupDropdown> {
  String get _selectedLabel {
    if (widget.selectedId == null) return 'No Group';
    final match =
        widget.groups.where((g) => g.id == widget.selectedId).firstOrNull;
    return match?.name ?? 'Unknown Group';
  }

  Future<void> _open() async {
    final result = await showDialog<_GroupPickResult>(
      context: context,
      builder: (context) => _GroupPickerDialog(
        groups: widget.groups,
        selectedId: widget.selectedId,
        allowNull: widget.allowNull,
      ),
    );
    if (result != null) {
      widget.onChanged(result.groupId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _open,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD7DBE7)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedLabel,
                    style: TextStyle(
                      fontSize: 16,
                      color: widget.selectedId == null
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFF111827),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down_rounded,
                    color: Color(0xFF6B7280)),
              ],
            ),
          ),
        ),
        if (widget.helperText != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Text(
              widget.helperText!,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ),
        // Invisible FormField to hook into form validation
        SizedBox(
          height: 0,
          child: Opacity(
            opacity: 0,
            child: TextFormField(
              initialValue: widget.selectedId?.toString() ?? '',
              validator: (_) => null,
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupPickResult {
  const _GroupPickResult(this.groupId);
  final int? groupId;
}

class _GroupPickerDialog extends StatefulWidget {
  const _GroupPickerDialog({
    required this.groups,
    required this.selectedId,
    required this.allowNull,
  });

  final List<GroupDefinition> groups;
  final int? selectedId;
  final bool allowNull;

  @override
  State<_GroupPickerDialog> createState() => _GroupPickerDialogState();
}

class _GroupPickerDialogState extends State<_GroupPickerDialog> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GroupDefinition> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.groups;
    return widget.groups
        .where((g) => g.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Group',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: (val) => setState(() => _query = val),
                    decoration: InputDecoration(
                      hintText: 'Search groups…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  if (widget.allowNull)
                    _GroupPickerItem(
                      name: 'No Group',
                      isSelected: widget.selectedId == null,
                      onTap: () =>
                          Navigator.of(context)
                              .pop(const _GroupPickResult(null)),
                    ),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('No groups match your search.',
                            style: TextStyle(color: Color(0xFF6B7280))),
                      ),
                    )
                  else
                    ...filtered.map(
                      (g) => _GroupPickerItem(
                        name: g.name,
                        isSelected: g.id == widget.selectedId,
                        onTap: () =>
                            Navigator.of(context).pop(_GroupPickResult(g.id)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupPickerItem extends StatelessWidget {
  const _GroupPickerItem({
    required this.name,
    required this.isSelected,
    required this.onTap,
  });

  final String name;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: const Color(0xFF111827),
          )),
      trailing: isSelected
          ? const Icon(Icons.check_rounded, size: 18, color: Color(0xFF2563EB))
          : null,
      dense: true,
      onTap: onTap,
      selected: isSelected,
      selectedTileColor: const Color(0xFFEFF6FF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
