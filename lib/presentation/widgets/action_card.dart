import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/action_item_model.dart';
import '../../core/app_theme.dart';

class ActionCard extends StatelessWidget {
  final ActionItemModel action;
  final VoidCallback onDismiss;

  const ActionCard({super.key, required this.action, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final isBlocker = action.severity == ActionSeverity.blocker;
    final bgColor = isBlocker ? const Color(0xFFFEF2F2) : const Color(0xFFFFF7ED);
    final borderColor = isBlocker
        ? const Color(0xFFFECACA)
        : const Color(0xFFFED7AA);
    final iconColor = isBlocker
        ? const Color(0xFFEF4444)
        : const Color(0xFFF97316);
    final iconData = isBlocker ? Icons.warning_rounded : Icons.schedule;

    return Dismissible(
      key: Key(action.id),
      onDismissed: (_) => onDismiss(),
      background: Container(
        color: Colors.grey[200],
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.check, color: Colors.grey),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor.withOpacity(0.5)),
              ),
              child: Icon(iconData, color: iconColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.title,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    action.subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {
                  // Map journal_pending_approval / journal-approval routes to Journals page
                  if (action.type == ActionType.journal_pending_approval || action.route.contains('journal-approval')) {
                    context.go('/journals', extra: action.argumentId ?? action.referenceId);
                  } else if (action.route.contains('rider-approval')) {
                    context.go(
                      action.route,
                      extra: {
                        'requestId': action.referenceId,
                        'actionItemId': action.id,
                      },
                    );
                  } else {
                    context.go(action.route, extra: action.argumentId);
                  }
                },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                "Resolve",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
