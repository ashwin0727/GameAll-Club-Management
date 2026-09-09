import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/staff.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../shared/widgets/picker_chip.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';
import 'staff_common.dart';

class AccessHistoryScreen extends ConsumerStatefulWidget {
  const AccessHistoryScreen({super.key});

  @override
  ConsumerState<AccessHistoryScreen> createState() => _AccessHistoryScreenState();
}

class _AccessHistoryScreenState extends ConsumerState<AccessHistoryScreen> {
  static const _pageSize = 25;
  String? _event;
  int _page = 0;
  List<SecurityEvent>? _events;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? get _facilityId => ref.read(sessionControllerProvider).facility?.id;

  Future<void> _load() async {
    final fid = _facilityId;
    if (fid == null) return;
    setState(() {
      _error = null;
      _events = null;
    });
    try {
      final page = await ref.read(staffRepositoryProvider).listSecurityEvents(
            facilityId: fid,
            event: _event,
            limit: _pageSize,
            offset: _page * _pageSize,
          );
      if (!mounted) return;
      setState(() {
        _events = page.events;
        _total = page.totalCount;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _events = const [];
      });
    }
  }

  Future<void> _pickEvent() async {
    final picked = await showPickerSheet<String>(
      context: context,
      selected: _event ?? 'ALL',
      options: [
        (value: 'ALL', label: 'All Activities'),
        ...securityEventLabels.entries.map((e) => (value: e.key, label: e.value)),
      ],
    );
    if (picked == null) return;
    setState(() {
      _event = picked == 'ALL' ? null : picked;
      _page = 0;
    });
    _load();
  }

  void _goToPage(int p) {
    setState(() => _page = p);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (!session.can('USERS_VIEW')) {
      return const StaffPermissionDenied(message: "You don't have permission to view access history.", title: 'Access History');
    }
    final totalPages = _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

    return Scaffold(
      appBar: AppBar(title: const Text('Access History')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text('Track role changes, access updates and important staff activities.',
                  style: AppTypography.secondary(context)),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: PickerChip(
                  label: _event == null ? 'All Activities' : (securityEventLabels[_event] ?? _event!),
                  onSelect: _pickEvent,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_events == null)
                const LoadingView(message: 'Loading…')
              else if (_events!.isEmpty)
                Text('No activity recorded yet.', style: AppTypography.secondary(context))
              else ...[
                ..._events!.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(securityEventLabels[e.event] ?? e.event,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                ),
                                Text(staffDate(e.createdAt), style: AppTypography.caption(context)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(e.summary, style: AppTypography.secondary(context)),
                            Text(
                              '${e.targetName != null ? '${e.targetName} · ' : ''}by ${e.actorName ?? 'System'}',
                              style: AppTypography.caption(context),
                            ),
                          ],
                        ),
                      ),
                    )),
                if (_total > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  PaginationBar(
                    page: _page,
                    totalPages: totalPages,
                    totalLabel: '$_total activities',
                    onPrevious: _page == 0 ? null : () => _goToPage(_page - 1),
                    onNext: _page + 1 >= totalPages ? null : () => _goToPage(_page + 1),
                  ),
                ],
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
