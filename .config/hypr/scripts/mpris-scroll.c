#include <glib.h>
#include <glib-object.h>
#include <playerctl/playerctl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEFAULT_WIDTH 34
#define DEFAULT_FRAME_MS 140
#define PAUSE_FRAMES 14       /* Hold ~2 seconds at start and end of scroll */
#define GONE_GRACE_MS 2500    /* 2.5 second grace period before hiding when no player detected */

typedef struct {
	PlayerctlPlayerManager *manager;
	GPtrArray *players;

	gchar *status;
	gchar *player_name;
	gchar *artist;
	gchar *title;

	gint width;
	guint frame_ms;
	gint offset;
	gint dir;
	gint pause_ticks;

	gboolean is_active;
	guint timer_id;
	guint gone_timer_id;
	gchar *last_frame;
} App;

static App app;

static gchar *
json_escape(const gchar *s)
{
	GString *out = g_string_new(NULL);
	for (const gchar *p = s; *p; p++) {
		switch (*p) {
		case '\\': g_string_append(out, "\\\\"); break;
		case '"':  g_string_append(out, "\\\""); break;
		case '\t': g_string_append(out, "\\t"); break;
		case '\n': g_string_append(out, "\\n"); break;
		default:   g_string_append_c(out, *p); break;
		}
	}
	return g_string_free(out, FALSE);
}

static gint
char_columns(gunichar ch)
{
	if (g_unichar_iszerowidth(ch))
		return 0;
	return (g_unichar_iswide_cjk(ch) || g_unichar_iswide(ch)) ? 2 : 1;
}

static gint
utf8_display_width(const gchar *s)
{
	gint w = 0;
	for (const gchar *p = s; *p; p = g_utf8_next_char(p))
		w += char_columns(g_utf8_get_char(p));
	return w;
}

static gint
compute_max_offset(const gchar *s, gint width)
{
	gint total_glyphs = (gint)g_utf8_strlen(s, -1);
	if (total_glyphs <= 0)
		return 0;

	const gchar *p = s;
	gint max_off = 0;
	for (gint i = 0; i < total_glyphs; i++) {
		gint rem_width = utf8_display_width(p);
		if (rem_width <= width) {
			max_off = i;
			break;
		}
		max_off = i;
		p = g_utf8_next_char(p);
	}
	return max_off;
}

static gchar *
center_text(const gchar *s, gint width, gint total_cols)
{
	if (total_cols >= width)
		return g_strdup(s);
	gint pad_left = (width - total_cols) / 2;
	gint pad_right = width - total_cols - pad_left;
	GString *out = g_string_new(NULL);
	for (gint i = 0; i < pad_left; i++)
		g_string_append_c(out, ' ');
	g_string_append(out, s);
	for (gint i = 0; i < pad_right; i++)
		g_string_append_c(out, ' ');
	return g_string_free(out, FALSE);
}

static gchar *
slice_window(const gchar *s, gint glyph_offset, gint width)
{
	GString *out = g_string_new(NULL);
	const gchar *p = s;
	for (gint i = 0; i < glyph_offset && *p; i++)
		p = g_utf8_next_char(p);

	gint used = 0;
	while (*p && used < width) {
		gunichar ch = g_utf8_get_char(p);
		gint cw = char_columns(ch);
		if (used + cw > width) {
			/* Wide char cannot fit in the last 1 column, pad 1 space */
			g_string_append_c(out, ' ');
			used++;
			break;
		}
		const gchar *next = g_utf8_next_char(p);
		g_string_append_len(out, p, (gssize)(next - p));
		used += cw;
		p = next;
	}
	while (used < width) {
		g_string_append_c(out, ' ');
		used++;
	}
	return g_string_free(out, FALSE);
}

