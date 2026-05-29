import 'package:flutter/material.dart';
import 'package:core_erp/core/widgets/app_button.dart';

class PMHero extends StatelessWidget {
  const PMHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A1E3A8A),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTight = constraints.maxWidth < 760;

          return Flex(
            direction: isTight ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                flex: isTight ? 0 : 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Text(
                        'PM',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Custom button and shared UI playground',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Use this space to collect the custom buttons, actions, and reusable UI patterns we want available across the app.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFFE5E7EB),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: isTight ? 0 : 24, height: isTight ? 24 : 0),
              const Expanded(flex: 2, child: _HeroPreviewCard()),
            ],
          );
        },
      ),
    );
  }
}

class _HeroPreviewCard extends StatelessWidget {
  const _HeroPreviewCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Pinned actions',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AppButton(label: 'Primary CTA', onPressed: null),
              AppButton(
                label: 'Secondary',
                onPressed: null,
                variant: AppButtonVariant.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
