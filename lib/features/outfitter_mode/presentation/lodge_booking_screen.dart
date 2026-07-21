import 'package:flutter/material.dart';
import '../../shared/data/services/local_database_service.dart';

class LodgeBookingScreen extends StatefulWidget {
  const LodgeBookingScreen({super.key});

  @override
  State<LodgeBookingScreen> createState() => _LodgeBookingScreenState();
}

class _LodgeBookingScreenState extends State<LodgeBookingScreen> {
  final LocalDatabaseService _dbService = LocalDatabaseService();
  
  final _clientNameController = TextEditingController();
  final _contactNumberController = TextEditingController();
  
  String _selectedLodging = 'Chalet 1';
  String _selectedVehicle = 'None';
  
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;
  
  static const Color accentGold = Color(0xFFC5A059);
  static const Color deepWalnut = Color(0xFF3E2723);
  
  static const List<String> _lodgingOptions = [
    'Chalet 1', 'Chalet 2', 'Chalet 3', 'Chalet 4', 
    'Family Suite', 'Hunter Lodge', 'Camp Site A', 'Camp Site B'
  ];
  
  static const List<String> _vehicleOptions = [
    'None', 'Land Cruiser 1', 'Land Cruiser 2', 'Land Cruiser 3',
    'Hilux Tracker', 'Safari Jeep', 'Custom Vehicle'
  ];

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _contactNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings() async {
    setState(() => _isLoading = true);
    try {
      final db = await _dbService.database;
      final results = await db.query('bookings', orderBy: 'arrivalDate DESC');
      setState(() {
        _bookings = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading bookings: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showBookingForm({Map<String, dynamic>? existingBooking}) async {
    final isEditing = existingBooking != null;
    _clientNameController.text = existingBooking?['clientName'] ?? '';
    _contactNumberController.text = existingBooking?['contactNumber'] ?? '';
    _selectedLodging = existingBooking?['lodgingId'] ?? 'Chalet 1';
    _selectedVehicle = existingBooking?['vehicleId'] ?? 'None';
    
    DateTime? startDate;
    DateTime? endDate;
    if (isEditing) {
      final startVal = existingBooking['arrivalDate'];
      final endVal = existingBooking['departureDate'];
      if (startVal != null) startDate = DateTime.tryParse(startVal.toString());
      if (endVal != null) endDate = DateTime.tryParse(endVal.toString());
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          bottom: true,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 
                      MediaQuery.of(sheetContext).padding.bottom + 16,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEditing ? 'EDIT BOOKING' : 'NEW BOOKING',
                    style: const TextStyle(color: accentGold, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _clientNameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Client Name',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _contactNumberController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact Number',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedLodging,
                    dropdownColor: Colors.black,
                    style: const TextStyle(color: Colors.white),
                    items: _lodgingOptions.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                    onChanged: (v) => setSheetState(() => _selectedLodging = v ?? 'Chalet 1'),
                    decoration: const InputDecoration(
                      labelText: 'Lodging',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedVehicle,
                    dropdownColor: Colors.black,
                    style: const TextStyle(color: Colors.white),
                    items: _vehicleOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (v) => setSheetState(() => _selectedVehicle = v ?? 'None'),
                    decoration: const InputDecoration(
                      labelText: 'Vehicle',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: startDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) setSheetState(() => startDate = date);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Arrival',
                              labelStyle: TextStyle(color: Colors.grey),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                            ),
                            child: Text(
                              startDate != null 
                                ? '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}'
                                : 'Select date',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: endDate ?? DateTime.now().add(const Duration(days: 3)),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) setSheetState(() => endDate = date);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Departure',
                              labelStyle: TextStyle(color: Colors.grey),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentGold)),
                            ),
                            child: Text(
                              endDate != null 
                                ? '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}'
                                : 'Select date',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: accentGold),
                      onPressed: () async {
                        if (_clientNameController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Client name required'), backgroundColor: Colors.orange),
                          );
                          return;
                        }
                        final bookingData = {
                          'clientName': _clientNameController.text,
                          'contactNumber': _contactNumberController.text,
                          'lodgingId': _selectedLodging,
                          'vehicleId': _selectedVehicle,
                          'arrivalDate': startDate?.toIso8601String(),
                          'departureDate': endDate?.toIso8601String(),
                          'status': 'Confirmed',
                        };
                        try {
                          final db = await _dbService.database;
                          if (isEditing) {
                            await db.update('bookings', bookingData, where: 'id = ?', whereArgs: [existingBooking['id']]);
                          } else {
                            bookingData['id'] = DateTime.now().millisecondsSinceEpoch.toString();
                            await db.insert('bookings', bookingData);
                          }
                          if (!mounted) return;
                          Navigator.pop(sheetContext);
                          await _loadBookings();
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red),
                          );
                        }
                      },
                      child: Text(isEditing ? 'UPDATE BOOKING' : 'CREATE BOOKING',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteBooking(String bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Cancel Booking?', style: TextStyle(color: Colors.white)),
        content: const Text('This action cannot be undone.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final db = await _dbService.database;
        await db.delete('bookings', where: 'id = ?', whereArgs: [bookingId]);
        await _loadBookings();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking cancelled'), backgroundColor: Colors.green),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('LODGE BOOKING MANAGER',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
        backgroundColor: deepWalnut,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _showBookingForm(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: accentGold))
          : _bookings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.grey, size: 64),
                      const SizedBox(height: 16),
                      const Text('No bookings yet', style: TextStyle(color: Colors.grey, fontSize: 18)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: accentGold),
                        onPressed: () => _showBookingForm(),
                        icon: const Icon(Icons.add, color: Colors.black),
                        label: const Text('Create First Booking', style: TextStyle(color: Colors.black)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80, left: 12, right: 12, top: 12),
                  itemCount: _bookings.length,
                  itemBuilder: (context, index) {
                    final booking = _bookings[index];
                    return Card(
                      color: const Color(0xFF1A1A1A),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: accentGold.withValues(alpha: 0.3)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(
                          (booking['clientName'] ?? 'Unknown') as String,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('📞 ${booking['contactNumber'] ?? 'N/A'}', style: const TextStyle(color: Colors.grey)),
                            Text('🏠 ${booking['lodgingId'] ?? 'N/A'}', style: const TextStyle(color: Colors.grey)),
                            Text('🚗 ${booking['vehicleId'] ?? 'None'}', style: const TextStyle(color: Colors.grey)),
                            if (booking['arrivalDate'] != null)
                              Text('📅 ${booking['arrivalDate']} → ${booking['departureDate'] ?? 'TBD'}',
                                style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _showBookingForm(existingBooking: booking),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteBooking(booking['id'] as String),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accentGold,
        onPressed: () => _showBookingForm(),
        label: const Text('NEW BOOKING', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}
