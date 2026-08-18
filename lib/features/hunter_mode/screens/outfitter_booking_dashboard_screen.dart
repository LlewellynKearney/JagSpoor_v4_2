import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../models/booking_status.dart';
import '../models/package_pricing.dart';
import '../services/booking_calendar_service.dart';
import '../services/outfitter_enterprise_manager.dart';
import '../services/package_booking_manager.dart';
import '../services/user_role_resolver.dart';
import '../services/chat_and_filter_service.dart';

class OutfitterBookingDashboardScreen extends StatefulWidget {
  final ThemeController theme;

  const OutfitterBookingDashboardScreen({super.key, required this.theme});

  @override
  State<OutfitterBookingDashboardScreen> createState() =>
      _OutfitterBookingDashboardScreenState();
}

class _OutfitterBookingDashboardScreenState
    extends State<OutfitterBookingDashboardScreen>
    with SingleTickerProviderStateMixin {
  late Query _bookingQuery;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _buildBookingQuery();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _buildBookingQuery() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (UserRoleResolver.instance.isManager) {
      // Isolate logs purely to the manager's assigned concession property.
      // firestore.rules grants a farm manager read access to bookings on
      // their assigned farm via `isFarmManagerForBooking()` (a
      // `farm_managers/{uid}` get()-based check). A get()-based rule is not
      // directly queryable for list queries, so the manager's
      // `.where('farmId', isEqualTo: assignedFarmId)` list query relies on
      // Firestore evaluating the rule per-returned-document after the query
      // runs (the server still requires the query to be "safe"; if the
      // manager list query is rejected, the manager should instead resolve
      // the parent outfitter from farm_managers/{uid} and the bookings
      // should carry a `managerUids` array -- a future data migration).
      _bookingQuery = FirebaseFirestore.instance
          .collection('bookings')
          .where('farmId', isEqualTo: UserRoleResolver.instance.assignedFarmId);
    } else {
      // Outfitters pull records matching their corporate profile.
      // firestore.rules `isBookingOutfitter()` allows read when
      // `resource.data.outfitterId == request.auth.uid`, and this query
      // constrains `outfitterId` to `request.auth.uid`, so the list query
      // is queryable and the outfitter sees only their own bookings.
      _bookingQuery = FirebaseFirestore.instance
          .collection('bookings')
          .where('outfitterId', isEqualTo: currentUserId);
    }
    // Note: orderBy removed to avoid composite index requirement
    // Sorting is done in-memory in the StreamBuilder below
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: widget.theme.accentColor,
          unselectedLabelColor: widget.theme.subtitleColor,
          indicatorColor: widget.theme.accentColor,
          tabs: const [
            Tab(
              icon: Icon(Icons.pending_actions_rounded),
              text: 'Active Requests',
            ),
            Tab(
              icon: Icon(Icons.archive_rounded),
              text: 'Archived',
            ),
          ],
        ),
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

          // Sort bookings in-memory by timestamp (descending)
          final List docs = snapshot.data?.docs ?? [];
          docs.sort((a, b) {
            final aTime = a['bookingTimestamp'] ?? 0;
            final bTime = b['bookingTimestamp'] ?? 0;
            return bTime.compareTo(aTime);
          });

          // Split bookings into active requests (need outfitter action) and
          // archived (confirmed / completed / declined / cancelled).
          final activeBookings = <QueryDocumentSnapshot>[];
          final archivedBookings = <QueryDocumentSnapshot>[];
          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'] as String? ?? '';
            // Active: pending approval (needs approve/decline) or awaiting
            // payment (needs verify-payment-received). Includes the legacy
            // 'Approved' status which predates the payment-verification flow
            // (treat as awaiting payment so the outfitter can confirm it).
            if (status == BookingStatus.pendingApproval ||
                status == BookingStatus.approvedAwaitingPayment ||
                status == 'Approved') {
              activeBookings.add(doc);
            } else {
              archivedBookings.add(doc);
            }
          }

          return TabBarView(
            controller: _tabController,
            children: [
              _buildBookingList(activeBookings, isArchived: false),
              _buildBookingList(archivedBookings, isArchived: true),
            ],
          );
        },
      ),
    );
  }

  /// Renders a list of booking cards, or an empty-state placeholder.
  Widget _buildBookingList(
    List<QueryDocumentSnapshot> bookings, {
    required bool isArchived,
  }) {
    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isArchived
                  ? Icons.archive_rounded
                  : Icons.inbox_rounded,
              color: widget.theme.accentColor.withValues(alpha: 0.5),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              isArchived ? 'No archived bookings' : 'No active requests',
              style: TextStyle(
                color: widget.theme.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isArchived
                  ? 'Confirmed and completed bookings will appear here'
                  : 'New booking requests will appear here',
              style: TextStyle(color: widget.theme.subtitleColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 16, 16, SafeBottomInset.of(context)),
      itemCount: bookings.length + 1,
      itemBuilder: (context, index) {
        if (index == bookings.length) {
          return const CopyrightFooter();
        }
        final booking = bookings[index];
        final data = booking.data() as Map<String, dynamic>;
        return _BookingCard(
          bookingId: booking.id,
          data: data,
          theme: widget.theme,
        );
      },
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
  bool _isCustomItemsExpanded = false;
  bool _isChatExpanded = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  Future<void> _updateStatus(String newStatus) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // On approval, transition the booking to the Awaiting Payment state
      // (the outfitter accepts the request; the hunter must now pay directly
      // off-platform). Revenue is NOT yet realized.
      if (newStatus == BookingStatus.approvedAwaitingPayment ||
          newStatus == 'Approved') {
        await PackageBookingManager.instance
            .approveBookingAndRequestDeposit(bookingId: widget.bookingId);
      } else {
        await OutfitterEnterpriseManager.instance.updateBookingStatus(
          bookingId: widget.bookingId,
          newStatus: newStatus,
        );
      }

      if (mounted) {
        final isApprove = newStatus == BookingStatus.approvedAwaitingPayment ||
            newStatus == 'Approved';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isApprove
                  ? '✅ Booking approved! Awaiting hunter payment.'
                  : '❌ Booking declined',
            ),
            backgroundColor: isApprove ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
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

  /// Outfitter verifies that the direct (off-platform) payment has been
  /// received from the hunter. Shows a confirmation dialog first; on confirm,
  /// transitions the booking to `Confirmed` (realized revenue) and the booking
  /// moves to the Archived tab.
  Future<void> _confirmPaymentReceived() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify Payment Received'),
        content: const Text(
          'Confirm that payment has been received directly from the hunter?\n\n'
          'This will mark the booking as Confirmed and move it to the '
          'Archived tab.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('CONFIRM PAYMENT'),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      await PackageBookingManager.instance
          .confirmPaymentReceived(bookingId: widget.bookingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Payment verified! Booking confirmed.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }


  /// Resolves a pending hunter date-change request (approve / decline).
  Future<void> _resolveDateChange(bool approved) async {
    setState(() {
      _isProcessing = true;
    });
    try {
      await PackageBookingManager.instance.resolveDateChange(
        bookingId: widget.bookingId,
        approved: approved,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approved
                ? '✅ Date change approved — booking dates updated.'
                : '❌ Date change declined'),
            backgroundColor: approved ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
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

  /// Saves the finalized (Confirmed / Completed) booking's hunt dates, farm
  /// details, and package title to the outfitter's device calendar via
  /// [BookingCalendarService]. Surfaces a snackbar on success / "no dates"
  /// / failure so the outfitter always gets feedback.
  ///
  /// Delegates to [BookingCalendarService.instance.addToCalendar], which uses
  /// [BookingCalendarService.buildEventWithPackageFallback] -- so the hunt
  /// window is resolved the SAME way the hunter card resolves it
  /// ([BookingCalendarEventBuilder.resolveWindow] on the booking map), with a
  /// fallback to the linked package's `availabilityStart` / `availabilityEnd`
  /// when the booking document itself lacks date fields.
  Future<void> _addToCalendar() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final launched = await BookingCalendarService.instance.addToCalendar(
        // The doc `id` lives on the QueryDocumentSnapshot, not inside the
        // data map -- inject it so the calendar event description can
        // reference the Booking ID (buildDescription reads booking['id']).
        {...widget.data, 'id': widget.bookingId},
      );
      if (!mounted) return;
      final snackBar = SnackBar(
        content: Text(
          launched
              ? 'Opening your calendar to save this hunt...'
              : 'No hunt dates on file for this booking -- cannot add to calendar.',
        ),
        backgroundColor: launched ? Colors.green : Colors.orange,
      );
      if (messenger != null) messenger.showSnackBar(snackBar);
    } catch (e) {
      if (!mounted) return;
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Unable to add to calendar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case BookingStatus.pendingApproval:
        return Colors.orange;
      case BookingStatus.approvedAwaitingPayment:
        return Colors.amber.shade700;
      case 'Approved': // legacy -- treat like awaiting payment
        return Colors.amber.shade700;
      case BookingStatus.confirmed:
        return Colors.green;
      case BookingStatus.completed:
        return Colors.blue;
      case BookingStatus.declined:
        return Colors.red;
      case BookingStatus.cancelled:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Widget _buildCustomItemsSection() {
    final selectedItems =
        widget.data['selectedItemsList'] as List<dynamic>? ?? [];

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
                          color: widget.theme.accentColor.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: widget.theme.accentColor.withValues(
                                alpha: 0.2,
                              ),
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

  /// Unread-message envelope indicator for the outfitter booking card header.
  ///
  /// Driven by the booking's `outfitterHasUnread` flag (written by the chat
  /// flow when a hunter sends a message the outfitter hasn't seen). When the
  /// flag is true the `Icons.mail` icon is highlighted in orange; otherwise
  /// it stays muted grey. Identical layout to the hunter booking card.
  /// Tapping it opens the chat drawer.
  Widget _buildUnreadMailIndicator() {
    final hasUnread = (widget.data['outfitterHasUnread'] as bool?) ?? false;
    return InkWell(
      onTap: () => setState(() {
        _isChatExpanded = !_isChatExpanded;
      }),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(
          Icons.mail,
          color: hasUnread ? Colors.orange : Colors.grey,
          size: 24,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalPrice = (widget.data['totalHunterPriceRands'] ?? 0).toDouble();
    final status = widget.data['status'] ?? BookingStatus.pendingApproval;
    final packageId = widget.data['packageId'] ?? 'Unknown';
    final hunterId = widget.data['hunterId'] ?? 'Unknown';

    // Date-change request state.
    final dateChangePending =
        (widget.data['dateChangeRequestPending'] as bool?) ?? false;
    final dateChangeMap =
        widget.data['dateChangeRequest'] as Map<String, dynamic>?;
    final dateChange = dateChangeMap != null
        ? DateChangeRequest.fromMap(dateChangeMap)
        : null;

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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
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
                _buildUnreadMailIndicator(),
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
                        packageId.substring(
                              0,
                              packageId.length > 8 ? 8 : packageId.length,
                            ) +
                            '...',
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
                        hunterId.substring(
                              0,
                              hunterId.length > 8 ? 8 : hunterId.length,
                            ) +
                            '...',
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
              border: Border.all(
                color: widget.theme.accentColor.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              children: [
                _FinancialRow(
                  label: 'Total',
                  value:
                      'R ${totalPrice.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                  theme: widget.theme,
                  isTotal: true,
                ),
              ],
            ),
          ),

          // Date-change request banner + approve/decline actions.
          if (dateChange != null) ...[
            const SizedBox(height: 12),
            _buildDateChangeSection(dateChange, dateChangePending),
          ],

          // Hunt dates banner: surfaces the booking's hunt window
          // (start -> end) using the SAME resolver the hunter card uses
          // ([BookingCalendarEventBuilder.resolveWindow]) so the outfitter
          // sees the dates before tapping "ADD HUNT TO CALENDAR". Hidden
          // when the booking has no dates on file (and the calendar action's
          // package fallback will still try to resolve them on tap).
          _buildHuntDatesBanner(),

          const SizedBox(height: 16),

          // Action Buttons -- context-specific per booking status.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildActionButtons(status),
          ),

          // 💬 Chat & Negotiation Thread Panel
          _buildChatDrawer(),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Toggles the embedded chat drawer open/closed.
  void _toggleChatDrawer() {
    setState(() {
      _isChatExpanded = !_isChatExpanded;
    });
  }

  /// Builds the hunt-dates banner for the outfitter booking card.
  ///
  /// Surfaces the booking's hunt window (`Hunt dates: <start> → <end>`)
  /// using [BookingCalendarEventBuilder.resolveWindow] -- the SAME resolver
  /// the hunter card uses (and the SAME resolver
  /// [BookingCalendarService.addToCalendar] uses, via
  /// [BookingCalendarService.buildEventWithPackageFallback]) -- so the
  /// outfitter sees the exact dates that will be written to the device
  /// calendar before tapping "ADD HUNT TO CALENDAR". Returns
  /// [SizedBox.shrink] when the booking has no resolvable dates on file
  /// (the calendar action's package fallback will still attempt to resolve
  /// them on tap).
  Widget _buildHuntDatesBanner() {
    final window = BookingCalendarEventBuilder.resolveWindow(widget.data);
    if (window == null) return const SizedBox.shrink();
    // Single source of truth for the date-range label format —
    // `d MMM yyyy – d MMM yyyy` (or one date for a single-day hunt). Mirrors
    // the hunter booking banner exactly, so the outfitter sees the same
    // dates that will be written to the device calendar.
    final dateLabel =
        BookingCalendarEventBuilder.formatWindow(window) ??
            'No hunt dates on file';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.theme.accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: widget.theme.accentColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.event_rounded,
                color: widget.theme.accentColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Hunt dates: $dateLabel',
                style: TextStyle(
                  color: widget.theme.textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the context-specific action buttons for a booking card.
  ///
  /// - `Pending Approval`: DECLINE + APPROVE REQUEST (outfitter accepts the
  ///   hunter's request; the booking moves to `Awaiting Payment`).
  /// - `Awaiting Payment` (or legacy `Approved`): a prominent
  ///   VERIFY / CONFIRM PAYMENT RECEIVED button (outfitter confirms the
  ///   direct off-platform payment; the booking moves to `Confirmed` /
  ///   Archived) plus a Chat Hunter row.
  /// - Archived (Confirmed / Completed): ADD HUNT TO CALENDAR (save the
  ///   finalized hunt to the native device calendar). Declined / Cancelled
  ///   render no actions.
  Widget _buildActionButtons(String status) {
    final isPending = status == BookingStatus.pendingApproval;
    final isAwaitingPayment = status == BookingStatus.approvedAwaitingPayment ||
        status == 'Approved';

    if (isPending) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () => _updateStatus(BookingStatus.declined),
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
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.red,
                          ),
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
                  onPressed: _isProcessing
                      ? null
                      : () => _updateStatus(BookingStatus.approvedAwaitingPayment),
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
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_rounded),
                  label: const Text(
                    'APPROVE REQUEST',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildContactHunterRow(),
        ],
      );
    }

    if (isAwaitingPayment) {
      return Column(
        children: [
          // Prominent verify-payment button.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isProcessing ? null : _confirmPaymentReceived,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                disabledBackgroundColor: Colors.green.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified_rounded),
              label: const Text(
                'VERIFY / CONFIRM PAYMENT RECEIVED',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildContactHunterRow(),
        ],
      );
    }

    // Archived / completed / declined / cancelled: (for finalized Confirmed /
    // Completed bookings) save the hunt to the native device calendar.
    final canAddToCalendar = status == BookingStatus.confirmed ||
        status == BookingStatus.completed;
    return Column(
      children: [
        if (canAddToCalendar) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _addToCalendar,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.event_available_rounded, size: 20),
              label: const Text(
                'ADD HUNT TO CALENDAR',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// "Chat Hunter" action button row -- lets the outfitter communicate with
  /// the hunter regarding the off-platform payment via the in-app chat
  /// drawer (the embedded chat thread for this booking).
  Widget _buildContactHunterRow() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _toggleChatDrawer,
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.theme.accentColor,
              side: BorderSide(color: widget.theme.accentColor),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.chat_rounded),
            label: const Text(
              'CHAT',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  /// Date-change request section: shows the hunter's requested dates + reason
  /// and, when pending, presents approve / decline actions to the outfitter.
  Widget _buildDateChangeSection(
      DateChangeRequest request, bool pending) {
    final start = request.requestedStartDate;
    final end = request.requestedEndDate;
    final dateRange = (start != null || end != null)
        ? '${start != null ? "${start.day}/${start.month}/${start.year}" : "?"}'
            ' → '
            '${end != null ? "${end.day}/${end.month}/${end.year}" : "?"}'
        : 'No dates specified';

    final statusColor = request.status == 'approved'
        ? Colors.green
        : request.status == 'declined'
            ? Colors.red
            : Colors.orange;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_repeat_rounded,
                  color: statusColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'DATE CHANGE REQUEST',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  request.status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _dateChangeDetailRow('Requested dates', dateRange),
          if (request.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _dateChangeDetailRow('Reason', request.reason),
            ),
          if (pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () => _resolveDateChange(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('DECLINE',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () => _resolveDateChange(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text('APPROVE NEW DATES',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _dateChangeDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:  ',
          style: TextStyle(
            color: widget.theme.subtitleColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: widget.theme.textColor,
              fontSize: 12,
            ),
          ),
        ),
      ],
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
                      stream:
                          FirebaseFirestore.instance
                              .collection('bookings')
                              .doc(widget.bookingId)
                              .collection('chats')
                              .orderBy('timestamp', descending: false)
                              .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.green,
                            ),
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
                            final isMe =
                                senderId ==
                                FirebaseAuth.instance.currentUser?.uid;

                            return _ChatBubble(
                              text: msg['text'] as String? ?? '',
                              senderName:
                                  msg['senderName'] as String? ?? 'Unknown',
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
                            hintStyle: TextStyle(
                              color: widget.theme.subtitleColor,
                            ),
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
                          icon: const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                          ),
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
          color:
              isMe ? theme.accentColor.withValues(alpha: 0.2) : theme.cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color:
                isMe
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
            Text(text, style: TextStyle(color: theme.textColor, fontSize: 14)),
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
  final bool isTotal;

  const _FinancialRow({
    required this.label,
    required this.value,
    required this.theme,
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
            color:
                isTotal
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
