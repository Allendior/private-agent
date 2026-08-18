package com.allendior.private_agent_companion

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.app.KeyguardManager
import android.graphics.Path
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo

class CompanionA11yService : AccessibilityService() {
    override fun onServiceConnected() {
        instance = this
    }

    override fun onAccessibilityEvent(event: android.view.accessibility.AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    fun requireUnlocked(): String? {
        val keyguard = getSystemService(KeyguardManager::class.java)
        return if (keyguard?.isKeyguardLocked == true) "LOCKED" else null
    }

    fun tapLabel(label: String): String? {
        val locked = requireUnlocked()
        if (locked != null) return locked
        val root = rootInActiveWindow ?: return "NO_WINDOW"
        val matches = ArrayList<AccessibilityNodeInfo>()
        collectMatches(root, label.trim(), matches)
        if (matches.isEmpty()) return "LABEL_NOT_FOUND"
        if (matches.size > 1) return "LABEL_AMBIGUOUS"
        val node = firstClickable(matches[0]) ?: return "NOT_CLICKABLE"
        return if (node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) null else "TAP_FAILED"
    }

    fun tapXy(x: Int, y: Int): String? {
        val locked = requireUnlocked()
        if (locked != null) return locked
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 50)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return if (dispatchGesture(gesture, null, null)) null else "TAP_FAILED"
    }

    fun press(action: Int): String? {
        val locked = requireUnlocked()
        if (locked != null) return locked
        return if (performGlobalAction(action)) null else "PRESS_FAILED"
    }

    fun typeText(text: String): String? {
        val locked = requireUnlocked()
        if (locked != null) return locked
        val root = rootInActiveWindow ?: return "NO_WINDOW"
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return "NO_FOCUSED_FIELD"
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return if (focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) null else "TYPE_FAILED"
    }

    private fun collectMatches(
        node: AccessibilityNodeInfo,
        label: String,
        out: MutableList<AccessibilityNodeInfo>,
    ) {
        val text = node.text?.toString()?.trim().orEmpty()
        val desc = node.contentDescription?.toString()?.trim().orEmpty()
        if (text.equals(label, ignoreCase = true) || desc.equals(label, ignoreCase = true)) {
            out.add(node)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectMatches(child, label, out)
        }
    }

    private fun firstClickable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var current: AccessibilityNodeInfo? = node
        while (current != null) {
            if (current.isClickable) return current
            current = current.parent
        }
        return null
    }

    companion object {
        @Volatile
        var instance: CompanionA11yService? = null
            private set
    }
}
