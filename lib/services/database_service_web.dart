import '../models/call_record.dart';

// Dummy Database class to satisfy return type if checked
class Database {}

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  // Return dummy database Future
  Future<Database> get database async => Database();

  Future<int> insertCallRecord(CallRecord record) async => 0;

  Future<List<CallRecord>> getAllCallRecords() async => [];

  Future<List<CallRecord>> getCallRecordsByStatus(UploadStatus status) async =>
      [];

  Future<int> updateCallRecord(CallRecord record) async => 0;

  Future<int> updateUploadStatus(int id, UploadStatus status) async => 0;

  Future<int> deleteCallRecord(int id) async => 0;

  Future<List<CallRecord>> getPendingUploads() async => [];

  Future<List<CallRecord>> searchByPhoneNumber(String query) async => [];

  Future<void> close() async {}
}
