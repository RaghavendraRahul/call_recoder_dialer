import 'dart:io' if (dart.library.html) 'platform/platform_io_stub.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/call_record.dart';
import 'database_service.dart';

class CRMService {
  static final CRMService _instance = CRMService._internal();
  factory CRMService() => _instance;
  CRMService._internal();

  final DatabaseService _dbService = DatabaseService();

  // For Android Emulator to access host's localhost, we MUST use 10.0.2.2
  // If you run on a real device, change this to your computer's local Wi-Fi IP (e.g., 192.168.x.x)
  static const String _baseUrl = 'http://192.168.18.29:8000';
  static const String _uploadEndpoint = '/api/call-logs/';
  static const String _historyEndpoint = '/api/client-call-history/';

  // TODO: Add your authentication method (API key, Bearer token, etc.)
  static const String _apiKey = 'YOUR_API_KEY_HERE';

  // Upload a single recording to CRM
  Future<bool> uploadRecording(CallRecord record) async {
    if (record.id == null) {
      print('Cannot upload: Missing record ID');
      return false;
    }

    try {
      print('\n=============================================');
      print('📤 PREPARING TO UPLOAD CALL RECORD');
      print('=============================================');
      print('• Record ID: ${record.id}');
      print('• Client ID (CRM Lead ID): ${record.clientId}');
      print('• Client Type: ${record.clientType}');
      print('• Phone Number: ${record.phoneNumber}');
      print('• Contact Name: ${record.contactName}');
      print('• Called By: ${record.calledBy}');
      print('• Duration: ${record.duration}');
      print('• Timestamp: ${record.timestamp}');
      print('• Call Status: ${record.callStatus}');
      print('• File Path: ${record.filePath}');
      print('=============================================\n');

      // Update status to uploading
      await _dbService.updateUploadStatus(record.id!, UploadStatus.uploading);

      // Create multipart request
      final uri = Uri.parse('$_baseUrl$_uploadEndpoint');
      final request = http.MultipartRequest('POST', uri);

      // Add headers
      request.headers['Authorization'] = 'Bearer $_apiKey';

      // Handle the file conditionally
      bool hasFile = false;
      if (record.filePath != null) {
        final file = File(record.filePath!);
        if (await file.exists()) {
          final fileStream = http.ByteStream(file.openRead());
          final fileLength = await file.length();
          final multipartFile = http.MultipartFile(
            'call_recording', // Updated key per backend spec
            fileStream,
            fileLength,
            filename: file.path.split('/').last,
          );
          request.files.add(multipartFile);
          hasFile = true;
        } else {
          print('Recording file not found at ${record.filePath}, sending data without file.');
        }
      }

      // Add metadata matching exact backend payload
      if (record.clientId != null) {
        request.fields['client_id'] = record.clientId.toString();
      }
      
      request.fields['phone_number'] = record.phoneNumber;
      
      // Handle timezone offset appropriately for the backend 
      request.fields['call_started'] = record.timestamp.toIso8601String();
      
      final callEnded = record.timestamp.add(Duration(seconds: record.duration));
      request.fields['call_ended'] = callEnded.toIso8601String();
      
      request.fields['call_duration'] = record.duration.toString();
      
      request.fields['call_status'] = record.callStatus ?? record.callType.toString().split('.').last;
      
      // Only keep recording if a file is actually successfully uploaded
      request.fields['keep_recording'] = hasFile ? 'true' : 'false';
      
      if (record.contactName != null) {
        request.fields['name'] = record.contactName!;
      }
      if (record.clientType != null && record.clientType!.isNotEmpty && record.clientType != 'null') {
        // Only valid types based on what little we know
        if (['B2B Lead', 'B2C Lead', 'B2B', 'B2C', 'Vendor', 'Quotation'].contains(record.clientType)) {
             request.fields['client_type'] = record.clientType!;
        } else {
             // Try to map correctly if needed, otherwise skip to prevent 400 errors
             print('Warning: Skipping potentially invalid client_type: ${record.clientType}');
        }
      }
      if (record.calledBy != null) {
        request.fields['called_by'] = record.calledBy!;
      }
      if (record.clientId != null) {
        request.fields['client_id'] = record.clientId.toString();
      }

      print('\n\n=================== PAYLOAD BEING SENT TO BACKEND ===================');
      request.fields.forEach((key, value) {
        print('$key: $value');
      });
      print('Included Audio File?: $hasFile');
      print('=====================================================================\n\n');

      // Send request with timeout
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Success
        await _dbService.updateUploadStatus(record.id!, UploadStatus.uploaded);
        print('Successfully uploaded recording: ${record.id}');
        return true;
      } else {
        // Failed
        print('\n\n=================== DJANGO API VALIDATION ERROR ===================');
        print('Upload failed with status code: ${response.statusCode}');
        print('ENDPOINT: $_baseUrl$_uploadEndpoint');
        
        // Strip out noisy HTML to find the actual Python traceback title
        final String body = response.body;
        if (body.contains('<title>')) {
           final match = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(body);
           if (match != null) {
               print('DJANGO CRASH EXCEPTION: ${match.group(1)?.trim()}');
           }
        }
        
        print('JSON RESPONSE BODY FROM BACKEND:');
        print(body.length > 500 ? '${body.substring(0, 500)}... [TRUNCATED]' : body);
        print('===================================================================\n\n');
        
        await _dbService.updateUploadStatus(record.id!, UploadStatus.failed);
        return false;
      }
    } catch (e) {
      print('\n\n=================== FLUTTER EXCEPTION DURING UPLOAD ===================');
      print('Error message: $e');
      print('==========================================================================\n\n');
      if (record.id != null) {
        await _dbService.updateUploadStatus(record.id!, UploadStatus.failed);
      }
      return false;
    }
  }

  // Upload all pending recordings
  Future<int> uploadPendingRecordings() async {
    final pendingRecords = await _dbService.getPendingUploads();
    int successCount = 0;

    for (var record in pendingRecords) {
      final success = await uploadRecording(record);
      if (success) {
        successCount++;
      }

      // Add a small delay between uploads to avoid overwhelming the server
      await Future.delayed(const Duration(milliseconds: 500));
    }

    print('Uploaded $successCount of ${pendingRecords.length} recordings');
    return successCount;
  }

  // Retry failed uploads
  Future<int> retryFailedUploads() async {
    final failedRecords = await _dbService.getCallRecordsByStatus(
      UploadStatus.failed,
    );
    int successCount = 0;

    for (var record in failedRecords) {
      final success = await uploadRecording(record);
      if (success) {
        successCount++;
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }

    print(
      'Retried and uploaded $successCount of ${failedRecords.length} failed recordings',
    );
    return successCount;
  }

  // Check network connectivity
  Future<bool> isNetworkAvailable() async {
    try {
      final result = await http.get(Uri.parse('https://www.google.com'));
      return result.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Auto-upload after call (call this after recording is saved)
  Future<void> autoUploadRecording(CallRecord record) async {
    // Check network before attempting upload
    final hasNetwork = await isNetworkAvailable();
    if (!hasNetwork) {
      print('No network available, upload will be retried later');
      return;
    }

    // Upload in background
    uploadRecording(record);
  }

  /// Fetches the client call history from the backend CRM
  Future<List<Map<String, dynamic>>> getClientCallHistory() async {
    try {
      final uri = Uri.parse('$_baseUrl$_historyEndpoint');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonResponse = json.decode(response.body);
        
        // Handle variations in standard JSON pagination/data wrapping
        if (jsonResponse is List) {
          return List<Map<String, dynamic>>.from(jsonResponse);
        } else if (jsonResponse is Map<String, dynamic>) {
           if (jsonResponse.containsKey('data') && jsonResponse['data'] is List) {
              return List<Map<String, dynamic>>.from(jsonResponse['data']);
           } else if (jsonResponse.containsKey('results') && jsonResponse['results'] is List) {
              return List<Map<String, dynamic>>.from(jsonResponse['results']);
           }
        }
        
        print('Unexpected JSON format from Call History API: $jsonResponse');
        return [];
      } else {
        print('Failed to fetch call history: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Network Error fetching call history: $e');
      return [];
    }
  }
}
