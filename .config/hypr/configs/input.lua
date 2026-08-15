hl.config({
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",

        follow_mouse = 1,
        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.
        accel_profile = "flat",
        force_no_accel = true,

        touchpad = {
            natural_scroll = true,
        },
    },
})

-- https://wiki.hyprland.org/Configuring/Variables/#gestures
-- Was: gesture = 3, horizontal, workspace
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Example per-device config
-- See https://wiki.hyprland.org/Configuring/Keywords/#per-device-input-configs for more
hl.device({ name = "epic-mouse-v1", sensitivity = -0.5 })
