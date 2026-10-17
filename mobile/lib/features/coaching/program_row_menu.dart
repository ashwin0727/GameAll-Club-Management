import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/repository_providers.dart';
import '../authentication/session_controller.dart';
import '../../shared/widgets/top_notice.dart';

/// Asks first, then deletes a program nobody has joined (the database refuses one with any enrollment).
/// Resolves true when it was deleted, so the caller can reload.
Future<bool> confirmAndDeleteProgram(BuildContext context, WidgetRef ref, {required String programId, required String name}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete program?'),
      content: Text('"$name" and its batches will be removed. This can\'t be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: ctx.tokens.destructive, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await ref.read(coachingRepositoryProvider).deleteProgram(programId);
    if (context.mounted) showTopNotice(context, 'Program deleted');
    return true;
  } on AppException catch (e) {
    if (context.mounted) showTopNotice(context, e.message, success: false);
    return false;
  }
}

enum _ProgramAction { details, enrollments, delete }

/// The ⋮ menu on a program row — View Details, View Enrollments and, only for a program nobody has joined (and
/// only for someone who may manage programs), a red Delete — the same three entries as the web's row menu.
class ProgramRowMenu extends ConsumerWidget {
  const ProgramRowMenu({
    super.key,
    required this.programId,
    required this.name,
    required this.studentCount,
    required this.onChanged,
    this.onOpen,
  });

  final String programId;
  final String name;
  final int studentCount;

  /// Called after the program was deleted, so the list can reload.
  final VoidCallback onChanged;

  /// Opens a route; defaults to `context.push`. A list that reloads on return passes its own.
  final Future<void> Function(String route)? onOpen;

  /// Delete is offered only when nobody has joined.
  static bool canDelete({required bool canManage, required int studentCount}) => canManage && studentCount == 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final canManage = ref.watch(sessionControllerProvider).can('COACHING_MANAGE_PROGRAMS');
    final showDelete = canDelete(canManage: canManage, studentCount: studentCount);

    Future<void> open(String route) async => onOpen != null ? onOpen!(route) : context.push(route);

    return PopupMenuButton<_ProgramAction>(
      tooltip: 'Program actions',
      icon: Icon(Icons.more_vert, color: t.textSecondary),
      padding: EdgeInsets.zero,
      onSelected: (a) async {
        switch (a) {
          case _ProgramAction.details:
            await open('${AppRoutes.coachingPrograms}/$programId');
          case _ProgramAction.enrollments:
            await open('${AppRoutes.coachingEnrollments}?programId=$programId');
          case _ProgramAction.delete:
            if (await confirmAndDeleteProgram(context, ref, programId: programId, name: name)) onChanged();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: _ProgramAction.details, child: Text('View Details')),
        const PopupMenuItem(value: _ProgramAction.enrollments, child: Text('View Enrollments')),
        if (showDelete)
          PopupMenuItem(
            value: _ProgramAction.delete,
            child: Row(children: [
              Icon(Icons.delete_outline, size: 20, color: t.destructive),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: t.destructive)),
            ]),
          ),
      ],
    );
  }
}
