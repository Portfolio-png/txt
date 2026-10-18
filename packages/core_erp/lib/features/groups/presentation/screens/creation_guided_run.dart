/// The guided first run: the presentation half.
///
/// A workspace with no items at all has nobody to copy from, so the bench —
/// thirteen cards and a free-form lineup — is the wrong first thing to meet.
/// This asks three questions in the factory's own words instead: what is the
/// part, what makes it, and does it run on a die of its own.
///
/// **Only the chrome lives here.** The writes, the state and the permission
/// checks stay in the workspace, which already holds the sitting, the records
/// added so far and the link service. Threading a dozen of those into a widget
/// would hide where the writing happens; a host that can see the state is
/// easier to reason about than a widget that has been handed pieces of it.
///
/// Offered, never forced: every step carries the way out to the full bench.
library;

import 'package:flutter/material.dart';

import '../../../../core/app_flow_hooks.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/soft_master_data.dart';

/// Which question is on screen.
enum GuidedStep {
  part('The part', 'What are you making?'),
  machine('The machine', 'Which machine makes this part?'),
  die('The die', 'Does it run on a die of its own?'),
  done('Done', 'What you just set up');

  const GuidedStep(this.label, this.prompt);

  final String label;
  final String prompt;

  /// Position among the three questions. `done` is not one of them.
  int get number => index + 1;

  static const int questionCount = 3;
}

/// The header every step carries: where you are, what is being asked, and the
/// way out.
class GuidedStepChrome extends StatelessWidget {
  const GuidedStepChrome({
    super.key,
    required this.step,
    required this.onSwitchToBench,
    this.trailing,
  });

  final GuidedStep step;

  /// Always offered. A guided run that cannot be left is a wizard somebody is
  /// trapped in.
  final VoidCallback onSwitchToBench;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isQuestion = step != GuidedStep.done;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isQuestion)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    'Step ${step.number} of ${GuidedStep.questionCount}',
                    key: ValueKey<String>('guided_step_${step.name}'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: SoftErpTheme.accent,
                    ),
                  ),
                ),
              const Spacer(),
              ?trailing,
              const SizedBox(width: 8),
              SoftActionLink(
                key: const ValueKey<String>('guided_switch_to_bench'),
                label: 'Switch to the full bench',
                onTap: onSwitchToBench,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            step.prompt,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One candidate to attach, as the picker lists it.
class GuidedCandidate {
  const GuidedCandidate({
    required this.id,
    required this.label,
    this.subtitle = '',
  });

  final String id;
  final String label;
  final String subtitle;
}

/// Steps 2 and 3: pick one that exists, or make one, or say there isn't one.
///
/// "Not sure yet" and "No die" are first-class answers, not a way of dodging
/// the question — a part whose machine nobody has decided yet is a real state,
/// and recording a guess would be worse than recording nothing.
class GuidedPickOrCreate extends StatelessWidget {
  const GuidedPickOrCreate({
    super.key,
    required this.step,
    required this.candidates,
    required this.onPick,
    required this.onSkip,
    required this.skipLabel,
    required this.onCreate,
    required this.createLabel,
    required this.denialReason,
    this.busyId,
  });

  final GuidedStep step;
  final List<GuidedCandidate> candidates;
  final ValueChanged<GuidedCandidate> onPick;
  final VoidCallback onSkip;
  final String skipLabel;

  /// Null when this user may not create one. The control is still drawn —
  /// hiding it would read as the feature not existing.
  final VoidCallback? onCreate;
  final String createLabel;

  /// Said out loud when [onCreate] is null, so a refusal names the permission
  /// instead of looking like a bug.
  final String denialReason;

  final String? busyId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
      children: [
        if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Nothing to pick from yet.',
              style: const TextStyle(
                fontSize: 15,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
        for (final candidate in candidates)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: SoftErpTheme.cardSurface,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
              child: InkWell(
                key: ValueKey<String>('guided_pick_${candidate.id}'),
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
                onTap: busyId != null ? null : () => onPick(candidate),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: SoftErpTheme.border),
                    borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              candidate.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: SoftErpTheme.textPrimary,
                              ),
                            ),
                            if (candidate.subtitle.isNotEmpty)
                              Text(
                                candidate.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: SoftErpTheme.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (busyId == candidate.id)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(
                          Icons.chevron_right,
                          color: SoftErpTheme.textSecondary,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Tooltip(
              message: onCreate == null ? denialReason : createLabel,
              child: AppButton(
                key: ValueKey<String>('guided_create_${step.name}'),
                label: createLabel,
                icon: Icons.add,
                variant: AppButtonVariant.secondary,
                onPressed: onCreate,
              ),
            ),
            const SizedBox(width: 12),
            SoftActionLink(
              key: ValueKey<String>('guided_skip_${step.name}'),
              label: skipLabel,
              onTap: onSkip,
            ),
          ],
        ),
      ],
    );
  }
}

/// What the guided run produced, in sentences.
///
/// Built from the answers the run already holds, not re-derived from the link
/// graph: it has to read for somebody **without** `audit.read`, and the local
/// session is the one source that needs no permission and no request.
class GuidedFinishLine extends StatelessWidget {
  const GuidedFinishLine({
    super.key,
    required this.partName,
    required this.machine,
    required this.die,
    required this.records,
    required this.onOpenPart,
    required this.onAddAnother,
    required this.onSwitchToBench,
  });

  final String partName;

  /// Null when the step was skipped — which is a real answer, and says so.
  final CreatedRecord? machine;
  final CreatedRecord? die;

  /// Everything saved in this opening, newest last, from the local session.
  final List<String> records;

  final VoidCallback onOpenPart;
  final VoidCallback onAddAnother;
  final VoidCallback onSwitchToBench;

  /// The run in one line, in the words somebody would use on the floor.
  String get sentence {
    final machineName = machine?.title;
    final dieName = die?.title;
    if (machineName != null && dieName != null) {
      return '$partName is made on $machineName with $dieName.';
    }
    if (machineName != null) return '$partName is made on $machineName.';
    if (dieName != null) return '$partName runs on $dieName.';
    return '$partName is set up. Nothing is attached to it yet.';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
      children: [
        Container(
          key: const ValueKey<String>('guided_finish_sentence'),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: SoftErpTheme.accentSoft,
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
          ),
          child: Text(
            sentence,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: SoftErpTheme.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Saved here',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: SoftErpTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        for (final record in records)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: SoftErpTheme.successText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    record,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton(
              key: const ValueKey<String>('guided_open_part'),
              label: 'Open the part',
              onPressed: onOpenPart,
            ),
            AppButton(
              key: const ValueKey<String>('guided_add_another'),
              label: 'Add another part',
              variant: AppButtonVariant.secondary,
              onPressed: onAddAnother,
            ),
            AppButton(
              key: const ValueKey<String>('guided_finish_bench'),
              label: 'Go to the full bench',
              variant: AppButtonVariant.secondary,
              onPressed: onSwitchToBench,
            ),
          ],
        ),
      ],
    );
  }
}
