import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_provider.dart';
import 'auth_repository.dart';
import 'facility_repository.dart';
import 'sports_repository.dart';
import 'playing_area_repository.dart';
import 'operating_hours_repository.dart';
import 'pricing_repository.dart';
import 'onboarding_repository.dart';
import 'dashboard_repository.dart';
import 'booking_repository.dart';
import 'guest_repository.dart';
import 'membership_repository.dart';
import 'membership_session_repository.dart';
import 'payment_repository.dart';
import 'refund_repository.dart';
import 'finance_repository.dart';
import 'reports_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final facilityRepositoryProvider = Provider<FacilityRepository>((ref) {
  return FacilityRepository(ref.watch(supabaseClientProvider));
});

final sportsRepositoryProvider = Provider<SportsRepository>((ref) {
  return SportsRepository(ref.watch(supabaseClientProvider));
});

final playingAreaRepositoryProvider = Provider<PlayingAreaRepository>((ref) {
  return PlayingAreaRepository(ref.watch(supabaseClientProvider));
});

final operatingHoursRepositoryProvider = Provider<OperatingHoursRepository>((ref) {
  return OperatingHoursRepository(ref.watch(supabaseClientProvider));
});

final pricingRepositoryProvider = Provider<PricingRepository>((ref) {
  return PricingRepository(ref.watch(supabaseClientProvider));
});

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(facilityRepositoryProvider),
    ref.watch(sportsRepositoryProvider),
    ref.watch(playingAreaRepositoryProvider),
    ref.watch(operatingHoursRepositoryProvider),
    ref.watch(pricingRepositoryProvider),
  );
});

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(facilityRepositoryProvider),
    ref.watch(sportsRepositoryProvider),
    ref.watch(playingAreaRepositoryProvider),
    ref.watch(operatingHoursRepositoryProvider),
  );
});

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(ref.watch(supabaseClientProvider));
});

final guestRepositoryProvider = Provider<GuestRepository>((ref) {
  return GuestRepository(ref.watch(supabaseClientProvider));
});

final membershipRepositoryProvider = Provider<MembershipRepository>((ref) {
  return MembershipRepository(ref.watch(supabaseClientProvider));
});

final membershipSessionRepositoryProvider = Provider<MembershipSessionRepository>((ref) {
  return MembershipSessionRepository(ref.watch(supabaseClientProvider));
});

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository(ref.watch(supabaseClientProvider));
});

final refundRepositoryProvider = Provider<RefundRepository>((ref) {
  return RefundRepository(ref.watch(supabaseClientProvider));
});

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(ref.watch(supabaseClientProvider));
});

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.watch(supabaseClientProvider));
});