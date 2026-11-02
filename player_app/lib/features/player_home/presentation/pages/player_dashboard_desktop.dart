import 'package:flutter/material.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/widgets/reveal.dart';
import '../../domain/player_home_models.dart';
import '../widgets/player_dashboard.dart';

/// The wide-screen Home of a signed-in player: welcome, the three summary cards, then the schedule and quick actions side by side. The brand bar scrolls with the page, as on the visitor's Home.
class PlayerDashboardDesktop extends StatelessWidget {
  const PlayerDashboardDesktop({super.key, required this.data, required this.onNavigate, this.header, this.now});

  final PlayerHomeData data;
  final RouteCallback onNavigate;
  final Widget? header;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = AppDimensions.desktopSidePadding(width);
    final twoColumns = width >= 1000;

    final schedule = Reveal(delay: const Duration(milliseconds: 120), child: ScheduleCard(items: data.schedule, now: now));
    final actions = Reveal(delay: const Duration(milliseconds: 160), child: QuickActionsCard(onNavigate: onNavigate));

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?header,
          Padding(
            padding: EdgeInsets.fromLTRB(side, 12, side, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Reveal(child: DashboardWelcome(data: data)),
                const SizedBox(height: 24),
                Reveal(delay: const Duration(milliseconds: 60), child: DashboardSummaryCards(data: data, onNavigate: onNavigate)),
                const SizedBox(height: 22),
                if (twoColumns)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Expanded(flex: 11, child: schedule), const SizedBox(width: 20), Expanded(flex: 9, child: actions)],
                  )
                else ...[schedule, const SizedBox(height: 20), actions],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
