import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/routing/page_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/guest_booking_dashboard.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import '../guests/guest_profile_screen.dart';
import 'potential_members.dart';

/// Guest Bookings → Potential Members — mirrors
/// src/features/bookings/components/potential-members-page.tsx.
///
/// Guests who have booked three or more times and aren't members yet, with the segment's headline
/// figures, the same filters as the web, and the actions a front desk actually uses: copy the
/// membership sign-up link, copy a guest's number, or select several and copy them all in one go.
/// Reached from Guest Bookings; not listed in the menu (same as the web).
class PotentialMembersScreen extends ConsumerStatefulWidget {
  const PotentialMembersScreen({super.key});

  @override
  ConsumerState<PotentialMembersScreen> createState() => _PotentialMembersScreenState();
}

class _PotentialMembersScreenState extends ConsumerState<PotentialMembersScreen> {
  static const _pageSize = 10;
  static const _bookingCounts = [3, 5, 10];
  static const _lastBookingOptions = <int?, String>{null: 'Any time', 7: 'Last 7 days', 30: 'Last 30 days', 90: 'Last 90 days'};
  static const _spentOptions = <int, String>{0: 'Any amount', 100000: '₹1,000 or more', 500000: '₹5,000 or more', 1000000: '₹10,000 or more'};

  final _searchController = TextEditingController();
  List<GuestProfile>? _guests; // every guest with a usable phone, members included
  String? _error;
  PotentialFilters _filters = const PotentialFilters();
  bool _descending = true;
  int _page = 0;
  final Set<String> _selected = {};

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final fid = _facilityId;
    if (fid == null) return;
    setState(() => _error = null);
    try {
      final repo = ref.read(bookingRepositoryProvider);
      final results = await Future.wait([repo.listAllGuestBookings(fid), repo.activeMemberPhoneKeys(fid)]);
      if (!mounted) return;
      setState(() {
        _guests = buildGuestProfiles(results[0] as List<GuestBookingRow>, results[1] as Set<String>, DateTime.now());
      });
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _guests = const [];
        });
      }
    }
  }

  List<GuestProfile> get _potential => potentialMembers(_guests ?? const []);

  List<GuestProfile> get _filtered => sortByBookings(filterPotential(_potential, _filters, DateTime.now()), descending: _descending);

  List<String> get _courts => ({..._potential.map((g) => g.preferredCourt)}.toList()..sort((a, b) => a.compareTo(b)));

  void _setFilters(PotentialFilters f) {
    setState(() {
      _filters = f;
      _page = 0;
      // forget guests that are no longer listed
      final visible = _filtered.map((g) => g.key).toSet();
      _selected.removeWhere((k) => !visible.contains(k));
    });
  }

  String? _joinLink() {
    final base = AppConfig.webAppUrl.trim();
    final fid = _facilityId;
    if (base.isEmpty || fid == null) return null;
    return '${base.replaceAll(RegExp(r'/+$'), '')}/join/$fid';
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _invite() async {
    final link = _joinLink();
    if (link == null) {
      _toast('Self-registration link is not configured for this build.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    _toast('Membership sign-up link copied');
  }

  Future<void> _copyPhone(GuestProfile g) async {
    await Clipboard.setData(ClipboardData(text: g.phone ?? ''));
    _toast("Copied ${g.name}'s number.");
  }

  /// The link, then the selected guests' numbers one to a line, ready to paste into a message.
  Future<void> _copySelected() async {
    final chosen = _filtered.where((g) => _selected.contains(g.key)).toList();
    final link = _joinLink();
    final text = [if (link != null) 'Membership invitation link: $link', '', ...chosen.map((g) => g.phone ?? '')].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    _toast('Copied ${chosen.length} ${chosen.length == 1 ? 'guest' : 'guests'}');
  }

  Future<void> _viewProfile(GuestProfile g) async {
    final fid = _facilityId;
    if (fid == null) return;
    try {
      final matches = await ref.read(guestRepositoryProvider).searchGuests(fid, g.name);
      final found = matches.where((m) => phoneKey(m.phone) == g.key).firstOrNull;
      if (!mounted) return;
      if (found == null) {
        _toast("Couldn't find a saved profile for ${g.name}.");
        return;
      }
      await Navigator.of(context).push(AppPageRoute(builder: (_) => GuestProfileScreen(facilityId: fid, guest: found)));
    } on AppException {
      if (mounted) _toast("Couldn't open the guest profile. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final filtered = _guests == null ? const <GuestProfile>[] : _filtered;
    final totalPages = filtered.isEmpty ? 1 : ((filtered.length + _pageSize - 1) ~/ _pageSize);
    final page = _page.clamp(0, totalPages - 1);
    final pageRows = filtered.skip(page * _pageSize).take(_pageSize).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Potential Members')),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(color: t.surface1, border: Border(top: BorderSide(color: t.borderColor))),
                child: Row(
                  children: [
                    Expanded(child: Text('${_selected.length} selected', style: AppTypography.rowTitle(context))),
                    TextButton(onPressed: () => setState(_selected.clear), child: const Text('Clear')),
                    const SizedBox(width: AppSpacing.xs),
                    FilledButton.icon(
                      onPressed: _copySelected,
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy numbers + link'),
                    ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        child: _error != null && (_guests?.isEmpty ?? true)
            ? ErrorView(message: _error!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text('Guests who frequently book and may be interested in a membership.', style: AppTypography.secondary(context)),
                    const SizedBox(height: AppSpacing.md),
                    _stats(),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _searchController,
                      onChanged: (v) => _setFilters(_filters.copyWith(search: v)),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Search by name or phone',
                        suffixIcon: _filters.search.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  _setFilters(_filters.copyWith(search: ''));
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        PickerChip(label: _filters.court ?? 'All Court Preferences', onSelect: _pickCourt),
                        PickerChip(label: '${_filters.minBookings} or more bookings', onSelect: _pickMinBookings),
                        PickerChip(label: _lastBookingOptions[_filters.lastBookingDays] ?? 'Any time', onSelect: _pickLastBooking),
                        PickerChip(label: _spentOptions[_filters.minSpentMinor] ?? 'Any amount', onSelect: _pickSpent),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _guests == null
                                ? ''
                                : filtered.isEmpty
                                    ? 'No guests'
                                    : '${filtered.length} ${filtered.length == 1 ? 'guest' : 'guests'}',
                            style: AppTypography.caption(context),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() => _descending = !_descending),
                          icon: Icon(_descending ? Icons.arrow_downward : Icons.arrow_upward, size: 16),
                          label: const Text('Bookings'),
                        ),
                        if (filtered.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() {
                              if (_selected.length == filtered.length) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(filtered.map((g) => g.key));
                              }
                            }),
                            child: Text(_selected.length == filtered.length ? 'Deselect all' : 'Select all'),
                          ),
                      ],
                    ),
                    if (_guests == null)
                      const _PotentialSkeleton()
                    else if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Text(
                          _potential.isEmpty
                              ? 'No guests have booked $potentialMinBookings or more times yet.'
                              : 'No guests match these filters.',
                          style: AppTypography.secondary(context),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else ...[
                      ...pageRows.map(_card),
                      const SizedBox(height: AppSpacing.md),
                      PaginationBar(
                        page: page,
                        totalPages: totalPages,
                        totalLabel: '${filtered.length} guests',
                        onPrevious: page == 0 ? null : () => setState(() => _page = page - 1),
                        onNext: page + 1 >= totalPages ? null : () => setState(() => _page = page + 1),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
      ),
    );
  }

  /// The four figures for the whole segment (not narrowed by the filters).
  Widget _stats() {
    final guests = _guests;
    if (guests == null) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 2.2,
        children: const [SkeletonStatTile(), SkeletonStatTile(), SkeletonStatTile(), SkeletonStatTile()],
      );
    }
    final s = segmentStats(guests);
    Widget tile(String label, String value, String sub) => AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text(label, style: AppTypography.caption(context), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(sub, style: AppTypography.caption(context), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 2.0,
      children: [
        tile('Potential Members', '${s.count}', 'Guests with $potentialMinBookings+ bookings'),
        tile('Potential Monthly Revenue', Formatters.currencyInr(s.monthlyRevenueMinor / 100), 'If all convert to members'),
        tile('Conversion Opportunity', '${s.conversionPercent.round()}%', 'Of frequent guests'),
        tile('Avg. Bookings per Guest', s.avgBookings.toStringAsFixed(1), 'Among this segment'),
      ],
    );
  }

  Widget _card(GuestProfile g) {
    final t = context.tokens;
    final selected = _selected.contains(g.key);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () => setState(() => selected ? _selected.remove(g.key) : _selected.add(g.key)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.md, AppSpacing.xs, AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => setState(() => v == true ? _selected.add(g.key) : _selected.remove(g.key)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(g.name, style: AppTypography.rowTitle(context))),
                          StatusBadge(label: g.label, tone: g.isFrequent ? StatusTone.success : StatusTone.neutral),
                        ],
                      ),
                      Text(g.phone ?? '—', style: AppTypography.caption(context)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${g.bookings} bookings · last ${DateFormat('d MMM yyyy').format(g.lastBookingAt)}',
                        style: AppTypography.body(context),
                      ),
                      Text(
                        '${Formatters.currencyInr(g.totalSpentMinor / 100)} spent · ${Formatters.currencyInr(g.monthlySpendMinor / 100)}/mo · ${g.preferredCourt}',
                        style: AppTypography.caption(context),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          _action(Icons.link, 'Invite', _invite, t.primary),
                          _action(Icons.copy_outlined, 'Copy number', () => _copyPhone(g), t.primary),
                          _action(Icons.person_outline, 'Profile', () => _viewProfile(g), t.primary),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap, Color color) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );

  Future<void> _pickCourt() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _filters.court ?? 'ALL',
      options: [(value: 'ALL', label: 'All Court Preferences'), ..._courts.map((c) => (value: c, label: c))],
    );
    if (picked == null) return;
    _setFilters(_filters.copyWith(court: picked == 'ALL' ? null : picked));
  }

  Future<void> _pickMinBookings() async {
    final picked = await showPickerSheet<int>(
      context: context,
      selected: _filters.minBookings,
      options: [for (final n in _bookingCounts) (value: n, label: '$n or more')],
    );
    if (picked != null) _setFilters(_filters.copyWith(minBookings: picked));
  }

  Future<void> _pickLastBooking() async {
    final picked = await showPickerSheet<int>(
      context: context,
      selected: _filters.lastBookingDays ?? -1,
      options: [for (final e in _lastBookingOptions.entries) (value: e.key ?? -1, label: e.value)],
    );
    if (picked == null) return;
    _setFilters(_filters.copyWith(lastBookingDays: picked == -1 ? null : picked));
  }

  Future<void> _pickSpent() async {
    final picked = await showPickerSheet<int>(
      context: context,
      selected: _filters.minSpentMinor,
      options: [for (final e in _spentOptions.entries) (value: e.key, label: e.value)],
    );
    if (picked != null) _setFilters(_filters.copyWith(minSpentMinor: picked));
  }
}

class _PotentialSkeleton extends StatelessWidget {
  const _PotentialSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
      ],
    );
  }
}
