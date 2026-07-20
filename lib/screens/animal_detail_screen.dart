import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/theme/app_theme.dart';
import '../models/animal.dart';

class AnimalDetailScreen extends StatefulWidget {
  final ThemeController theme;
  final Animal animal;

  const AnimalDetailScreen({
    super.key,
    required this.theme,
    required this.animal,
  });

  @override
  State<AnimalDetailScreen> createState() => _AnimalDetailScreenState();
}

class _AnimalDetailScreenState extends State<AnimalDetailScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _currentPage) {
        setState(() => _currentPage = page);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<String> _galleryImages(Animal animal) {
    final assetPath = _getAssetPathForAnimal(animal.name);
    if (assetPath != null) {
      return [assetPath];
    }
    return [];
  }

  String? _getAssetPathForAnimal(String animalName) {
    final sanitized = animalName
        .replaceAll("'", '')
        .replaceAll('(', '')
        .replaceAll(')', '');
    final assetPath = 'assets/images/$sanitized.jpg';
    return assetPath;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.theme,
      builder: (context, _) {
        final theme = widget.theme;
        final animal = widget.animal;
        final images = _galleryImages(animal);

        return Scaffold(
          backgroundColor: theme.backgroundColor,
          appBar: AppBar(
            title: Text(
              animal.name,
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: theme.backgroundColor,
            iconTheme: IconThemeData(color: theme.accentColor),
            elevation: 0,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ImageGallery(
                    theme: theme,
                    animal: animal,
                    images: images,
                    pageController: _pageController,
                    currentPage: _currentPage,
                  ),
                  const SizedBox(height: 20),
                  _SectionCard(
                    theme: theme,
                    title: 'IDENTIFICATION',
                    children: [
                      _DetailRow(
                        theme: theme,
                        label: 'Common Name',
                        value: animal.name,
                      ),
                      _DetailRow(
                        theme: theme,
                        label: 'Scientific Name',
                        value: animal.scientificName,
                        italic: true,
                      ),
                      if (animal.afrikaansName != null &&
                          animal.afrikaansName!.isNotEmpty)
                        _DetailRow(
                          theme: theme,
                          label: 'Afrikaans Name',
                          value: animal.afrikaansName!,
                        ),
                      if (animal.displayWeightRange != null)
                        _DetailRow(
                          theme: theme,
                          label: 'Typical Weight',
                          value: animal.displayWeightRange!,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Prominent Roland Ward trophy standard summary
                  Builder(
                    builder: (context) {
                      final rwValue =
                          animal.rwMinimum?.trim() ??
                          animal.rolandWardMinimum?.trim() ??
                          animal.trophyMinimumRW?.trim();
                      final measurementType = (() {
                        final m = animal.rwMeasurementMethod?.toLowerCase();
                        if (m != null && m.contains('horn')) return 'Horn';
                        if (m != null && m.contains('tusk')) return 'Tusk';
                        if (m != null &&
                            (m.contains('point') || m.contains('skull'))) {
                          return 'Points';
                        }
                        final d = animal.rwHornDescription?.toLowerCase();
                        if (d != null && d.contains('horn')) return 'Horn';
                        if (d != null && d.contains('tusk')) return 'Tusk';
                        if (d != null && d.contains('point')) return 'Points';
                        return null;
                      })();

                      return Card(
                        color: theme.cardColor,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Roland Ward Minimum Trophy Standard',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: theme.subtitleColor,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      rwValue == null || rwValue.isEmpty
                                          ? '—'
                                          : rwValue,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: theme.textColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (measurementType != null) ...[
                                Tooltip(
                                  message: 'Measurement: $measurementType',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.accentColor.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: theme.accentColor.withValues(
                                          alpha: 0.25,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      measurementType,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: theme.accentColor,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (animal.recommendedCaliber != null &&
                      animal.recommendedCaliber!.isNotEmpty)
                    _FirearmCompatibilitySection(
                      theme: theme,
                      recommendedCaliber: animal.recommendedCaliber!,
                    ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    theme: theme,
                    title: 'TROPHY REFERENCE',
                    children: [
                      _DetailRow(
                        theme: theme,
                        label: 'Rowland Ward Minimum',
                        value: _valueOrDash(animal.trophyMinimumRW),
                      ),
                      if (animal.rwMeasurementMethod != null &&
                          animal.rwMeasurementMethod!.isNotEmpty)
                        _DetailRow(
                          theme: theme,
                          label: 'Measurement Method',
                          value: animal.rwMeasurementMethod!,
                        ),
                      if (animal.rwHornDescription != null &&
                          animal.rwHornDescription!.isNotEmpty)
                        _DetailRow(
                          theme: theme,
                          label: 'Horn Description',
                          value: animal.rwHornDescription!,
                        ),
                    ],
                  ),
                  if (_hasText(animal.shotPlacementTip)) ...[
                    const SizedBox(height: 16),
                    _SectionCard(
                      theme: theme,
                      title: 'SHOT PLACEMENT',
                      children: [
                        Text(
                          animal.shotPlacementTip!,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: theme.textColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_hasText(animal.habitat) ||
                      _hasText(animal.huntingNotes)) ...[
                    const SizedBox(height: 16),
                    _SectionCard(
                      theme: theme,
                      title: 'HABITAT & HUNTING NOTES',
                      children: [
                        if (_hasText(animal.habitat)) ...[
                          Text(
                            'Habitat',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.accentColor,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            animal.habitat,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: theme.textColor,
                            ),
                          ),
                        ],
                        if (_hasText(animal.habitat) &&
                            _hasText(animal.huntingNotes))
                          const SizedBox(height: 14),
                        if (_hasText(animal.huntingNotes)) ...[
                          Text(
                            'Hunting Notes',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.accentColor,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            animal.huntingNotes!,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: theme.textColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  // Ecological Information Tabs
                  if (_hasEcologicalData(animal)) ...[
                    const SizedBox(height: 16),
                    _EcologicalInfoTabs(theme: theme, animal: animal),
                  ],
                  if (animal.provincialRegulations.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SectionCard(
                      theme: theme,
                      title: 'PROVINCIAL REGULATIONS',
                      children: [
                        ...animal.provincialRegulations.asMap().entries.map((
                          entry,
                        ) {
                          final isLast =
                              entry.key ==
                              animal.provincialRegulations.length - 1;
                          final regulation = entry.value;
                          return Padding(
                            padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  regulation.province,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: theme.textColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  regulation.regulation,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.45,
                                    color: theme.subtitleColor,
                                  ),
                                ),
                                if (!isLast)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Divider(
                                      color: theme.accentColor.withValues(
                                        alpha: 0.15,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

  String _valueOrDash(String? value) {
    if (value == null || value.trim().isEmpty) return '—';
    return value.trim();
  }

  bool _hasEcologicalData(Animal animal) {
    return _hasText(animal.waterDependence) ||
        _hasText(animal.primaryDiet) ||
        _hasText(animal.ruttingMonths) ||
        _hasText(animal.lambingMonths) ||
        _hasText(animal.socialStructure) ||
        animal.longevityYears != null ||
        animal.shoulderHeightMm != null;
  }
}

class _ImageGallery extends StatelessWidget {
  final ThemeController theme;
  final Animal animal;
  final List<String> images;
  final PageController pageController;
  final int currentPage;

  const _ImageGallery({
    required this.theme,
    required this.animal,
    required this.images,
    required this.pageController,
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        width: double.infinity,
        height: 260,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 48,
              color: theme.subtitleColor,
            ),
            const SizedBox(height: 8),
            Text(
              'No photos available',
              style: TextStyle(color: theme.subtitleColor),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 260,
            width: double.infinity,
            child: PageView.builder(
              controller: pageController,
              itemCount: images.length,
              itemBuilder: (context, index) {
                return Image.asset(
                  images[index],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => ColoredBox(
                    color: theme.cardColor,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_not_supported_outlined,
                          size: 40,
                          color: theme.subtitleColor,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Image not available',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.subtitleColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              images.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: currentPage == index ? 10 : 7,
                height: currentPage == index ? 10 : 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: currentPage == index
                      ? theme.accentColor
                      : theme.subtitleColor.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final ThemeController theme;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.theme,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: theme.cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.subtitleColor,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final ThemeController theme;
  final String label;
  final String value;
  final bool italic;

  const _DetailRow({
    required this.theme,
    required this.label,
    required this.value,
    this.italic = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: theme.subtitleColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: theme.textColor,
                fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirearmCompatibilitySection extends StatelessWidget {
  final ThemeController theme;
  final String recommendedCaliber;

  const _FirearmCompatibilitySection({
    required this.theme,
    required this.recommendedCaliber,
  });

  bool _isCaliberMatch(String firearmCaliber, String? recommendedCaliber) {
    if (recommendedCaliber == null || recommendedCaliber.isEmpty) {
      return false;
    }
    final recommended = recommendedCaliber.toLowerCase().trim();
    final caliber = firearmCaliber.toLowerCase().trim();

    // Exact match
    if (caliber == recommended) return true;

    // Contains match
    if (caliber.contains(recommended) || recommended.contains(caliber)) {
      return true;
    }

    return false;
  }

  bool _isSufficientCaliber(
    String firearmCaliber,
    String? recommendedCaliber,
    String? firearmType,
  ) {
    // Strict handgun exclusion - handguns must match exactly
    if (firearmType != null && firearmType.toLowerCase().contains('handgun')) {
      return _isCaliberMatch(firearmCaliber, recommendedCaliber);
    }

    if (recommendedCaliber == null || recommendedCaliber.isEmpty) {
      return false;
    }

    final recommended = recommendedCaliber.toLowerCase().trim();
    final caliber = firearmCaliber.toLowerCase().trim();

    // Exact match
    if (caliber == recommended) return true;

    // Contains match
    if (caliber.contains(recommended) || recommended.contains(caliber)) {
      return true;
    }

    // Downgrade logic: if recommended is large caliber (.308 Win) and firearm is smaller plains-game caliber (.243 Win)
    final largeCalibers = [
      '.308',
      '30-06',
      '7mm',
      '.300',
      '8mm',
      '9.3mm',
      '.375',
      '.416',
      '.458',
    ];
    final plainsGameCalibers = [
      '.223',
      '.243',
      '.257',
      '.270',
      '6.5mm',
      '7mm-08',
    ];

    bool isLargeCaliber = largeCalibers.any((lc) => recommended.contains(lc));
    bool isPlainsGameCaliber = plainsGameCalibers.any(
      (pc) => caliber.contains(pc),
    );

    if (isLargeCaliber && isPlainsGameCaliber) {
      return true;
    }

    return false;
  }

  bool _isDowngradeMatch(
    String firearmCaliber,
    String? recommendedCaliber,
    String? firearmType,
  ) {
    // Handguns cannot use downgrade logic
    if (firearmType != null && firearmType.toLowerCase().contains('handgun')) {
      return false;
    }

    if (recommendedCaliber == null || recommendedCaliber.isEmpty) {
      return false;
    }

    final recommended = recommendedCaliber.toLowerCase().trim();
    final caliber = firearmCaliber.toLowerCase().trim();

    // Check if this is a downgrade match (not exact or contains)
    if (_isCaliberMatch(firearmCaliber, recommendedCaliber)) {
      return false;
    }

    // Downgrade logic: if recommended is large caliber (.308 Win) and firearm is smaller plains-game caliber (.243 Win)
    final largeCalibers = [
      '.308',
      '30-06',
      '7mm',
      '.300',
      '8mm',
      '9.3mm',
      '.375',
      '.416',
      '.458',
    ];
    final plainsGameCalibers = [
      '.223',
      '.243',
      '.257',
      '.270',
      '6.5mm',
      '7mm-08',
    ];

    bool isLargeCaliber = largeCalibers.any((lc) => recommended.contains(lc));
    bool isPlainsGameCaliber = plainsGameCalibers.any(
      (pc) => caliber.contains(pc),
    );

    if (isLargeCaliber && isPlainsGameCaliber) {
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Card(
        color: theme.cardColor,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Sign in to view your firearm compatibility',
            style: TextStyle(color: theme.subtitleColor),
          ),
        ),
      );
    }

    return Card(
      color: theme.cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FIREARM COMPATIBILITY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.subtitleColor,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('firearms')
                  .where('ownerId', isEqualTo: user.uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Error loading firearms: ${snapshot.error}',
                    style: TextStyle(color: theme.subtitleColor, fontSize: 13),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.accentColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Loading firearms...',
                        style: TextStyle(
                          color: theme.subtitleColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  );
                }

                final firearms = snapshot.data?.docs;

                if (firearms == null || firearms.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recommended: $recommendedCaliber',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No firearms in your digital safe',
                        style: TextStyle(
                          color: theme.subtitleColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recommended: $recommendedCaliber',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...firearms.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final firearmCaliber = data['caliber'] as String? ?? '';
                      final make = data['make'] as String? ?? '';
                      final firearmType = data['firearmType'] as String?;

                      final isMatch = _isSufficientCaliber(
                        firearmCaliber,
                        recommendedCaliber,
                        firearmType,
                      );
                      final isDowngrade = _isDowngradeMatch(
                        firearmCaliber,
                        recommendedCaliber,
                        firearmType,
                      );

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Checkbox(
                              value: isMatch,
                              onChanged: null,
                              activeColor: isDowngrade
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$make ($firearmCaliber)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: theme.textColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (isDowngrade)
                                    Text(
                                      'Sufficient caliber match for this species',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EcologicalInfoTabs extends StatefulWidget {
  final ThemeController theme;
  final Animal animal;

  const _EcologicalInfoTabs({required this.theme, required this.animal});

  @override
  State<_EcologicalInfoTabs> createState() => _EcologicalInfoTabsState();
}

class _EcologicalInfoTabsState extends State<_EcologicalInfoTabs>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
    final theme = widget.theme;
    final animal = widget.animal;

    return Card(
      color: theme.cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: theme.accentColor,
            unselectedLabelColor: theme.subtitleColor,
            indicatorColor: theme.accentColor,
            tabs: const [
              Tab(
                icon: Icon(Icons.landscape, size: 20),
                text: 'Habitat & Diet',
              ),
              Tab(
                icon: Icon(Icons.family_restroom, size: 20),
                text: 'Breeding & Social',
              ),
              Tab(icon: Icon(Icons.straighten, size: 20), text: 'Physical'),
            ],
          ),
          SizedBox(
            height: 200,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildHabitatDietTab(theme, animal),
                _buildBreedingSocialTab(theme, animal),
                _buildPhysicalTab(theme, animal),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHabitatDietTab(ThemeController theme, Animal animal) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (animal.waterDependence != null) ...[
            _EcologicalDetailRow(
              theme: theme,
              icon: Icons.water_drop,
              label: 'Water Dependence',
              value: animal.waterDependence!,
            ),
            const SizedBox(height: 12),
          ],
          if (animal.primaryDiet != null) ...[
            _EcologicalDetailRow(
              theme: theme,
              icon: Icons.restaurant,
              label: 'Primary Diet',
              value: animal.primaryDiet!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreedingSocialTab(ThemeController theme, Animal animal) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (animal.ruttingMonths != null) ...[
            _EcologicalDetailRow(
              theme: theme,
              icon: Icons.calendar_today,
              label: 'Rutting Months',
              value: animal.ruttingMonths!,
            ),
            const SizedBox(height: 12),
          ],
          if (animal.lambingMonths != null) ...[
            _EcologicalDetailRow(
              theme: theme,
              icon: Icons.child_care,
              label: 'Lambing/Calving Months',
              value: animal.lambingMonths!,
            ),
            const SizedBox(height: 12),
          ],
          if (animal.socialStructure != null) ...[
            _EcologicalDetailRow(
              theme: theme,
              icon: Icons.groups,
              label: 'Social Structure',
              value: animal.socialStructure!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhysicalTab(ThemeController theme, Animal animal) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (animal.shoulderHeightMm != null) ...[
            _EcologicalDetailRow(
              theme: theme,
              icon: Icons.height,
              label: 'Shoulder Height',
              value: '${animal.shoulderHeightMm} mm',
            ),
            const SizedBox(height: 12),
          ],
          if (animal.longevityYears != null) ...[
            _EcologicalDetailRow(
              theme: theme,
              icon: Icons.schedule,
              label: 'Longevity',
              value: '${animal.longevityYears} years',
            ),
          ],
        ],
      ),
    );
  }
}

class _EcologicalDetailRow extends StatelessWidget {
  final ThemeController theme;
  final IconData icon;
  final String label;
  final String value;

  const _EcologicalDetailRow({
    required this.theme,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.accentColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.subtitleColor,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: theme.textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
