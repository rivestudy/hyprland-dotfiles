-- Hyprland 0.55+ Lua config
-- Colors are provided by matugen as ~/.config/hypr/colors.lua (see configs/looknfeel.lua)

------------------ MONITORS ------------------
hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "0x0", scale = 1 })

------------------ ENVIRONMENT VARIABLES ------
-- See https://wiki.hyprland.org/Configuring/Environment-variables/
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("DBUS_SESSION_BUS_ADDRESS", "unix:path=" .. os.getenv("XDG_RUNTIME_DIR") .. "/bus")

------------------ AUTOSTART ------------------
-- Was exec-once (run only on first launch)
hl.on("hyprland.start", function()
    hl.exec_cmd("brightnessctl set 5%")
    hl.exec_cmd("nm-applet")
    hl.exec_cmd("waybar")
    hl.exec_cmd("swww-daemon")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("swaync")
    hl.exec_cmd("/usr/lib/hyprpolkitagent/hyprpolkitagent")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("~/.config/hypr/scripts/cliphist-listen.sh")
end)

------------------ PERMISSIONS ------------------
-- See https://wiki.hyprland.org/Configuring/Permissions/
-- Please note permission changes here require a Hyprland restart and are not applied on-the-fly
-- for security reasons

-- hl.config({ ecosystem = { enforce_permissions = true } })
-- hl.permission({ executable = "/usr/(bin|local/bin)/grim", action = "screencopy", permission = "allow" })
-- hl.permission({ executable = "/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", action = "screencopy", permission = "allow" })
-- hl.permission({ executable = "/usr/(bin|local/bin)/hyprpm", action = "plugin", permission = "allow" })

------------------ TAGS ------------------
require("configs.tags")

------------------ LOOK AND FEEL ------------------
require("configs.looknfeel")

------------------ ANIMATIONS ------------------
require("configs.animations")

-- Ref https://wiki.hyprland.org/Configuring/Workspace-Rules/
-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]", gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({ match = { float = false, workspace = "w[tv1]" }, border_size = 0 })
-- hl.window_rule({ match = { float = false, workspace = "w[tv1]" }, rounding = 0 })
-- hl.window_rule({ match = { float = false, workspace = "f[1]" }, border_size = 0 })
-- hl.window_rule({ match = { float = false, workspace = "f[1]" }, rounding = 0 })

------------------ WINDOWRULES AND LAYERRULES ------------------
require("configs.windowrules")

-- See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
hl.config({
    dwindle = { preserve_split = true },
})

-- See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
hl.config({
    master = { new_status = "master" },
})

-- https://wiki.hyprland.org/Configuring/Variables/#misc
hl.config({
    misc = {
        force_default_wallpaper = 0, -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo = true, -- If true disables the random hyprland logo / anime girl background. :(
    },
})

hl.config({
    debug = { vfr = true }, -- save resources
})

hl.config({
    render = { new_render_scheduling = true },
})

------------------ INPUT ------------------
require("configs.input")

------------------ KEYBINDS ------------------
require("configs.keybinds")
