package com.youngs.leavesync

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** 홈 화면 위젯: 잔여 연차 / 총 연차, 다음 초기화일 표시. 탭하면 앱 실행 */
class LeaveWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.leave_widget).apply {
                val remaining = widgetData.getString("remaining", null)
                val total = widgetData.getString("total", null)
                val progress = widgetData.getInt("progress", 0)
                val resetDate = widgetData.getString("reset_date", "") ?: ""
                val dday = widgetData.getString("dday", "") ?: ""

                if (remaining == null || total == null) {
                    setTextViewText(R.id.widget_remaining, "--")
                    setTextViewText(R.id.widget_total, "앱을 열어 동기화하세요")
                    setTextViewText(R.id.widget_reset, "")
                    setProgressBar(R.id.widget_progress, 100, 0, false)
                } else {
                    setTextViewText(R.id.widget_remaining, remaining)
                    setTextViewText(R.id.widget_total, "/ $total")
                    val resetText = when {
                        resetDate.isEmpty() -> ""
                        dday.isEmpty() -> "초기화 $resetDate"
                        else -> "초기화 $resetDate ($dday)"
                    }
                    setTextViewText(R.id.widget_reset, resetText)
                    setProgressBar(R.id.widget_progress, 100, progress, false)
                }

                val pendingIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_container, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
