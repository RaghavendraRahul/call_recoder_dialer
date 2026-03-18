package com.example.call_record

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.util.Log

class CallAccessibilityService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        // This is called when an accessibility event occurs.
        // We can monitor window state changes to detect when a call app is active.
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val packageName = event.packageName?.toString()
            Log.d("CallAccessibility", "Window state changed for package: $packageName")
            
            // We can notify Flutter if needed about specific window changes
            if (packageName == "com.android.phone" || packageName == "com.google.android.dialer") {
                notifyFlutter("accessibility_call_window_active", mapOf("packageName" to packageName))
            }
        }
    }

    override fun onInterrupt() {
        Log.d("CallAccessibility", "Service interrupted")
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("CallAccessibility", "Service connected")
        notifyFlutter("accessibility_service_connected", mapOf("status" to "connected"))
    }

    private fun notifyFlutter(event: String, data: Map<String, Any?>) {
        try {
            MainActivity.sendEvent(event, data)
        } catch (e: Exception) {
            Log.e("CallAccessibility", "Error notifying Flutter: ${e.message}")
        }
    }
}
