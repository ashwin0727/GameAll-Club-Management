import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/dashboard.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';

const Map<DateRangePreset, String> _presetLabels = {
  DateRangePreset.today: 'Today',
  DateRangePreset.yesterday: 'Yesterday',
  DateRangePreset.thisWeek: 'This Week',
  DateRangePreset.thisMonth: 'This Month',
};

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String? _facilityId;
  String? _selectedSportId;
  DateRangePreset _preset = DateRangePreset.today;

  bool _isLoading = true;
  String? _loadError;
  DashboardSummary? _summary;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final facility = ref.read(sessionControllerProvider).facility;
    _facilityId = facility?.id;
    await _load();
  }

  Future<void> _load() async {
    if (_facilityId == null) {
      setState(() {
        _isLoading = false;
        _loadError = 'Unable to load your facility.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final summary = await ref.read(dashboardRepositoryProvider).getDashboardSummary(
        _facilityId!,
        facilitySportId: _selectedSportId,
        preset: _preset,
      );
      setState(() {
        _summary = summary;
        _isLoading = false;
      });
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Bookings',
            onPressed: () => context.push(AppRoutes.bookings),
          ),
          IconButton(
            icon: const Icon(Icons.groups_outlined),
            tooltip: 'Guest Players',
            onPressed: () => context.push(AppRoutes.guests),
          ),
          IconButton(
            icon: const Icon(Icons.card_membership),
            tooltip: 'Members',
            onPressed: () => context.push(AppRoutes.members),
          ),
          IconButton(
            icon: const Icon(Icons.event_repeat),
            tooltip: 'Membership Sessions',
            onPressed: () => context.push(AppRoutes.membershipSessions),
          ),
          IconButton(
            icon: const Icon(Icons.currency_rupee),
            tooltip: 'Refunds',
            onPressed: () => context.push(AppRoutes.refunds),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading dashboard…')
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ResponsivePage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_greeting()}${user?.fullName.split(' ').first != null ? ', ${user!.fullName.split(' ').first}' : ''} 👋',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${_summary!.facilityName}${_summary!.facilityCity.isNotEmpty ? ' · ${_summary!.facilityCity}' : ''}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          _SelectorChip<String?>(
                            value: _selectedSportId,
                            label: _selectedSportId == null
                                ? 'All Sports'
                                : _summary!.sports
                                      .where((s) => s.facilitySportId == _selectedSportId)
                                      .map((s) => s.sportName)
                                      .firstOrNull ?? 'All Sports',
                            onSelect: () async {
                              final picked = await _showSportPicker(context, _summary!.sports);
                              if (picked != _selectedSportId) {
                                setState(() => _selectedSportId = picked);
                                _load();
                              }
                            },
                          ),
                          _SelectorChip<DateRangePreset>(
                            value: _preset,
                            label: _presetLabels[_preset]!,
                            onSelect: () async {
                              final picked = await _showDatePresetPicker(context, _preset);
                              if (picked != null && picked != _preset) {
                                setState(() => _preset = picked);
                                _load();
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SecondaryButton(
                        label: '+ New Booking',
                        onPressed: () => context.push(AppRoutes.bookings),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _KpiGrid(summary: _summary!),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Attention Required'),
                      const SizedBox(height: AppSpacing.sm),
                      AppCard(
                        child: _summary!.attentionItems.isEmpty
                            ? const Row(
                                children: [
                                  Icon(Icons.check_circle, color: AppColors.success, size: 18),
                                  SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text('Everything looks good. No immediate attention required.'),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _summary!.attentionItems
                                    .map((a) => Padding(
                                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                                          child: Text('⚠ ${a.message}'),
                                        ))
                                    .toList(),
                              ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: "Today's Schedule"),
                      const SizedBox(height: AppSpacing.sm),
                      AppCard(
                        child: _summary!.schedule.isEmpty
                            ? const Text('No operating hours configured for today.')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _summary!.schedule
                                    .take(20)
                                    .map(
                                      (entry) => Padding(
                                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${entry.time} · ${entry.sportName} — ${entry.playingAreaName}',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            StatusBadge(
                                              label: entry.status == ScheduleSlotStatus.booked
                                                  ? 'Booked'
                                                  : 'Available',
                                              tone: entry.status == ScheduleSlotStatus.booked
                                                  ? StatusTone.neutral
                                                  : StatusTone.success,
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Revenue by Sport'),
                      const SizedBox(height: AppSpacing.sm),
                      const UnavailableCard(
                        message: 'Revenue by sport isn\'t available yet — it needs completed booking payments to report on.',
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Court/Turf Utilization'),
                      const SizedBox(height: AppSpacing.sm),
                      AppCard(
                        child: _summary!.utilization.bySport.isEmpty
                            ? const Text('No sports configured yet.')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _summary!.utilization.bySport
                                    .map(
                                      (s) => Padding(
                                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                        child: Row(
                                          children: [
                                            Expanded(child: Text(s.sportName)),
                                            Text('${s.utilizationPercent}%'),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Memberships'),
                      const SizedBox(height: AppSpacing.sm),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${_summary!.memberships.active}', style: Theme.of(context).textTheme.titleLarge),
                            Text(
                              '${_summary!.memberships.expiringSoon} expiring soon · ${_summary!.memberships.newThisMonth} new this month',
                              style: const TextStyle(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Payments'),
                      const SizedBox(height: AppSpacing.sm),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CurrencyText(
                              _summary!.payments.collectedInr,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              '${Formatters.currencyInr(_summary!.payments.pendingInr)} pending · '
                              '${Formatters.currencyInr(_summary!.payments.refundsInr)} refunded',
                              style: const TextStyle(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Live Activity'),
                      const SizedBox(height: AppSpacing.sm),
                      const UnavailableCard(
                        message: 'Live check-ins and in-progress sessions aren\'t tracked yet.',
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Guest Players'),
                      const SizedBox(height: AppSpacing.sm),
                      const UnavailableCard(
                        message: 'Guest player tracking isn\'t available yet.',
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Expenses'),
                      const SizedBox(height: AppSpacing.sm),
                      const UnavailableCard(
                        message: 'Expense tracking isn\'t available yet.',
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Business Position'),
                      const SizedBox(height: AppSpacing.sm),
                      const UnavailableCard(
                        message: 'Profit/loss reporting needs expenses to be tracked first.',
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeader(title: 'Upcoming'),
                      const SizedBox(height: AppSpacing.sm),
                      const UnavailableCard(
                        message: 'Tournaments and coaching sessions aren\'t available yet.',
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Future<String?> _showSportPicker(BuildContext context, List<AvailableSportOption> sports) {
    return showModalBottomSheet<String?>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('All Sports'), onTap: () => Navigator.pop(context, null)),
            ...sports.map(
              (s) => ListTile(
                leading: Text(s.sportIcon),
                title: Text(s.sportName),
                onTap: () => Navigator.pop(context, s.facilitySportId),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<DateRangePreset?> _showDatePresetPicker(BuildContext context, DateRangePreset current) {
    return showModalBottomSheet<DateRangePreset>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _presetLabels.entries
              .map((e) => ListTile(title: Text(e.value), onTap: () => Navigator.pop(context, e.key)))
              .toList(),
        ),
      ),
    );
  }
}

class _SelectorChip<T> extends StatelessWidget {
  const _SelectorChip({required this.value, required this.label, required this.onSelect});

  final T value;
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 400;
        final tiles = [
          _KpiTile(label: 'Revenue', valueText: Formatters.currencyInr(summary.kpis.revenueInr.value)),
          _KpiTile(label: 'Bookings', valueText: summary.kpis.bookings.value.toStringAsFixed(0)),
          _KpiTile(label: 'Utilization', valueText: '${summary.kpis.utilizationPercent.value}%'),
          _KpiTile(label: 'Active Members', valueText: summary.kpis.activeMembers.value.toStringAsFixed(0)),
        ];
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: tiles
              .map((t) => SizedBox(width: isNarrow ? constraints.maxWidth : (constraints.maxWidth - AppSpacing.md) / 2, child: t))
              .toList(),
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.label, required this.valueText});

  final String label;
  final String valueText;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            valueText,
            style: Theme.of(context).textTheme.titleLarge,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}