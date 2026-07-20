import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../data/models/lodging_unit.dart';
import '../data/models/fleet_asset.dart';
import '../data/services/outfitter_firebase_service.dart';

class AddBookingSheet extends StatefulWidget {
  const AddBookingSheet({super.key});

  @override
  State<AddBookingSheet> createState() => _AddBookingSheetState();
}

class _AddBookingSheetState extends State<AddBookingSheet> {
  final _formKey = GlobalKey<FormState>();
  final _service = OutfitterFirebaseService();
  final _clientNameController = TextEditingController();
  final _contactNumberController = TextEditingController();

  DateTime? _arrivalDate;
  DateTime? _departureDate;
  String? _selectedLodgingId;
  String? _selectedVehicleId;

  bool _isLoading = false;

  @override
  void dispose() {
    _clientNameController.dispose();
    _contactNumberController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_arrivalDate == null || _departureDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select arrival and departure dates'),
        ),
      );
      return;
    }

    if (_selectedLodgingId == null || _selectedVehicleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select lodging and vehicle')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _service.createBooking(
        clientName: _clientNameController.text.trim(),
        contactNumber: _contactNumberController.text.trim(),
        arrivalDate: _arrivalDate!,
        departureDate: _departureDate!,
        lodgingId: _selectedLodgingId!,
        vehicleId: _selectedVehicleId!,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking created successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating booking: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final firstDate = now;
    final lastDate = DateTime(now.year + 2);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: _arrivalDate != null && _departureDate != null
          ? DateTimeRange(start: _arrivalDate!, end: _departureDate!)
          : null,
      builder: (context, child) {
        final theme = ThemeController();
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: theme.accentColor,
              onPrimary: theme.backgroundColor,
              surface: theme.cardColor,
              onSurface: theme.textColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _arrivalDate = picked.start;
        _departureDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController();

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.textColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NEW RESERVATION',
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _clientNameController,
                            style: TextStyle(color: theme.textColor),
                            decoration: InputDecoration(
                              labelText: 'Client Name',
                              labelStyle: TextStyle(color: theme.subtitleColor),
                              prefixIcon: Icon(
                                Icons.person,
                                color: theme.accentColor,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.accentColor.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.accentColor.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.accentColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter client name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _contactNumberController,
                            style: TextStyle(color: theme.textColor),
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'Contact Number',
                              labelStyle: TextStyle(color: theme.subtitleColor),
                              prefixIcon: Icon(
                                Icons.phone,
                                color: theme.accentColor,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.accentColor.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.accentColor.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.accentColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter contact number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: _selectDateRange,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: theme.accentColor.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    color: theme.accentColor,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _arrivalDate != null &&
                                              _departureDate != null
                                          ? '${DateFormat('MMM dd, yyyy').format(_arrivalDate!)} - ${DateFormat('MMM dd, yyyy').format(_departureDate!)}'
                                          : 'Select Arrival & Departure Dates',
                                      style: TextStyle(
                                        color: _arrivalDate != null
                                            ? theme.textColor
                                            : theme.subtitleColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          StreamBuilder<List<LodgingUnit>>(
                            stream: _service.getVacantLodgingStream(),
                            builder: (context, snapshot) {
                              return DropdownButtonFormField<String>(
                                initialValue: _selectedLodgingId,
                                decoration: InputDecoration(
                                  labelText: 'Select Lodging Unit',
                                  labelStyle: TextStyle(
                                    color: theme.subtitleColor,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.bed,
                                    color: theme.accentColor,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.accentColor.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.accentColor.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.accentColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                dropdownColor: theme.cardColor,
                                style: TextStyle(color: theme.textColor),
                                items:
                                    snapshot.data?.map((unit) {
                                      return DropdownMenuItem<String>(
                                        value: unit.id,
                                        child: Text(
                                          '${unit.unitName} (Capacity: ${unit.maxCapacity})',
                                          style: TextStyle(
                                            color: theme.textColor,
                                          ),
                                        ),
                                      );
                                    }).toList() ??
                                    [],
                                onChanged: (value) {
                                  setState(() => _selectedLodgingId = value);
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'Please select lodging unit';
                                  }
                                  return null;
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          StreamBuilder<List<FleetAsset>>(
                            stream: _service.getActiveFleetStream(),
                            builder: (context, snapshot) {
                              return DropdownButtonFormField<String>(
                                initialValue: _selectedVehicleId,
                                decoration: InputDecoration(
                                  labelText: 'Select Vehicle',
                                  labelStyle: TextStyle(
                                    color: theme.subtitleColor,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.directions_car,
                                    color: theme.accentColor,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.accentColor.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.accentColor.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.accentColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                dropdownColor: theme.cardColor,
                                style: TextStyle(color: theme.textColor),
                                items:
                                    snapshot.data?.map((asset) {
                                      return DropdownMenuItem<String>(
                                        value: asset.id,
                                        child: Text(
                                          '${asset.vehicleName} (${asset.registrationNumber})',
                                          style: TextStyle(
                                            color: theme.textColor,
                                          ),
                                        ),
                                      );
                                    }).toList() ??
                                    [],
                                onChanged: (value) {
                                  setState(() => _selectedVehicleId = value);
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'Please select vehicle';
                                  }
                                  return null;
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _submitForm,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.accentColor,
                                foregroundColor: theme.backgroundColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              theme.backgroundColor,
                                            ),
                                      ),
                                    )
                                  : const Text(
                                      'CREATE BOOKING',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
