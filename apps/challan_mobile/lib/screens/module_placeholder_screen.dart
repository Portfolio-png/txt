import 'package:flutter/material.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';

/// Placeholder shown for modules whose full screens live in the desktop `paper`
/// package and are not yet wired into the mobile app (Production, Jobs).
class ModulePlaceholderScreen extends StatelessWidget {
  const ModulePlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: SoftErpTheme.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 44, color: SoftErpTheme.accent),
              ),
              const SizedBox(height: 20),
              Text(
                '$title coming soon',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This module is not available on mobile yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SoftErpTheme.textSecondary, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
