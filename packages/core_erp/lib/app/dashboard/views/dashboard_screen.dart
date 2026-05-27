import 'package:flutter/material.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../../../core/widgets/soft_primitives.dart';
import '../../reports/views/challan_invoice_reconciliation_screen.dart';
import '../../reports/widgets/client_report_generator_dialog.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dashboard',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Welcome to Paper ERP. System is live.',
            style: TextStyle(color: SoftErpTheme.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 48),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: [
              _DashboardActionCard(
                title: 'Client Report',
                description:
                    'Generate itemized pricing reports and spreadsheets for commercial clients from issued delivery challans.',
                icon: Icons.summarize_outlined,
                onTap: () => ClientReportGeneratorDialog.open(context),
              ),
              _DashboardActionCard(
                title: 'Client Statement',
                description:
                    'Review client-owned material input, finished units delivered, and remaining material balance.',
                icon: Icons.receipt_long_outlined,
                onTap: () =>
                    ChallanInvoiceReconciliationScreen.openClientStatementDialog(
                      context,
                    ),
              ),
              _DashboardActionCard(
                title: 'Misc Audit',
                description:
                    'Review internal waste snapshots, source challan references, and audit-only reconciliation details.',
                icon: Icons.fact_check_outlined,
                onTap: () =>
                    ChallanInvoiceReconciliationScreen.openMiscDialog(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardActionCard extends StatelessWidget {
  const _DashboardActionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SoftErpTheme.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: SoftErpTheme.accent, size: 32),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    height: 1.45,
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
