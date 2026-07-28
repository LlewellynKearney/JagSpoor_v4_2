import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../services/outfitter_enterprise_manager.dart';

class OutfitterBookingDashboardScreen extends StatelessWidget {
  final ThemeController theme;

  const OutfitterBookingDashboardScreen({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          '💳 Booking Requests',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('outfitterId', isEqualTo: currentUserId)
            .orderBy('bookingTimestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.green),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading bookings',
                    style: TextStyle(color: theme.textColor),
                  ),
                ],
              ),
            );
          }

          final bookings = snapshot.data?.docs ?? [];

          if (bookings.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inbox_rounded,
                    color: theme.accentColor.withValues(alpha: 0.5),
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No booking requests',
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Booking requests will appear here',
                    style: TextStyle(color: theme.subtitleColor),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length,
            itemBuilder: (context, index) {
              final booking = bookings[index];
              final data = booking.data() as Map<String, dynamic>;
              return _BookingCard(
                bookingId: booking.id,
                data: data,
                theme: theme,
              );
            },
          );
        },
      ),
    );
  }
}

class _BookingCard extends StatefulWidget {
  final String bookingId;
  final Map<String, dynamic> data;
  final ThemeController theme;

  const _BookingCard({
    required this.bookingId,
    required this.data,
    required this.theme,
  });

  @override
  State<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<_BookingCard> {
  bool _isProcessing = false;

  Future<void> _updateStatus(String newStatus) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await OutfitterEnterpriseManager.instance.updateBookingStatus(
        bookingId: widget.bookingId,
        newStatus: newStatus,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'Approved'
                  ? '✅ Booking approved!'
                  : '❌ Booking declined',
            ),
            backgroundColor: newStatus == 'Approved' ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending Approval':
        return Colors.orange;
      case 'Approved':
        return Colors.green;
      case 'Declined':
        return Colors.red;
      case 'Completed':
        return Colors.blue;
      case 'Cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final basePrice = (widget.data['basePriceRands'] ?? 0).toDouble();
    final commission = (widget.data['platformCommissionRands'] ?? 0).toDouble();
    final totalPrice = (widget.data['totalHunterPriceRands'] ?? 0).toDouble();
    final status = widget.data['status'] ?? 'Pending Approval';
    final packageId = widget.data['packageId'] ?? 'Unknown';
    final hunterId = widget.data['hunterId'] ?? 'Unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: widget.theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getStatusColor(status).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.book_online_rounded,
                    color: _getStatusColor(status),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Booking Request',
                        style: TextStyle(
                          color: widget.theme.textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Package Info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_rounded,
                      color: widget.theme.subtitleColor,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Package ID: ',
                      style: TextStyle(
                        color: widget.theme.subtitleColor,
                        fontSize: 13,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        packageId.substring(0, packageId.length > 8 ? 8 : packageId.length) + '...',
                        style: TextStyle(
                          color: widget.theme.textColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.person_rounded,
                      color: widget.theme.subtitleColor,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Hunter ID: ',
                      style: TextStyle(
                        color: widget.theme.subtitleColor,
                        fontSize: 13,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        hunterId.substring(0, hunterId.length > 8 ? 8 : hunterId.length) + '...',
                        style: TextStyle(
                          color: widget.theme.textColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Financial Breakdown
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.theme.backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.theme.accentColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                _FinancialRow(
                  label: 'Base Package Rate',
                  value: 'R ${basePrice.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                  theme: widget.theme,
                ),
                const Divider(height: 16),
                _FinancialRow(
                  label: '5% Platform Admin Fee',
                  value: 'R ${commission.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                  theme: widget.theme,
                  isFee: true,
                ),
                const Divider(height: 16),
                _FinancialRow(
                  label: 'Total Cost',
                  value: 'R ${totalPrice.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                  theme: widget.theme,
                  isTotal: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Action Buttons (only for Pending Approval)
          if (status == 'Pending Approval')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : () => _updateStatus('Declined'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                            )
                          : const Icon(Icons.close_rounded),
                      label: const Text(
                        'DECLINE',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : () => _updateStatus('Approved'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_rounded),
                      label: const Text(
                        'APPROVE',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _FinancialRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeController theme;
  final bool isFee;
  final bool isTotal;

  const _FinancialRow({
    required this.label,
    required this.value,
    required this.theme,
    this.isFee = false,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isTotal ? theme.textColor : theme.subtitleColor,
            fontSize: isTotal ? 14 : 13,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isFee
                ? Colors.amber.shade700
                : isTotal
                    ? Colors.green
                    : theme.textColor,
            fontSize: isTotal ? 18 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
