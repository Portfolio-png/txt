import 'package:flutter/material.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../column_def.dart';
import '../sheet_controller.dart';
import '../sheet_draft.dart';
import '../sheet_binding.dart';
import '../sheet_engine.dart';

/// One entry in the sidebar's section rail.
@immutable
class SheetSection {
  const SheetSection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
}

/// The rail beside a sheet: what is being edited, where to jump, and the live
/// shape of the columns.
///
/// This is `ItemMasterSidebar` with the three things that made it unusable for
/// any other sheet taken out:
///
/// 1. **It read cells by literal id** — `draft.get(3)` for the name,
///    `draft.get(5)` for the code, and a column tree whose branch labels were
///    the words "Alloy", "Thickness" and "Finish" typed into the build method.
///    Everything here now goes through [SheetBindsTo], so inserting a column
///    cannot silently repoint the identity card, and the tree names whatever
///    properties the sheet actually has.
/// 2. **Its sections were a hardcoded list of four.** They are [sections] now.
/// 3. **It invented a client.** The footnote read
///    `draft.get(20)?.optionLabel ?? 'Gold Medal'`, so a part developed for
///    nobody claimed a real company by name. [footnote] is supplied by the
///    caller or the line is left out.
///
/// Type sizes are at the house floor (body ≥14, pills ≥13, the identifying
/// name large); the original ran 9–12 throughout.
class SheetSidebar extends StatelessWidget {
  const SheetSidebar({
    super.key,
    required this.controller,
    required this.sections,
    required this.activeSection,
    required this.onSelectSection,
    this.badgeText,
    this.badgeIsPositive = false,
    this.footnote,
    this.footnoteIcon,
    this.width = 268,
    this.showIdentity = true,
  });

  /// The sheet whose identity and columns are shown.
  final SheetController controller;

  final List<SheetSection> sections;
  final String activeSection;
  final ValueChanged<String> onSelectSection;

  /// The state chip — "SAVED #5012", "NEW RECORD", "DRAFT". Omitted when null.
  final String? badgeText;
  final bool badgeIsPositive;

  /// One line under the group path, for whatever the host knows and the sheet
  /// does not. Null leaves the line out rather than guessing at it.
  final String? footnote;
  final IconData? footnoteIcon;

  final double width;

  /// Whether to draw the identity card at the top.
  ///
  /// A host that already names the record elsewhere — the item sheet pins the
  /// part above its content — turns this off rather than saying it twice.
  final bool showIdentity;

