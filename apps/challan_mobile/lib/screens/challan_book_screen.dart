import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import 'package:core_erp/features/delivery_challans/presentation/widgets/challan_printable_document.dart';

/// "Challan Book" — every challan THE CURRENT USER created (server-scoped via
/// ?mine=1), newest first. Read-only history for the person on this device.
class ChallanBookScreen extends StatefulWidget {
  const ChallanBookScreen({super.key});

  @override
  State<ChallanBookScreen> createState() => _ChallanBookScreenState();
}

class _ChallanBookScreenState extends State<ChallanBookScreen> {
  bool _loading = true;
  String? _error;
  List<DeliveryChallan> _challans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<DeliveryChallanProvider>().repository;
      final list = await repo.getChallans(mineOnly: true);
      final sorted = [...list]..sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() {
        _challans = sorted;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: const Text('Challan Book',
            style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          _CenteredMessage(
            icon: Icons.error_outline_rounded,
            title: 'Could not load challans',
            message: _error!,
            onRetry: _load,
          ),
        ],
      );
    }
    if (_challans.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          _CenteredMessage(
            icon: Icons.menu_book_outlined,
            title: 'No challans yet',
            message: 'Challans you create will show up here.',
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _challans.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _ChallanTile(
        challan: _challans[i],
        allChallans: _challans,
        index: i,
      ),
    );
  }
}

class _ChallanTile extends StatelessWidget {
  const _ChallanTile({
    required this.challan,
    required this.allChallans,
    required this.index,
  });

  final DeliveryChallan challan;
  final List<DeliveryChallan> allChallans;
  final int index;

  @override
  Widget build(BuildContext context) {
    final party = challan.vendorName.trim().isNotEmpty
        ? challan.vendorName.trim()
        : challan.customerName.trim().isNotEmpty
            ? challan.customerName.trim()
            : challan.orderNo.trim().isNotEmpty
                ? 'Order ${challan.orderNo.trim()}'
                : '—';
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _ChallanPreviewScreen(
            allChallans: allChallans,
            initialIndex: index,
          ),
        ));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    challan.challanNo.trim().isEmpty
                        ? '(no number)'
                        : challan.challanNo.trim(),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_typeLabel(challan.type)} · $party',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: SoftErpTheme.textSecondary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _fmtDate(challan.date),
                  style: const TextStyle(
                      fontSize: 12, color: SoftErpTheme.textSecondary),
                ),
                const SizedBox(height: 5),
                _StatusPill(status: challan.status.name),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChallanPreviewScreen extends StatefulWidget {
  final List<DeliveryChallan> allChallans;
  final int initialIndex;

  const _ChallanPreviewScreen({
    required this.allChallans,
    required this.initialIndex,
  });

  @override
  State<_ChallanPreviewScreen> createState() => _ChallanPreviewScreenState();
}

class _ChallanPreviewScreenState extends State<_ChallanPreviewScreen> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: const Text('Challan Preview', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.allChallans.length,
        itemBuilder: (context, index) {
          final challan = widget.allChallans[index];
          return InteractiveViewer(
            minScale: 0.4,
            maxScale: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: Material(
                  elevation: 3,
                  child: ChallanPrintableDocument(challan: challan),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    late final Color bg;
    late final Color fg;
    if (s == 'completed') {
      bg = const Color(0xFFEAF8EE);
      fg = const Color(0xFF0F8B45);
    } else if (s == 'issued') {
      bg = const Color(0xFFEAF1FB);
      fg = const Color(0xFF2F7DD1);
    } else if (s == 'cancelled' || s == 'canceled') {
      bg = const Color(0xFFFDECEC);
      fg = const Color(0xFF8A2E2E);
    } else {
      bg = const Color(0xFFF1F2F6);
      fg = SoftErpTheme.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        status.isEmpty ? '—' : status[0].toUpperCase() + status.substring(1),
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: SoftErpTheme.textSecondary),
            const SizedBox(height: 12),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: SoftErpTheme.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _typeLabel(ChallanType type) {
  final n = type.name;
  return n.isEmpty ? 'Challan' : n[0].toUpperCase() + n.substring(1);
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = d.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
