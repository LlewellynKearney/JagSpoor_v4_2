import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/location_resolver_service.dart';
import '../../utils/image_helper.dart';
import 'edit_trophy_screen.dart';

class TrophyDetailScreen extends StatefulWidget {
  final ThemeController theme;
  final Map<String, dynamic> trophy;
  final VoidCallback? onEdit;
  final List<Map<String, String>>? firearms;

  const TrophyDetailScreen({
    super.key,
    required this.theme,
    required this.trophy,
    this.onEdit,
    this.firearms,
  });

  @override
  State<TrophyDetailScreen> createState() => _TrophyDetailScreenState();
}

class _TrophyDetailScreenState extends State<TrophyDetailScreen> {
  String? _resolvedTownName;

  @override
  void initState() {
    super.initState();
    _resolveLocation();
  }

  Future<void> _resolveLocation() async {
    final coordinates = widget.trophy['coordinates']?.toString();

    if (coordinates != null && coordinates.contains(',')) {
      final parts = coordinates.split(',');
      if (parts.length == 2) {
        try {
          final lat = double.tryParse(parts[0].trim());
          final lng = double.tryParse(parts[1].trim());

          if (lat != null && lng != null) {
            final townName = await LocationResolverService.getClosestTown(
              lat,
              lng,
            );
            if (mounted) {
              setState(() {
                _resolvedTownName = townName;
              });
            }
          }
        } catch (e) {
          // Fallback to coordinates if resolution fails
        }
      }
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
              widget.trophy['species'] ?? 'Trophy Details',
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: widget.theme.backgroundColor,
            iconTheme: IconThemeData(color: widget.theme.accentColor),
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(Icons.edit, color: widget.theme.accentColor),
                tooltip: 'Edit Trophy',
                onPressed: () async {
                  final scaffold = ScaffoldMessenger.of(context);
                  final nav = Navigator.of(context);

                  final result = await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditTrophyScreen(
                        theme: widget.theme,
                        trophy: widget.trophy,
                        firearms: widget.firearms,
                      ),
                    ),
                  );

                  if (result != null && mounted) {
                    // Update the trophy data and rebuild
                    scaffold.showSnackBar(
                      const SnackBar(
                        content: Text('Trophy updated successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    // Optionally pop back to TrophyRoomScreen with updated data
                    nav.pop(result);
                  }
                },
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                // Trophy image or placeholder
                _buildImageSection(),
                const SizedBox(height: 24),

                // Trophy details card
                _buildDetailsCard(),
                const SizedBox(height: 16),

                // Measurement data card
                _buildMeasurementsCard(),
                const SizedBox(height: 16),

                // Harvest information card
                _buildHarvestInfoCard(),
                const SizedBox(height: 16),

                // Tags section
                if ((widget.trophy['tags'] as List?)?.isNotEmpty ?? false)
                  _buildTagsSection(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageSection() {
    final photos = (widget.trophy['photos'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();

    if (photos == null || photos.isEmpty) {
      return Container(
        width: double.infinity,
        height: 250,
        decoration: BoxDecoration(
          color: widget.theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.theme.accentColor.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_not_supported,
              size: 48,
              color: widget.theme.subtitleColor,
            ),
            const SizedBox(height: 8),
            Text(
              'No photos available',
              style: TextStyle(color: widget.theme.subtitleColor),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: widget.theme.cardColor,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AdaptiveImage(
          imagePath: photos.first,
          fit: BoxFit.cover,
          placeholder: Container(
            color: widget.theme.accentColor.withValues(alpha: 0.1),
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
            color: widget.theme.cardColor,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.broken_image,
                  size: 48,
                  color: widget.theme.subtitleColor,
                ),
                const SizedBox(height: 8),
                Text(
                  'Photo unavailable',
                  style: TextStyle(color: widget.theme.subtitleColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsCard() {
    return Card(
      color: widget.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TROPHY INFORMATION',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: widget.theme.subtitleColor,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Species', widget.trophy['species'] ?? 'Unknown'),
            _buildDetailRow(
              'Harvest Date',
              widget.trophy['harvestDate'] ?? 'N/A',
            ),
            _buildDetailRow(
              'Firearm Used',
              widget.trophy['firearmUsed'] ?? 'N/A',
            ),
            _buildDetailRow('Location', widget.trophy['location'] ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _buildMeasurementsCard() {
    final hasMeasurements =
        (widget.trophy['antlerSpread'] != null ||
        widget.trophy['antlerLength'] != null ||
        widget.trophy['antlerCircumference'] != null ||
        widget.trophy['weight'] != null);

    if (!hasMeasurements) {
      return const SizedBox.shrink();
    }

    return Card(
      color: widget.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MEASUREMENTS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: widget.theme.subtitleColor,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.trophy['antlerSpread'] != null)
              _buildDetailRow(
                'Antler Spread',
                '${widget.trophy['antlerSpread']} cm',
              ),
            if (widget.trophy['antlerLength'] != null)
              _buildDetailRow(
                'Antler Length',
                '${widget.trophy['antlerLength']} cm',
              ),
            if (widget.trophy['antlerCircumference'] != null)
              _buildDetailRow(
                'Antler Circumference',
                '${widget.trophy['antlerCircumference']} cm',
              ),
            if (widget.trophy['weight'] != null)
              _buildDetailRow('Weight', '${widget.trophy['weight']} kg'),
          ],
        ),
      ),
    );
  }

  Widget _buildHarvestInfoCard() {
    final coordinates =
        widget.trophy['coordinates']?.toString() ?? 'Not logged';
    final displayLocation = _resolvedTownName ?? coordinates;

    return Card(
      color: widget.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HARVEST DETAILS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: widget.theme.subtitleColor,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: widget.theme.accentColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Location',
                        style: TextStyle(
                          color: widget.theme.subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        displayLocation,
                        style: TextStyle(
                          color: widget.theme.textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_resolvedTownName != null &&
                          coordinates != 'Not logged')
                        Text(
                          coordinates,
                          style: TextStyle(
                            color: widget.theme.subtitleColor,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagsSection() {
    final tags = (widget.trophy['tags'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();
    if (tags == null || tags.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TAGS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: widget.theme.subtitleColor,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags
              .map(
                (tag) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: widget.theme.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: widget.theme.accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      color: widget.theme.accentColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Text(
              label,
              style: TextStyle(color: widget.theme.subtitleColor, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
