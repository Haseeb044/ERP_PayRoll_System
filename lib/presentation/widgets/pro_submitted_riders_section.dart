import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/rider_request_model.dart';
import 'package:intl/intl.dart';

class ProSubmittedRidersSection extends StatefulWidget {
  const ProSubmittedRidersSection({super.key});

  @override
  State<ProSubmittedRidersSection> createState() => _ProSubmittedRidersSectionState();
}

class _ProSubmittedRidersSectionState extends State<ProSubmittedRidersSection> {
  List<RiderRequestModel> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final data = await supabase
          .from('rider_requests')
          .select()
          .eq('submitted_by', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _requests = (data as List<dynamic>?)
                  ?.map((e) => RiderRequestModel.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_requests.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "My Submitted Riders",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _requests.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final req = _requests[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: req.statusColor.withOpacity(0.1),
                      child: Icon(
                        _getStatusIcon(req.status),
                        color: req.statusColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            req.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            "ID: ${req.riderCode ?? 'N/A'} • Submitted ${DateFormat('MMM d, h:mm a').format(req.createdAt)}",
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: req.statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        req.statusDisplay,
                        style: TextStyle(
                          color: req.statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(RiderRequestStatus status) {
    switch (status) {
      case RiderRequestStatus.pending:
        return Icons.hourglass_empty;
      case RiderRequestStatus.approved:
        return Icons.check_circle;
      case RiderRequestStatus.rejected:
        return Icons.cancel;
    }
  }
}
