package com.example.call_record

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.telecom.TelecomManager
import android.content.Context
import android.app.role.RoleManager
import android.os.Build
import android.os.Bundle
import android.net.Uri
import android.content.pm.PackageManager
import android.util.Log
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.call_record/call_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "answerCall" -> {
                    CallRecordingService.activeInstance?.answerCall()
                    result.success(true)
                }
                "rejectCall" -> {
                    CallRecordingService.activeInstance?.rejectCall()
                    result.success(true)
                }
                "endCall" -> {
                    val success = CallRecordingService.activeInstance?.endCall() ?: false
                    result.success(success)
                }
                "requestDefaultDialer" -> {
                    requestDefaultDialer()
                    result.success(true)
                }
                "isDefaultDialer" -> {
                    val isDefault = isDefaultDialer()
                    result.success(isDefault)
                }
                "makeCall" -> {
                    val number = call.argument<String>("phoneNumber")
                    if (number != null) {
                        makeCall(number)
                        result.success(true)
                    } else {
                        result.error("invalid_argument", "Phone number is null", null)
                    }
                }
                "getInitialNumber" -> {
                    val number = intent?.data?.schemeSpecificPart
                    result.success(number)
                }
                "getLeadData" -> {
                    // Log all keys to debug exactly what the CRM passed us
                    val keys = intent?.extras?.keySet()?.joinToString(", ") ?: "no_extras"
                    Log.d("MainActivity", "Intent extra keys received: $keys")

                    // Read lead context extras passed from CRM app via Intent
                    val leadIdAny = intent?.extras?.get("lead_id") ?: intent?.extras?.get("client_id")
                    val leadId: String? = when (leadIdAny) {
                        is Int -> leadIdAny.toString()
                        is String -> leadIdAny
                        is Long -> leadIdAny.toString()
                        is Double -> leadIdAny.toInt().toString()
                        else -> null
                    }

                    val leadName = intent?.getStringExtra("lead_name")
                    val clientType = intent?.getStringExtra("client_type")
                    val calledBy = intent?.getStringExtra("called_by")
                    val contactNumber = intent?.getStringExtra("contact_number")
                        ?: intent?.data?.schemeSpecificPart
                        
                    // Prevent infinite auto-dial loops on resume by clearing the consumed contact number
                    intent?.removeExtra("contact_number")
                    intent?.data = null

                    result.success(mapOf(
                        "lead_id" to leadId,
                        "lead_name" to leadName,
                        "client_type" to clientType,
                        "called_by" to calledBy,
                        "contact_number" to contactNumber
                    ))
                }
                "clearLeadData" -> {
                    // Wipes the intent to prevent infinite autodialing loop from background resumption
                    intent?.replaceExtras(Bundle())
                    intent?.data = null
                    setIntent(intent)
                    result.success(true)
                }
                "toggleSpeaker" -> {
                    val isOn = call.argument<Boolean>("isOn") ?: false
                    CallRecordingService.activeInstance?.setSpeakerphoneOn(isOn)
                    result.success(true)
                }
                "toggleMute" -> {
                    val isMuted = call.argument<Boolean>("isMuted") ?: false
                    CallRecordingService.activeInstance?.setCallMute(isMuted)
                    result.success(true)
                }
                "getCallLogs" -> {
                    val limit = call.argument<Int>("limit") ?: 50
                    val offset = call.argument<Int>("offset") ?: 0
                    val logs = getCallLogs(limit, offset)
                    result.success(logs)
                }
                "isAccessibilityServiceEnabled" -> {
                    val isEnabled = isAccessibilityServiceEnabled()
                    result.success(isEnabled)
                }
                "openAccessibilitySettings" -> {
                    openAccessibilitySettings()
                    result.success(true)
                }
                "requestRole" -> {
                    val role = call.argument<String>("role")
                    if (role != null) {
                        requestRole(role)
                        result.success(true)
                    } else {
                        result.error("invalid_argument", "Role is null", null)
                    }
                }
                "openDefaultAppsSettings" -> {
                    openDefaultAppsSettings()
                    result.success(true)
                }
                "deleteCallLogs" -> {
                    val ids = call.argument<List<String>>("ids")
                    if (ids != null) {
                        val deletedCount = deleteCallLogs(ids)
                        result.success(deletedCount)
                    } else {
                        result.error("invalid_argument", "IDs list is null", null)
                    }
                }
                "startRecord" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val success = CallRecordingService.activeInstance?.startRecording(path) ?: false
                        result.success(success)
                    } else {
                         result.error("invalid_argument", "Path is null", null)
                    }
                }
                "stopRecord" -> {
                     val success = CallRecordingService.activeInstance?.stopRecording() ?: false
                     result.success(success)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        var methodChannel: MethodChannel? = null
        private const val REQUEST_CODE_SET_DEFAULT_DIALER = 123
        
        fun sendEvent(event: String, data: Map<String, Any?>) {
            Handler(Looper.getMainLooper()).post {
                methodChannel?.invokeMethod(event, data)
            }
        }
    }

    private fun requestDefaultDialer() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = getSystemService(RoleManager::class.java)
                if (roleManager != null && roleManager.isRoleAvailable(RoleManager.ROLE_DIALER)) {
                    if (!roleManager.isRoleHeld(RoleManager.ROLE_DIALER)) {
                        val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_DIALER)
                        startActivityForResult(intent, REQUEST_CODE_SET_DEFAULT_DIALER)
                    }
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                if (packageName != telecomManager.defaultDialerPackage) {
                    val intent = Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER).apply {
                        putExtra(TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME, packageName)
                    }
                    startActivity(intent)
                }
            }
        } catch (e: Exception) {
            println("Error requesting default dialer: $e")
        }
    }

    private fun isDefaultDialer(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = getSystemService(RoleManager::class.java)
                roleManager?.isRoleHeld(RoleManager.ROLE_DIALER) == true
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                packageName == telecomManager.defaultDialerPackage
            } else {
                false
            }
        } catch (e: Exception) {
            println("Error checking default dialer: ${e.message}")
            false
        }
    }


    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Enable showing over lock screen and turning screen on for incoming calls
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        window.addFlags(
            android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            android.view.WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
        )
        
        handleIncomingCallIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingCallIntent(intent)
    }

    private fun handleIncomingCallIntent(intent: Intent?) {
        intent?.let {
            val isIncoming = it.getBooleanExtra("isIncomingCall", false)
            val phoneNumber = it.getStringExtra("phoneNumber")
            if (isIncoming && phoneNumber != null) {
                // Determine if this is a cold start by checking if Flutter is ready. 
                // A safer approach than a fixed 1-second delay is a tiny delay only if needed, 
                // but let's drop it to 100ms for incoming ringing, and 0 for outgoing.
                Handler(Looper.getMainLooper()).postDelayed({
                    sendEvent("call_state_changed", mapOf(
                        "phoneNumber" to phoneNumber,
                        "state" to "ringing"
                    ))
                }, 100)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SET_DEFAULT_DIALER) {
            val isDefault = isDefaultDialer()
            sendEvent("default_dialer_result", mapOf("isDefault" to isDefault))
        } else if (requestCode == REQUEST_CODE_SET_ROLE) {
            // General role request result handler can be added here if needed
            Log.d("MainActivity", "Role request completed")
        }
    }

    private fun makeCall(phoneNumber: String) {
        Log.d("MainActivity", "makeCall requested for: $phoneNumber")
        val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val isOurAppDefault = isDefaultDialer()
        Log.d("MainActivity", "isDefaultDialer: $isOurAppDefault")

        val uri = Uri.fromParts("tel", phoneNumber, null)
        val extras = Bundle()

        if (checkSelfPermission(android.Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED) {
            if (isOurAppDefault) {
                Log.d("MainActivity", "Placing integrated call via TelecomManager")
                try {
                    telecomManager.placeCall(uri, extras)
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error in placeCall: ${e.message}")
                    // Fallback to intent
                    val intent = Intent(Intent.ACTION_CALL).apply {
                        data = uri
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                }
            } else {
                Log.d("MainActivity", "Not default dialer, using ACTION_CALL intent")
                val intent = Intent(Intent.ACTION_CALL).apply {
                    data = uri
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
            }
        } else {
            Log.e("MainActivity", "CALL_PHONE permission not granted")
        }
    }

    private fun getCallLogs(limit: Int, offset: Int): List<Map<String, Any?>> {
        val logs = mutableListOf<Map<String, Any?>>()
        if (checkSelfPermission(android.Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
            return logs
        }

        val projection = arrayOf(
            android.provider.CallLog.Calls._ID,
            android.provider.CallLog.Calls.NUMBER,
            android.provider.CallLog.Calls.CACHED_NAME,
            android.provider.CallLog.Calls.TYPE,
            android.provider.CallLog.Calls.DATE,
            android.provider.CallLog.Calls.DURATION
        )

        val sortOrder = "${android.provider.CallLog.Calls.DATE} DESC LIMIT $limit OFFSET $offset"

        try {
            contentResolver.query(
                android.provider.CallLog.Calls.CONTENT_URI,
                projection,
                null,
                null,
                sortOrder
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndex(android.provider.CallLog.Calls._ID)
                val numberIndex = cursor.getColumnIndex(android.provider.CallLog.Calls.NUMBER)
                val nameIndex = cursor.getColumnIndex(android.provider.CallLog.Calls.CACHED_NAME)
                val typeIndex = cursor.getColumnIndex(android.provider.CallLog.Calls.TYPE)
                val dateIndex = cursor.getColumnIndex(android.provider.CallLog.Calls.DATE)
                val durationIndex = cursor.getColumnIndex(android.provider.CallLog.Calls.DURATION)

                while (cursor.moveToNext()) {
                    val log = mapOf(
                        "id" to cursor.getLong(idIndex).toString(),
                        "number" to cursor.getString(numberIndex),
                        "name" to cursor.getString(nameIndex),
                        "type" to cursor.getInt(typeIndex),
                        "timestamp" to cursor.getLong(dateIndex),
                        "duration" to cursor.getInt(durationIndex)
                    )
                    logs.add(log)
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error querying call log: ${e.message}")
        }
        return logs
    }

    private fun deleteCallLogs(ids: List<String>): Int {
        if (checkSelfPermission(android.Manifest.permission.WRITE_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
            return 0
        }
        
        var deletedTotal = 0
        try {
            // Delete in batches to avoid URI length issues
            for (id in ids) {
                val where = "${android.provider.CallLog.Calls._ID} = ?"
                val selectionArgs = arrayOf(id)
                deletedTotal += contentResolver.delete(
                    android.provider.CallLog.Calls.CONTENT_URI,
                    where,
                    selectionArgs
                )
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error deleting call logs: ${e.message}")
        }
        return deletedTotal
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val service = "$packageName/${CallAccessibilityService::class.java.canonicalName}"
        val enabledServices = android.provider.Settings.Secure.getString(
            contentResolver,
            android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        )
        return enabledServices?.contains(service) == true
    }

    private fun openAccessibilitySettings() {
        val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun openDefaultAppsSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val intent = Intent(android.provider.Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } else {
            // Fallback for older versions if needed, though most modern apps use RoleManager for critical ones
            val intent = Intent(android.provider.Settings.ACTION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        }
    }

    private fun requestRole(role: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = getSystemService(RoleManager::class.java)
                if (roleManager != null && roleManager.isRoleAvailable(role)) {
                    if (!roleManager.isRoleHeld(role)) {
                        val intent = roleManager.createRequestRoleIntent(role)
                        startActivityForResult(intent, REQUEST_CODE_SET_ROLE)
                    }
                }
            } else {
                // Legacy support for specific roles if needed
                if (role == RoleManager.ROLE_DIALER) {
                    requestDefaultDialer()
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error requesting role $role: ${e.message}")
        }
    }

    private val REQUEST_CODE_SET_ROLE = 124

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            val callService = CallRecordingService.activeInstance
            // Check if we have an incoming call ringing
            val isRinging = callService?.isCallRinging() == true
            if (isRinging) {
                // If it's ringing, consume the event and tell Flutter to silence the ringing
                sendEvent("silence_ringer", emptyMap<String, Any>())
                return true 
            }
            
            // If it's an active call, let the system handle volume changes via STREAM_VOICE_CALL
            // If not, use the default stream type so normal volume control works.
            if (callService != null && callService.hasActiveCall()) {
                volumeControlStream = android.media.AudioManager.STREAM_VOICE_CALL
            } else {
                volumeControlStream = android.media.AudioManager.USE_DEFAULT_STREAM_TYPE
            }
        }
        return super.onKeyDown(keyCode, event)
    }
}
