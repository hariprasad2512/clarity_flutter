package com.harry.Clarity

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.actionStartActivity
import org.json.JSONArray

/**
 * Clarity home-screen widget (Android). Mirrors the native widget contract:
 * incomplete Today/overdue tasks first, max 6 rows.
 *
 * Data comes from prefs JSON written by Dart (`tasks_json`, `today_count`).
 * Taps are deep links handled in the main isolate — the widget never
 * touches the database: circle → toggle (opens app, completes instantly),
 * row/background → open Today.
 */
class ClarityWidget : GlanceAppWidget() {

    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                Content(context, currentState())
            }
        }
    }

    @Composable
    private fun Content(context: Context, state: HomeWidgetGlanceState) {
        val prefs = state.preferences
        val tasks = try {
            JSONArray(prefs.getString("tasks_json", "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
        val count = prefs.getInt("today_count", 0) ?: 0

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(GlanceTheme.colors.surface)
                .padding(12.dp)
                .clickable(onClick = actionStartActivity<MainActivity>(
                    context, Uri.parse("com.harry.Clarity://today"))),
        ) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.Vertical.CenterVertically,
            ) {
                Text(
                    "Today",
                    style = TextStyle(
                        fontWeight = FontWeight.Medium,
                        fontSize = 14.sp,
                        color = GlanceTheme.colors.onSurface,
                    ),
                )
                Spacer(modifier = GlanceModifier.defaultWeight())
                Text(
                    "$count",
                    style = TextStyle(
                        fontSize = 14.sp,
                        color = GlanceTheme.colors.primary,
                    ),
                )
            }
            if (tasks.length() == 0) {
                Text(
                    "Nothing due. Enjoy the calm.",
                    style = TextStyle(
                        fontSize = 13.sp,
                        color = GlanceTheme.colors.onSurfaceVariant,
                    ),
                    modifier = GlanceModifier.padding(top = 8.dp),
                )
            }
            for (i in 0 until tasks.length()) {
                val obj = tasks.optJSONObject(i) ?: continue
                val id = obj.optString("id", "")
                val title = obj.optString("title", "")
                val due = obj.optString("due", "")
                if (id.isEmpty() || title.isEmpty()) continue
                Row(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .padding(vertical = 5.dp),
                    verticalAlignment = Alignment.Vertical.CenterVertically,
                ) {
                    Text(
                        "○",
                        style = TextStyle(
                            fontSize = 20.sp,
                            color = GlanceTheme.colors.primary,
                        ),
                        modifier = GlanceModifier
                            .padding(end = 10.dp)
                            .clickable(onClick = actionStartActivity<MainActivity>(
                                context,
                                Uri.parse("com.harry.Clarity://widget-toggle?id=$id"),
                            )),
                    )
                    Column {
                        Text(
                            title,
                            maxLines = 1,
                            style = TextStyle(
                                fontSize = 14.sp,
                                color = GlanceTheme.colors.onSurface,
                            ),
                        )
                        if (due.isNotEmpty()) {
                            Text(
                                due,
                                maxLines = 1,
                                style = TextStyle(
                                    fontSize = 12.sp,
                                    color = GlanceTheme.colors.onSurfaceVariant,
                                ),
                            )
                        }
                    }
                }
            }
        }
    }
}
