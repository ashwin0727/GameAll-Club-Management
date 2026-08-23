import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

const List<String> _steps = [
  'Facility Details',
  'Sports',
  'Courts & Turfs',
  'Operating Hours',
  'Pricing',
  'Setup',
];

/// Mirrors the web app's OnboardingProgress — compact "Step N of 6" plus
/// the current step's name, sized to fit the AppBar without truncating
/// (long step names still wrap the title area if the font is scaled up).
class OnboardingProgressBar extends StatelessWidget implements PreferredSizeWidget {
  const OnboardingProgressBar({super.key, required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step $currentStep of ${_steps.length}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.muted),
        ),
        Text(
          _steps[currentStep - 1],
          style: Theme.of(context).textTheme.titleMedium,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(48);
}