static void
emit_frame(void)
{
	gchar *esc_text = NULL;
	gchar *esc_tip = NULL;
	gchar *tip = NULL;
	gchar *frame = NULL;
	gchar *text = NULL;
	gchar *combined = NULL;
	const gchar *status = app.status ? app.status : "Stopped";
	gboolean active = app.is_active && (strcmp(status, "Playing") == 0 || strcmp(status, "Paused") == 0);

	if (active && ((app.title && *app.title) || (app.artist && *app.artist))) {
		const gchar *a = (app.artist && *app.artist) ? app.artist : "";
		const gchar *t = (app.title && *app.title) ? app.title : "";
		if (*a && *t)
			combined = g_strdup_printf("%s - %s", a, t);
		else if (*t)
			combined = g_strdup(t);
		else
			combined = g_strdup(a);

		gint total = utf8_display_width(combined);

		if (total <= app.width) {
			text = center_text(combined, app.width, total);
		} else {
			gint max_offset = compute_max_offset(combined, app.width);
			if (strcmp(status, "Playing") == 0) {
				if (app.pause_ticks > 0) {
					app.pause_ticks--;
				} else {
					app.offset += app.dir;
					if (app.offset >= max_offset) {
						app.offset = max_offset;
						app.dir = -1;
						app.pause_ticks = PAUSE_FRAMES;
					} else if (app.offset <= 0) {
						app.offset = 0;
						app.dir = 1;
						app.pause_ticks = PAUSE_FRAMES;
					}
				}
			}
			text = slice_window(combined, app.offset, app.width);
		}
		tip = g_strdup_printf("%s: %s - %s - %s\nLeft Click: previous\nMid Click: Play/Pause\nRight Click: Next",
		                      status, app.player_name ? app.player_name : "",
		                      app.artist ? app.artist : "", app.title ? app.title : "");
	} else {
		text = g_strdup("");
		tip = g_strdup("");
	}

	esc_text = json_escape(text);
	esc_tip = json_escape(tip);
	frame = g_strdup_printf("{\"text\":\"%s\",\"tooltip\":\"%s\",\"alt\":\"%s\",\"class\":\"%s\"}",
	                        esc_text, esc_tip, (*text ? status : "Stopped"), (*text ? status : "Stopped"));

	if (!app.last_frame || strcmp(frame, app.last_frame) != 0) {
		printf("%s\n", frame);
		fflush(stdout);
		g_free(app.last_frame);
		app.last_frame = g_strdup(frame);
	}

	g_free(frame);
	g_free(esc_tip);
	g_free(tip);
	g_free(esc_text);
	g_free(text);
	g_free(combined);
}

static gboolean
on_timer(gpointer user_data)
{
	emit_frame();
	return TRUE;
}

static void
sync_timer(void)
{
	if (app.timer_id) {
		g_source_remove(app.timer_id);
		app.timer_id = 0;
	}
	if (app.is_active && app.status && strcmp(app.status, "Playing") == 0) {
		const gchar *a = (app.artist && *app.artist) ? app.artist : "";
		const gchar *t = (app.title && *app.title) ? app.title : "";
		gchar *combined = NULL;
		if (*a && *t)
			combined = g_strdup_printf("%s - %s", a, t);
		else if (*t)
			combined = g_strdup(t);
		else
			combined = g_strdup(a);

		if (combined && utf8_display_width(combined) > app.width) {
			app.timer_id = g_timeout_add(app.frame_ms, on_timer, NULL);
		}
		g_free(combined);
	}
}

static const gchar *
get_player_playback_status(PlayerctlPlayer *p)
{
	PlayerctlPlaybackStatus st = PLAYERCTL_PLAYBACK_STATUS_STOPPED;
	g_object_get(p, "playback-status", &st, NULL);
	switch (st) {
	case PLAYERCTL_PLAYBACK_STATUS_PLAYING: return "Playing";
	case PLAYERCTL_PLAYBACK_STATUS_PAUSED:  return "Paused";
	default:                                return "Stopped";
	}
}

static gboolean
on_gone_timeout(gpointer user_data)
{
	app.gone_timer_id = 0;
	app.is_active = FALSE;
	g_free(app.status);
	g_free(app.player_name);
	g_free(app.artist);
	g_free(app.title);
	app.status = g_strdup("Stopped");
	app.player_name = g_strdup("");
	app.artist = g_strdup("");
	app.title = g_strdup("");

	sync_timer();
	emit_frame();
	return G_SOURCE_REMOVE;
}

static void refresh_active(PlayerctlPlayer *player, gpointer unused, gpointer user_data);
static void on_player_vanished(PlayerctlPlayer *player, gpointer user_data);

static void
add_player(PlayerctlPlayer *p)
{
	g_ptr_array_add(app.players, p);
	g_signal_connect(p, "metadata", G_CALLBACK(refresh_active), NULL);
	g_signal_connect(p, "playback-status", G_CALLBACK(refresh_active), NULL);
	g_signal_connect(p, "exit", G_CALLBACK(on_player_vanished), NULL);
}

