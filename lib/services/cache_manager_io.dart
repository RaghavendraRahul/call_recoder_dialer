import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CacheManager {
  static final CacheManager _instance = CacheManager._internal();
  factory CacheManager() => _instance;
  CacheManager._internal();

  // Get cache directory for recordings
  Future<Directory> getRecordingsDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${docsDir.path}/recordings');

    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }

    return recordingsDir;
  }

  // Generate filename for recording
  String generateFilename(String phoneNumber, DateTime timestamp) {
    final formattedDate = timestamp.toIso8601String().replaceAll(':', '-');
    final sanitizedPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    return '${formattedDate}_$sanitizedPhone.m4a';
  }

  // Get full file path
  Future<String> getFilePath(String phoneNumber, DateTime timestamp) async {
    final dir = await getRecordingsDirectory();
    final filename = generateFilename(phoneNumber, timestamp);
    return '${dir.path}/$filename';
  }

  // Check if file exists
  Future<bool> fileExists(String filePath) async {
    final file = File(filePath);
    return await file.exists();
  }

  // Get file size
  Future<int> getFileSize(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  // Delete recording file
  Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      print('Error deleting file: $e');
      return false;
    }
  }

  // Clean up old recordings (older than specified days)
  Future<int> cleanupOldRecordings({int daysOld = 30}) async {
    try {
      final dir = await getRecordingsDirectory();
      final files = await dir.list().toList();
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      int deletedCount = 0;

      for (var entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            await entity.delete();
            deletedCount++;
          }
        }
      }

      return deletedCount;
    } catch (e) {
      print('Error cleaning up recordings: $e');
      return 0;
    }
  }

  // Get all recording files
  Future<List<FileSystemEntity>> getAllRecordings() async {
    final dir = await getRecordingsDirectory();
    return await dir.list().toList();
  }

  // Get total cache size
  Future<int> getTotalCacheSize() async {
    try {
      final dir = await getRecordingsDirectory();
      final files = await dir.list().toList();
      int totalSize = 0;

      for (var entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }

      return totalSize;
    } catch (e) {
      print('Error calculating cache size: $e');
      return 0;
    }
  }

  // Format bytes to human-readable string
  String formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    int unitIndex = 0;
    double size = bytes.toDouble();

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return '${size.toStringAsFixed(2)} ${units[unitIndex]}';
  }
}
