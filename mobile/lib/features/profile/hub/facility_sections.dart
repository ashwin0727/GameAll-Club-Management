import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/facility.dart';
import '../../../data/models/pricing.dart';
import '../../../data/models/sport.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../authentication/auth_widgets.dart';
import '../../authentication/session_controller.dart';
import '../../onboarding/operating_hours_summary.dart';
import '../../onboarding/pricing_summary.dart';
import 'hub_providers.dart';
import 'hub_widgets.dart';

/// Is the signed-in user the owner of this facility? Only the owner can change the facility's setup.
bool isFacilityOwner(WidgetRef ref) {
  final session = ref.watch(sessionControllerProvider);
  final facility = session.facility;
  return facility != null && facility.ownerId == session.user?.id;
}

/// Opens a setup screen in edit mode and refreshes what the facility pages show when it saves.
Future<void> openSetupEditor(BuildContext context, WidgetRef ref, String route) async {
  final saved = await context.push<bool>(route);
  if (saved == true) {
    ref.invalidate(facilityDataProvider);
    ref.invalidate(hubStatsProvider);
  }
}

// ── Facility details ───────────────────────────────────────────────────────

/// The facility's own details. The address and description can be edited; the name, type and contact details are fixed.
class FacilityInfoCard extends ConsumerWidget {
  const FacilityInfoCard({super.key, required this.facility});

  final Facility facility;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final owner = isFacilityOwner(ref);
    final a = facility.address;
    final address = [a.line1, a.area, a.city, a.state, a.pinCode].where((s) => s.trim().isNotEmpty).join(', ');
    final active = facility.status == 'ACTIVE';
    return HubCard(
      title: 'Your Facility',
      subtitle: 'What you entered when you set the facility up.',
      trailing: owner ? HubAction(label: 'Edit', onTap: () => showEditFacilityAddressSheet(context, ref, facility)) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (facility.logoUrl != null && facility.logoUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.network(facility.logoUrl!, width: 52, height: 52, fit: BoxFit.cover),
                )
              else
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: t.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Text(facility.name.isEmpty ? '?' : facility.name[0].toUpperCase(),
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.primary)),
                ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(facility.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: t.textPrimary)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: (active ? t.success : t.textSecondary).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(active ? 'Active' : 'Inactive',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? t.success : t.textSecondary)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          HubInfoRow('Facility type', facility.type == FacilityType.other ? (facility.customType ?? 'Other') : facility.type.label),
          HubInfoRow('Business email', facility.businessEmail),
          HubInfoRow('Business phone', facility.businessPhone),
          HubInfoRow('City', a.city),
          HubInfoRow('Address', address),
          if (facility.description != null && facility.description!.trim().isNotEmpty) HubInfoRow('About', facility.description),
        ],
      ),
    );
  }
}

/// Edit the address fields and "About" in a sheet. The other details are shown locked, as on the web.
Future<void> showEditFacilityAddressSheet(BuildContext context, WidgetRef ref, Facility facility) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditAddressSheet(facility: facility),
  );
  if (saved == true) await ref.read(sessionControllerProvider.notifier).refresh();
}

class _EditAddressSheet extends ConsumerStatefulWidget {
  const _EditAddressSheet({required this.facility});

  final Facility facility;

  @override
  ConsumerState<_EditAddressSheet> createState() => _EditAddressSheetState();
}

