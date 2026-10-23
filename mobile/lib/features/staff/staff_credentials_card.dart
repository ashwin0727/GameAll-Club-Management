import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// A staff member's sign-in details: the generated @gameall.co login and (optionally) the default password. The
/// password stays hidden until the owner taps the eye; each value has its own copy button.
class StaffCredentialsCard extends StatefulWidget {
  const StaffCredentialsCard({super.key, required this.loginEmail, this.password});

  final String loginEmail;
  final String? password;

  @override
  State<StaffCredentialsCard> createState() => _StaffCredentialsCardState();
}

class _StaffCredentialsCardState extends State<StaffCredentialsCard> {
  bool _reveal = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CredentialRow(label: 'Login Email', value: widget.loginEmail),
        if (widget.password != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _CredentialRow(
            label: 'Password',
            value: widget.password!,
            secret: true,
            reveal: _reveal,
            onToggleReveal: () => setState(() => _reveal = !_reveal),
          ),
        ],
      ],
    );
  }
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({
    required this.label,
    required this.value,
    this.secret = false,
    this.reveal = false,
    this.onToggleReveal,
  });

  final String label;
  final String value;
  final bool secret;
  final bool reveal;
  final VoidCallback? onToggleReveal;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final shown = secret && !reveal ? '•' * (value.length.clamp(0, 14)) : value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption(context)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.only(left: AppSpacing.md, right: 4),
          decoration: BoxDecoration(
            color: tokens.surface1,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: tokens.borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: SelectableText(shown, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
              if (secret)
                IconButton(
                  tooltip: reveal ? 'Hide password' : 'Show password',
                  icon: Icon(reveal ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                  onPressed: onToggleReveal,
                ),
              IconButton(
                tooltip: 'Copy $label',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
