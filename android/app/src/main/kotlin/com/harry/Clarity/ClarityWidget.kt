package com.harry.Clarity

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
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
 * Clarity home-screen widget v3 (Android). Three store sizes (Small 3 rows,
 * Medium 4, Large 6) with Google-Tasks rhythm: switchable Today/Inbox
 * header, real strikethrough titles on completed rows (U+0336 combining
 * stroke — Glance text has no strike style), red overdue labels.
 *
 * Display state only, rendered from prefs JSON:
 * * header tap flips Today ⇄ Inbox in a background isolate (no app open);
 * * circle tap strikes/undoes via a prefs outbox (no app open) — the app
 *   reconciles pending ids on start/resume/pull;
 * * row/background tap opens the app.
 */
class ClarityWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = SizeMode.Exact
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                Content(context, currentState())
            }
        }
    }

    private data class Row(
        val id: String,
        val title: String,
        val due: String,
        val done: Boolean,
        val overdue: Boolean,
    )

    // Combining long stroke overlay: renders as struck text in Roboto
    // (Glance Text has no strikethrough style).
    private fun strike(text: String): String =
        text.map { "${it}\u0336" }.joinToString("")

    @Composable
    private fun Content(context: Context, state: HomeWidgetGlanceState) {
        val prefs = state.preferences
        val selected = prefs.getString("selected_list", "today") ?: "today"
        val doc = try {
            JSONObject(prefs.getString("tasks_json", "{}") ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }
        val pending = try {
            val raw = prefs.getString("pending_strikes", "[]") ?: "[]"
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.optString(it, "") }.toSet()
        } catch (_: Exception) {
            emptySet<String>()
        }

        fun rowsOf(key: String): List<Row> {
            val arr = try {
                doc.optJSONArray(key) ?: JSONArray()
            } catch (_: Exception) {
                JSONArray()
            }
            return (0 until arr.length()).mapNotNull { i ->
                val obj = arr.optJSONObject(i) ?: return@mapNotNull null
                val id = obj.optString("id", "")
                val title = obj.optString("title", "")
                if (id.isEmpty() || title.isEmpty()) return@mapNotNull null
                Row(
                    id = id,
                    title = title,
                    due = obj.optString("due", ""),
                    done = obj.optString("done", "").isNotEmpty() ||
                        pending.contains(id),
                    overdue = obj.optString("overdue", "").isNotEmpty(),
                )
            }
        }

        val listKey = if (selected == "inbox") "inbox_open" else "today_open"
        val title = if (selected == "inbox") "Inbox" else "Today"
        val count = if (selected == "inbox") {
            prefs.getInt("inbox_count", 0) ?: 0
        } else {
            prefs.getInt("today_count", 0) ?: 0
        }

        // Size buckets: Small ≤200dp wide, Medium ≤320dp, else Large.
        val width = LocalSize.current.width
        val maxRows = if (width <= 200.dp) 3 else if (width <= 320.dp) 4 else 6
        val showDue = width > 200.dp

        val open = rowsOf(listKey).filter { !it.done }
        val struck = (rowsOf("struck") + open.filter { pending.contains(it.id) })
            .distinctBy { it.id }
        val room = (maxRows - struck.size).coerceAtLeast(0)
        val displayed = (open.take(room) + struck).take(maxRows)

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(GlanceTheme.colors.surface)
                .padding(horizontal = 14.dp, vertical = 10.dp)
                .clickable(onClick = actionStartActivity<MainActivity>(
                    context, Uri.parse("com.harry.Clarity://today"))),
        ) {
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
                        fontSize = 16.sp,
                        color = GlanceTheme.colors.onSurface,
                    ),
                )
                Text(
                    " ▾",
                    style = TextStyle(
                        fontSize = 16.sp,
                        color = GlanceTheme.colors.onSurfaceVariant,
                    ),
                )
                Spacer(modifier = GlanceModifier.defaultWeight())
                Text(
                    "$count",
                    style = TextStyle(
                        fontSize = 16.sp,
                        color = GlanceTheme.colors.primary,
                    ),
                )
            }
            if (displayed.isEmpty()) {
                Text(
                    if (selected == "inbox") "Inbox zero." else "Nothing due.",
                    style = TextStyle(
                        fontSize = 13.sp,
                        color = GlanceTheme.colors.onSurfaceVariant,
                    ),
                    modifier = GlanceModifier.padding(top = 6.dp),
                )
            }
            for (row in displayed) {
                Row(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .padding(vertical = 7.dp),
                    verticalAlignment = Alignment.Vertical.CenterVertically,
                ) {
                    Text(
                        if (row.done) "●" else "○",
                        style = TextStyle(
                            fontSize = 20.sp,
                            color = if (row.done) {
                                GlanceTheme.colors.onSurfaceVariant
                            } else {
                                GlanceTheme.colors.primary
                            },
                        ),
                        modifier = GlanceModifier
                            .padding(end = 10.dp)
                            .clickable(onClick = actionRunCallback<ToggleStrikeAction>(
                                actionParametersOf(
                                    ActionParameters.Key<String>("taskId") to row.id,
                                ),
                            )),
                    )
                    Column {
                        Text(
                            if (row.done) strike(row.title) else row.title,
                            maxLines = 1,
                            style = TextStyle(
                                fontSize = 15.sp,
                                color = if (row.done) {
                                    GlanceTheme.colors.onSurfaceVariant
                                } else {
                                    GlanceTheme.colors.onSurface
                                },
                            ),
                        )
                        if (showDue && row.due.isNotEmpty()) {
                            Text(
                                row.due,
                                maxLines = 1,
                                style = TextStyle(
                                    fontSize = 12.sp,
                                    color = if (row.overdue && !row.done) {
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
        HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse("clarity-widget://switch-list"),
        ).send()
    }
}

/**
 * Circle tap: strike/undo via the prefs outbox (no app open). The app
 * reconciles pending ids into real completions on start/resume/pull.
 */
class ToggleStrikeAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val id = parameters[ActionParameters.Key<String>("taskId")]
            ?: return
        HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse("com.harry.Clarity://widget-toggle?id=$id"),
        ).send()
    }
}

class ClarityWidgetSmallReceiver :
    es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver<ClarityWidget>() {
    override val glanceAppWidget = ClarityWidget()
}

class ClarityWidgetMediumReceiver :
    es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver<ClarityWidget>() {
    override val glanceAppWidget = ClarityWidget()
}

class ClarityWidgetLargeReceiver :
    es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver<ClarityWidget>() {
    override val glanceAppWidget = ClarityWidget()
}