static void
refresh_active(PlayerctlPlayer *player, gpointer unused, gpointer user_data)
{
	PlayerctlPlayer *best = NULL;
	const gchar *best_status = NULL;

	/* Priority: Playing > Paused > Stopped */
	for (guint i = 0; i < app.players->len; i++) {
		PlayerctlPlayer *p = g_ptr_array_index(app.players, i);
		const gchar *st = get_player_playback_status(p);

		if (!best) {
			best = p;
			best_status = st;
		} else if (strcmp(st, "Playing") == 0) {
			if (strcmp(best_status, "Playing") != 0) {
				best = p;
				best_status = st;
			}
		} else if (strcmp(st, "Paused") == 0) {
			if (strcmp(best_status, "Playing") != 0 && strcmp(best_status, "Paused") != 0) {
				best = p;
				best_status = st;
			}
		}
	}

	gboolean has_media = FALSE;

	if (best && (strcmp(best_status, "Playing") == 0 || strcmp(best_status, "Paused") == 0)) {
		GError *err = NULL;
		gchar *title = NULL;
		gchar *artist = NULL;
		gchar *name = NULL;

		g_object_get(best, "player-name", &name, NULL);
		title = playerctl_player_get_title(best, &err);
		if (err) {
			g_clear_error(&err);
			title = NULL;
		}
		artist = playerctl_player_get_artist(best, &err);
		if (err) {
			g_clear_error(&err);
			artist = NULL;
		}

		if ((title && *title) || (artist && *artist)) {
			has_media = TRUE;

			/* Cancel pending gone timeout because we found an active player */
			if (app.gone_timer_id) {
				g_source_remove(app.gone_timer_id);
				app.gone_timer_id = 0;
			}

			gboolean track_changed = (g_strcmp0(app.title, title) != 0 || g_strcmp0(app.artist, artist) != 0);

			g_free(app.player_name);
			g_free(app.artist);
			g_free(app.title);
			g_free(app.status);

			app.player_name = name ? name : g_strdup("");
			app.artist = artist ? artist : g_strdup("");
			app.title = title ? title : g_strdup("");
			app.status = g_strdup(best_status);
			app.is_active = TRUE;

			if (track_changed) {
				app.offset = 0;
				app.dir = 1;
				app.pause_ticks = PAUSE_FRAMES;
			}
		} else {
			g_free(name);
			g_free(title);
			g_free(artist);
		}
	}

	if (!has_media) {
		/* If we were previously showing media, start a grace period before declaring it gone */
		if (app.is_active) {
			if (!app.gone_timer_id) {
				app.gone_timer_id = g_timeout_add(GONE_GRACE_MS, on_gone_timeout, NULL);
			}
		} else {
			/* Already inactive */
			g_free(app.status);
			g_free(app.player_name);
			g_free(app.artist);
			g_free(app.title);
			app.status = g_strdup("Stopped");
			app.player_name = g_strdup("");
			app.artist = g_strdup("");
			app.title = g_strdup("");
			app.is_active = FALSE;
		}
	}

	sync_timer();
	emit_frame();
}

static void
on_player_vanished(PlayerctlPlayer *player, gpointer user_data)
{
	g_ptr_array_remove(app.players, player);
	refresh_active(NULL, NULL, NULL);
}

static gboolean
on_name_appeared(PlayerctlPlayerManager *manager, PlayerctlPlayerName *player_name, gpointer user_data)
{
	GError *err = NULL;
	PlayerctlPlayer *p = playerctl_player_new_from_name(player_name, &err);
	if (!p) {
		g_clear_error(&err);
		return FALSE;
	}
	add_player(p);
	refresh_active(NULL, NULL, NULL);
	return FALSE;
}

int
main(int argc, char **argv)
{
	GError *err = NULL;
	const gchar *width_env = g_getenv("MPRIS_SCROLL_WIDTH");
	const gchar *frame_env = g_getenv("MPRIS_SCROLL_FRAME");

	app.width = width_env ? atoi(width_env) : DEFAULT_WIDTH;
	app.frame_ms = frame_env ? (guint)(atof(frame_env) * 1000) : DEFAULT_FRAME_MS;
	if (app.width < 1)
		app.width = DEFAULT_WIDTH;
	if (app.frame_ms < 1)
		app.frame_ms = DEFAULT_FRAME_MS;

	app.players = g_ptr_array_new();
	app.status = g_strdup("Stopped");
	app.player_name = g_strdup("");
	app.artist = g_strdup("");
	app.title = g_strdup("");
	app.offset = 0;
	app.dir = 1;
	app.pause_ticks = PAUSE_FRAMES;
	app.is_active = FALSE;
	app.timer_id = 0;
	app.gone_timer_id = 0;
	app.last_frame = NULL;

	GMainLoop *loop = g_main_loop_new(NULL, FALSE);

	app.manager = playerctl_player_manager_new(&err);
	if (!app.manager) {
		g_printerr("mpris-scroll: %s\n", err ? err->message : "failed to create manager");
		g_clear_error(&err);
		return 1;
	}

	g_signal_connect(app.manager, "name-appeared", G_CALLBACK(on_name_appeared), NULL);
	g_signal_connect(app.manager, "name-vanished", G_CALLBACK(on_player_vanished), NULL);

	GList *names = playerctl_list_players(&err);
	if (err) {
		g_clear_error(&err);
	}
	for (GList *l = names; l; l = l->next) {
		GError *e = NULL;
		PlayerctlPlayer *p = playerctl_player_new_from_name((PlayerctlPlayerName *)l->data, &e);
		if (p) {
			add_player(p);
		} else if (e) {
			g_clear_error(&e);
		}
	}
	g_list_free(names);

	refresh_active(NULL, NULL, NULL);

	g_main_loop_run(loop);

	return 0;
}