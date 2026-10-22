import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../authentication/session_controller.dart';
import 'facility_sections.dart';
import 'hub_providers.dart';
import 'hub_widgets.dart';

/// The pages under Profile → Facility, and the combined "Manage Facility Details" page the Profile hub opens. They all
/// read the same [facilityDataProvider], so the sections can never disagree with each other.
class _FacilityPage extends ConsumerWidget {
  const _FacilityPage({required this.title, required this.sections});

  final String title;

  /// Builds the sections from the loaded data.
  final List<Widget> Function(BuildContext context, FacilityData data) sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(facilityDataProvider);
    final facility = ref.watch(sessionControllerProvider).facility;
    return HubPage(
      title: title,
      onRefresh: () async {
        ref.invalidate(facilityDataProvider);
        await ref.read(facilityDataProvider.future);
      },
      children: [
        if (facility == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text('No facility is set up for this account yet.', style: TextStyle(color: context.tokens.textSecondary)),
          )
        else
          HubAsync<FacilityData>(
            value: data,
            skeletonHeight: 220,
            onRetry: () => ref.invalidate(facilityDataProvider),
            builder: (d) => Column(
              children: [
                for (final s in sections(context, d)) ...[s, const SizedBox(height: AppSpacing.lg)],
              ],
            ),
          ),
      ],
    );
  }
}

/// Profile → Facility → Facility Details.
class FacilityInfoScreen extends ConsumerWidget {
  const FacilityInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facility = ref.watch(sessionControllerProvider).facility;
    return HubPage(
      title: 'Facility Details',
      onRefresh: () => ref.read(sessionControllerProvider.notifier).refresh(),
      children: [
        if (facility == null)
          Text('No facility is set up for this account yet.', style: TextStyle(color: context.tokens.textSecondary))
        else ...[
          FacilityInfoCard(facility: facility),
          const SizedBox(height: AppSpacing.lg),
          AccessDaysSection(facility: facility),
        ],
      ],
    );
  }
}

/// Profile → Facility → Sports & Courts.
class SportsCourtsOverviewScreen extends StatelessWidget {
  const SportsCourtsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      _FacilityPage(title: 'Sports & Courts', sections: (_, d) => [CourtsCard(data: d), SportsSection(data: d)]);
}

/// Profile → Facility → Operating Hours.
class HoursOverviewScreen extends StatelessWidget {
  const HoursOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) => _FacilityPage(title: 'Operating Hours', sections: (_, d) => [TimingsSection(data: d)]);
}

/// Profile → Facility → Pricing Rules.
class PricingOverviewScreen extends StatelessWidget {
  const PricingOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) => _FacilityPage(title: 'Pricing Rules', sections: (_, d) => [PricingSection(data: d)]);
}

/// The Profile hub's "Manage Facility Details": timings, sports, courts, membership access days, then pricing.
class ManageFacilityScreen extends ConsumerWidget {
  const ManageFacilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facility = ref.watch(sessionControllerProvider).facility;
    return _FacilityPage(
      title: 'Manage Facility Details',
      sections: (_, d) => [
        TimingsSection(data: d),
        SportsSection(data: d),
        CourtsCard(data: d),
        if (facility != null) AccessDaysSection(facility: facility),
        PricingSection(data: d),
      ],
    );
  }
}
