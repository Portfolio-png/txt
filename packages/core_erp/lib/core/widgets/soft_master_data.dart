import 'package:flutter/material.dart';

import '../theme/soft_erp_theme.dart';
import 'page_container.dart';
import 'soft_primitives.dart';

class SoftMasterDataPage extends StatelessWidget {
  const SoftMasterDataPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.toolbar,
    required this.body,
    this.messages = const <Widget>[],
  });

  final String title;
  final String subtitle;
  final Widget action;
  final Widget toolbar;
  final Widget body;
  final List<Widget> messages;

  @override
  Widget build(BuildContext context) {
    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SoftMasterHeader(title: title, subtitle: subtitle, action: action),
          const SizedBox(height: 18),
          toolbar,
          for (final message in messages) ...[
            const SizedBox(height: 12),
            message,
          ],
          const SizedBox(height: 18),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _SoftMasterHeader extends StatelessWidget {
  const _SoftMasterHeader({
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: SoftErpTheme.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: compact ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: SoftErpTheme.textSecondary,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft, child: action),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 18),
            action,
          ],
        );
      },
    );
  }
}

class SoftMasterToolbar extends StatelessWidget {
  const SoftMasterToolbar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      color: const Color(0x80FFFFFF),
      radius: SoftErpTheme.radiusLg,
      elevated: false,
      strongBorder: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

class SoftSegmentOption<T> {
  const SoftSegmentOption({
    required this.value,
    required this.label,
    this.count,
  });

  final T value;
  final String label;
  final int? count;
}

class SoftSegmentedFilter<T> extends StatelessWidget {
  const SoftSegmentedFilter({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<SoftSegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SoftErpTheme.border),
        boxShadow: SoftErpTheme.insetShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options
            .map((option) {
              final isSelected = option.value == selected;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _SoftSegmentButton<T>(
                  option: option,
                  isSelected: isSelected,
                  onTap: () => onChanged(option.value),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _SoftSegmentButton<T> extends StatelessWidget {
  const _SoftSegmentButton({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final SoftSegmentOption<T> option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected ? Colors.white : SoftErpTheme.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 36, minWidth: 92),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: isSelected ? SoftErpTheme.accentGradient : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: isSelected ? SoftErpTheme.subtleShadow : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                option.label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              if (option.count != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.22)
                        : SoftErpTheme.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${option.count}',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : SoftErpTheme.accentDark,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SoftMasterSearchField extends StatelessWidget {
  const SoftMasterSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.width = 360,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: const Color(0xFFF8F9FD),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: SoftErpTheme.accent),
          ),
        ),
      ),
    );
  }
}

class SoftMasterTable extends StatelessWidget {
  const SoftMasterTable({
    super.key,
    required this.columns,
    required this.itemCount,
    required this.rowBuilder,
    this.minWidth = 980,
  });

  final List<SoftTableColumn> columns;
  final int itemCount;
  final IndexedWidgetBuilder rowBuilder;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < minWidth
            ? minWidth
            : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: constraints.maxWidth < minWidth
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                SoftMasterHeaderStrip(columns: columns),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    itemCount: itemCount,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: rowBuilder,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SoftMasterHeaderStrip extends StatelessWidget {
  const SoftMasterHeaderStrip({super.key, required this.columns});

  final List<SoftTableColumn> columns;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF0F9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SoftErpTheme.borderStrong),
      ),
      child: Row(
        children: columns
            .map(
              (column) => Expanded(
                flex: column.flex,
                child: Text(
                  column.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class SoftTableColumn {
  const SoftTableColumn(this.label, {this.flex = 1});

  final String label;
  final int flex;
}

class SoftMasterRow extends StatelessWidget {
  const SoftMasterRow({
    super.key,
    required this.children,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
  });

  final List<Widget> children;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SoftRowCard(
      onTap: onTap ?? () {},
      baseColor: SoftErpTheme.cardSurface,
      hoverColor: const Color(0xFFFDFDFF),
      child: Padding(
        padding: padding,
        child: Row(children: children),
      ),
    );
  }
}

class SoftActionLink extends StatelessWidget {
  const SoftActionLink({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: SoftErpTheme.accentDark,
        backgroundColor: onTap == null
            ? SoftErpTheme.cardSurfaceAlt
            : SoftErpTheme.accentSoft,
        disabledForegroundColor: SoftErpTheme.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class SoftInlineText extends StatelessWidget {
  const SoftInlineText(
    this.value, {
    super.key,
    this.weight = FontWeight.w500,
    this.color,
    this.maxLines = 1,
  });

  final String value;
  final FontWeight weight;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? SoftErpTheme.textPrimary,
        fontSize: 14,
        fontWeight: weight,
      ),
    );
  }
}
