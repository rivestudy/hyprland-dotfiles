-- APPLICATIONS BLUR
hl.window_rule({ match = { tag = "multimedia_video*" }, no_blur = true })
hl.window_rule({ match = { tag = "multimedia_video*" }, opacity = "1.0" })
hl.window_rule({ match = { tag = "settings*" }, opacity = "0.8" })
hl.window_rule({ match = { class = "^(org.gnome.Nautilus)$" }, opacity = "0.8" })
hl.window_rule({ match = { class = "^(gedit|org.gnome.TextEditor|mousepad)$" }, opacity = "0.9" })
hl.window_rule({ match = { class = "^(org.pulseaudio.pavucontrol)$" }, opacity = "0.9" })
hl.window_rule({ match = { class = "^(kitty)$" }, opacity = "0.9" })
hl.window_rule({ match = { class = "^(discord|vesktop|org.telegram.desktop)$" }, opacity = "0.85 override 0.7 override 1 override" })
hl.window_rule({ match = { class = "^(Spotify)$" }, opacity = "0.8 override 0.6 override 1 override" })
hl.window_rule({ match = { class = "^(zen)$" }, opacity = "0.9 override 0.7 override 1 override" })
-- hl.window_rule({ match = { tag = "viewer*" }, opacity = "0.8 override 0.6 override 1 override" })

-- LAYER RULES
-- hl.layer_rule({ match = { namespace = "rofi" }, blur = true })
-- hl.layer_rule({ match = { namespace = "rofi" }, ignore_alpha = 0 })
-- hl.layer_rule({ match = { namespace = "rofi" }, ignore_alpha = 0.5 })
-- hl.layer_rule({ match = { namespace = "rofi" }, dim_around = true })
-- hl.layer_rule({ match = { namespace = "rofi" }, animation = "popin 10%" })
-- hl.layer_rule({ match = { namespace = "notifications" }, blur = true })
-- hl.layer_rule({ match = { namespace = "notifications" }, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "waybar" }, blur = true })
-- hl.layer_rule({ match = { namespace = "waybar" }, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "waybar" }, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "swaync-notification-window" }, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "logout_dialog" }, blur = true })

-- SWAYNC BLUR & XRAY
hl.layer_rule({ match = { namespace = "swaync-control-center" }, blur = true })
hl.layer_rule({ match = { namespace = "swaync-notification-window" }, blur = true })
hl.layer_rule({ match = { namespace = "swaync-control-center" }, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "swaync-notification-window" }, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "swaync-control-center" }, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "swaync-notification-window" }, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "swaync-control-center" }, xray = false })
hl.layer_rule({ match = { namespace = "swaync-notification-window" }, xray = false })

-- FLOAT
hl.window_rule({ match = { tag = "settings*" }, float = true })
hl.window_rule({ match = { tag = "viewer*" }, float = true })
hl.window_rule({ match = { tag = "multimedia_video*" }, float = true })
hl.window_rule({ match = { tag = "multimedia_video*" }, size = {900, 506} })
hl.window_rule({ match = { class = "^(org.pulseaudio.pavucontrol)$" }, float = true })
hl.window_rule({ match = { class = "^(org.pulseaudio.pavucontrol)$" }, size = {"50%", "60%"} })

-- Ignore maximize requests from apps. You'll probably like this.
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })

-- Fix some dragging issues with XWayland
hl.window_rule({
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-- POP UPS AND DIALOGUES
hl.window_rule({ match = { title = "^(Save As|Save a File|Pick Files)$" }, float = true })
hl.window_rule({ match = { title = "^(Save As|Save a File|Pick Files)$" }, size = {"50%", "60%"} })
hl.window_rule({ match = { title = "^(Save As|Save a File|Pick Files)$" }, center = true })

hl.window_rule({ match = { initial_title = "Open Files" }, float = true })
hl.window_rule({ match = { initial_title = "Open Files" }, size = {"70%", "60%"} })
