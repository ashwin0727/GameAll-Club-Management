import 'package:flutter/material.dart';

import '../../shared/widgets/states.dart';

/// Coaching → Manage Students — placeholder for the new dedicated coaching-students workspace
/// (the roster of students across every program, independent of the per-program Enrollments
/// list). Not built yet; this just gives "Manage Students" a real destination instead of a dead
/// link. Mirrors src/features/coaching/components/students-page.tsx.
class CoachingStudentsScreen extends StatelessWidget {
  const CoachingStudentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Students')),
      body: const SafeArea(
        child: EmptyStateView(
          icon: Icons.groups_outlined,
          title: 'Coming soon',
          message:
              "This section is being built. In the meantime, manage students from each program's Enrollments tab.",
        ),
      ),
    );
  }
}
