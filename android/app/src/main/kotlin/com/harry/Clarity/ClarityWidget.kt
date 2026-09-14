package com.harry.Clarity

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.action.ActionParameters
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
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
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.actionStartActivity
import org.json.JSONArray
import org.json.JSONObject

/**
 * Clarity home-screen widget v2 (Android). Google-Tasks rhythm: switchable
 * Today/Inbox header, roomy rows, red overdue labels, struck-till-midnight
 * completions (filled circle + dimmed title — Glance has no strikethrough).
 *
 * Display state only: rows render prefs JSON from Dart; the header switch
 * flips prefs in a background isolate (no app open); circle/row taps are
 * deep links applied in the main isolate, which owns the database.
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
        val selected = prefs.getString("selected_list", "today") ?: "today"
        val doc = try {
            JSONObject(prefs.getString("tasks_json", "{}") ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }
        val listKey = if (selected == "inbox") "inbox" else "today"
        val title = if (selected == "inbox") "Inbox" else "Today"
        val count = if (selected == "inbox") {
            prefs.getInt("inbox_count", 0) ?: 0
        } else {
            prefs.getInt("today_count", 0) ?: 0
        }
        val rows = try {
            doc.optJSONArray(listKey) ?: JSONArray()
        } catch (_: Exception) {
            JSONArray()
        }

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(GlanceTheme.colors.surface)
                .padding(horizontal = 14.dp, vertical = 10.dp)
                .clickable(onClick = actionStartActivity<MainActivity>(
                    context, Uri.parse("com.harry.Clarity://today"))),
        ) {
            // Switchable header: tap toggles Today ⇄ Inbox in place.
            Row(
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .padding(bottom = 4.dp)
                    .clickable(onClick = actionRunCallback<SwitchListAction>()),
                verticalAlignment = Alignment.Vertical.CenterVertically,
            ) {
                Text(
                    title,
                    style = TextStyle(
                        fontWeight = FontWeight.Medium,
                        fontSize = 14.sp,
                        color = GlanceTheme.colors.onSurface,
                    ),
                )
                Text(
                    " ▾",
                    style = TextStyle(
                        fontSize = 14.sp,
                        color = GlanceTheme.colors.onSurfaceVariant,
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
            if (rows.length() == 0) {
                Text(
                    if (selected == "inbox") "Inbox zero." else "Nothing due.",
                    style = TextStyle(
                        fontSize = 13.sp,
                        color = GlanceTheme.colors.onSurfaceVariant,
                    ),
                    modifier = GlanceModifier.padding(top = 6.dp),
                )
            }
            for (i in 0 until rows.length()) {
                val obj = rows.optJSONObject(i) ?: continue
                val id = obj.optString("id", "")
                val rowTitle = obj.optString("title", "")
                val due = obj.optString("due", "")
                val done = obj.optString("done", "").isNotEmpty()
                val overdue = obj.optString("overdue", "").isNotEmpty()
                if (id.isEmpty() || rowTitle.isEmpty()) continue
                Row(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .padding(vertical = 7.dp),
                    verticalAlignment = Alignment.Vertical.CenterVertically,
                ) {
                    Text(
                        if (done) "●" else "○",
                        style = TextStyle(
                            fontSize = 20.sp,
                            color = if (done) {
                                GlanceTheme.colors.onSurfaceVariant
                            } else {
                                GlanceTheme.colors.primary
                            },
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
                            rowTitle,
                            maxLines = 1,
                            style = TextStyle(
                                fontSize = 15.sp,
                                color = if (done) {
                                    GlanceTheme.colors.onSurfaceVariant
                                } else {
                                    GlanceTheme.colors.onSurface
                                },
                            ),
                        )
                        if (due.isNotEmpty()) {
                            Text(
                                due,
                                maxLines = 1,
                                style = TextStyle(
                                    fontSize = 12.sp,
                                    color = if (overdue) {
                                        GlanceTheme.colors.error
                                    } else {
                                        GlanceTheme.colors.onSurfaceVariant
                                    },
                                ),
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Header tap: flip Today ⇄ Inbox via the background isolate (no app open). */
class SwitchListAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val backgroundIntent =
            HomeWidgetBackgroundIntent.getBroadcast(
                context,
                Uri.parse("clarity-widget://switch-list"),
            )
        backgroundIntent.send()
    }
}
