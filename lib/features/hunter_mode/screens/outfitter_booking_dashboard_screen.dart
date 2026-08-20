import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../models/booking_status.dart';
import '../models/package_pricing.dart';
import '../services/booking_category_classifier.dart';
import '../services/booking_date_formatter.dart';
import '../services/outfitter_enterprise_manager.dart';
import '../services/package_booking_manager.dart';
import '../services/user_role_resolver.dart';
import '../widgets/hunter_contact_card.dart';
import '../../outfitter_mode/widgets/outfitter_scaffold.dart';

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

  /// The active category filter for the request lists. `null` shows every
  /// booking; otherwise only bookings of that category are listed.
  BookingCategory? _categoryFilter;

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
      resizeToAvoidBottomInset: true,
      backgroundColor: widget.theme.backgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          UserRoleResolver.instance.isManager
              ? '💳 Farm Booking Requests'
              : '💳 Booking Requests',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: OutfitterUi.titleColor(widget.theme),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: OutfitterUi.titleColor(widget.theme),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: widget.theme.isDarkMode
              ? widget.theme.accentColor
              : OutfitterUi.lightTitle,
          unselectedLabelColor: OutfitterUi.subtitleColor(widget.theme),
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
      body: OutfitterBushveldBackground.stack(
        fallbackColor: widget.theme.backgroundColor,
        child: SafeArea(
          child: StreamBuilder(
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

          // Apply the category filter (standard / custom / trophy) selected
          // via the filter chips below the AppBar. `null` = show all.
          bool matchesCategory(QueryDocumentSnapshot doc) {
            final filter = _categoryFilter;
            if (filter == null) return true;
            final data = doc.data() as Map<String, dynamic>;
            return BookingCategoryClassifier.classify(data) == filter;
          }

          final filteredActive =
              activeBookings.where(matchesCategory).toList();
          final filteredArchived =
              archivedBookings.where(matchesCategory).toList();

          return Column(
            children: [
              // Clear the transparent full-bleed AppBar + TabBar (the
              // SafeArea above only accounts for the status bar) so the
              // category filter chips render cleanly below them.
              const SizedBox(height: kToolbarHeight + kTextTabBarHeight),
              _buildCategoryFilterBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildBookingList(filteredActive, isArchived: false),
                    _buildBookingList(filteredArchived, isArchived: true),
                  ],
                ),
              ),
            ],
          );
        },
          ),
        ),
      ),
    );
  }

  /// The three category filter buttons shown under the AppBar (plus an "All"
  /// reset chip). Selecting a chip filters both the Active Requests and
  /// Archived lists to that booking category.
  Widget _buildCategoryFilterBar() {
    final theme = widget.theme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: OutfitterUi.cardColor(theme),
        border: Border(
          bottom: BorderSide(color: OutfitterUi.cardBorderColor(theme)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _categoryChip(
              theme,
              label: 'All',
              icon: Icons.apps_rounded,
              selected: _categoryFilter == null,
              onSelected: () => setState(() => _categoryFilter = null),
            ),
            const SizedBox(width: 8),
            _categoryChip(
              theme,
              label: 'Standard Hunting Packages',
              icon: Icons.inventory_2_rounded,
              selected: _categoryFilter == BookingCategory.standard,
              onSelected: () =>
                  setState(() => _categoryFilter = BookingCategory.standard),
            ),
            const SizedBox(width: 8),
            _categoryChip(
              theme,
              label: 'Custom Hunting Packages',
              icon: Icons.tune_rounded,
              selected: _categoryFilter == BookingCategory.custom,
              onSelected: () =>
                  setState(() => _categoryFilter = BookingCategory.custom),
            ),
            const SizedBox(width: 8),
            _categoryChip(
              theme,
              label: 'Trophy Hunt Requests',
              icon: Icons.emoji_events_rounded,
              selected: _categoryFilter == BookingCategory.trophy,
              onSelected: () =>
                  setState(() => _categoryFilter = BookingCategory.trophy),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(
    ThemeController theme, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return FilterChip(
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : theme.accentColor,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? Colors.white : OutfitterUi.subtitleColor(theme),
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
      backgroundColor: OutfitterUi.cardColor(theme),
      selectedColor: theme.accentColor,
      side: BorderSide(
        color: selected
            ? theme.accentColor
            : OutfitterUi.cardBorderColor(theme),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  /// Renders a list of booking cards, or an empty-state placeholder.
  Widget _buildBookingList(
    List<QueryDocumentSnapshot> bookings, {
    required bool isArchived,
  }) {
    if (bookings.isEmpty) {
      final filterLabel = switch (_categoryFilter) {
        BookingCategory.standard => 'standard hunting package',
        BookingCategory.custom => 'custom hunting package',
        BookingCategory.trophy => 'trophy hunt',
        null => null,
      };
      final suffix = filterLabel != null ? ' $filterLabel' : '';
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
              isArchived
                  ? 'No archived$suffix bookings'
                  : 'No active$suffix requests',
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
              style: TextStyle(color: OutfitterUi.subtitleColor(widget.theme)),
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
  // Cached resolved display names for the card's Package / Hunter rows. The
  // booking document carries only the `packageId` + `hunterId` (opaque ids);
  // the full names are resolved async from `packages/{packageId}` +
  // `users/{hunterId}` once per card lifetime and cached so a stream re-emit
  // doesn't re-trigger the lookups.
  String _packageNameDisplay = '';
  String _hunterNameDisplay = '';
  bool _isResolvingNames = false;

  @override
  void initState() {
    super.initState();
    _resolveDisplayNames();
  }

  @override
  void didUpdateWidget(covariant _BookingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-resolve the display names when the underlying booking document id or
    // the packageId/hunterId changes (e.g. the card is recycled for a new
    // booking by the ListView builder).
    if (oldWidget.data['packageId'] != widget.data['packageId'] ||
        oldWidget.data['hunterId'] != widget.data['hunterId']) {
      _resolveDisplayNames();
    }
  }

  /// Resolves the full package name + hunter name for the card from the
  /// referenced `packages/{packageId}` + `users/{hunterId}` documents.
  ///
  /// The booking document stores only `packageName` (an optional snapshot
  /// written at booking time) + `packageId` + `hunterId`. To show a
  /// human-readable package title + hunter name on the card we resolve them
  /// from the referenced documents (best-effort: a missing doc or a fetch
  /// failure falls back to the booking-doc snapshot / the opaque id so the
  /// card never renders an empty row).
  Future<void> _resolveDisplayNames() async {
    if (_isResolvingNames) return;
    setState(() => _isResolvingNames = true);
    String packageName =
        (widget.data['packageName'] as String?)?.trim() ?? '';
    String hunterName = (widget.data['hunterName'] as String?)?.trim() ?? '';

    final packageId = (widget.data['packageId'] as String?)?.trim() ?? '';
    final hunterId = (widget.data['hunterId'] as String?)?.trim() ?? '';

    String? resolvedPackage;
    String? resolvedHunter;
    // Package title: prefer the booking-doc snapshot, else resolve from
    // the package doc (custom-built bookings carry the 'CUSTOM_BUILT'
    // sentinel, which has no package doc -- the snapshot is used).
    if (packageName.isEmpty &&
        packageId.isNotEmpty &&
        packageId != 'CUSTOM_BUILT') {
      try {
        final pkgSnap = await FirebaseFirestore.instance
            .collection('packages')
            .doc(packageId)
            .get();
        if (pkgSnap.exists) {
          final pkgData = pkgSnap.data() ?? const <String, dynamic>{};
          final resolved = (pkgData['title'] as String?)?.trim() ?? '';
          if (resolved.isNotEmpty) resolvedPackage = resolved;
        }
      } catch (_) {
        // Offline / permissions -- fall back to the snapshot / id below.
      }
    }

    // Hunter name: prefer the booking-doc snapshot, else resolve from the
    // user profile (`users/{hunterId}` carries `fullName` / `name`).
    if (hunterName.isEmpty && hunterId.isNotEmpty) {
      try {
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(hunterId)
            .get();
        if (userSnap.exists) {
          final userData = userSnap.data() ?? const <String, dynamic>{};
          final resolved = (userData['fullName'] as String?)?.trim() ??
              (userData['name'] as String?)?.trim() ??
              '';
          if (resolved.isNotEmpty) resolvedHunter = resolved;
        }
      } catch (_) {
        // Offline / permissions -- fall back to the opaque id below.
      }
    }

    if (resolvedPackage != null) packageName = resolvedPackage;
    if (resolvedHunter != null) hunterName = resolvedHunter;
    if (!mounted) {
      _isResolvingNames = false;
      return;
    }
    setState(() {
      _packageNameDisplay = packageName.isNotEmpty
          ? packageName
          : (packageId.isNotEmpty ? packageId : 'Unknown package');
      _hunterNameDisplay = hunterName.isNotEmpty
          ? hunterName
          : (hunterId.isNotEmpty ? hunterId : 'Unknown hunter');
      _isResolvingNames = false;
    });
  }

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
                            color: OutfitterUi.subtitleColor(widget.theme),
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

  @override
  Widget build(BuildContext context) {
    final totalPrice = (widget.data['totalHunterPriceRands'] ?? 0).toDouble();
    final status = widget.data['status'] ?? BookingStatus.pendingApproval;
    final packageId = widget.data['packageId'] ?? 'Unknown';

    // Resolved display values (populated async by [_resolveDisplayNames] in
    // initState). Fall back to the opaque ids while the lookup is in flight
    // so the card never renders an empty Package / Hunter row on first paint.
    final packageNameDisplay = _packageNameDisplay.isNotEmpty
        ? _packageNameDisplay
        : (packageId == 'CUSTOM_BUILT' ? 'Custom Package' : packageId);
    final hunterNameDisplay = _hunterNameDisplay.isNotEmpty
        ? _hunterNameDisplay
        : (widget.data['hunterId'] as String? ?? 'Unknown');

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
        color: OutfitterUi.cardColor(widget.theme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.theme.isDarkMode
              ? _getStatusColor(status).withValues(alpha: 0.3)
              : OutfitterUi.cardBorderColor(widget.theme),
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
                      color: OutfitterUi.subtitleColor(widget.theme),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Package: ',
                      style: TextStyle(
                        color: OutfitterUi.subtitleColor(widget.theme),
                        fontSize: 13,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        packageNameDisplay,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.theme.textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
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
                      color: OutfitterUi.subtitleColor(widget.theme),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Hunter: ',
                      style: TextStyle(
                        color: OutfitterUi.subtitleColor(widget.theme),
                        fontSize: 13,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        hunterNameDisplay,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.theme.textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
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
          // (start -> end) so the outfitter sees the dates on the card.
          // Hidden when the booking has no dates on file.
          _buildHuntDatesBanner(),

          const SizedBox(height: 16),

          // Action Buttons -- context-specific per booking status.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildActionButtons(status),
          ),

          // 📞 Hunter contact card: surfaces the hunter's name / surname +
          // tappable phone (tel:) + tappable email (mailto:) so the outfitter
          // can reach the hunter directly to coordinate the off-platform
          // payment. Renders a loading state + graceful "not available"
          // fallback.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: HunterContactCard(
              source: widget.data,
              theme: widget.theme,
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Builds the hunt-dates banner for the outfitter booking card.
  ///
  /// Surfaces the booking's hunt window (`Hunt dates: <start> – <end>`) using
  /// [BookingDateFormatter.resolveWindow] — the SAME resolver the hunter card
  /// uses — so the outfitter sees the same dates the hunter sees. Returns
  /// [SizedBox.shrink] when the booking has no resolvable dates on file.
  Widget _buildHuntDatesBanner() {
    final window = BookingDateFormatter.resolveWindow(widget.data);
    if (window == null) return const SizedBox.shrink();
    // Single source of truth for the date-range label format —
    // `d MMM yyyy – d MMM yyyy` (or one date for a single-day hunt). Mirrors
    // the hunter booking banner exactly.
    final dateLabel =
        BookingDateFormatter.formatWindow(window) ??
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
  ///   Archived).
  /// - Archived (Confirmed / Completed / Declined / Cancelled): no action
  ///   buttons (the hunter contact card below the action row remains
  ///   available for any finalized booking).
  Widget _buildActionButtons(String status) {
    final isPending = status == BookingStatus.pendingApproval;
    final isAwaitingPayment = status == BookingStatus.approvedAwaitingPayment ||
        status == 'Approved';

    if (isPending) {
      return Row(
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
      );
    }

    if (isAwaitingPayment) {
      return SizedBox(
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
      );
    }

    // Archived / completed / declined / cancelled: no action buttons (the
    // hunter contact card below the action row remains available).
    return const SizedBox.shrink();
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
            color: OutfitterUi.subtitleColor(widget.theme),
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
            color: isTotal ? theme.textColor : OutfitterUi.subtitleColor(theme),
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
