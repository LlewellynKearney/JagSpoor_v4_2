import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../services/outfitter_enterprise_manager.dart';
import '../services/outfitter_invoice_exporter.dart';
import '../services/user_role_resolver.dart';
import '../services/chat_and_filter_service.dart';

class OutfitterBookingDashboardScreen extends StatefulWidget {
  final ThemeController theme;

  const OutfitterBookingDashboardScreen({super.key, required this.theme});

  @override
  State<OutfitterBookingDashboardScreen> createState() => _OutfitterBookingDashboardScreenState();
}

class _OutfitterBookingDashboardScreenState extends State<OutfitterBookingDashboardScreen> {
  late Query _bookingQuery;

  @override
  void initState() {
    super.initState();
    _buildBookingQuery();
  }

  void _buildBookingQuery() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (UserRoleResolver.instance.isManager) {
      // Isolate logs purely to the manager's assigned concession property
      _bookingQuery = FirebaseFirestore.instance
          .collection('bookings')
          .where('farmId', isEqualTo: UserRoleResolver.instance.assignedFarmId);
    } else {
      // Outfitters pull records matching their corporate profile
      _bookingQuery = FirebaseFirestore.instance
          .collection('bookings')
          .where('outfitterId', isEqualTo: currentUserId);
    }
    _bookingQuery = _bookingQuery.orderBy('bookingTimestamp', descending: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          UserRoleResolver.instance.isManager 
              ? '💳 Farm Booking Requests'
              : '💳 Booking Requests',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: widget.theme.backgroundColor,
        foregroundColor: widget.theme.textColor,
        elevation: 0,
      ),
      body: StreamBuilder(
        stream: _bookingQuery.snapshots(),
        builder: (context, AsyncSnapshot snapshot) {
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
                    style: TextStyle(color: widget.theme.textColor),
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
                    color: widget.theme.accentColor.withValues(alpha: 0.5),
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No booking requests',
                    style: TextStyle(
                      color: widget.theme.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Booking requests will appear here',
                    style: TextStyle(color: widget.theme.subtitleColor),
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
                theme: widget.theme,
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
  bool _isExporting = false;
  bool _isCustomItemsExpanded = false;
  bool _isChatExpanded = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

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

  Future<void> _exportInvoice() async {
    setState(() {
      _isExporting = true;
    });

    try {
      final packageName = widget.data['packageName'] as String? ?? 'Hunting Package';
      final farmName = widget.data['farmName'] as String? ?? 'Outfitter Farm';
      final hunterName = widget.data['hunterName'] as String? ?? 'Hunter';
      final basePrice = (widget.data['basePriceRands'] ?? 0).toDouble();
      final commission = (widget.data['platformCommissionRands'] ?? 0).toDouble();
      final totalPrice = (widget.data['totalHunterPriceRands'] ?? 0).toDouble();

      await OutfitterInvoiceExporter().generateAndShareInvoice(
        bookingId: widget.bookingId,
        packageName: packageName,
        farmName: farmName,
        hunterName: hunterName,
        basePrice: basePrice,
        platformFee: commission,
        totalPrice: totalPrice,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Invoice exported and shared!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
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

  Widget _buildCustomItemsSection() {
    final selectedItems = widget.data['selectedItemsList'] as List<dynamic>? ?? [];
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: widget.theme.accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.theme.accentColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // Expandable Header
          InkWell(
            onTap: () {
              setState(() {
                _isCustomItemsExpanded = !_isCustomItemsExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.theme.accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.list_alt_rounded,
                      color: widget.theme.accentColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CUSTOM BUILT PACKAGE',
                          style: TextStyle(
                            color: widget.theme.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${selectedItems.length} item${selectedItems.length != 1 ? 's' : ''} selected',
                          style: TextStyle(
                            color: widget.theme.subtitleColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isCustomItemsExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: widget.theme.accentColor,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),

          // Expandable Content
          if (_isCustomItemsExpanded && selectedItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  ...selectedItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value as Map<String, dynamic>;
                    final itemName = item['name'] ?? 'Unknown Item';
                    final hunterPrice = (item['hunterPrice'] ?? 0.0).toDouble();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: widget.theme.backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: widget.theme.accentColor.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: widget.theme.accentColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: widget.theme.accentColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              itemName,
                              style: TextStyle(
                                color: widget.theme.textColor,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            'R ${hunterPrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
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

          // CUSTOM_BUILT Expandable Container
          if (packageId == 'CUSTOM_BUILT') ...[
            _buildCustomItemsSection(),
            const SizedBox(height: 8),
          ],

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

          // Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: status == 'Pending Approval'
                ? Row(
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
                  )
                : status == 'Approved'
                    ? SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isExporting ? null : _exportInvoice,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: _isExporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.picture_as_pdf_rounded),
                          label: const Text(
                            'EXPORT INVOICE',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
          ),

          // 💬 Chat & Negotiation Thread Panel
          _buildChatDrawer(),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildChatDrawer() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: widget.theme.accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.theme.accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // Expandable Header
          InkWell(
            onTap: () {
              setState(() {
                _isChatExpanded = !_isChatExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.theme.accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.chat_rounded,
                      color: widget.theme.accentColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '💬 Open Chat & Negotiation Thread',
                      style: TextStyle(
                        color: widget.theme.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    _isChatExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: widget.theme.accentColor,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),

          // Expandable Chat Content
          if (_isChatExpanded)
            Container(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Chat Messages Stream
                  SizedBox(
                    height: 200,
                    child: StreamBuilder(
                      stream: FirebaseFirestore.instance
                          .collection('bookings')
                          .doc(widget.bookingId)
                          .collection('chats')
                          .orderBy('timestamp', descending: false)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: Colors.green),
                          );
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Error loading chat',
                              style: TextStyle(color: Colors.red),
                            ),
                          );
                        }

                        final messages = snapshot.data?.docs ?? [];
                        if (messages.isEmpty) {
                          return Center(
                            child: Text(
                              'No messages yet',
                              style: TextStyle(
                                color: widget.theme.subtitleColor,
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: _chatScrollController,
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index].data();
                            final senderId = msg['senderId'] as String? ?? '';
                            final isMe = senderId == FirebaseAuth.instance.currentUser?.uid;

                            return _ChatBubble(
                              text: msg['text'] as String? ?? '',
                              senderName: msg['senderName'] as String? ?? 'Unknown',
                              isMe: isMe,
                              theme: widget.theme,
                            );
                          },
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Chat Input Row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          style: TextStyle(color: widget.theme.textColor),
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(color: widget.theme.subtitleColor),
                            filled: true,
                            fillColor: widget.theme.backgroundColor,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: widget.theme.accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send_rounded, color: Colors.white),
                          onPressed: _sendChatMessage,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _sendChatMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    try {
      await ChatAndFilterService.instance.sendChatMessage(
        bookingId: widget.bookingId,
        messageText: text,
        senderName: FirebaseAuth.instance.currentUser?.displayName ?? 'User',
      );
      _chatController.clear();
      // Scroll to bottom after sending
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final String senderName;
  final bool isMe;
  final ThemeController theme;

  const _ChatBubble({
    required this.text,
    required this.senderName,
    required this.isMe,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? theme.accentColor.withValues(alpha: 0.2)
              : theme.cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color: isMe
                ? theme.accentColor.withValues(alpha: 0.3)
                : theme.accentColor.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                senderName,
                style: TextStyle(
                  color: theme.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              text,
              style: TextStyle(
                color: theme.textColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
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
