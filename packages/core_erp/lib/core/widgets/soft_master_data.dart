import 'package:flutter/material.dart';

import '../theme/soft_erp_theme.dart';
import 'page_container.dart';
import 'soft_primitives.dart';

class SoftMasterDataPage extends StatelessWidget {
  const SoftMasterDataPage({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    required this.action,
    required this.toolbar,
    required this.body,
    this.messages = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
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
          _SoftMasterHeader(
            title: title,
            subtitle: subtitle,
            subtitleWidget: subtitleWidget,
            action: action,
          ),
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
    this.subtitle,
    this.subtitleWidget,
    required this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
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
            if (subtitleWidget != null) ...[
              const SizedBox(height: 6),
              subtitleWidget!,
            ] else if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                maxLines: compact ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SoftErpTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
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
    this.customLabel,
  });

  final T value;
  final String label;
  final int? count;
  final Widget? customLabel;
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
              if (option.customLabel != null)
                option.customLabel!
              else
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
    this.onDoubleTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
  });

  final List<Widget> children;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SoftRowCard(
      onTap: onTap ?? () {},
      onDoubleTap: onDoubleTap,
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

/// Card/List switch for a master list. Machines and Dies each carried their own
/// copy of this; every master that gains a card view shares this one.
class SoftViewToggleButton extends StatelessWidget {
  const SoftViewToggleButton({
    super.key,
    required this.isGridView,
    required this.onTap,
  });

  final bool isGridView;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: SoftErpTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SoftErpTheme.border),
            boxShadow: SoftErpTheme.insetShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isGridView
                    ? Icons.view_headline_rounded
                    : Icons.grid_view_rounded,
                size: 18,
                color: SoftErpTheme.textPrimary,
              ),
              const SizedBox(width: 10),
              Text(
                isGridView ? 'List View' : 'Card View',
                style: const TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One fact on a master card: an icon and a value, optionally labelled. Passed
/// as data rather than a widget so the card can both draw the line and put the
/// full text in its hover bubble — a card is too small to show everything.
class SoftEntityDetail {
  const SoftEntityDetail({required this.icon, required this.value, this.label});

  final IconData icon;
  final String value;
  final String? label;

  bool get isEmpty => value.trim().isEmpty;
}

/// The card the masters share: a photo band that falls back to initials, then a
/// title, a subtitle and any number of trailing detail lines. Only the first
/// few lines fit, so hovering shows the rest in a bubble. Actions reveal on
/// hover so a resting grid stays quiet.
class SoftEntityCard extends StatefulWidget {
  const SoftEntityCard({
    super.key,
    required this.title,
    this.subtitle = '',
    this.photoUrl,
    this.fallbackIcon = Icons.folder_outlined,
    this.details = const <SoftEntityDetail>[],
    this.visibleDetailCount = 2,
    this.badge,
    this.onTap,
    this.actions,
  });

  final String title;
  final String subtitle;
  final String? photoUrl;
  final IconData fallbackIcon;
  final int visibleDetailCount;

  /// Facts under the subtitle. The card shows [visibleDetailCount] of them and
  /// the hover bubble carries all of them in full.
  final List<SoftEntityDetail> details;

  /// Sits on the photo band's top-left, e.g. a status pill.
  final Widget? badge;
  final VoidCallback? onTap;

  /// Revealed on hover at the photo band's top-right.
  final Widget? actions;

  @override
  State<SoftEntityCard> createState() => _SoftEntityCardState();
}

class _SoftEntityCardState extends State<SoftEntityCard> {
  bool _hovered = false;

  String get _token {
    final parts = widget.title
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase());
    return parts.isEmpty ? '—' : parts.join();
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.photoUrl;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final facts = widget.details
        .where((detail) => !detail.isEmpty)
        .toList(growable: false);
    final shown = facts.take(widget.visibleDetailCount).toList(growable: false);
    final hidden = facts.length - shown.length;
    final overflowFacts = facts.skip(shown.length).toList(growable: false);
    return _MaybeTooltip(
      // Only what the card had no room for. Repeating the title, subtitle and
      // the lines already printed just makes the reader re-read them.
      message: overflowFacts.isEmpty ? null : _bubble(overflowFacts),
      child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SoftErpTheme.border),
              boxShadow: SoftErpTheme.insetShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasPhoto)
                          Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _fallback(),
                          )
                        else
                          _fallback(),
                        if (widget.badge != null)
                          Positioned(top: 8, left: 8, child: widget.badge!),
                        if (widget.actions != null)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 150),
                              opacity: _hovered ? 1 : 0,
                              child: IgnorePointer(
                                ignoring: !_hovered,
                                child: widget.actions!,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SoftErpTheme.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (widget.subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: SoftErpTheme.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (shown.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            for (final detail in shown) _line(detail),
                            if (hidden > 0)
                              Text(
                                '+$hidden more — hover for details',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: SoftErpTheme.textSecondary,
                                  fontSize: 10.5,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// Everything the card had to truncate, in full.
  TextSpan _bubble(List<SoftEntityDetail> facts) {
    const heading = TextStyle(
      color: Colors.white,
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      height: 1.4,
    );
    const body = TextStyle(
      color: Color(0xFFE2E8F0),
      fontSize: 11.5,
      height: 1.5,
    );
    const label = TextStyle(
      color: Color(0xFF94A3B8),
      fontSize: 11,
      height: 1.5,
    );
    return TextSpan(children: [
      TextSpan(text: widget.title, style: heading),
      if (widget.subtitle.trim().isNotEmpty)
        TextSpan(text: '\n${widget.subtitle}', style: label),
      for (final fact in facts)
        TextSpan(children: [
          const TextSpan(text: '\n'),
          if (fact.label != null)
            TextSpan(text: '${fact.label}: ', style: label),
          TextSpan(text: fact.value, style: body),
        ]),
    ]);
  }

  Widget _line(SoftEntityDetail detail) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(detail.icon, size: 12, color: SoftErpTheme.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              detail.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFDFBF6), Color(0xFFF1F5F9)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.fallbackIcon,
              size: 24,
              color: SoftErpTheme.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              _token,
              style: const TextStyle(
                color: SoftErpTheme.accentDark,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a child in a tooltip only when there is something to say, so a card
/// with nothing hidden shows no bubble at all.
class _MaybeTooltip extends StatelessWidget {
  const _MaybeTooltip({required this.message, required this.child});

  final InlineSpan? message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (message == null) return child;
    return Tooltip(
      richMessage: message,
      waitDuration: const Duration(milliseconds: 350),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: child,
    );
  }
}

/// The grid every master card view uses, so spacing and card size match.
class SoftEntityCardGrid extends StatelessWidget {
  const SoftEntityCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.maxCardWidth = 260,
    this.cardHeight = 252,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double maxCardWidth;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCardWidth,
        mainAxisExtent: cardHeight,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}
