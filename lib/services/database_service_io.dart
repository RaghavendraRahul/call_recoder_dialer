import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/call_record.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'call_records.db');

    return await openDatabase(
      path, 
      version: 3, 
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE recordings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phoneNumber TEXT NOT NULL,
        contactName TEXT,
        timestamp TEXT NOT NULL,
        duration INTEGER NOT NULL,
        filePath TEXT,
        callType TEXT NOT NULL,
        uploadStatus TEXT NOT NULL,
        clientType TEXT,
        calledBy TEXT,
        clientId TEXT,
        callStatus TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add columns for CRM Intent Data
      await db.execute('ALTER TABLE recordings ADD COLUMN clientType TEXT;');
      await db.execute('ALTER TABLE recordings ADD COLUMN calledBy TEXT;');
    }
    if (oldVersion < 3) {
      // Add columns for Backend alignment
      await db.execute('ALTER TABLE recordings ADD COLUMN clientId TEXT;');
      await db.execute('ALTER TABLE recordings ADD COLUMN callStatus TEXT;');
    }
  }

  // Insert a new call record
  Future<int> insertCallRecord(CallRecord record) async {
    final db = await database;
    return await db.insert(
      'recordings',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Get all call records
  Future<List<CallRecord>> getAllCallRecords() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'recordings',
      orderBy: 'timestamp DESC',
    );

    return List.generate(maps.length, (i) {
      return CallRecord.fromMap(maps[i]);
    });
  }

  // Get call records by upload status
  Future<List<CallRecord>> getCallRecordsByStatus(UploadStatus status) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'recordings',
      where: 'uploadStatus = ?',
      whereArgs: [status.toString().split('.').last],
      orderBy: 'timestamp DESC',
    );

    return List.generate(maps.length, (i) {
      return CallRecord.fromMap(maps[i]);
    });
  }

  // Update call record
  Future<int> updateCallRecord(CallRecord record) async {
    final db = await database;
    return await db.update(
      'recordings',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  // Update upload status
  Future<int> updateUploadStatus(int id, UploadStatus status) async {
    final db = await database;
    return await db.update(
      'recordings',
      {'uploadStatus': status.toString().split('.').last},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Delete a call record
  Future<int> deleteCallRecord(int id) async {
    final db = await database;
    return await db.delete('recordings', where: 'id = ?', whereArgs: [id]);
  }

  // Get records that need to be uploaded
  Future<List<CallRecord>> getPendingUploads() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'recordings',
      where: 'uploadStatus = ? AND filePath IS NOT NULL',
      whereArgs: [UploadStatus.pending.toString().split('.').last],
      orderBy: 'timestamp ASC',
    );

    return List.generate(maps.length, (i) {
      return CallRecord.fromMap(maps[i]);
    });
  }

  // Search by phone number
  Future<List<CallRecord>> searchByPhoneNumber(String query) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'recordings',
      where: 'phoneNumber LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'timestamp DESC',
    );

    return List.generate(maps.length, (i) {
      return CallRecord.fromMap(maps[i]);
    });
  }

  // Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