  @override
  Widget build(BuildContext context) {
    final sheet = controller.sheetDef;
    final draft = controller.draft;

    final nameColumn =
        sheet.columnBoundTo(SheetBindsTo.name) ?? sheet.itemColumn;
    final name = nameColumn == null ? null : _labelOf(draft.get(nameColumn.id));

    final codeColumn = sheet.columnBoundTo(SheetBindsTo.partCode);
    final code = codeColumn == null ? null : _labelOf(draft.get(codeColumn.id));

    final groupPath = nameColumn == null
        ? ''
        : SheetEngine.groupPathString(sheet, draft, nameColumn.id);

    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: SoftErpTheme.cardSurface,
        border: Border(right: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showIdentity)
            _identityCard(name: name, code: code, groupPath: groupPath),
          // One scrollable below the identity card, rather than a fixed stack
          // over an Expanded tree: the sections, the headings and the tree
          // together are taller than a short window, and a Column of fixed
          // parts over one Expanded child overflows instead of scrolling.
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _railHeading('SECTIONS'),
                for (final section in sections)
                  _sectionTile(
                    section,
                    isSelected: section.id == activeSection,
                  ),
                const Divider(
                  height: 24,
                  thickness: 1,
                  color: SoftErpTheme.sectionSurface,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                        child: Text(
                          'COLUMN TREE',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: SoftErpTheme.textSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${sheet.columns.length} columns',
                        style: const TextStyle(
                          fontSize: 13,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ..._columnTreeBranches(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _identityCard({
    required String? name,
    required String? code,
    required String groupPath,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SoftErpTheme.accent.withValues(alpha: 0.08),
            SoftErpTheme.cardSurface,
          ],
        ),
        border: const Border(bottom: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Both sides flex: a status chip and a part code are each as
              // long as they happen to be, and neither should paint past the
              // card's edge when the other is wordy.
              if (badgeText != null)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: badgeIsPositive
                          ? SoftErpTheme.successBg
                          : SoftErpTheme.warningBg,
                      borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
                    ),
                    child: Text(
                      badgeText!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: badgeIsPositive
                            ? SoftErpTheme.successText
                            : SoftErpTheme.warningText,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
              const SizedBox(width: 6),
              if (code != null && code.isNotEmpty)
                Flexible(
                  child: Text(
                    code,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: SoftErpTheme.accent,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            // Not "New Item": an unnamed row is unnamed, and saying so beats
            // showing a name nobody typed.
            (name == null || name.isEmpty) ? 'Unnamed' : name,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: (name == null || name.isEmpty)
                  ? SoftErpTheme.textMuted
                  : SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            groupPath.isEmpty ? 'Not filed under a group yet' : groupPath,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SoftErpTheme.textSecondary,
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  footnoteIcon ?? Icons.info_outline_rounded,
                  size: 15,
                  color: SoftErpTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    footnote!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _railHeading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: SoftErpTheme.textSecondary,
        letterSpacing: 0.8,
      ),
    ),
  );

  Widget _sectionTile(SheetSection section, {required bool isSelected}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? SoftErpTheme.accent.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          section.icon,
          size: 20,
          color: isSelected ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
        ),
        title: Text(
          section.title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? SoftErpTheme.accent : SoftErpTheme.textPrimary,
          ),
        ),
        subtitle: Text(
          section.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary),
        ),
        onTap: () => onSelectSection(section.id),
      ),
    );
  }

  /// The identity chain at its real depth, then one branch per property the
  /// sheet actually declares — rather than the three property names the old
  /// sidebar had typed into it.
  List<Widget> _columnTreeBranches() {
    final sheet = controller.sheetDef;
    final draft = controller.draft;
    final nameColumn =
        sheet.columnBoundTo(SheetBindsTo.name) ?? sheet.itemColumn;

    final chain = <ColumnDef>[
      if (nameColumn != null) ...sheet.ancestors(nameColumn.id),
      ?nameColumn,
    ];

    final identityIds = {for (final c in chain) c.id};
    final trailing = [
      for (final col in sheet.columns)
        if (col.parentId == nameColumn?.id && !identityIds.contains(col.id))
          col,
    ];
    final properties = [
      for (final col in sheet.variationColumns)
        if (!identityIds.contains(col.id)) col,
    ];

    return [
      for (var i = 0; i < chain.length; i++)
        _branch(
          label: '${chain[i].label}: ${_display(draft.get(chain[i].id))}',
          depth: i,
          isBold: true,
          color: chain[i].id == nameColumn?.id ? SoftErpTheme.accent : null,
        ),
      for (final col in trailing)
        _branch(
          label:
              '${col.label}: ${_display(draft.get(col.id))}'
              '${col.kind == ColumnKind.seq ? ' (Seq)' : ''}',
          depth: chain.length,
        ),
      if (properties.isNotEmpty) const SizedBox(height: 8),
      for (final col in properties)
        _branch(
          label: '${col.label}: ${_display(draft.get(col.id))}',
          depth: 0,
        ),
    ];
  }

  Widget _branch({
    required String label,
    required int depth,
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        left: 14 + depth * 14.0,
        right: 14,
        top: 3,
        bottom: 3,
      ),
      child: Row(
        children: [
          Icon(
            depth == 0
                ? Icons.folder_open_rounded
                : Icons.subdirectory_arrow_right_rounded,
            size: 15,
            color: color ?? SoftErpTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                color: color ?? SoftErpTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String? _labelOf(CellValue? value) {
    if (value == null) return null;
    final label = value.optionLabel ?? value.textValue;
    return (label == null || label.trim().isEmpty) ? null : label;
  }

  static String _display(CellValue? value) {
    final label = _labelOf(value);
    if (label != null) return label;
    final n = value?.intValue;
    return n == null ? '—' : '$n';
  }
}
