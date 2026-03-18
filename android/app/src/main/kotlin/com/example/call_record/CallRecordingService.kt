package com.example.call_record

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telecom.Call
import android.telecom.InCallService
import android.telecom.CallAudioState
import android.view.KeyEvent
import android.content.BroadcastReceiver
import android.content.pm.ServiceInfo
import android.media.AudioManager
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

class CallRecordingService : InCallService() {
    private var currentCall: Call? = null
    private var methodChannel: MethodChannel? = null
    internal var isMuted = false
    internal var isSpeakerOn = false
    private val NOTIFICATION_ID_RINGING = 101
    private val NOTIFICATION_ID_ONGOING = 102
    private val CHANNEL_ID = "active_call_channel"
    private val previousCallStates = mutableMapOf<Call, Int>()

    companion object {
        private const val CHANNEL_NAME = "com.example.call_record/call_service"
        private const val ACTION_MUTE = "com.example.call_record.ACTION_MUTE"
        private const val ACTION_SPEAKER = "com.example.call_record.ACTION_SPEAKER"
        private const val ACTION_END_CALL = "com.example.call_record.ACTION_END_CALL"
        var activeInstance: CallRecordingService? = null
    }

    private var recorder: android.media.MediaRecorder? = null
    private var isRecording = false

    fun isCallRinging(): Boolean {
        return currentCall?.state == Call.STATE_RINGING
    }

    fun hasActiveCall(): Boolean {
        return currentCall != null && currentCall?.state != Call.STATE_DISCONNECTED && currentCall?.state != Call.STATE_DISCONNECTING
    }

    fun startRecording(path: String): Boolean {
        if (isRecording) return false
        
        try {
            recorder = android.media.MediaRecorder().apply {
                setAudioSource(android.media.MediaRecorder.AudioSource.VOICE_COMMUNICATION) // Best for Android 10+ if unfiltered
                setOutputFormat(android.media.MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(android.media.MediaRecorder.AudioEncoder.AAC)
                setOutputFile(path)
                prepare()
                start()
            }
            isRecording = true
            android.util.Log.i("CallRecordingService", "Native recording started at: $path")
            return true
        } catch (e: Exception) {
            android.util.Log.w("CallRecordingService", "VOICE_COMMUNICATION failed, falling back to VOICE_RECOGNITION via Accessibility exemption", e)
            releaseRecorder()
            
            try {
                // Fallback 1: Utilize Accessibility Service exemption for concurrent capture (Android 11+)
                recorder = android.media.MediaRecorder().apply {
                    setAudioSource(android.media.MediaRecorder.AudioSource.VOICE_RECOGNITION)
                    setOutputFormat(android.media.MediaRecorder.OutputFormat.MPEG_4)
                    setAudioEncoder(android.media.MediaRecorder.AudioEncoder.AAC)
                    setOutputFile(path)
                    prepare()
                    start()
                }
                isRecording = true
                android.util.Log.i("CallRecordingService", "Native recording started with VOICE_RECOGNITION (Accessibility) fallback at: $path")
                return true
            } catch (fallbackError1: Exception) {
                android.util.Log.w("CallRecordingService", "VOICE_RECOGNITION failed, falling back to MIC", fallbackError1)
                releaseRecorder()
                
                try {
                    // Fallback 2: For older devices (Android 9/10) that might block VOICE_COMMUNICATION
                    recorder = android.media.MediaRecorder().apply {
                        setAudioSource(android.media.MediaRecorder.AudioSource.MIC)
                        setOutputFormat(android.media.MediaRecorder.OutputFormat.MPEG_4)
                        setAudioEncoder(android.media.MediaRecorder.AudioEncoder.AAC)
                        setOutputFile(path)
                        prepare()
                        start()
                    }
                    isRecording = true
                    android.util.Log.i("CallRecordingService", "Native recording started with MIC fallback at: $path")
                    return true
                } catch (fallbackError2: Exception) {
                    android.util.Log.e("CallRecordingService", "Native recording failed entirely", fallbackError2)
                    fallbackError2.printStackTrace()
                    releaseRecorder()
                    return false
                }
            }
        }
    }

    fun stopRecording(): Boolean {
        if (!isRecording) return false
        
        try {
            recorder?.stop()
            println("Native recording stopped")
            return true
        } catch (e: Exception) {
            println("Native recording failed to stop cleanly: $e")
            return false
        } finally {
            releaseRecorder()
        }
    }

    private fun releaseRecorder() {
        try {
            recorder?.reset()
            recorder?.release()
        } catch (e: Exception) {
            // Ignore
        }
        recorder = null
        isRecording = false
    }

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
        createNotificationChannel()
    }

