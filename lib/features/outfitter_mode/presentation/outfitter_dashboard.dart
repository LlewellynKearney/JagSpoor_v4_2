import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../data/models/client_booking.dart';
import '../data/models/fleet_asset.dart';
import '../data/models/lodging_unit.dart';
import '../data/services/outfitter_firebase_service.dart';

class OutfitterDashboard extends StatefulWidget {
  const OutfitterDashboard({super.key});

  @override
  State<OutfitterDashboard> createState() => _OutfitterDashboardState();
}

class _OutfitterDashboardState extends State<OutfitterDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ThemeController _theme = ThemeController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _theme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _ClientCalendarsTab(),
                  _LodgingManagerTab(),
                  _FleetTrackerTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _theme.cardColor,
        border: Border(
          bottom: BorderSide(color: _theme.accentColor.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.dashboard_outlined, color: _theme.accentColor, size: 28),
          const SizedBox(width: 12),
          Text(
            'OUTFITTER COMMAND',
            style: TextStyle(
              color: _theme.textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: _theme.cardColor,
        border: Border(
          bottom: BorderSide(color: _theme.accentColor.withValues(alpha: 0.3)),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: _theme.accentColor,
        indicatorWeight: 3,
        labelColor: _theme.accentColor,
        unselectedLabelColor: _theme.subtitleColor,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
        tabs: const [
          Tab(text: 'CLIENT CALENDARS'),
          Tab(text: 'LODGING MANAGER'),
          Tab(text: 'FLEET TRACKER'),
        ],
      ),
    );
  }
}

class _ClientCalendarsTab extends StatelessWidget {
  const _ClientCalendarsTab();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController();
    final service = OutfitterFirebaseService();

