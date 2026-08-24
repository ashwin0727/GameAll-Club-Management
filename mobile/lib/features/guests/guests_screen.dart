import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/app_exception.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/guest.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_search_field.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import 'guest_form_sheet.dart';
import 'guest_profile_screen.dart';

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
      final facility = await ref.read(facilityRepositoryProvider).getFacility();
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

  Future<void> _openAddGuest() async {
    final guest = await showModalBottomSheet<GuestPlayer>(
      context: context,
      isScrollControlled: true,
      builder: (context) => GuestFormSheet(facilityId: _facilityId!),
    );
    if (guest != null) _upsertGuest(guest);
  }

  Future<void> _openProfile(GuestPlayer guest) async {
    final result = await Navigator.of(context).push<GuestPlayer>(
      MaterialPageRoute(builder: (context) => GuestProfileScreen(facilityId: _facilityId!, guest: guest)),
    );
    if (result != null) _upsertGuest(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guest Players')),
      body: SafeArea(
        child: _isLoading
            ? const LoadingView(message: 'Loading guest players…')
            : _loadError != null
            ? ErrorView(message: _loadError!, onRetry: _load)
            : ResponsivePage(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSearchField(
                      controller: _queryController,
                      hintText: 'Search by name or phone',
                      onChanged: _onQueryChanged,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        ChoiceChip(
                          label: const Text('Active'),
                          selected: _statusFilter == GuestStatus.active,
                          onSelected: (_) {
                            setState(() => _statusFilter = GuestStatus.active);
                            _refreshList();
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Inactive'),
                          selected: _statusFilter == GuestStatus.inactive,
                          onSelected: (_) {
                            setState(() => _statusFilter = GuestStatus.inactive);
                            _refreshList();
                          },
                        ),
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _statusFilter == null,
                          onSelected: (_) {
                            setState(() => _statusFilter = null);
                            _refreshList();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_listLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_guests.isEmpty)
                      EmptyStateView(
                        message: _query.trim().length >= 2 ? 'No guest players found.' : 'No guest players have been added yet.',
                        actionLabel: _query.trim().length >= 2 ? null : '+ Add Guest',
                        onAction: _query.trim().length >= 2 ? null : _openAddGuest,
                      )
                    else
                      ..._guests.map(
                        (g) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: InkWell(
                            onTap: () => _openProfile(g),
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            child: AppCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(g.name, style: AppTypography.rowTitle(context)),
                                        if (g.phone != null)
                                          Text(g.phone!, style: AppTypography.caption(context)),
                                      ],
                                    ),
                                  ),
                                  if (g.status == GuestStatus.inactive) ...[
                                    const StatusBadge(label: 'Inactive', tone: StatusTone.neutral),
                                    const SizedBox(width: AppSpacing.sm),
                                  ],
                                  const Icon(Icons.chevron_right, color: AppColors.muted),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      floatingActionButton: _facilityId == null
          ? null
          : FloatingActionButton.extended(onPressed: _openAddGuest, icon: const Icon(Icons.add), label: const Text('Add Guest')),
    );
  }
}