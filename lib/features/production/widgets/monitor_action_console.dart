import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';
import 'material_ledger_closure_dialog.dart';
import 'order_fulfillment_prompt_dialog.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import 'package:core_erp/features/orders/domain/order_inputs.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';

class RemoteActionConsole extends StatelessWidget {
  const RemoteActionConsole({super.key, required this.provider});

  final ProductionProvider provider;

  @override
  Widget build(BuildContext context) {
    final runState = context.select<ProductionRunProvider, ProductionState>(
      (p) => p.state,
    );
    final isRunning = runState == ProductionState.running;
    final isPaused = runState == ProductionState.paused;
    final isInputLocked = context.select<ProductionRunProvider, bool>(
      (p) => p.isInputLocked,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _ConsoleAction(
                  label: isRunning ? 'DEPLOYED TO MACHINE' : 'DEPLOY & START RUN',
                  icon: Icons.rocket_launch,
                  color: const Color(0xFF10B981),
                  onPressed: isRunning || isInputLocked
                      ? null
                      : () => _deployAndStart(context),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ConsoleAction(
                  label: isPaused ? 'RESUME EXECUTION' : 'HALT / PAUSE',
                  icon: isPaused ? Icons.play_arrow : Icons.stop_circle_outlined,
                  color: const Color(0xFFF59E0B),
                  onPressed: isRunning || (isPaused && !isInputLocked)
                      ? () => _togglePause(context, isPaused)
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ConsoleAction(
                  label: 'FORCE LEDGER CLOSURE',
                  icon: Icons.inventory_2_outlined,
                  color: const Color(0xFF64748B),
                  onPressed: isRunning || isPaused
                      ? () => _openClosure(context)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deployAndStart(BuildContext context) async {
    final production = context.read<ProductionProvider>();
    final run = context.read<ProductionRunProvider>();
    
    // Simulate remote deployment confirmation
    String selectedScrapRouting = 'inventory';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Deploy Configuration', style: TextStyle(color: Color(0xFF0F172A))),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will push the active routing specs to the physical machine and initialize the run.',
                  style: TextStyle(color: Color(0xFF475569)),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Scrap Destination',
                  style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedScrapRouting,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'inventory', child: Text('Return to Inventory')),
                    DropdownMenuItem(value: 'scrap_table', child: Text('Send to Scrap Table')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => selectedScrapRouting = val);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCEL', style: TextStyle(color: Color(0xFF64748B))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('DEPLOY', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        }
      ),
    );

    if (confirm == true && context.mounted) {
      final repo = context.read<PipelineRunRepository>();
      final template = production.template;

      String runId;
      if (run.runId != null) {
        runId = run.runId!;
      } else {
        try {
          final newRun = await repo.createRun(template.id, name: '${template.name} Run', scrapRouting: selectedScrapRouting);
          runId = newRun.id;
        } catch (e) {
          // Fallback: create template first if it doesn't exist
          await repo.createTemplate(template);
          final newRun = await repo.createRun(template.id, name: '${template.name} Run', scrapRouting: selectedScrapRouting);
          runId = newRun.id;
        }
      }

      if (context.mounted) {
        production.startRun();
        run.startRun(runId: runId);

        if (template.linkedOrderId != null) {
          try {
            await context.read<OrdersProvider>().updateOrderLifecycle(
              UpdateOrderLifecycleInput(
                id: template.linkedOrderId!,
                status: OrderStatus.inProgress,
              ),
            );
          } catch (e) {
            debugPrint('Failed to update order status: $e');
          }
        }
      }
    }
  }

  Future<void> _togglePause(BuildContext context, bool isPaused) async {
    final production = context.read<ProductionProvider>();
    final run = context.read<ProductionRunProvider>();
    if (isPaused) {
      // It is essentially starting the run again from paused state
      production.startRun(); 
      run.resumeRun();
      return;
    }
    production.pauseRun();
    await run.pauseRun();
  }

  Future<void> _openClosure(BuildContext context) async {
    final production = context.read<ProductionProvider>();
    final run = context.read<ProductionRunProvider>();
    production.initiateClosure();
    await run.pauseRun();
    if (!context.mounted) return;
    
    final committed = await showDialog<bool>(
      context: context,
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider<ProductionProvider>.value(value: production),
          ChangeNotifierProvider<ProductionRunProvider>.value(value: run),
        ],
        child: const MaterialLedgerClosureDialog(),
      ),
    );
    if (!context.mounted) return;
    if (committed == true) {
      final repo = context.read<PipelineRunRepository>();
      final workingTemplate = production.template;
      final blueprint = production.blueprint;
      
      // If the template was structurally modified by dynamics (branch, reverse, skip)
      if (workingTemplate.id != blueprint.id) {
        try {
          await repo.createTemplate(
            workingTemplate.copyWith(
              name: '${blueprint.name} (Production Route)',
              status: PipelineTemplateStatus.active,
            ),
          );
        } catch (e) {
          debugPrint('Failed to save dynamic pipeline route: $e');
        }
      }

      await run.completeRun();
      final yieldProduced = production.goodYieldCount;
      final linkedOrderId = production.linkedOrderId;

      production.completeClosure();

      if (linkedOrderId != null && yieldProduced > 0) {
        if (!context.mounted) return;
        final orders = context.read<OrdersProvider>().orders;
        final index = orders.indexWhere((o) => o.id == linkedOrderId);
        if (index >= 0) {
          final order = orders[index];
          // Determine if we should show the prompt
          final totalNow = order.totalDeliveredQty + yieldProduced;
          if (totalNow >= order.quantity * 0.95) {
             await showDialog(
               context: context,
               builder: (_) => OrderFulfillmentPromptDialog(
                 order: order,
                 yieldProduced: yieldProduced.toInt(),
               ),
             );
          }
        }
      }

    } else {
      production.cancelClosure();
      run.resumeRun();
    }
  }

}

class _ConsoleAction extends StatelessWidget {
  const _ConsoleAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
      ),
      style: ElevatedButton.styleFrom(
        foregroundColor: disabled ? const Color(0xFF94A3B8) : color.withValues(alpha: 0.9),
        backgroundColor: disabled ? const Color(0xFFF1F5F9) : color.withValues(alpha: 0.1),
        disabledBackgroundColor: const Color(0xFFF1F5F9),
        padding: const EdgeInsets.symmetric(vertical: 24),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: disabled ? const Color(0xFFE2E8F0) : color.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
      ),
    );
  }
}

