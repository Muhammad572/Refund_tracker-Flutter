import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/receipt_model.dart';

class DatabaseService {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'refunds.db');
    return await openDatabase(
      path,
      version: 2, // FIXED: Increased version to trigger the update
      onCreate: (db, version) async {
        // FIXED: Added missing columns (fullText, category, currency, notes)
        await db.execute(
          'CREATE TABLE receipts(id TEXT PRIMARY KEY, storeName TEXT, amount REAL, purchaseDate TEXT, refundDeadline TEXT, imagePath TEXT, fullText TEXT, category TEXT, currency TEXT, notes TEXT)',
        );
        // ADDED FOR NFR: Indexing the deadline ensures "Offline First" sorting is always fast (<3s)
        await db.execute('CREATE INDEX idx_deadline ON receipts (refundDeadline)');
      },
      // FIXED: This adds the notes column to your existing app without deleting data
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE receipts ADD COLUMN fullText TEXT');
          await db.execute('ALTER TABLE receipts ADD COLUMN category TEXT');
          await db.execute('ALTER TABLE receipts ADD COLUMN currency TEXT');
          await db.execute('ALTER TABLE receipts ADD COLUMN notes TEXT');
          // ADDED FOR NFR: Ensure index exists for users upgrading
          await db.execute('CREATE INDEX idx_deadline ON receipts (refundDeadline)');
        }
      },
    );
  }

  // Save a receipt to the database
  // FIXED: Changed parameter to accept the Map from ocr_screen.dart
  Future<void> insertReceipt(Map<String, dynamic> receipt) async {
    final db = await database;
    await db.insert(
      'receipts',
      receipt, // FIXED: Now uses the full Map including notes
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Get all receipts to show in a list later
  // UPDATED FOR STEP 3: Added orderBy to sort by deadline (most urgent first)
  Future<List<Map<String, dynamic>>> getReceipts() async {
    final db = await database;
    return await db.query(
      'receipts',
      orderBy: 'refundDeadline ASC',
    );
  }

  // Add this at the bottom of the class
  Future<void> deleteReceipt(String id) async {
    final db = await database;
    await db.delete(
      'receipts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}