    override fun onDestroy() {
        super.onDestroy()
        activeInstance = null
        currentCall = null
        stopForegroundCompat()
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        currentCall = call

        // Initialize state tracking immediately
        previousCallStates[call] = call.state

        // Monitor call state changes
        try {
            call.registerCallback(object : Call.Callback() {
                override fun onStateChanged(call: Call, state: Int) {
                    handleCallStateChange(call, state)
                }
            })
        } catch (e: Exception) {
            println("Error registering call callback: $e")
        }

        updateNotification(call)

        // Force Screen On for Incoming Calls (Especially for MIUI/Poco devices)
        if (call.state == Call.STATE_RINGING) {
            try {
                val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                val wakeLock = powerManager.newWakeLock(
                    android.os.PowerManager.FULL_WAKE_LOCK or
                    android.os.PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    android.os.PowerManager.ON_AFTER_RELEASE,
                    "CallRecord::IncomingCallWakeLock"
                )
                wakeLock.acquire(3000) // Wake up for 3 seconds
            } catch (e: Exception) {
                println("Error waking screen: $e")
            }
        }

        // Automatically open UI for incoming and outgoing calls
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                if (call.state == Call.STATE_RINGING) {
                     // Add flag to wake up device screen when launching UI
                     addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            }
            startActivity(intent)
        } catch (e: Exception) {
            println("Error launching activity from service: $e")
        }

