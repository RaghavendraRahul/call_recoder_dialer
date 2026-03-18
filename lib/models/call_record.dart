// Enum for call type
enum CallType { incoming, outgoing, missed }

// Enum for upload status
enum UploadStatus { pending, uploading, uploaded, failed, notUploaded }

// Model for call recording
class CallRecord {
  final int? id;
  final String phoneNumber;
  final String? contactName;
  final DateTime timestamp;
  final int duration; // in seconds
  final String? filePath;
  final CallType callType;
  final UploadStatus uploadStatus;
  final String? clientType;
  final String? calledBy;
  final String? clientId;
  final String? callStatus;

  CallRecord({
    this.id,
    required this.phoneNumber,
    this.contactName,
    required this.timestamp,
    required this.duration,
    this.filePath,
    required this.callType,
    this.uploadStatus = UploadStatus.pending,
    this.clientType,
    this.calledBy,
    this.clientId,
    this.callStatus,
  });

  // Convert to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'contactName': contactName,
      'timestamp': timestamp.toIso8601String(),
      'duration': duration,
      'filePath': filePath,
      'callType': callType.toString().split('.').last,
      'uploadStatus': uploadStatus.toString().split('.').last,
      'clientType': clientType,
      'calledBy': calledBy,
      'clientId': clientId,
      'callStatus': callStatus,
    };
  }

  // Create from Map (from database)
  factory CallRecord.fromMap(Map<String, dynamic> map) {
    return CallRecord(
      id: map['id'] as int?,
      phoneNumber: map['phoneNumber'] as String,
      contactName: map['contactName'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      duration: map['duration'] as int,
      filePath: map['filePath'] as String?,
      callType: CallType.values.firstWhere(
        (e) => e.toString().split('.').last == map['callType'],
        orElse: () => CallType.incoming,
      ),
      uploadStatus: UploadStatus.values.firstWhere(
        (e) => e.toString().split('.').last == map['uploadStatus'],
        orElse: () => UploadStatus.pending,
      ),
      clientType: map['clientType'] as String?,
      calledBy: map['calledBy'] as String?,
      clientId: map['clientId']?.toString(),
      callStatus: map['callStatus'] as String?,
    );
  }

  // Create a copy with updated fields
  CallRecord copyWith({
    int? id,
    String? phoneNumber,
    String? contactName,
    DateTime? timestamp,
    int? duration,
    String? filePath,
    CallType? callType,
    UploadStatus? uploadStatus,
    String? clientType,
    String? calledBy,
    String? clientId,
    String? callStatus,
  }) {
    return CallRecord(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      contactName: contactName ?? this.contactName,
      timestamp: timestamp ?? this.timestamp,
      duration: duration ?? this.duration,
      filePath: filePath ?? this.filePath,
      callType: callType ?? this.callType,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      clientType: clientType ?? this.clientType,
      calledBy: calledBy ?? this.calledBy,
      clientId: clientId ?? this.clientId,
      callStatus: callStatus ?? this.callStatus,
    );
  }
}
