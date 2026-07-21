import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabaseService {
  static Database? _database;
  static final LocalDatabaseService instance = LocalDatabaseService._internal();

  factory LocalDatabaseService() => instance;

  LocalDatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'jagspoor.db');

    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create carcass_records table for Slaghuis Matrix with correct column mappings
    await db.execute('''
      CREATE TABLE IF NOT EXISTS carcass_records (
        id TEXT PRIMARY KEY,
        hunterId TEXT,
        species TEXT,
        carcassWeight REAL,
        slaughterFee REAL,
        coldroomDays INTEGER,
        status TEXT,
        isDirty INTEGER DEFAULT 1
      )
    ''');

    // Create invoices table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id TEXT PRIMARY KEY,
        clientName TEXT,
        packageName TEXT,
        packageBasePrice REAL,
        totalAmount REAL,
        extras TEXT,
        createdAt TEXT
      )
    ''');

    // Create bookings table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bookings (
        id TEXT PRIMARY KEY,
        clientName TEXT,
        contactNumber TEXT,
        arrivalDate TEXT,
        departureDate TEXT,
        lodgingId TEXT,
        vehicleId TEXT,
        status TEXT,
        createdAt TEXT
      )
    ''');

    // Create outfitter_packages table for package management with includedAnimalsJson
    await db.execute('''
      CREATE TABLE IF NOT EXISTS outfitter_packages (
        id TEXT PRIMARY KEY,
        packageName TEXT,
        packageLocation TEXT,
        startDate TEXT,
        endDate TEXT,
        packageDescription TEXT,
        basePrice REAL,
        includedAnimalsJson TEXT,
        createdAt TEXT,
        updatedAt TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migrate from v1 to v2
    if (oldVersion < 2) {
      try {
        await db.execute("ALTER TABLE carcass_records ADD COLUMN status TEXT");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE carcass_records ADD COLUMN slaughterFee REAL");
      } catch (_) {}
    }
    // Migrate from v2 to v3 - add includedAnimalsJson column
    if (oldVersion < 3) {
      try {
        await db.execute("ALTER TABLE outfitter_packages ADD COLUMN includedAnimalsJson TEXT");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE outfitter_packages ADD COLUMN basePrice REAL DEFAULT 0");
      } catch (_) {}
    }
  }
}
