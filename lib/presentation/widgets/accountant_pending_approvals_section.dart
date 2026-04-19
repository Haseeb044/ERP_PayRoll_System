import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../logic/actions/action_bloc.dart';
import '../../data/models/action_item_model.dart';

class AccountantPendingApprovalsSection extends StatelessWidget {
  const AccountantPendingApprovalsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ActionBloc, ActionState>(
      builder: (context, state) {
        if (state is ActionLoading) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (state is ActionLoaded) {
          final pendingRiders = state.actions
              .where((a) =>
                  a.type == ActionType.rider_pending_approval &&
                  a.resolvedAt == null &&
                  a.responsibleRole == 'accountant')
              .toList();

          final pendingJournals = state.actions
              .where((a) =>
                  a.type == ActionType.journal_pending_approval &&
                  a.resolvedAt == null &&
                  a.responsibleRole == 'accountant')
              .toList();

          if (pendingRiders.isEmpty && pendingJournals.isEmpty) {
            return const SizedBox.shrink();
          }

          return Column(
            children: [
              if (pendingRiders.isNotEmpty)
                _buildSection(
                  context,
                  title: "Pending Rider Approvals",
                  items: pendingRiders,
                  icon: Icons.person_add,
                  color: Colors.orange,
                ),
              if (pendingJournals.isNotEmpty)
                _buildSection(
                  context,
                  title: "Pending Expenses",
                  items: pendingJournals,
                  icon: Icons.receipt_long,
                  color: Colors.blue,
                ),
            ],
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<ActionItemModel> items,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                "${items.length} Pending",
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final action = items[index];
              final createdAt = action.createdAt ?? DateTime.now();

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: color.withValues(alpha: 0.2)),
                ),
                color: color.withValues(alpha: 0.05),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.2),
                    child: Icon(icon, color: color),
                  ),
                  title: Text(
                    action.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    "Submitted ${DateFormat('MMM d, h:mm a').format(createdAt)}",
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async {
                    if (action.type == ActionType.rider_pending_approval) {
                      await context.push(
                        '/accountant-dashboard/rider-approval',
                        extra: {
                          'requestId': action.referenceId,
                          'actionItemId': action.id,
                        },
                      );
                    } else if (action.type == ActionType.journal_pending_approval) {
                       // Navigate to Journals page and highlight the related expense
                       await context.push(
                        '/journals',
                        extra: action.argumentId ?? action.referenceId,
                      );
                    }
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