        // Notify Flutter about the call
        notifyFlutter("call_added", mapOf(
            "phoneNumber" to getPhoneNumber(call),
            "state" to call.state
        ))
    }


    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        
        // Check for missed call on removal if we haven't already
        val previousState = previousCallStates[call]
        if (call.state == Call.STATE_DISCONNECTED && previousState == Call.STATE_RINGING) {
             val phoneNumber = getPhoneNumber(call)
             showMissedCallNotification(phoneNumber)
        }

        // Always try to stop foreground to ensure notification is gone
        stopForegroundCompat()
        
        // Notify Flutter that call ended (always, to be safe)
        notifyFlutter("call_removed", mapOf(
            "phoneNumber" to getPhoneNumber(call)
        ))

        if (currentCall == call) {
            currentCall = null
        }
        
        previousCallStates.remove(call)
    }

    private fun handleCallStateChange(call: Call, state: Int) {
        val stateString = when (state) {
            Call.STATE_ACTIVE -> "active"
            Call.STATE_RINGING -> "ringing"
            Call.STATE_DIALING -> "dialing"
            Call.STATE_DISCONNECTED -> "disconnected"
            Call.STATE_HOLDING -> "holding"
            else -> "unknown"
        }

        // Missed Call Detection
        val previousState = previousCallStates[call]
        if (state == Call.STATE_DISCONNECTED && previousState == Call.STATE_RINGING) {
            // It was ringing and now it's disconnected -> Missed Call
            val phoneNumber = getPhoneNumber(call) // Get number before details are gone (hopefully)
            showMissedCallNotification(phoneNumber)
        }

        // Update state tracking
        previousCallStates[call] = state

        updateNotification(call)

        notifyFlutter("call_state_changed", mapOf(
            "phoneNumber" to getPhoneNumber(call),
            "state" to stateString
        ))
    }

    private fun getPhoneNumber(call: Call): String {
        val details = call.details
        val handle = details.handle
        return handle?.schemeSpecificPart ?: "Unknown"
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
            println("Error stopping foreground service: $e")
        }
    }

    private fun notifyFlutter(event: String, data: Map<String, Any?>) {
        try {
            MainActivity.sendEvent(event, data)
        } catch (e: Exception) {
            println("Error notifying Flutter: $e")
        }
    }

    override fun onCallAudioStateChanged(audioState: CallAudioState) {
        super.onCallAudioStateChanged(audioState)
        isMuted = audioState.isMuted
        isSpeakerOn = audioState.route == CallAudioState.ROUTE_SPEAKER
        currentCall?.let { updateNotification(it) }

        // Notify Flutter so UI can update buttons
        notifyFlutter("call_audio_state_changed", mapOf(
            "isMuted" to isMuted,
            "isSpeakerOn" to isSpeakerOn
        ))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // 1. Channel for Active/Ongoing Calls (Low Importance)
            val activeChannel = NotificationChannel(CHANNEL_ID, "Active Call", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Notifications for ongoing calls"
            }
            notificationManager.createNotificationChannel(activeChannel)

            // 2. Channel for Incoming Calls (High Importance, SILENT - Audio handled by Flutter)
            val incomingChannel = NotificationChannel(
                "incoming_call_channel_v2", // New ID to reset settings
                "Incoming Calls", 
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for incoming calls"
                enableVibration(false) // Handle vibration in Flutter
                setSound(null, null) // Handle sound in Flutter
            }
            notificationManager.createNotificationChannel(incomingChannel)

            // 3. Channel for Missed Calls (High Importance, visible)
            val missedChannel = NotificationChannel(
                "missed_call_channel",
                "Missed Calls",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Notifications for missed calls"
                enableLights(true)
                setShowBadge(true)
            }
            notificationManager.createNotificationChannel(missedChannel)
        }
    }

    private fun updateNotification(call: Call) {
        val phoneNumber = getPhoneNumber(call)
        val isRinging = call.state == Call.STATE_RINGING
        
        val stateText = when (call.state) {
            Call.STATE_ACTIVE -> "Active"
            Call.STATE_DIALING -> "Dialing"
            Call.STATE_RINGING -> "Incoming Call..."
            else -> "Call ongoing"
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            // Removed EXCLUDE_FROM_RECENTS and NO_USER_ACTION so bringing from background works properly when clicked
            putExtra("isIncomingCall", isRinging)
            putExtra("phoneNumber", phoneNumber)
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent, 
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // Actions
        val muteIntent = Intent(this, NotificationActionReceiver::class.java).apply { action = ACTION_MUTE }
        val speakerIntent = Intent(this, NotificationActionReceiver::class.java).apply { action = ACTION_SPEAKER }
        val endCallIntent = Intent(this, NotificationActionReceiver::class.java).apply { action = ACTION_END_CALL }
        // Answer action for incoming
        val answerIntent = Intent(this, NotificationActionReceiver::class.java).apply { action = "com.example.call_record.ACTION_ANSWER" }

        val mutePendingIntent = PendingIntent.getBroadcast(this, 1, muteIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val speakerPendingIntent = PendingIntent.getBroadcast(this, 2, speakerIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val endCallPendingIntent = PendingIntent.getBroadcast(this, 3, endCallIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val answerPendingIntent = PendingIntent.getBroadcast(this, 4, answerIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        val channelId = if (isRinging) "incoming_call_channel_v2" else CHANNEL_ID
        val priority = if (isRinging) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_LOW

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(if (isRinging) "Incoming Call" else stateText)
            .setContentText(phoneNumber)
            .setPriority(priority)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setAutoCancel(false)

        if (isRinging) {
            builder.setFullScreenIntent(pendingIntent, true) // Crucial for showing UI
            builder.addAction(android.R.drawable.ic_menu_call, "Answer", answerPendingIntent)
            builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Decline", endCallPendingIntent)
        } else {
            builder.addAction(if (isMuted) android.R.drawable.stat_notify_call_mute else android.R.drawable.stat_notify_call_mute, if (isMuted) "Unmute" else "Mute", mutePendingIntent)
            builder.addAction(if (isSpeakerOn) android.R.drawable.stat_sys_speakerphone else android.R.drawable.stat_sys_speakerphone, if (isSpeakerOn) "Phone" else "Speaker", speakerPendingIntent)
            builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "End Call", endCallPendingIntent)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(if (isRinging) NOTIFICATION_ID_RINGING else NOTIFICATION_ID_ONGOING, builder.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(if (isRinging) NOTIFICATION_ID_RINGING else NOTIFICATION_ID_ONGOING, builder.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL)
        } else {
            startForeground(if (isRinging) NOTIFICATION_ID_RINGING else NOTIFICATION_ID_ONGOING, builder.build())
        }

        // Clean up the obsolete notification
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (isRinging) {
            notificationManager.cancel(NOTIFICATION_ID_ONGOING)
        } else {
            notificationManager.cancel(NOTIFICATION_ID_RINGING)
        }
    }

    fun answerCall() {
        currentCall?.answer(0)
    }

    fun rejectCall() {
        currentCall?.disconnect()
    }

    fun endCall(): Boolean {
        val callToDisconnect = currentCall ?: calls.lastOrNull()
        if (callToDisconnect != null) {
            if (callToDisconnect.state != Call.STATE_DISCONNECTED && callToDisconnect.state != Call.STATE_DISCONNECTING) {
                callToDisconnect.disconnect()
                return true
            }
        } else {
            println("endCall failed: No current or active calls found")
        }
        return false
    }

    fun setSpeakerphoneOn(isOn: Boolean) {
        if (isOn) {
            setAudioRoute(CallAudioState.ROUTE_SPEAKER)
        } else {
            setAudioRoute(CallAudioState.ROUTE_EARPIECE)
        }
    }

    fun setCallMute(muted: Boolean) {
        setMuted(muted) // Call standard InCallService method
        // Reinforce with AudioManager
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.isMicrophoneMute = muted
    }

    private fun showMissedCallNotification(phoneNumber: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // Open Call Log (MainActivity)
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent, 
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // Call Back Action
        val callIntent = Intent(Intent.ACTION_DIAL, android.net.Uri.parse("tel:$phoneNumber"))
        val callPendingIntent = PendingIntent.getActivity(
            this, 1, callIntent, 
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = NotificationCompat.Builder(this, "missed_call_channel")
            .setSmallIcon(android.R.drawable.sym_call_missed)
            .setContentTitle("Missed call")
            .setContentText(phoneNumber)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .addAction(android.R.drawable.ic_menu_call, "Call Back", callPendingIntent)

        // Use a unique ID for each missed call (or reuse to stack? unique is better)
        // Using System.currentTimeMillis to generate unique ID
        notificationManager.notify(System.currentTimeMillis().toInt(), builder.build())
    }
}

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        val service = CallRecordingService.activeInstance ?: return

        when (action) {
            "com.example.call_record.ACTION_MUTE" -> {
                val newState = !service.isMuted
                service.setCallMute(newState)
            }
            "com.example.call_record.ACTION_SPEAKER" -> {
                val newState = !service.isSpeakerOn
                service.setSpeakerphoneOn(newState)
            }
            "com.example.call_record.ACTION_END_CALL" -> {
                service.endCall()
            }
            "com.example.call_record.ACTION_ANSWER" -> {
                service.answerCall()
                // Bring app to foreground (notification shade collapses automatically)
                val appIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(appIntent)
            }
        }
    }
}
