import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/responsive/responsive_layout.dart';
import 'package:gameall_club_mobile/shared/widgets/states.dart';

/// Regression: a page-load [LoadingView] renders `SkeletonList`, and most
/// finance screens place it inside `ResponsivePage` — a `SingleChildScrollView`
/// with an unbounded incoming height. A non-shrink-wrapped `ListView` there
/// throws "Vertical viewport was given unbounded height" and the whole page
/// renders blank (only the AppBar), which is exactly what Pending Payments
/// did while its request was in flight.
void main() {
  testWidgets('LoadingView renders inside a scrollable ResponsivePage without overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Pending Payments')),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {},
              child: ResponsivePage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Track and collect outstanding payments.'),
                    SizedBox(height: 16),
                    LoadingView(message: 'Loading pending payments…'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // No layout exception was thrown…
    expect(tester.takeException(), isNull);
    // …and the skeleton placeholder actually painted (the page is not blank).
    expect(find.byType(ListView), findsWidgets);
  });
}