    return StreamBuilder<List<ClientBooking>>(
      stream: service.getBookingsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: theme.accentColor),
          );
        }

        if (snapshot.hasError) {
          return _buildEmptyState(
            theme: theme,
            icon: Icons.error_outline,
            message: 'Error loading bookings',
          );
        }

        final bookings = snapshot.data ?? [];
        final total = bookings.length;
        final pending = bookings.where((b) => b.status == 'pending').length;
        final checkedIn = bookings
            .where((b) => b.status == 'checked_in')
            .length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildMetricCard(
              theme: theme,
              title: 'TOTAL BOOKINGS',
              value: total.toString(),
              icon: Icons.calendar_month,
            ),
            const SizedBox(height: 16),
            _buildMetricCard(
              theme: theme,
              title: 'PENDING',
              value: pending.toString(),
              icon: Icons.pending,
            ),
            const SizedBox(height: 16),
            _buildMetricCard(
              theme: theme,
              title: 'CHECKED IN',
              value: checkedIn.toString(),
              icon: Icons.check_circle,
            ),
            const SizedBox(height: 24),
            if (bookings.isEmpty)
              _buildEmptyState(
                theme: theme,
                icon: Icons.event_busy,
                message: 'No client bookings loaded',
              )
            else
              ...bookings.map((booking) => _buildBookingCard(booking, theme)),
          ],
        );
      },
    );
  }

  Widget _buildBookingCard(ClientBooking booking, ThemeController theme) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final statusColor = _getStatusColor(booking.status, theme);
    final statusLabel = _getStatusLabel(booking.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  booking.clientName,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor, width: 1.5),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.phone, color: theme.subtitleColor, size: 18),
              const SizedBox(width: 8),
              Text(
                booking.contactNumber,
                style: TextStyle(color: theme.subtitleColor, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today, color: theme.subtitleColor, size: 18),
              const SizedBox(width: 8),
              Text(
                '${dateFormat.format(booking.arrivalDate)} - ${dateFormat.format(booking.departureDate)}',
                style: TextStyle(color: theme.subtitleColor, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildCommunicationActions(booking, theme),
        ],
      ),
    );
  }

  Widget _buildCommunicationActions(
    ClientBooking booking,
    ThemeController theme,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUICK CONTACT',
            style: TextStyle(
              color: theme.subtitleColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildContactButton(
                  theme: theme,
                  icon: Icons.phone,
                  label: 'Call',
                  onPressed: () => _launchPhoneCall(booking.contactNumber),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildContactButton(
                  theme: theme,
                  icon: Icons.message,
                  label: 'WhatsApp',
                  onPressed: () => _launchWhatsApp(booking.contactNumber),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactButton({
    required ThemeController theme,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: theme.accentColor, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: theme.textColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchPhoneCall(String phoneNumber) async {
    final cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleanedNumber);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchWhatsApp(String phoneNumber) async {
    final cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('https://wa.me/$cleanedNumber');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Color _getStatusColor(String status, ThemeController theme) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFFFA726);
      case 'checked_in':
        return const Color(0xFF66BB6A);
      case 'checked_out':
        return const Color(0xFF42A5F5);
      case 'cancelled':
        return const Color(0xFFEF5350);
      default:
        return theme.accentColor;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'PENDING';
      case 'checked_in':
        return 'CHECKED IN';
      case 'checked_out':
        return 'CHECKED OUT';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return status.toUpperCase();
    }
  }

  Widget _buildMetricCard({
    required ThemeController theme,
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.accentColor, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required ThemeController theme,
    required IconData icon,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: theme.subtitleColor, size: 48),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: theme.subtitleColor,
              fontSize: 16,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _LodgingManagerTab extends StatefulWidget {
  const _LodgingManagerTab();

  @override
  State<_LodgingManagerTab> createState() => _LodgingManagerTabState();
}

class _LodgingManagerTabState extends State<_LodgingManagerTab> {
  final OutfitterFirebaseService _service = OutfitterFirebaseService();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController();

    return StreamBuilder<List<LodgingUnit>>(
      stream: _service.getLodgingStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: theme.accentColor),
          );
        }

        if (snapshot.hasError) {
          return _buildEmptyState(
            theme: theme,
            icon: Icons.error_outline,
            message: 'Error loading lodging units',
          );
        }

        final lodgingUnits = snapshot.data ?? [];
        final total = lodgingUnits.length;
        final vacant = lodgingUnits.where((u) => u.status == 'vacant').length;
        final occupied = lodgingUnits
            .where((u) => u.status == 'occupied')
            .length;
        final cleaning = lodgingUnits
            .where((u) => u.status == 'cleaning')
            .length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildMetricCard(
              theme: theme,
              title: 'TOTAL UNITS',
              value: total.toString(),
              icon: Icons.home_work,
            ),
            const SizedBox(height: 16),
            _buildMetricCard(
              theme: theme,
              title: 'VACANT',
              value: vacant.toString(),
              icon: Icons.bed,
            ),
            const SizedBox(height: 16),
            _buildMetricCard(
              theme: theme,
              title: 'OCCUPIED',
              value: occupied.toString(),
              icon: Icons.people,
            ),
            const SizedBox(height: 16),
            _buildMetricCard(
              theme: theme,
              title: 'CLEANING',
              value: cleaning.toString(),
              icon: Icons.cleaning_services,
            ),
            const SizedBox(height: 24),
            if (lodgingUnits.isEmpty)
              _buildEmptyState(
                theme: theme,
                icon: Icons.domain_disabled,
                message: 'No lodging units loaded',
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: lodgingUnits.length,
                itemBuilder: (context, index) {
                  return _buildLodgingCard(lodgingUnits[index], theme);
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildLodgingCard(LodgingUnit unit, ThemeController theme) {
    final statusColor = _getLodgingStatusColor(unit.status, theme);
    final statusLabel = _getLodgingStatusLabel(unit.status);
    final occupancyRatio = '${unit.currentOccupants}/${unit.maxCapacity}';
    final occupancyPercentage = unit.maxCapacity > 0
        ? (unit.currentOccupants / unit.maxCapacity).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  unit.unitName,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor, width: 1),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.people_outline, color: theme.subtitleColor, size: 16),
              const SizedBox(width: 6),
              Text(
                occupancyRatio,
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: theme.textColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              widthFactor: occupancyPercentage,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: _getOccupancyColor(occupancyPercentage),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _buildOccupancyButton(
                      theme: theme,
                      icon: Icons.remove,
                      onPressed: unit.currentOccupants > 0
                          ? () => _updateOccupants(
                              unit.id,
                              unit.currentOccupants - 1,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    _buildOccupancyButton(
                      theme: theme,
                      icon: Icons.add,
                      onPressed: unit.currentOccupants < unit.maxCapacity
                          ? () => _updateOccupants(
                              unit.id,
                              unit.currentOccupants + 1,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusCycleButton(
                theme: theme,
                currentStatus: unit.status,
                onPressed: () => _cycleStatus(unit.id, unit.status),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOccupancyButton({
    required ThemeController theme,
    required IconData icon,
    VoidCallback? onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: IconButton(
        icon: Icon(icon, color: theme.accentColor, size: 18),
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }

  Widget _buildStatusCycleButton({
    required ThemeController theme,
    required String currentStatus,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: IconButton(
        icon: Icon(Icons.sync, color: theme.accentColor, size: 18),
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        tooltip: 'Cycle Status',
      ),
    );
  }

  Color _getLodgingStatusColor(String status, ThemeController theme) {
    switch (status.toLowerCase()) {
      case 'vacant':
        return const Color(0xFF66BB6A);
      case 'occupied':
        return const Color(0xFFEF5350);
      case 'cleaning':
        return const Color(0xFFFFA726);
      default:
        return theme.accentColor;
    }
  }

  String _getLodgingStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'vacant':
        return 'VACANT';
      case 'occupied':
        return 'OCCUPIED';
      case 'cleaning':
        return 'CLEANING';
      default:
        return status.toUpperCase();
    }
  }

  Color _getOccupancyColor(double percentage) {
    if (percentage >= 0.8) return const Color(0xFFEF5350);
    if (percentage >= 0.5) return const Color(0xFFFFA726);
    return const Color(0xFF66BB6A);
  }

  Future<void> _updateOccupants(String lodgingId, int newCount) async {
    try {
      await _service.updateLodgingOccupants(
        lodgingId: lodgingId,
        newOccupantCount: newCount,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating occupants: $e')));
      }
    }
  }

  Future<void> _cycleStatus(String lodgingId, String currentStatus) async {
    String nextStatus;
    switch (currentStatus.toLowerCase()) {
      case 'vacant':
        nextStatus = 'occupied';
        break;
      case 'occupied':
        nextStatus = 'cleaning';
        break;
      case 'cleaning':
        nextStatus = 'vacant';
        break;
      default:
        nextStatus = 'vacant';
    }

    try {
      await _service.updateLodgingStatus(
        lodgingId: lodgingId,
        newStatus: nextStatus,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
      }
    }
  }

  Widget _buildMetricCard({
    required ThemeController theme,
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.accentColor, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required ThemeController theme,
    required IconData icon,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: theme.subtitleColor, size: 48),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: theme.subtitleColor,
              fontSize: 16,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _FleetTrackerTab extends StatefulWidget {
  const _FleetTrackerTab();

  @override
  State<_FleetTrackerTab> createState() => _FleetTrackerTabState();
}

class _FleetTrackerTabState extends State<_FleetTrackerTab> {
  final OutfitterFirebaseService _service = OutfitterFirebaseService();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController();

    return StreamBuilder<List<FleetAsset>>(
      stream: _service.getFleetStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: theme.accentColor),
          );
        }

        if (snapshot.hasError) {
          return _buildEmptyState(
            theme: theme,
            icon: Icons.error_outline,
            message: 'Error loading fleet',
          );
        }

        final fleet = snapshot.data ?? [];
        final total = fleet.length;
        final active = fleet
            .where((v) => v.operationalStatus == 'active')
            .length;
        final maintenance = fleet
            .where((v) => v.operationalStatus == 'maintenance')
            .length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildMetricCard(
              theme: theme,
              title: 'TOTAL VEHICLES',
              value: total.toString(),
              icon: Icons.directions_car,
            ),
            const SizedBox(height: 16),
            _buildMetricCard(
              theme: theme,
              title: 'ACTIVE',
              value: active.toString(),
              icon: Icons.check_circle,
            ),
            const SizedBox(height: 16),
            _buildMetricCard(
              theme: theme,
              title: 'MAINTENANCE',
              value: maintenance.toString(),
              icon: Icons.build,
            ),
            const SizedBox(height: 24),
            if (fleet.isEmpty)
              _buildEmptyState(
                theme: theme,
                icon: Icons.no_crash,
                message: 'No fleet assets loaded',
              )
            else
              ...fleet.map((asset) => _buildFleetCard(asset, theme)),
          ],
        );
      },
    );
  }

  Widget _buildFleetCard(FleetAsset asset, ThemeController theme) {
    final statusColor = _getOperationalColor(asset.operationalStatus, theme);
    final statusLabel = _getOperationalLabel(asset.operationalStatus);
    final isMaintenance =
        asset.operationalStatus.toLowerCase() == 'maintenance';

    return Opacity(
      opacity: isMaintenance ? 0.7 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMaintenance
                ? const Color(0xFFEF5350)
                : theme.accentColor.withValues(alpha: 0.3),
            width: isMaintenance ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.vehicleName,
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        asset.registrationNumber,
                        style: TextStyle(
                          color: theme.subtitleColor,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor, width: 1.5),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.local_gas_station,
                  color: theme.subtitleColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FUEL LEVEL',
                        style: TextStyle(
                          color: theme.subtitleColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: theme.textColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: FractionallySizedBox(
                          widthFactor: asset.fuelLevelPercentage / 100,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _getFuelColor(asset.fuelLevelPercentage),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${asset.fuelLevelPercentage}%',
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (asset.currentDriver.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.person, color: theme.subtitleColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Driver: ${asset.currentDriver}',
                    style: TextStyle(color: theme.subtitleColor, fontSize: 14),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.build, color: theme.subtitleColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  'OPERATIONAL STATUS',
                  style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: !isMaintenance,
                  onChanged: (value) => _toggleOperationalStatus(
                    asset.id,
                    value ? 'active' : 'maintenance',
                  ),
                  activeThumbColor: const Color(0xFF66BB6A),
                  activeTrackColor: const Color(
                    0xFF66BB6A,
                  ).withValues(alpha: 0.3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getOperationalColor(String status, ThemeController theme) {
    switch (status.toLowerCase()) {
      case 'active':
        return const Color(0xFF66BB6A);
      case 'maintenance':
        return const Color(0xFFFFA726);
      case 'inactive':
        return const Color(0xFFEF5350);
      default:
        return theme.accentColor;
    }
  }

  String _getOperationalLabel(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'ACTIVE';
      case 'maintenance':
        return 'MAINTENANCE';
      case 'inactive':
        return 'INACTIVE';
      default:
        return status.toUpperCase();
    }
  }

  Color _getFuelColor(int percentage) {
    if (percentage >= 50) return const Color(0xFF66BB6A);
    if (percentage >= 25) return const Color(0xFFFFA726);
    return const Color(0xFFEF5350);
  }

  Future<void> _toggleOperationalStatus(
    String vehicleId,
    String newStatus,
  ) async {
    try {
      await _service.toggleAssetOperationalState(
        vehicleId: vehicleId,
        newStatus: newStatus,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating operational status: $e')),
        );
      }
    }
  }

  Widget _buildMetricCard({
    required ThemeController theme,
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.accentColor, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required ThemeController theme,
    required IconData icon,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: theme.subtitleColor, size: 48),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: theme.subtitleColor,
              fontSize: 16,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
