import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';
import '../../services/location_resolver_service.dart';
import '../../utils/image_helper.dart';
import 'trophy_detail_screen.dart';
import 'add_trophy_screen.dart';

class TrophyRoomScreen extends StatefulWidget {
  final ThemeController theme;
  final List<Map<String, String>>? initialFirearms;

  const TrophyRoomScreen({
    super.key,
    required this.theme,
    this.initialFirearms,
  });

  @override
  State<TrophyRoomScreen> createState() => _TrophyRoomScreenState();
}

class _TrophyRoomScreenState extends State<TrophyRoomScreen> {
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;
  final Map<String, String?> _locationCache = {};

  @override
  void initState() {
    super.initState();
  }

  Future<String?> _resolveLocationName(Map<String, dynamic> trophy) async {
    final coordinates = trophy['coordinates']?.toString();
    final location = trophy['location']?.toString();

    // If coordinates are available, try to resolve town name
    if (coordinates != null && coordinates.contains(',')) {
      final parts = coordinates.split(',');
      if (parts.length == 2) {
        try {
          final lat = double.tryParse(parts[0].trim());
          final lng = double.tryParse(parts[1].trim());

          if (lat != null && lng != null) {
            final cacheKey =
                '${lat.toStringAsFixed(2)}_${lng.toStringAsFixed(2)}';

            if (_locationCache.containsKey(cacheKey)) {
              return _locationCache[cacheKey];
            }

            final townName = await LocationResolverService.getClosestTown(
              lat,
              lng,
            );
            _locationCache[cacheKey] = townName;
            return townName;
          }
        } catch (e) {
          // Fallback to location field if parsing fails
        }
      }
    }

    // Fallback to the stored location field
    return location;
  }

  Future<void> _openAddTrophyScreen() async {
    try {
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => AddTrophyScreen(
            theme: widget.theme,
            firearms: widget.initialFirearms,
          ),
        ),
      );

      if (result != null && mounted) {
        final ownerId =
            _currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
        if (ownerId != null) {
          await FirebaseFirestore.instance.collection('trophies').add({
            ...result,
            'ownerId': ownerId,
            'createdAt': FieldValue.serverTimestamp(),
          });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trophy added successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding trophy: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openTrophyDetail(Map<String, dynamic> trophy) {
    try {
      // Validate trophy data
      if (trophy['species'] == null || trophy['species'].toString().isEmpty) {
        throw Exception('Invalid trophy data: missing species');
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TrophyDetailScreen(
            theme: widget.theme,
            trophy: trophy,
            firearms: widget.initialFirearms,
            onEdit: () {
              // Handle edit callback
            },
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening trophy: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.theme,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: widget.theme.backgroundColor,
          appBar: AppBar(
            title: Text(
              'Digital Trophy Room',
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: widget.theme.backgroundColor,
            iconTheme: IconThemeData(color: widget.theme.accentColor),
            elevation: 0,
          ),
          body: SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: _currentUserId != null
                  ? FirebaseFirestore.instance
                        .collection('trophies')
                        .where('ownerId', isEqualTo: _currentUserId)
                        .orderBy('createdAt', descending: true)
                        .snapshots()
                  : const Stream.empty(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Unable to load trophies.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: widget.theme.subtitleColor),
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingState();
                }

                final trophies = snapshot.data?.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return <String, dynamic>{'docId': doc.id, ...data};
                }).toList();

                if (trophies == null || trophies.isEmpty) {
                  return _buildEmptyState();
                }

                return _buildTrophyList(trophies);
              },
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openAddTrophyScreen,
            backgroundColor: widget.theme.accentColor,
            foregroundColor: widget.theme.isDarkMode
                ? Colors.black
                : Colors.white,
            icon: const Icon(Icons.add),
            label: const Text(
              'ADD TROPHY',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(widget.theme.accentColor),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading trophies...',
            style: TextStyle(color: widget.theme.subtitleColor),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 64,
            color: widget.theme.accentColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No trophies yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: widget.theme.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button below to add your first trophy',
            style: TextStyle(color: widget.theme.subtitleColor),
          ),
        ],
      ),
    );
  }

  Widget _buildTrophyList(List<Map<String, dynamic>> trophies) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: trophies.length,
      itemBuilder: (context, index) => _buildPremiumTrophyCard(trophies[index]),
    );
  }

  Widget _buildPremiumTrophyCard(Map<String, dynamic> trophy) {
    final species = trophy['species']?.toString() ?? 'Unknown Trophy';
    final location = trophy['location']?.toString() ?? 'Location unknown';
    final harvestDate = trophy['harvestDate']?.toString() ?? 'N/A';
    final photos = (trophy['photos'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();
    final firstPhoto = photos?.isNotEmpty == true ? photos!.first : null;

    return Card(
      color: widget.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openTrophyDetail(trophy),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: firstPhoto != null
                    ? AdaptiveImage(
                        imagePath: firstPhoto,
                        fit: BoxFit.cover,
                        placeholder: Container(
                          color: widget.theme.accentColor.withValues(
                            alpha: 0.1,
                          ),
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                widget.theme.accentColor,
                              ),
                            ),
                          ),
                        ),
                        errorWidget: Container(
                          color: widget.theme.accentColor.withValues(
                            alpha: 0.1,
                          ),
                          child: Icon(
                            Icons.emoji_events_rounded,
                            size: 48,
                            color: widget.theme.accentColor.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      )
                    : Container(
                        color: widget.theme.accentColor.withValues(alpha: 0.1),
                        child: Icon(
                          Icons.emoji_events_rounded,
                          size: 48,
                          color: widget.theme.accentColor.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    species,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: widget.theme.textColor,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  FutureBuilder<String?>(
                    future: _resolveLocationName(trophy),
                    builder: (context, snapshot) {
                      final displayLocation = snapshot.data ?? location;
                      return Text(
                        displayLocation,
                        style: TextStyle(
                          color: widget.theme.subtitleColor,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        harvestDate,
                        style: TextStyle(
                          color: widget.theme.subtitleColor,
                          fontSize: 11,
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 12,
                        color: widget.theme.accentColor,
                      ),
                    ],
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
