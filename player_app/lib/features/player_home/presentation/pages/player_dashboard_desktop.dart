import 'package:flutter/material.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/widgets/reveal.dart';
import '../../domain/player_home_models.dart';
import '../widgets/payment_prompts.dart';
import '../widgets/player_dashboard.dart';

/// The wide-screen Home of a signed-in player: welcome, the three summary cards, then the schedule and quick actions side by side. The brand bar scrolls with the page, as on the visitor's Home.
class PlayerDashboardDesktop extends StatelessWidget {
  const PlayerDashboardDesktop({
    super.key,
    required this.data,
    required this.onNavigate,
    this.header,
    this.now,
  });

  final PlayerHomeData data;
  final RouteCallback onNavigate;
  final Widget? header;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = AppDimensions.desktopSidePadding(width);

    final schedule = Reveal(
      delay: const Duration(milliseconds: 120),
      child: ScheduleCard(items: data.schedule, now: now),
    );

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
                // Anything not fully paid is a prompt with a way to pay, ahead of the cards (it is not "Active" until it is paid).
                if (data.pendingPayments.isNotEmpty) ...[
                  PaymentPrompts(payments: data.pendingPayments, onNavigate: onNavigate),
                  const SizedBox(height: 10),
                ],
                Reveal(
                  delay: const Duration(milliseconds: 60),
                  child: DashboardSummaryCards(
                    data: data,
                    onNavigate: onNavigate,
                  ),
                ),
                const SizedBox(height: 22),
                // the schedule has the whole width now that Quick Actions is gone
                schedule,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
