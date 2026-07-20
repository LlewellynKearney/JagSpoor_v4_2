import 'package:flutter/material.dart';

class TacticalModuleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData leadingIcon;
  final bool isFavorite;
  final VoidCallback? onTap;               // ← make optional if you don’t need the whole card tappable
  final VoidCallback onFavoriteToggle;

  const TacticalModuleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    required this.isFavorite,
    this.onTap,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
      // --------------------------------------------------------------
      // 1️⃣  Card tap – keep only if you still want navigation.
      // --------------------------------------------------------------
      onTap: onTap,               // set to null or remove if you don’t want any tap
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 8.0,
      ),

      // --------------------------------------------------------------
      // 2️⃣  Leading icon (unchanged)
      // --------------------------------------------------------------
      leading: Icon(leadingIcon, size: 32.0),

      // --------------------------------------------------------------
      // 3️⃣  Title / subtitle (unchanged)
      // --------------------------------------------------------------
      title: Text(
        title,
style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodyMedium,
      ),

      // --------------------------------------------------------------
      // 4️⃣  Trailing – ONLY the heart icon, perfectly centered.
      // --------------------------------------------------------------
      trailing: Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          icon: Icon(
            isFavorite ? Icons.favorite : Icons.favorite_border,
            color: Colors.redAccent,
          ),
          tooltip: isFavorite ? 'Un‑favorite' : 'Favorite',
          onPressed: onFavoriteToggle,
        ),
      ),
      ),
    );
  }
}

// ... existing imports ...

class HunterDashboardScreen extends StatefulWidget {
  const HunterDashboardScreen({super.key});

  @override
  State<HunterDashboardScreen> createState() => _HunterDashboardScreenState();
}

class _HunterDashboardScreenState extends State<HunterDashboardScreen> {
  // ... existing code ...

  @override
  Widget build(BuildContext context) {
    // ... existing code ...

    String header = 'Header';
    String subHeader = 'Subheader';
    String description = 'Description';
    String footnote = 'Footnote';

    return Card(
      child: Column(
        children: [
          Text(header),
          Text(subHeader),
          Text(description),
          Text(footnote),
        ],
      ),
    );
  }
}