class _EditAddressSheetState extends ConsumerState<_EditAddressSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _line1 = TextEditingController(text: widget.facility.address.line1);
  late final _area = TextEditingController(text: widget.facility.address.area);
  late final _city = TextEditingController(text: widget.facility.address.city);
  late final _state = TextEditingController(text: widget.facility.address.state);
  late final _pin = TextEditingController(text: widget.facility.address.pinCode);
  late final _about = TextEditingController(text: widget.facility.description ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_line1, _area, _city, _state, _pin, _about]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v, String what) => (v == null || v.trim().isEmpty) ? '$what is required.' : null;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileHubRepositoryProvider).updateFacilityAddress(
            widget.facility.id,
            line1: _line1.text,
            area: _area.text,
            city: _city.text,
            state: _state.text,
            pinCode: _pin.text,
            description: _about.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "We couldn't save your facility details. Please try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final f = widget.facility;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(color: t.surface0, borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg2),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit facility details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.textPrimary)),
                const SizedBox(height: 2),
                Text('You can update your address and description. The other details are fixed — contact GameAll support if they need to change.',
                    style: TextStyle(fontSize: 12.5, color: t.textSecondary, height: 1.4)),
                const SizedBox(height: AppSpacing.lg),
                _Locked('Facility name', f.name),
                _Locked('Facility type', f.type == FacilityType.other ? (f.customType ?? 'Other') : f.type.label),
                _Locked('Business contact number', f.businessPhone),
                _Locked('Business email', f.businessEmail),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(label: 'Address', controller: _line1, textInputAction: TextInputAction.next, validator: (v) => _required(v, 'Address')),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(label: 'Area / Locality', controller: _area, textInputAction: TextInputAction.next, validator: (v) => _required(v, 'Area')),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: AppTextField(label: 'City', controller: _city, textInputAction: TextInputAction.next, validator: (v) => _required(v, 'City'))),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: AppTextField(label: 'State', controller: _state, textInputAction: TextInputAction.next, validator: (v) => _required(v, 'State'))),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'PIN code',
                  controller: _pin,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) => RegExp(r'^\d{6}$').hasMatch(v?.trim() ?? '') ? null : 'PIN code must be exactly 6 digits.',
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(label: 'About your facility', controller: _about, maxLines: 3),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_error!, style: TextStyle(color: t.destructive, fontSize: 13)),
                ],
                const SizedBox(height: AppSpacing.xl),
                AuthGradientButton(label: 'Save changes', loadingLabel: 'Saving…', isLoading: _saving, onPressed: _save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: t.borderColor)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: t.textSecondary)),
                  Text(value.isEmpty ? '—' : value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.lock_outline_rounded, size: 16, color: t.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ── Courts & sports ────────────────────────────────────────────────────────

const _tileTints = [
  Color(0xFF10B981),
  Color(0xFF3B82F6),
  Color(0xFFF97316),
  Color(0xFF84CC16),
  Color(0xFF8B5CF6),
];

/// How many courts, how many are bookable, how many sports — and which sports.
class CourtsCard extends ConsumerWidget {
  const CourtsCard({super.key, required this.data});

  final FacilityData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final owner = isFacilityOwner(ref);
    return HubCard(
      title: 'Courts',
      trailing: owner ? HubAction(label: 'Manage', onTap: () => openSetupEditor(context, ref, AppRoutes.profileEditSports)) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _Count(icon: Icons.grid_view_rounded, color: t.success, value: data.totalCourts, label: 'Total Courts'),
                  VerticalDivider(width: 1, color: t.borderColor),
                  _Count(icon: Icons.check_circle_outline_rounded, color: t.electricBlue, value: data.activeCourts, label: 'Active Courts'),
                  VerticalDivider(width: 1, color: t.borderColor),
                  _Count(icon: Icons.emoji_events_outlined, color: t.violet, value: data.sports.length, label: 'Sports'),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Sports Available', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: t.textPrimary)),
          const SizedBox(height: AppSpacing.md),
          if (data.sports.isEmpty)
            Text('No sports configured yet.', style: TextStyle(color: t.textSecondary))
          else
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 420 ? 4 : 2;
              final w = (c.maxWidth - AppSpacing.md * (cols - 1)) / cols;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (var i = 0; i < data.sports.length; i++)
                    Container(
                      width: w,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: _tileTints[i % _tileTints.length].withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Column(
                        children: [
                          Text(data.iconOf(data.sports[i]), style: const TextStyle(fontSize: 30)),
                          const SizedBox(height: 6),
                          Text(data.nameOf(data.sports[i]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.textPrimary)),
                        ],
                      ),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.icon, required this.color, required this.value, required this.label});

  final IconData icon;
  final Color color;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Column(
          children: [
            IconBadge(icon: icon, color: color, size: 36),
            const SizedBox(height: 6),
            Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.textPrimary)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: t.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Every sport the facility offers, with the courts / turfs under it.
class SportsSection extends ConsumerWidget {
  const SportsSection({super.key, required this.data});

  final FacilityData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final owner = isFacilityOwner(ref);
    return HubCard(
      title: 'Sports',
      subtitle: 'Every sport you offer, and the courts or turfs under it.',
      trailing: owner ? HubAction(label: 'Edit sports', onTap: () => openSetupEditor(context, ref, AppRoutes.profileEditSports)) : null,
      child: data.sports.isEmpty
          ? Text('No sports configured yet.', style: TextStyle(color: t.textSecondary))
          : Column(
              children: [
                for (final fs in data.sports)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(border: Border.all(color: t.borderColor), borderRadius: BorderRadius.circular(AppRadius.md)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(data.iconOf(fs), style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(child: Text(data.nameOf(fs), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: t.textPrimary))),
                            Text(
                              '${data.areasOf(fs).length} ${data.areaLabelOf(fs).toLowerCase()}${data.areasOf(fs).length == 1 ? '' : 's'}',
                              style: TextStyle(fontSize: 12, color: t.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final a in data.areasOf(fs))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(AppRadius.pill)),
                                child: Text(a.name, style: TextStyle(fontSize: 12.5, color: t.textPrimary)),
                              ),
                            if (data.areasOf(fs).isEmpty) Text('None added', style: TextStyle(fontSize: 12, color: t.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ── Operating hours ────────────────────────────────────────────────────────

class TimingsSection extends ConsumerWidget {
  const TimingsSection({super.key, required this.data});

  final FacilityData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final owner = isFacilityOwner(ref);
    final groups = data.schedule == null ? <OperatingHoursGroup>[] : groupOperatingDays(data.schedule!.days);
    return HubCard(
      title: 'Court Timings',
      subtitle: 'When your facility is open.',
      trailing: owner ? HubAction(label: 'Edit timings', onTap: () => openSetupEditor(context, ref, AppRoutes.profileEditHours)) : null,
      child: groups.isEmpty
          ? Text("Operating hours aren't configured yet.", style: TextStyle(color: t.textSecondary))
          : Column(
              children: [
                for (var i = 0; i < groups.length; i++) ...[
                  if (i > 0) Divider(height: AppSpacing.lg, color: t.borderColor),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.schedule_rounded, size: 17, color: t.textSecondary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 5,
                        child: Text(groups[i].label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary)),
                      ),
                      Expanded(
                        flex: 6,
                        child: Text(groups[i].description, textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: t.textSecondary)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

/// The days a member may use a court by default.
class AccessDaysSection extends StatelessWidget {
  const AccessDaysSection({super.key, required this.facility});

  final Facility facility;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return HubCard(
      title: 'Membership Access Days',
      subtitle: 'The days a member may use a court by default.',
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < 7; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: facility.membershipAccessDays.contains(i) ? t.primary.withValues(alpha: 0.16) : t.surface2,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                names[i],
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: facility.membershipAccessDays.contains(i) ? t.primary : t.textSecondary,
                  decoration: facility.membershipAccessDays.contains(i) ? null : TextDecoration.lineThrough,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Pricing ────────────────────────────────────────────────────────────────

SummaryPeriod _period(PricingRule r) => SummaryPeriod(
      dayType: r.dayType,
      coversFullDay: r.coversFullDay,
      startTime: r.startTime,
      endTime: r.endTime,
      amountInr: r.amountMinor / 100,
    );

/// Every sport's rates exactly as saved: its default rate (if it has one), then each court with a rate of its own.
/// Courts on identical rates are shown once, and a sport priced entirely per court shows no default line.
class PricingSection extends ConsumerWidget {
  const PricingSection({super.key, required this.data});

  final FacilityData data;

  String _money(num inr) => hubMoney((inr * 100).round());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final owner = isFacilityOwner(ref);
    final rules = data.pricing?.rules ?? const <PricingRule>[];
    return HubCard(
      title: 'Pricing',
      subtitle: 'What a booking costs, by sport and court.',
      trailing: owner ? HubAction(label: 'Edit pricing', onTap: () => openSetupEditor(context, ref, AppRoutes.profileEditPricing)) : null,
      child: data.sports.isEmpty || rules.isEmpty
          ? Text("Pricing isn't configured yet.", style: TextStyle(color: t.textSecondary))
          : Column(
              children: [
                for (var i = 0; i < data.sports.length; i++) ...[
                  if (i > 0) Divider(height: AppSpacing.xl, color: t.borderColor),
                  _sport(context, data.sports[i], rules),
                ],
              ],
            ),
    );
  }

  Widget _sport(BuildContext context, FacilitySport fs, List<PricingRule> rules) {
    final t = context.tokens;
    final areas = data.areasOf(fs);
    final defaults = rules.where((r) => r.facilitySportId == fs.id && r.playingAreaId == null).map(_period).toList();
    final customized = [
      for (final a in areas)
        CustomizedArea(a.name, rules.where((r) => r.playingAreaId == a.id).map(_period).toList()),
    ].where((c) => c.periods.isNotEmpty).toList();
    final allCustomized = areas.isNotEmpty && customized.length == areas.length;
    final label = allCustomized ? 'Rate per court' : (defaults.isNotEmpty ? 'Default rate' : 'No default rate');
    final blocks = sportSummaryBlocks(defaults: defaults, customized: customized, areaCount: areas.length, areaLabel: data.areaLabelOf(fs));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(data.iconOf(fs), style: const TextStyle(fontSize: 18)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(data.nameOf(fs), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: t.textPrimary))),
            Text(label, style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (blocks.every((b) => b.periods.isEmpty))
          Text('Not set', style: TextStyle(fontSize: 13, color: t.textSecondary))
        else
          for (final b in blocks)
            if (b.periods.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: b.indented ? const EdgeInsets.only(left: AppSpacing.md) : EdgeInsets.zero,
                decoration: b.indented ? BoxDecoration(border: Border(left: BorderSide(color: t.primary.withValues(alpha: 0.4), width: 2))) : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (b.title != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(b.title!, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.textPrimary)),
                      ),
                    for (final p in b.periods)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(child: Text(periodLabel(p), style: TextStyle(fontSize: 13, color: t.textSecondary))),
                            Text('${_money(p.amountInr)} / hour', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.textPrimary)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ],
    );
  }
}
