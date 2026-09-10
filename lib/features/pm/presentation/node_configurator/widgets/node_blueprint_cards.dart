import 'package:flutter/material.dart';

import '../domain/node_blueprint.dart';
import 'slot_controls.dart';

/// A row in the library rail. Carries all three slot chips so the shelf can be
/// scanned for "which of these still need a die picked" or "which route no
/// scrap", not just for names.
class NodeBlueprintLibraryCard extends StatelessWidget {
  const NodeBlueprintLibraryCard({
    super.key,
    required this.blueprint,
    required this.selected,
    required this.onTap,
  });

  final NodeBlueprint blueprint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF1EEFF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF5E49E6) : const Color(0xFFE6E8F4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    blueprint.name.trim().isEmpty
                        ? 'Untitled node'
                        : blueprint.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF303646),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  blueprint.processType,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF9AA0B2),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                SlotChip(
                  icon: blueprint.machineMode.icon,
                  label: NodeBindingRules.machineSummary(blueprint),
                  tone: blueprint.machineMode.tone,
                  dense: true,
                ),
                SlotChip(
                  icon: blueprint.dieMode.icon,
                  label: NodeBindingRules.dieSummary(blueprint),
                  tone: blueprint.dieMode.tone,
                  dense: true,
                ),
                SlotChip(
                  icon: Icons.recycling,
                  label: NodeBindingRules.lossSummary(blueprint),
                  tone: NodeBindingRules.lossTone(blueprint),
                  dense: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The node as it lands on a canvas, beside the one thing a canvas node cannot
/// show: what it still owes a human before it can run.
class NodeBlueprintPreview extends StatelessWidget {
  const NodeBlueprintPreview({super.key, required this.blueprint});

  final NodeBlueprint blueprint;

  @override
  Widget build(BuildContext context) {
    final prompts = NodeBindingRules.runtimePrompts(blueprint);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF201C4B), Color(0xFF4740B7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTight = constraints.maxWidth < 700;
          final nodeCard = _CanvasNodePreview(blueprint: blueprint);
          final promptPanel = _RuntimePromptPanel(prompts: prompts);

          if (isTight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [nodeCard, const SizedBox(height: 14), promptPanel],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: nodeCard),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: promptPanel),
            ],
          );
        },
      ),
    );
  }
}

class _CanvasNodePreview extends StatelessWidget {
  const _CanvasNodePreview({required this.blueprint});

  final NodeBlueprint blueprint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  blueprint.name.trim().isEmpty
                      ? 'Untitled node'
                      : blueprint.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF303646),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1EEFF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  blueprint.processType.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: Color(0xFF4740B7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PreviewSlotRow(
            caption: 'Machine',
            icon: blueprint.machineMode.icon,
            value: NodeBindingRules.machineSummary(blueprint),
            tone: blueprint.machineMode.tone,
          ),
          const SizedBox(height: 6),
          _PreviewSlotRow(
            caption: 'Die',
            icon: blueprint.dieMode.icon,
            value: NodeBindingRules.dieSummary(blueprint),
            tone: blueprint.dieMode.tone,
          ),
          const SizedBox(height: 6),
          _PreviewSlotRow(
            caption: 'Loss',
            icon: Icons.recycling,
            value: NodeBindingRules.lossSummary(blueprint),
            tone: NodeBindingRules.lossTone(blueprint),
          ),
        ],
      ),
    );
  }
}

class _PreviewSlotRow extends StatelessWidget {
  const _PreviewSlotRow({
    required this.caption,
    required this.icon,
    required this.value,
    required this.tone,
  });

  final String caption;
  final IconData icon;
  final String value;
  final SlotTone tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            caption,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9AA0B2),
            ),
          ),
        ),
        Flexible(
          child: SlotChip(icon: icon, label: value, tone: tone, dense: true),
        ),
      ],
    );
  }
}

class _RuntimePromptPanel extends StatelessWidget {
  const _RuntimePromptPanel({required this.prompts});

  final List<RuntimePrompt> prompts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ASKED AT RUN TIME',
          style: TextStyle(
            color: Color(0xFFB9B4F0),
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        if (prompts.isEmpty)
          Row(
            children: const [
              Icon(Icons.check_circle, size: 15, color: Color(0xFF7BE0A6)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nothing — starts as-is.',
                  style: TextStyle(color: Color(0xFFE7E5FA), fontSize: 12.5),
                ),
              ),
            ],
          )
        else
          for (var i = 0; i < prompts.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _PromptRow(prompt: prompts[i]),
          ],
      ],
    );
  }
}

class _PromptRow extends StatelessWidget {
  const _PromptRow({required this.prompt});

  final RuntimePrompt prompt;

  @override
  Widget build(BuildContext context) {
    final isOpen = prompt.kind == PromptKind.open;
    final accent = isOpen ? const Color(0xFFFFC46B) : const Color(0xFF8FB4FF);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isOpen ? Icons.help_outline : Icons.filter_alt,
          size: 14,
          color: accent,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: prompt.slot,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: ' — ${prompt.detail}',
                  style: const TextStyle(color: Color(0xFFD5D1F2)),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 12, height: 1.35),
          ),
        ),
      ],
    );
  }
}
