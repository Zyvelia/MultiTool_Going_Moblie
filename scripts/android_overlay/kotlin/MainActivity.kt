package com.zsmultitool.multi_tool_remote

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val stepsWidgetChannel = "com.zsmultitool/steps_widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            stepsWidgetChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method == "refresh") {
                val mgr = AppWidgetManager.getInstance(this)
                val component = ComponentName(this, StepsGlanceWidget::class.java)
                val ids = mgr.getAppWidgetIds(component)
                if (ids.isNotEmpty()) {
                    val intent = Intent(this, StepsGlanceWidget::class.java).apply {
                        action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    }
                    sendBroadcast(intent)
                }
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }
}
