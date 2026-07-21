import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../domain/track_event.dart';
import '../providers/auth_provider.dart';

/// A reusable "Track" feed — the who/what/when history of a record, with
/// field-level diffs. Drop it into any master editor:
///   TrackPanel.entity(entityType: 'items', entityId: '$id')
/// or into a person's profile to show everything they changed:
///   TrackPanel.actor(userId: login.userId)
class TrackPanel extends StatefulWidget {
  const TrackPanel.entity({
    super.key,
    required this.entityType,
    required this.entityId,
    this.showHeader = true,
  }) : actorUserId = null;

  const TrackPanel.actor({
    super.key,
    required this.actorUserId,
    this.showHeader = true,
  }) : entityType = null,
       entityId = null;

  final String? entityType;
  final String? entityId;
  final int? actorUserId;

  /// Whether to render the internal "Track" header + refresh row. Turn off when
  /// embedding inside a section card that already provides a title.
  final bool showHeader;

  bool get _isActor => actorUserId != null;

  @override
  State<TrackPanel> createState() => _TrackPanelState();
}

class _TrackPanelState extends State<TrackPanel> {
  late Future<List<TrackEvent>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<TrackEvent>> _load() {
    final auth = context.read<AuthProvider>();
    if (widget._isActor) return auth.getActorTrack(widget.actorUserId!);
    return auth.getEntityTrack(widget.entityType!, widget.entityId!);
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) ...[
          Row(
            children: [
              const Icon(
                Icons.timeline_rounded,
                size: 18,
                color: SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Track',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                iconSize: 18,
                color: SoftErpTheme.textSecondary,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        FutureBuilder<List<TrackEvent>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              );
            }
            final events = snapshot.data ?? const <TrackEvent>[];
            if (events.isEmpty) {
              return const _TrackEmpty();
            }
            return Column(
              children: [
                for (final e in events)
                  _TrackTile(event: e, showEntity: widget._isActor),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TrackEmpty extends StatelessWidget {
  const _TrackEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      alignment: Alignment.center,
      child: const Column(
        children: [
          Icon(Icons.history_toggle_off_outlined,
              size: 26, color: SoftErpTheme.textSecondary),
          SizedBox(height: 8),
          Text(
            'No activity tracked yet',
            style: TextStyle(
              color: SoftErpTheme.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Creates, edits and deletes will appear here.',
            style: TextStyle(color: SoftErpTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.event, required this.showEntity});

  final TrackEvent event;
  final bool showEntity;

  ({IconData icon, Color color, String verb}) get _style {
    switch (event.action) {
      case 'created':
        return (
          icon: Icons.add_circle_outline,
          color: SoftErpTheme.successText,
          verb: 'Created',
        );
      case 'deleted':
        return (
          icon: Icons.remove_circle_outline,
          color: const Color(0xFFD64545),
          verb: 'Deleted',
        );
      default:
        return (
          icon: Icons.edit_outlined,
          color: SoftErpTheme.accent,
          verb: 'Updated',
        );
    }
  }

  String get _title {
    final s = _style;
    if (showEntity) {
      final label = event.label.isEmpty ? event.entityNoun : event.label;
      return '${s.verb} $label · ${event.entityNoun}';
    }
    return event.actorName.isEmpty
        ? s.verb
        : '${s.verb} by ${event.actorName}';
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(s.icon, size: 18, color: s.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(),
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
                if (event.changes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final c in event.changes) _ChangeLine(change: c),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    if (showEntity) {
      // Title already names the record; show actor + role here.
      if (event.actorName.isNotEmpty) {
        parts.add(
          event.actorRole.isEmpty
              ? event.actorName
              : '${event.actorName} (${event.actorRole})',
        );
      }
    } else if (event.actorRole.isNotEmpty) {
      parts.add(event.actorRole);
    }
    final ts = _formatTime(event.createdAt);
    if (ts.isNotEmpty) parts.add(ts);
    return parts.join(' · ');
  }
}

class _ChangeLine extends StatelessWidget {
  const _ChangeLine({required this.change});

  final TrackChange change;

  @override
  Widget build(BuildContext context) {
    final from = change.from.trim();
    final to = change.to.trim();
    final String body;
    if (from.isEmpty) {
      body = 'set to "$to"';
    } else if (to.isEmpty) {
      body = 'cleared (was "$from")';
    } else {
      body = '"$from" → "$to"';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11.5, color: SoftErpTheme.textSecondary),
          children: [
            TextSpan(
              text: '${change.field}: ',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: SoftErpTheme.textPrimary,
              ),
            ),
            TextSpan(text: body),
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime? dt) {
  if (dt == null) return '';
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${two(local.day)} ${months[local.month - 1]} ${local.year}, '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Opens the Track feed for a master record in a modal dialog. Lets any master
/// screen surface Track in one line without restructuring its editor.
Future<void> showTrackDialog(
  BuildContext context, {
  required String entityType,
  required String entityId,
  String? title,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title ?? 'Track',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: SoftErpTheme.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: TrackPanel.entity(
                    entityType: entityType,
                    entityId: entityId,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
