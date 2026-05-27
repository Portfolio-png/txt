import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../../../core/widgets/app_button.dart';

enum PricingMetric { pcs, weight }

class PricingRule {
  final double price;
  final PricingMetric metric;

  const PricingRule(this.price, this.metric);
}

class ItemPricingDialog extends StatefulWidget {
  const ItemPricingDialog({super.key, required this.uniqueItemNames});

  final List<String> uniqueItemNames;

  static Future<Map<String, PricingRule>?> open(
    BuildContext context,
    List<String> uniqueItemNames,
  ) {
    return showDialog<Map<String, PricingRule>?>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ItemPricingDialog(uniqueItemNames: uniqueItemNames),
    );
  }

  @override
  State<ItemPricingDialog> createState() => _ItemPricingDialogState();
}

class _ItemPricingDialogState extends State<ItemPricingDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, PricingMetric> _metrics = {};

  @override
  void initState() {
    super.initState();
    for (final itemName in widget.uniqueItemNames) {
      _controllers[itemName] = TextEditingController();
      _metrics[itemName] = PricingMetric.pcs;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final rules = <String, PricingRule>{};
    for (final itemName in widget.uniqueItemNames) {
      final text = _controllers[itemName]!.text.trim();
      final price = double.tryParse(text) ?? 0.0;
      rules[itemName] = PricingRule(price, _metrics[itemName]!);
    }
    Navigator.of(context).pop(rules);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: SoftErpTheme.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Item Pricing',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Specify the unit price for each item to calculate totals.',
                    style: TextStyle(color: SoftErpTheme.textSecondary),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: SoftErpTheme.border),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: widget.uniqueItemNames.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final itemName = widget.uniqueItemNames[index];
                  return Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          itemName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _controllers[itemName],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'),
                            ),
                          ],
                          decoration: InputDecoration(
                            prefixText: '₹ ',
                            hintText: '0.00',
                            filled: true,
                            fillColor: SoftErpTheme.cardSurfaceAlt,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: SoftErpTheme.border,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: SoftErpTheme.border,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: SoftErpTheme.cardSurfaceAlt,
                          border: Border.all(color: SoftErpTheme.border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<PricingMetric>(
                            value: _metrics[itemName],
                            icon: const Icon(
                              Icons.expand_more_rounded,
                              size: 18,
                            ),
                            style: const TextStyle(
                              color: SoftErpTheme.textPrimary,
                              fontSize: 14,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: PricingMetric.pcs,
                                child: Text('Per Pc'),
                              ),
                              DropdownMenuItem(
                                value: PricingMetric.weight,
                                child: Text('Per Kg'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _metrics[itemName] = value);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1, color: SoftErpTheme.border),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  AppButton(
                    label: 'Continue',
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
