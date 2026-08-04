import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../ballistics/data/models/saps_application_model.dart';

/// SAPS License & Competency Application Tracker Screen.
/// Provides a dashboard for registering and monitoring firearm license
/// and competency application statuses.
class SapsTrackerScreen extends StatefulWidget {
  const SapsTrackerScreen({super.key});

  @override
  State<SapsTrackerScreen> createState() => _SapsTrackerScreenState();
}

class _SapsTrackerScreenState extends State<SapsTrackerScreen> {
  final _idNumberController = TextEditingController();
  final _referenceController = TextEditingController();
  String _selectedApplicationType = SapsApplication.applicationTypes.first;
  bool _isLoading = false;

  @override
  void dispose() {
    _idNumberController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _registerApplication() async {
    if (_currentUserId == null) {
      _showErrorSnackBar('Please log in to track applications');
      return;
    }

    final idNumber = _idNumberController.text.trim();
    final referenceNumber = _referenceController.text.trim();

    if (idNumber.isEmpty) {
      _showErrorSnackBar('Please enter your ID Number');
      return;
    }

    if (referenceNumber.isEmpty) {
      _showErrorSnackBar('Please enter the Application Reference Code');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final docRef = await firestore.collection('license_applications').add({
        'hunterId': _currentUserId,
        'referenceNumber': referenceNumber,
        'idNumber': idNumber,
        'applicationType': _selectedApplicationType,
        'currentStatus': 'Submitted',
        'lastChecked': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        _idNumberController.clear();
        _referenceController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Application registered: ${docRef.id}'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to register: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          '💳 SAPS Tracker',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        iconTheme: IconThemeData(color: theme.colorScheme.primary),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Input Block
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                color: theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'REGISTER APPLICATION',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ID Number Input
                      TextField(
                        controller: _idNumberController,
                        decoration: InputDecoration(
                          labelText: 'ID Number',
                          hintText: 'Enter your 13-digit SA ID',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.badge_outlined),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      // Reference Number Input
                      TextField(
                        controller: _referenceController,
                        decoration: InputDecoration(
                          labelText: 'Application Reference Code',
                          hintText: 'e.g., SAPS-2024-001234',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.tag),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Application Type Dropdown
                      DropdownButtonFormField<String>(
                        initialValue: _selectedApplicationType,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Application Type',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.category_outlined),
                        ),
                        items:
                            SapsApplication.applicationTypes
                                .map(
                                  (typeString) => DropdownMenuItem(
                                    value: typeString,
                                    child: Text(
                                      typeString,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedApplicationType = value);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      // Register Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _registerApplication,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child:
                              _isLoading
                                  ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Text(
                                    'Register Application for Tracking',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Active Tracker Grid View
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'TRACKED APPLICATIONS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.secondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // StreamBuilder for active applications
            Expanded(
              child:
                  _currentUserId == null
                      ? Center(
                        child: Text(
                          'Please log in to view tracked applications',
                          style: TextStyle(color: theme.hintColor),
                        ),
                      )
                      : StreamBuilder<QuerySnapshot>(
                        stream:
                            FirebaseFirestore.instance
                                .collection('license_applications')
                                .where('hunterId', isEqualTo: _currentUserId)
                                .orderBy('lastChecked', descending: true)
                                .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                'Error loading applications: ${snapshot.error}',
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            );
                          }

                          final docs = snapshot.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.inbox_outlined,
                                    size: 64,
                                    color: theme.hintColor,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No applications tracked yet',
                                    style: TextStyle(color: theme.hintColor),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Register your first application above',
                                    style: TextStyle(
                                      color: theme.hintColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final app = SapsApplication.fromFirestore(
                                docs[index]
                                    as DocumentSnapshot<Map<String, dynamic>>,
                              );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _ApplicationCard(application: app),
                              );
                            },
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card widget displaying a single tracked application with stage progress bar.
class _ApplicationCard extends StatelessWidget {
  final SapsApplication application;

  const _ApplicationCard({required this.application});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    application.applicationType,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    application.currentStatus,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Ref: ${application.referenceNumber}',
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
            const SizedBox(height: 12),
            // Stage Progress Tracker Bar
            _StageProgressBar(
              currentStage: application.stageIndex,
              stages: SapsApplication.statusStages,
            ),
            const SizedBox(height: 8),
            Text(
              'Last checked: ${_formatDate(application.lastChecked)}',
              style: TextStyle(fontSize: 11, color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

/// Horizontal stage progress bar for tracking application status.
class _StageProgressBar extends StatelessWidget {
  final int currentStage;
  final List<String> stages;

  const _StageProgressBar({required this.currentStage, required this.stages});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: List.generate(stages.length * 2 - 1, (index) {
        if (index.isOdd) {
          // Connector line
          final stageIndex = index ~/ 2;
          final isCompleted = stageIndex < currentStage;
          return Expanded(
            child: Container(
              height: 3,
              color:
                  isCompleted
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
          );
        } else {
          // Stage node
          final stageIndex = index ~/ 2;
          final isCompleted = stageIndex <= currentStage;
          return Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  isCompleted
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withValues(alpha: 0.3),
              border: Border.all(color: theme.colorScheme.primary, width: 2),
            ),
            child: Center(
              child: Text(
                '${stageIndex + 1}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color:
                      isCompleted
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.primary,
                ),
              ),
            ),
          );
        }
      }),
    );
  }
}
