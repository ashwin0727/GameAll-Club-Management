import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/maintenance.dart';
import '../../data/repositories/repository_providers.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/misc.dart';
import '../../shared/widgets/states.dart';
import '../authentication/session_controller.dart';

const _iconKeys = ['court', 'lightbulb', 'grid', 'snowflake', 'cog', 'droplet', 'lock', 'paint', 'wrench', 'more'];

IconData _iconFor(String key) => switch (key) {
      'court' => Icons.grid_4x4,
      'lightbulb' => Icons.lightbulb_outline,
      'grid' => Icons.grid_on,
      'snowflake' => Icons.ac_unit,
      'cog' => Icons.settings,
      'droplet' => Icons.water_drop_outlined,
      'lock' => Icons.lock_outline,
      'paint' => Icons.format_paint_outlined,
      'more' => Icons.more_horiz,
      _ => Icons.build_outlined,
    };

/// Maintenance → Issue Categories — mirrors
/// src/features/maintenance/components/issue-categories-page.tsx.
class MaintenanceIssueCategoriesScreen extends ConsumerStatefulWidget {
  const MaintenanceIssueCategoriesScreen({super.key});

  @override
  ConsumerState<MaintenanceIssueCategoriesScreen> createState() => _State();
}

class _State extends ConsumerState<MaintenanceIssueCategoriesScreen> {
  List<MaintenanceIssueCategory>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) return;
    try {
      final rows = await ref.read(maintenanceRepositoryProvider).listIssueCategories(facility.id);
      if (mounted) setState(() => _items = rows);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Issue Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editSheet(null),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: _error != null && _items == null
            ? ErrorView(message: _error!, onRetry: _load)
            : _items == null
                ? const LoadingView()
                : _items!.isEmpty
                    ? const EmptyStateView(message: 'No issue categories yet.')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: _items!.length,
                          separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, i) {
                            final c = _items![i];
                            return AppCard(
                              onTap: c.isShared ? null : () => _editSheet(c),
                              child: Row(
                                children: [
                                  Icon(_iconFor(c.icon)),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                            if (c.isShared)
                                              const Padding(
                                                padding: EdgeInsets.only(left: 6),
                                                child: Text('Default', style: TextStyle(fontSize: 11)),
                                              ),
                                          ],
                                        ),
                                        if (c.description != null) Text(c.description!, style: Theme.of(context).textTheme.bodySmall),
                                      ],
                                    ),
                                  ),
                                  StatusBadge(
                                    label: c.isActive ? 'Active' : 'Inactive',
                                    tone: c.isActive ? StatusTone.success : StatusTone.neutral,
                                  ),
                                  const SizedBox(width: 6),
                                  Text('${c.issueCount}', style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }

  Future<void> _editSheet(MaintenanceIssueCategory? category) async {
    final facility = ref.read(sessionControllerProvider).facility;
    if (facility == null) return;
    final name = TextEditingController(text: category?.name ?? '');
    final description = TextEditingController(text: category?.description ?? '');
    var icon = category?.icon ?? 'wrench';
    var isActive = category?.isActive ?? true;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(category == null ? 'Add Issue Category' : 'Edit Issue Category', style: Theme.of(ctx).textTheme.titleMedium),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Category Name'), maxLength: 60),
              TextField(controller: description, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2, maxLength: 200),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (final k in _iconKeys)
                    ChoiceChip(
                      avatar: Icon(_iconFor(k), size: 16),
                      label: const Text(''),
                      selected: icon == k,
                      onSelected: (_) => setSheet(() => icon = k),
                    ),
                ],
              ),
              if (category != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: isActive,
                  onChanged: (v) => setSheet(() => isActive = v),
                ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save Category')),
            ],
          ),
        ),
      ),
    );

    if (saved == true && name.text.trim().isNotEmpty) {
      try {
        final repo = ref.read(maintenanceRepositoryProvider);
        if (category == null) {
          await repo.createIssueCategory(facilityId: facility.id, name: name.text.trim(), icon: icon, description: description.text.trim());
        } else {
          await repo.updateIssueCategory(
            categoryId: category.id,
            name: name.text.trim(),
            icon: icon,
            description: description.text.trim(),
            isActive: isActive,
          );
        }
        await _load();
      } on AppException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    name.dispose();
    description.dispose();
  }
}
