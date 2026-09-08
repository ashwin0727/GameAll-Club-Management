import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import 'app_bottom_nav.dart';

/// Wraps a bottom-nav destination so the Android back button / swipe walks
/// toward the Today tab instead of closing the app. Back from Today exits
/// normally.
class TabPopScope extends StatelessWidget {
  const TabPopScope({super.key, required this.tab, required this.child});

  final AppTab tab;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isHome = tab == AppTab.today;
    return PopScope(
      canPop: isHome,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.go(AppRoutes.dashboard);
      },
      child: child,
    );
  }
}
