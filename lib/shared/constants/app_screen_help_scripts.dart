/// Centralised repository of rich, professional help scripts for every core
/// screen in the JagSpoor Hunter and Outfitter portals.
///
/// Each entry pairs a screen key (see [AppScreenHelpScripts.*] constants)
/// with an [AppScreenHelpScript]: a title, a plain-language description of
/// what the screen does, and a list of key concepts / how-to steps rendered
/// by the universal info modal (`lib/shared/widgets/app_info_modal.dart`).
library;

/// A single key-concept row inside a help script: a bolded label with an
/// explanation beneath it.
class AppHelpConcept {
  const AppHelpConcept({required this.label, required this.detail});

  /// Short label, e.g. "Booking a hunt" or "Service rates".
  final String label;

  /// One-to-two sentence plain-language explanation.
  final String detail;
}

/// The full help payload for one screen.
class AppScreenHelpScript {
  const AppScreenHelpScript({
    required this.title,
    required this.description,
    this.concepts = const <AppHelpConcept>[],
  });

  /// Human-readable screen title shown at the top of the modal.
  final String title;

  /// Paragraph describing what the screen is for and how to use it.
  final String description;

  /// Key concepts / step-by-step rows rendered under the description.
  final List<AppHelpConcept> concepts;
}

/// Help-script registry for the universal info modal.
///
/// Screen keys are stable string identifiers; each target screen passes its
/// key to `showAppInfoModal(context, screenKey)`.
abstract final class AppScreenHelpScripts {
  AppScreenHelpScripts._();

  // Hunter Portal screen keys.
  static const String hunterMarketplace = 'hunter_marketplace';
  static const String hunterCustomPackageBuilder =
      'hunter_custom_package_builder';
  static const String hunterTrophyRegistry = 'hunter_trophy_registry';
  static const String hunterFirearmSafe = 'hunter_firearm_safe';
  static const String hunterBallisticsCalculator =
      'hunter_ballistics_calculator';
  static const String hunterSpoorIdentification =
      'hunter_spoor_identification';
  static const String hunterVenisonPermits = 'hunter_venison_permits';

  // Outfitter Portal screen keys.
  static const String outfitterDashboard = 'outfitter_dashboard';
  static const String outfitterFarmControlPanel =
      'outfitter_farm_control_panel';
  static const String outfitterPackageManager = 'outfitter_package_manager';
  static const String outfitterTrophyStock = 'outfitter_trophy_stock';
  static const String outfitterPriceLists = 'outfitter_price_lists';
  static const String outfitterVenisonPermits = 'outfitter_venison_permits';

  /// All registered screen keys (used by tests to assert coverage).
  static const List<String> allKeys = <String>[
    hunterMarketplace,
    hunterCustomPackageBuilder,
    hunterTrophyRegistry,
    hunterFirearmSafe,
    hunterBallisticsCalculator,
    hunterSpoorIdentification,
    hunterVenisonPermits,
    outfitterDashboard,
    outfitterFarmControlPanel,
    outfitterPackageManager,
    outfitterTrophyStock,
    outfitterPriceLists,
    outfitterVenisonPermits,
  ];

  /// Resolves the help script for [screenKey], falling back to a generic
  /// script for unknown keys so the modal always shows something useful.
  static AppScreenHelpScript forKey(String screenKey) {
    return scripts[screenKey] ?? _fallback;
  }

