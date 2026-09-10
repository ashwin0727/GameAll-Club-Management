import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/models/finance.dart';
import 'package:gameall_club_mobile/data/repositories/finance_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/finance/pending_payments_screen.dart';

Facility _facility() => Facility(
      id: 'facility-1',
      ownerId: 'owner-1',
      name: 'Test Arena',
      type: FacilityType.multiSport,
      businessEmail: 'o@x.com',
      businessPhone: '900',
      address: const FacilityAddress(
        line1: 'a', area: 'b', city: 'c', state: 'd', country: 'India', pinCode: '600001',
      ),
      status: 'ACTIVE',
      onboardingStep: OnboardingStep.completed,
    );

PaymentObligation _obligation() => const PaymentObligation(
      sourceType: ObligationSource.guestBooking,
      sourceId: 'src-1',
      reference: 'GB-1234',
      customerName: 'Neha',
      customerPhone: '900',
      description: 'Court 2 · 6-7pm',
      facilityName: 'Test Arena',
      courtName: 'Court 2',
      startsAt: null,
      endsAt: null,
      totalMinor: 100000,
      paidMinor: 0,
      outstandingMinor: 100000,
      status: ObligationStatus.pending,
      paymentMethod: null,
      dueOn: '2026-09-09',
    );

/// `implements` (not `extends`) so no real `SupabaseClient` — which would
/// start a token-refresh Timer and leak past the test — is constructed.
class _FakeFinanceRepository implements FinanceRepository {
  @override
  Future<PendingPaymentsPage> listPendingPayments(ListPendingPaymentsInput input) async {
    return PendingPaymentsPage(obligations: [_obligation()], totalCount: 1);
  }

  @override
  Future<PendingPaymentsSummary> getPendingPaymentsSummary(String facilityId, {String? from, String? to}) async {
    return const PendingPaymentsSummary(
      outstandingMinor: 100000,
      pendingMinor: 100000,
      partiallyPaidMinor: 0,
      overdueMinor: 0,
      obligationCount: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSession extends SessionController {
  @override
  SessionState build() => SessionState(user: null, facility: _facility(), isLoading: false);
}

void main() {
  testWidgets('Pending Payments — filter chips and Record button receive taps', (tester) async {
    final router = GoRouter(
      initialLocation: '/finance/pending-payments',
      routes: [
        GoRoute(
          path: '/finance/pending-payments',
          builder: (_, _) =>const PendingPaymentsScreen(),
        ),
        GoRoute(
          path: '/finance/pending-payments/:sourceId/record',
          builder: (_, _) =>const Scaffold(body: Text('RECORD PAGE')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeRepositoryProvider.overrideWithValue(_FakeFinanceRepository()),
          sessionControllerProvider.overrideWith(_FakeSession.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // Data rendered.
    expect(find.text('Neha'), findsOneWidget);
    expect(find.textContaining('Record'), findsWidgets);

    // A filter chip opens its options sheet.
    await tester.tap(find.text('All Outstanding'));
    await tester.pumpAndSettle();
    expect(find.text('Overdue'), findsWidgets, reason: 'tapping the status chip must open the picker sheet');
    await tester.tapAt(const Offset(20, 20)); // dismiss the sheet
    await tester.pumpAndSettle();

    // The Record button navigates.
    final recordButton = find.ancestor(
      of: find.textContaining('Record ₹'),
      matching: find.byType(ElevatedButton),
    );
    expect(recordButton, findsOneWidget);
    await tester.ensureVisible(recordButton);
    await tester.pumpAndSettle();
    await tester.tap(recordButton);
    await tester.pumpAndSettle();
    expect(find.text('RECORD PAGE'), findsOneWidget, reason: 'the Record button tap must push the record route');
  });
}
