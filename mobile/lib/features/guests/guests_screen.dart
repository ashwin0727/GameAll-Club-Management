import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/routing/page_transitions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/guest.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_search_field.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/states.dart';
import '../authentication/auth_widgets.dart';
import 'guest_profile_screen.dart';
import '../authentication/session_controller.dart';

class GuestsScreen extends ConsumerStatefulWidget {
  const GuestsScreen({super.key});

  @override
  ConsumerState<GuestsScreen> createState() => _GuestsScreenState();
}

class _GuestsScreenState extends ConsumerState<GuestsScreen> {
  String? _facilityId;
  bool _isLoading = true;
  String? _loadError;

  final _queryController = TextEditingController();
  String _query = '';
  GuestStatus? _statusFilter = GuestStatus.active;
  List<GuestPlayer> _guests = [];
  bool _listLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final facility = ref.read(sessionControllerProvider).facility ??
          await ref.read(facilityRepositoryProvider).getFacility();
      if (facility == null) {
        setState(() {
          _isLoading = false;
          _loadError = 'Complete your facility setup before managing guest players.';
        });
        return;
      }
      setState(() {
        _facilityId = facility.id;
        _isLoading = false;
      });
      await _refreshList();
    } on AppException catch (e) {
      setState(() {
        _isLoading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _refreshList() async {
    if (_facilityId == null) return;
    setState(() => _listLoading = true);
    try {
      final repo = ref.read(guestRepositoryProvider);
      final results = _query.trim().length >= 2
          ? await repo.searchGuests(_facilityId!, _query)
          : await repo.listGuests(_facilityId!, status: _statusFilter);
      if (mounted) {
        setState(() {
          _guests = results;
          _listLoading = false;
        });
      }
    } on AppException catch (_) {
      if (mounted) setState(() => _listLoading = false);
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _refreshList);
  }

  void _upsertGuest(GuestPlayer guest) {
    setState(() {
      final index = _guests.indexWhere((g) => g.id == guest.id);
      if (index >= 0) {
        _guests[index] = guest;
      } else {
        _guests = [guest, ..._guests];
      }
    });
  }

  Future<void> _openProfile(GuestPlayer guest) async {
    final result = await Navigator.of(context).push<GuestPlayer>(
      AppPageRoute(builder: (context) => GuestProfileScreen(facilityId: _facilityId!, guest: guest)),
    );
    if (result != null) _upsertGuest(result);
  }

  /// One shared bottom sheet for every filter on this page — the same
  /// pattern as Guest Bookings and Pending Payments, so filtering feels
  /// like the same gesture everywhere in the app. There's only one filter
  /// here (status) but it still gets the common treatment rather than a
  /// row of inline chips competing with the search field for space.
  Future<void> _openFilterSheet() async {
    final tokens = context.tokens;
    var tmp = _statusFilter;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: tokens.surface0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Filter guest players',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                      ),
                      if (tmp != GuestStatus.active)
                        TextButton(
                          onPressed: () =>
                              setSheet(() => tmp = GuestStatus.active),
                          child: const Text('Reset'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('STATUS',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: tokens.textSecondary)),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      _StatusChip(
                        label: 'Active',
                        selected: tmp == GuestStatus.active,
                        onTap: () => setSheet(() => tmp = GuestStatus.active),
                      ),
                      _StatusChip(
                        label: 'Inactive',
                        selected: tmp == GuestStatus.inactive,
                        onTap: () =>
                            setSheet(() => tmp = GuestStatus.inactive),
                      ),
                      _StatusChip(
                        label: 'All',
                        selected: tmp == null,
                        onTap: () => setSheet(() => tmp = null),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AuthGradientButton(
                    label: 'Show results',
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      setState(() => _statusFilter = tmp);
                      _refreshList();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.surface0,
      appBar: AppBar(
        title: const Text('Guest Players',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: _isLoading
            ? const _GuestsSkeleton()
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : ResponsivePage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AppSearchField(
                            controller: _queryController,
                            hintText: 'Search by name or phone',
                            onChanged: _onQueryChanged,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _FilterButton(
                          active: _statusFilter != GuestStatus.active,
                          onTap: _openFilterSheet,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_listLoading)
                      const _GuestListSkeleton()
                    else if (_guests.isEmpty)
                      EmptyStateView(
                        icon: Icons.person_search_rounded,
                        title: _query.trim().length >= 2
                            ? 'No matches'
                            : 'No guest players yet',
                        message: _query.trim().length >= 2
                            ? 'Nobody matches "${_query.trim()}".'
                            // Nothing to "add" here anymore — a guest player
                            // is created automatically the moment they book,
                            // via the phone-number check in Guest Booking.
                            : 'Guests appear here automatically once they book a court.',
                      )
                    else
                      ..._guests.map(
                        (g) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _GuestRow(
                            guest: g,
                            onTap: () => _openProfile(g),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// The filter affordance beside search. Carries a dot when a non-default
/// filter is active, so an unexpectedly short list is never a mystery.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fill = active ? t.accentSolid(t.primary) : t.surface1;
    final fg = active ? t.onAccent(t.primary) : t.textPrimary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: active ? fill : t.borderColor),
        ),
        child: Icon(Icons.tune_rounded, size: 20, color: fg),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fill = selected ? t.accentSolid(t.primary) : t.surface1;
    final fg = selected ? t.onAccent(t.primary) : t.textPrimary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 9),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? fill : t.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 14, color: fg),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: fg)),
          ],
        ),
      ),
    );
  }
}

class _GuestRow extends StatelessWidget {
  const _GuestRow({required this.guest, required this.onTap});

  final GuestPlayer guest;
  final VoidCallback onTap;

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final inactive = guest.status == GuestStatus.inactive;
    return Material(
      color: t.surface1,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: t.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: inactive ? t.surface2 : t.accentSolid(t.violet),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(_initials(guest.name),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: inactive
                            ? t.textSecondary
                            : t.onAccent(t.violet))),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(guest.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: t.textPrimary)),
                    if (guest.phone != null) ...[
                      const SizedBox(height: 1),
                      Text(guest.phone!,
                          style: TextStyle(
                              fontSize: 12.5, color: t.textSecondary)),
                    ],
                  ],
                ),
              ),
              if (inactive) ...[
                const StatusBadge(label: 'Inactive', tone: StatusTone.neutral),
                const SizedBox(width: AppSpacing.sm),
              ],
              Icon(Icons.chevron_right_rounded,
                  color: t.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Structure-shaped placeholder for the whole page — the search/filter row
/// plus the guest row list below it.
class _GuestsSkeleton extends StatelessWidget {
  const _GuestsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: AppSkeleton(height: 48, radius: AppRadius.md)),
              SizedBox(width: AppSpacing.sm),
              AppSkeleton(width: 48, height: 48, radius: AppRadius.md),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          _GuestListSkeleton(),
        ],
      ),
    );
  }
}

/// The status-chip row + guest rows alone — reused for the list's own
/// refresh region so the shape stays the same as the full-page gate.
class _GuestListSkeleton extends StatelessWidget {
  const _GuestListSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonChipRow(count: 3),
        SizedBox(height: AppSpacing.lg),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
        SizedBox(height: AppSpacing.sm),
        SkeletonListRow(),
      ],
    );
  }
}

