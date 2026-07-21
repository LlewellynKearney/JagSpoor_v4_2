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
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create carcass_records table for Slaghuis Matrix
    await db.execute('''
      CREATE TABLE IF NOT EXISTS carcass_records (
        id TEXT PRIMARY KEY,
        hunterId TEXT,
        species TEXT,
        carcassWeight REAL,
        coldroomDays INTEGER DEFAULT 0,
        isDirty INTEGER DEFAULT 0,
        slaughterFee REAL DEFAULT 0,
        createdAt TEXT
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
  }
}
