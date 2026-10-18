import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../data/entity_link_service.dart';
import '../../domain/entity_link.dart';
import 'link_type_icon.dart';

/// What a record works with, as a strip of chips above its details.
///
/// One record's operational cell: the part, the die that cuts it, the machine
/// it runs on. The link graph answers this from either end — a die's ribbon
/// lists its parts from the same rows an item's ribbon reads — so one widget
/// serves every master.
///
/// **This is not the same question as "usage".** An item panel's usage count
/// comes from `/api/items/:id/usage` and means orders, challans and BOM lines.
/// This reads `/api/links/:type/:id` and means what the record is attached to.
/// The heading says "Works with" so the two cannot be read as one.
///
/// **Reads are permissive and silent.** The endpoint checks read on the subject
/// only, and drops whole groups the caller may not read rather than refusing —
/// so two people can legitimately see different ribbons on the same record, and
/// a short ribbon is not evidence that nothing is attached. Only an empty
/// payload says that.
class LinkedEcosystemRibbon extends StatefulWidget {
  const LinkedEcosystemRibbon({
    super.key,
    required this.type,
    required this.id,
    this.onOpen,
    this.service,
    this.heading = 'Works with',
  });

  /// The subject, in the links catalogue's own keys — `item`, `die`, `machine`…
  final String type;
  final String id;

  /// Tapping a chip. Null leaves the chips drawn but inert, which is the
  /// honest state where there is nowhere to pivot to yet.
  final ValueChanged<LinkRef>? onOpen;

  /// Injected by tests and by a host with no Provider for it.
  final EntityLinkService? service;

  final String heading;

  @override
  State<LinkedEcosystemRibbon> createState() => _LinkedEcosystemRibbonState();
}

class _LinkedEcosystemRibbonState extends State<LinkedEcosystemRibbon> {
  EntityLinks? _links;
  bool _loading = true;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LinkedEcosystemRibbon old) {
    super.didUpdateWidget(old);
    // The subject can change under a panel that pivots in place rather than
    // reopening, so a changed type or id has to refetch.
    if (old.type != widget.type || old.id != widget.id) _load();
  }

  EntityLinkService? _resolve() {
    final injected = widget.service;
    if (injected != null) return injected;
    try {
      return context.read<EntityLinkService>();
    } catch (_) {
      // No Provider: `main.dart` is the only registration, so a host or a test
      // tree without it degrades to hidden rather than throwing.
      return null;
    }
  }

  Future<void> _load() async {
    final service = _resolve();
    if (service == null) {
      setState(() {
        _unavailable = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _unavailable = false;
    });
    try {
      final found = await service.fetchLinks(widget.type, widget.id);
      if (!mounted) return;
      setState(() {
        _links = found;
        _loading = false;
      });
    } catch (_) {
      // A record whose links cannot be read shows no ribbon at all. Saying
      // "nothing linked" would be a claim this widget cannot support.
      if (!mounted) return;
      setState(() {
        _unavailable = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) return const SizedBox.shrink();
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final links = _links;
    if (links == null) return const SizedBox.shrink();

    return Container(
      key: const ValueKey<String>('linked_ecosystem_ribbon'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.heading,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          if (links.isEmpty)
            const Text(
              'Nothing linked yet.',
              key: ValueKey<String>('linked_ecosystem_empty'),
              style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Every group the payload returns, not a hand-picked two: sets,
                // groups, pipelines and materials are linkable too, and
                // filtering here would hide a real attachment.
                for (final group in links.groups)
                  for (final ref in group.links)
                    _RibbonChip(
                      ref: ref,
                      onTap: widget.onOpen == null
                          ? null
                          : () => widget.onOpen!(ref),
                    ),
              ],
            ),
        ],
      ),
    );
  }
}

/// One linked record. A chip, not a row — this strip sits above a panel's
/// details, where the column-shaped row the Miller columns use would eat the
/// height the details need.
class _RibbonChip extends StatelessWidget {
  const _RibbonChip({required this.ref, this.onTap});

  final LinkRef ref;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final interactive = onTap != null;
    return Material(
      color: SoftErpTheme.cardSurface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        key: ValueKey<String>('ribbon_chip_${ref.key}'),
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: SoftErpTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                linkTypeIcon(ref.type),
                size: 18,
                color: interactive
                    ? SoftErpTheme.accent
                    : SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                ref.label.trim().isEmpty ? '(unnamed)' : ref.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              if (ref.subtitle.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  ref.subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: SoftErpTheme.textSecondary,
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
