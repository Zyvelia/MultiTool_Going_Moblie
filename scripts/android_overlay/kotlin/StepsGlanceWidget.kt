package com.zsmultitool.multi_tool_remote

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

/** Reads today's step count written by [StepsWidgetBridge] in Flutter. */
class StepsGlanceWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.steps_widget_today", null)
        val count = raw?.trim()?.removeSurrounding("\"") ?: "—"
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.steps_glance_widget)
            views.setTextViewText(R.id.steps_count, count)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