  /// The full help-script map, keyed by screen key.
  static const Map<String, AppScreenHelpScript> scripts =
      <String, AppScreenHelpScript>{
    // ====================== HUNTER PORTAL ======================
    hunterMarketplace: AppScreenHelpScript(
      title: 'Package Marketplace',
      description:
          'Browse hunting packages published by outfitters across South '
          'Africa. Compare farms, species and prices, view the outfitter\'s '
          'availability, and submit a booking request. The "My Bookings" tab '
          'tracks your active hunts, while "Past Hunts" archives completed '
          'and cancelled bookings.',
      concepts: <AppHelpConcept>[
        AppHelpConcept(
          label: 'Browsing packages',
          detail:
              'Filter by province, search by species or farm, and tap a '
              'package card to open the full details sheet with photos, '
              'pricing and the availability calendar.',
        ),
        AppHelpConcept(
          label: 'Booking a hunt',
          detail:
              'Tap "Book This Package" to send a booking request to the '
              'outfitter. Your request stays Pending until the outfitter '
              'approves it.',
        ),
        AppHelpConcept(
          label: 'Payment',
          detail:
              'Payment is arranged directly with the outfitter off-platform. '
              'Once the outfitter verifies your payment the booking is '
              'Confirmed and you can add the hunt to your device calendar.',
        ),
        AppHelpConcept(
          label: 'Availability strip',
          detail:
              'The green/red date strip on the details sheet shows real-time '
              'availability from the outfitter\'s calendar before you book.',
        ),
      ],
    ),
    hunterCustomPackageBuilder: AppScreenHelpScript(
      title: 'Custom Package Builder',
      description:
          'Build your own hunting package from a farm\'s published price '
          'list. Choose your hunt dates, party size, species and optional '
          'services, review the live total, and submit the request to the '
          'outfitter for approval.',
      concepts: <AppHelpConcept>[
        AppHelpConcept(
          label: 'Selecting a farm',
          detail:
              'Only farms with a published price list appear in the farm '
              'list. Tap a farm card to load its species and service rates.',
        ),
        AppHelpConcept(
          label: 'Adding species',
          detail:
              'Use the + / - steppers to set how many of each species you '
              'want to harvest. Quantities are capped at the outfitter\'s '
              'available stock.',
        ),
        AppHelpConcept(
          label: 'Services & fees',
          detail:
              'Daily rates, accommodation, vehicle and guide fees from the '
              'farm\'s service sheet can be added per day, night or animal.',
        ),
        AppHelpConcept(
          label: 'Live total',
          detail:
              'The total at the bottom updates as you build. Submitting '
              'sends the full itinerary to the outfitter as a Pending '
              'booking request.',
        ),
      ],
    ),
    hunterTrophyRegistry: AppScreenHelpScript(
      title: 'Trophy Registry & Booking',
      description:
          'Browse trophy animals currently offered by outfitters, including '
          'measurements, photos and pricing, and book a specific trophy '
          'animal directly from the registry.',
      concepts: <AppHelpConcept>[
        AppHelpConcept(
          label: 'Trophy cards',
          detail:
              'Each card shows the species, the hosting farm, the measured '
              'trophy size and the asking price. Tap a card for the full '
              'details sheet with the farm photo gallery.',
        ),
        AppHelpConcept(
          label: 'Booking a trophy',
          detail:
              'Tap "Book This Trophy" in the details sheet. The request is '
              'sent to the outfitter and the animal is reserved while your '
              'booking is Pending.',
        ),
        AppHelpConcept(
          label: 'Measurements',
          detail:
              'Horn and tusk lengths are recorded by the outfitter. Compare '
              'them with Rowland Ward minimums in the SA Game Guide to '
              'gauge trophy quality.',
        ),
      ],
    ),
    hunterFirearmSafe: AppScreenHelpScript(
      title: 'Digital Firearm Safe',
      description:
          'Register and manage your firearms digitally. Each firearm record '
          'stores the make, model, calibre, serial number and licence '
          'details, and links to ballistics, optic profiles and maintenance '
          'history.',
      concepts: <AppHelpConcept>[
        AppHelpConcept(
          label: 'Registering a firearm',
          detail:
              'Tap the add button and enter the firearm\'s details, or scan '
              'your licence card with the built-in licence scanner to '
              'pre-fill the form automatically.',
        ),
        AppHelpConcept(
          label: 'Licence renewals',
          detail:
              'Expiry dates are tracked per firearm so you receive a clear '
              'warning well before a licence needs renewal.',
        ),
        AppHelpConcept(
          label: 'Linked profiles',
          detail:
              'A registered firearm can be linked to optic settings and '
              'ammunition profiles, which then feed the ballistics '
              'calculator and shot-group analyser.',
        ),
        AppHelpConcept(
          label: 'Export',
          detail:
              'Use the PDF action to export a printable register of your '
              'safe for insurance or compliance purposes.',
        ),
      ],
    ),
    hunterBallisticsCalculator: AppScreenHelpScript(
      title: 'Ballistics Calculator',
      description:
          'Compute a precise trajectory for your rifle and load. Select a '
          'firearm from your Digital Firearm Safe, set the cartridge and '
          'environmental conditions, and read drop, windage, energy and '
          'sight adjustments for any range.',
      concepts: <AppHelpConcept>[
        AppHelpConcept(
          label: 'Firearm & load',
          detail:
              'Choose a firearm from your safe, then pick a factory load or '
              'a custom handload. Bullet weight, ballistic coefficient and '
              'muzzle velocity drive the solution.',
        ),
        AppHelpConcept(
          label: 'Atmosphere',
          detail:
              'Altitude, temperature, pressure and humidity all change air '
              'density. Set them for the hunting area to keep the '
              'trajectory honest.',
        ),
        AppHelpConcept(
          label: 'Reading the table',
          detail:
              'The table lists drop and windage in centimetres plus MOA / '
              'MIL click values per range step, so you can dial your scope '
              'directly.',
        ),
        AppHelpConcept(
          label: 'Drag models',
          detail:
              'Use G1 for flat-base bullets and G7 for boat-tail / VLD '
              'bullets. The G7 curve usually matches modern hunting '
              'bullets best.',
        ),
      ],
    ),
    hunterSpoorIdentification: AppScreenHelpScript(
      title: 'Track (Spoor) Identifier',
      description:
          'Identify animal tracks in the field. Photograph the spoor with a '
          'scale reference, and the on-device AI analyses the track shape '
          'and dimensions to suggest the most likely species.',
      concepts: <AppHelpConcept>[
        AppHelpConcept(
          label: 'Taking the photo',
          detail:
              'Place a coin or ruler next to the track before photographing '
              'it. The scale reference lets the app convert pixels to real '
              'millimetres.',
        ),
        AppHelpConcept(
          label: 'Morphological categories',
          detail:
              'Tracks are grouped as paw (carnivore), cloven-hoofed '
              '(ungulate) or solid hoof (equine). The AI first classifies '
              'the category, then ranks candidate species.',
        ),
        AppHelpConcept(
          label: 'Confidence scores',
          detail:
              'Each suggestion carries a confidence percentage. Low light '
              'or partial prints lower confidence. Retake the photo if '
              'the result seems off.',
        ),
        AppHelpConcept(
          label: 'History',
          detail:
              'Identified tracks are saved to your history with GPS '
              'coordinates, building a personal record of animal movement '
              'on the property.',
        ),
      ],
    ),

    // ====================== OUTFITTER PORTAL ======================
    outfitterDashboard: AppScreenHelpScript(
      title: 'Outfitter Dashboard',
      description:
          'Your command centre for the outfitting business. From here you '
          'can manage farms, packages, trophy stock, price lists, incoming '
          'booking requests, venison permits and business analytics.',
      concepts: <AppHelpConcept>[
        AppHelpConcept(
          label: 'Feature cards',
          detail:
              'Each card opens one management area. Cards marked for owner '
              'access are hidden when you sign in as an assigned farm '
              'manager.',
        ),
        AppHelpConcept(
          label: 'Booking requests',
          detail:
              'New hunter booking requests land in Incoming Booking '
              'Requests. Approve, decline, or verify payment from there.',
        ),
        AppHelpConcept(
          label: 'Day / Night mode',
          detail:
              'Use the settings sheet to switch between Day and Night '
              'mode; the choice is remembered on this device.',
        ),
      ],
    ),
    outfitterFarmControlPanel: AppScreenHelpScript(
      title: 'Farm Control Panel',
      description:
          'Register and manage the farms you operate on, assign farm '
          'managers, and configure booking synchronisation. Farm details '
          'and photos shown here appear to hunters in the marketplace.',
      concepts: <AppHelpConcept>[
        AppHelpConcept(
          label: 'Registering a farm',
          detail:
              'Complete the form with the farm name, district, province '
              'and contact details, optionally add a photo, then save. '
              'The farm immediately becomes selectable in packages and '
              'price lists.',
        ),
        AppHelpConcept(
          label: 'Editing a farm',
          detail:
              'Tap any registered farm card to edit its details, service '
              'rates and photo. Changes apply everywhere the farm is '
              'referenced.',
        ),
        AppHelpConcept(
          label: 'Farm managers',
          detail:
              'Assign a manager to a farm so they can handle day-to-day '
              'bookings and stock for that property with a restricted '
              'dashboard view.',
        ),
        AppHelpConcept(
          label: 'Booking & ERP sync',
          detail:
              'Connect an external calendar (iCal feed) or use manual '
              'mode so hunters see accurate availability before booking.',
        ),
      ],
    ),
    outfitterPackageManager: AppScreenHelpScript(
      title: 'Package Manager',
      description:
          'Create, edit and retire the hunting packages hunters see in the '
          'marketplace. Control listing status, quantity slots and pricing '
          'for every package you publish.',
      concepts: <AppHelpConcept>[
        AppHelpConcept(
          label: 'Publishing a package',
          detail:
              'Tap + to open the publisher: set the title, description, '
              'farm, pricing (all-inclusive or itemised), photos and the '
              'availability window, then publish.',
        ),
        AppHelpConcept(
          label: 'Listing status',
          detail:
              'Active packages are bookable in the marketplace. Drafts are '
              'hidden, Archived packages are retired, and Sold Out shows '
              'when all slots are booked.',
        ),
        AppHelpConcept(
          label: 'Quantity slots',
          detail:
              'Set how many hunters can book the package. Each confirmed '
              'booking decrements the count automatically.',
        ),
        AppHelpConcept(
          label: 'Editing & restocking',
          detail:
              'Tap Edit on any card to change details, or Restock a '
              'sold-out package to make it bookable again.',
        ),
      ],
    ),
    outfitterTrophyStock: AppScreenHelpScript(
      title: 'Trophy Stock Management',
      description:
          'Maintain the sellable trophy inventory per farm. Each entry '
          'records the species, available count, price, measurement and '
          'photos, and appears in the hunter Trophy Registry.',
      concepts: <AppHelpConcept>[
        AppHelpConcept(
          label: 'Syncing stock',
          detail:
              'Complete the form (species, farm, count, price and an '
              'optional measurement with photos) then sync. The entry '
              'goes live for hunters immediately.',
        ),
        AppHelpConcept(
          label: 'Stock by farm',
          detail:
              'The "Current Stock by Farm" section groups entries per '
              'farm with live counts. Tap an entry to edit or delete it.',
        ),
        AppHelpConcept(
          label: 'Automatic sold-out',
          detail:
              'When a hunter books a trophy the available count drops '
              'automatically, and the entry marks itself sold out at '
              'zero.',
        ),
        AppHelpConcept(
          label: 'Inventory report',
          detail:
              'Use the PDF action to export a branded trophy inventory '
              'report for your records or insurers.',
        ),
      ],
    ),
    outfitterPriceLists: AppScreenHelpScript(
      title: 'Game Price Lists & Services',
      description:
          'Publish per-farm game pricing and itemised service rates. '
          'Hunters building a custom package against a farm see exactly '
          'what you enter here: species, sex, trophy size and price.',
      concepts: <AppHelpConcept>[
        AppHelpConcept(
          label: 'Species entries',
          detail:
              'Select a farm, then add each huntable species with its '
              'gender, horn/tusk class, quantity limit and price. Entries '
              'can be edited or removed at any time.',
        ),
        AppHelpConcept(
          label: 'Service rates',
          detail:
              'Set per-day hunter and observer rates, accommodation, '
              'catering, vehicle, guide and slaughter fees. Only '
              'configured (non-zero) services appear to hunters.',
        ),
        AppHelpConcept(
          label: 'Import & export',
          detail:
              'Use the CSV action to bulk-import a price list, or the PDF '
              'action to export a branded price list you can share with '
              'clients.',
        ),
      ],
    ),
    outfitterVenisonPermits: AppScreenHelpScript(
      title: 'Venison Permit Manager',
      description:
          'Issue, sign and track legal venison / game transport permits. '
          'Every permit captures the hunter, the authorised person, the '
          'hunt window, species transported and both digital signatures.',
      concepts: <AppHelpConcept>[
        AppHelpConcept(
          label: 'Issuing a permit',
          detail:
              'Tap "New Permit", complete the statutory fields, and have '
              'both parties sign on-screen. The permit is stored and '
              'visible to the hunter immediately.',
        ),
        AppHelpConcept(
          label: 'Permit log',
          detail:
              'The list is searchable and stays in sync. Tap a card to '
              'view the full permit with both signatures, export it as a '
              'PDF, or void it.',
        ),
        AppHelpConcept(
          label: 'Legality',
          detail:
              'A valid permit is required to transport game meat. Export '
              'the PDF before the vehicle leaves the farm so it travels '
              'with the carcass.',
        ),
      ],
    ),
    hunterVenisonPermits: AppScreenHelpScript(
      title: 'My Transport Permits',
      description:
          'View the venison / game transport permits issued for your hunts. '
          'Each permit records the hunt window, the species transported, and '
          'both signatures, and can be exported as a PDF to carry with the '
          'meat.',
      concepts: <AppHelpConcept>[
        AppHelpConcept(
          label: 'Finding a permit',
          detail:
              'Use the search bar to filter by permit number, farm or '
              'species. Tap a card to open the full permit details.',
        ),
        AppHelpConcept(
          label: 'Exporting',
          detail:
              'Open a permit and use the export action to generate a '
              'printable PDF. Keep it with the vehicle whenever game meat '
              'is being transported.',
        ),
        AppHelpConcept(
          label: 'Validity',
          detail:
              'Check the hunt window dates and status on the card. A '
              'voided permit is not valid for transport; ask the outfitter '
              'to issue a replacement.',
        ),
      ],
    ),
  };

  static const AppScreenHelpScript _fallback = AppScreenHelpScript(
    title: 'About This Screen',
    description:
        'This screen is part of the JagSpoor hunting management platform. '
        'Explore the controls on screen, or return to the dashboard to '
        'open another feature.',
    concepts: <AppHelpConcept>[
      AppHelpConcept(
        label: 'Need more help?',
        detail:
            'Use the Report Bug or Suggest Feature options on your '
            'dashboard to reach the support team directly.',
      ),
    ],
  );
}
