#!/usr/bin/env python3
# =============================================================================
# Brutalist 3D/Tilted Carousel Wallpaper Picker with Live Desktop Fade
# Native Python 3 + GTK 3 + Cairo 60 FPS animated carousel
# =============================================================================
import os
import sys
import glob
import math
import time
import subprocess
import threading

import cairo
import gi
gi.require_version('Gtk', '3.0')
gi.require_version('GdkPixbuf', '2.0')
from gi.repository import Gtk, Gdk, GLib, GdkPixbuf, Pango

WALLPAPER_DIR = os.path.expanduser("~/Pictures/wallpapers")
SYMLINK_PATH = os.path.expanduser("~/.config/hypr/current_wallpaper")
COLOR_FILE = os.path.expanduser("~/.config/rofi/colors.rasi")

CARD_WIDTH = 460
CARD_HEIGHT = 260
CARD_SPACING = 370

def load_theme_colors():
    colors = {
        "primary": (0.50, 0.83, 0.86),       # #80d4dc
        "outline": (0.54, 0.58, 0.58),       # #899393
        "outline_variant": (0.25, 0.28, 0.29),# #3f4849
        "surface": (0.05, 0.08, 0.08),       # #0e1415
        "on_surface": (0.87, 0.89, 0.89),    # #dee4e4
    }
    if os.path.exists(COLOR_FILE):
        try:
            with open(COLOR_FILE, "r") as f:
                for line in f:
                    line = line.strip()
                    if ":" in line and line.endswith(";"):
                        parts = line[:-1].split(":")
                        key = parts[0].strip().replace("-", "_")
                        val = parts[1].strip()
                        if val.startswith("#") and len(val) == 7:
                            r = int(val[1:3], 16) / 255.0
                            g = int(val[3:5], 16) / 255.0
                            b = int(val[5:7], 16) / 255.0
                            colors[key] = (r, g, b)
        except Exception:
            pass
    return colors

THEME = load_theme_colors()

class WallpaperCarousel(Gtk.Window):
    def __init__(self):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)

        GLib.set_prgname("wallpaper-carousel")
        GLib.set_application_name("wallpaper-carousel")
        self.set_title("Wallpaper Carousel")
        self.set_default_size(1080, 580)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_decorated(False)
        self.set_app_paintable(True)

        # Translucent visual
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual and screen.is_composited():
            self.set_visual(visual)

        # Wallpapers list
        self.wallpapers = self.scan_wallpapers()
        if not self.wallpapers:
            print("No wallpapers found in", WALLPAPER_DIR)
            sys.exit(1)

        # Initial active wallpaper
        self.initial_wallpaper = None
        self.current_index = 0
        if os.path.islink(SYMLINK_PATH):
            try:
                target = os.path.realpath(SYMLINK_PATH)
                if target in self.wallpapers:
                    self.current_index = self.wallpapers.index(target)
                    self.initial_wallpaper = target
            except Exception:
                pass
        if not self.initial_wallpaper and self.wallpapers:
            self.initial_wallpaper = self.wallpapers[0]

        # Animation states
        self.anim_progress = 0.0       # smooth transition offset
        self.is_animating = False
        self.anim_timer_id = None
        self.preview_timer_id = None
        self.applied = False

        # Thumbnail cache
        self.pixbuf_cache = {}
        self.cache_lock = threading.Lock()

        # UI container
        self.draw_area = Gtk.DrawingArea()
        self.draw_area.connect("draw", self.on_draw)
        self.add(self.draw_area)

        # Event handling
        self.add_events(
            Gdk.EventMask.KEY_PRESS_MASK |
            Gdk.EventMask.BUTTON_PRESS_MASK |
            Gdk.EventMask.SCROLL_MASK |
            Gdk.EventMask.POINTER_MOTION_MASK
        )
        self.connect("key-press-event", self.on_key_press)
        self.connect("button-press-event", self.on_button_press)
        self.connect("scroll-event", self.on_scroll)
        self.connect("destroy", self.on_destroy)

        # Preload initial batch
        self.preload_around(self.current_index)

    def scan_wallpapers(self):
        exts = ("*.jpg", "*.png", "*.jpeg", "*.webp", "*.gif")
        files = []
        for ext in exts:
            files.extend(glob.glob(os.path.join(WALLPAPER_DIR, ext)))
            files.extend(glob.glob(os.path.join(WALLPAPER_DIR, ext.upper())))
        # Sort newest first
        files.sort(key=lambda f: os.path.getmtime(f), reverse=True)
        return files

    def get_pixbuf(self, path):
        with self.cache_lock:
            if path in self.pixbuf_cache:
                return self.pixbuf_cache[path]

        try:
            pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, CARD_WIDTH, CARD_HEIGHT, False)
            with self.cache_lock:
                self.pixbuf_cache[path] = pb
            return pb
        except Exception:
            return None

    def preload_around(self, index):
        def worker():
            indices = [index, (index + 1) % len(self.wallpapers), (index - 1) % len(self.wallpapers),
                       (index + 2) % len(self.wallpapers), (index - 2) % len(self.wallpapers)]
            for i in indices:
                path = self.wallpapers[i]
                with self.cache_lock:
                    if path in self.pixbuf_cache:
                        continue
                try:
                    pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, CARD_WIDTH, CARD_HEIGHT, False)
                    with self.cache_lock:
                        self.pixbuf_cache[path] = pb
                except Exception:
                    pass
        threading.Thread(target=worker, daemon=True).start()

    def navigate(self, direction):
        # direction: +1 for Next, -1 for Prev
        n = len(self.wallpapers)
        self.current_index = (self.current_index + direction) % n
        self.anim_progress += float(direction)

        self.start_animation()
        self.preload_around(self.current_index)
        self.schedule_desktop_preview()

    def start_animation(self):
        if not self.is_animating:
            self.is_animating = True
            self.anim_timer_id = GLib.timeout_add(16, self.on_anim_tick)

    def on_anim_tick(self):
        # Easing towards 0.0
        diff = -self.anim_progress
        if abs(diff) < 0.005:
            self.anim_progress = 0.0
            self.is_animating = False
            self.draw_area.queue_draw()
            return False

        # Fast snappy brutalist ease
        self.anim_progress += diff * 0.26
        self.draw_area.queue_draw()
        return True

    def schedule_desktop_preview(self):
        if self.preview_timer_id:
            GLib.source_remove(self.preview_timer_id)

        # 180ms debounce so rapid navigation doesn't lag swww
        self.preview_timer_id = GLib.timeout_add(180, self.trigger_desktop_preview)

    def trigger_desktop_preview(self):
        self.preview_timer_id = None
        current_wall = self.wallpapers[self.current_index]
        subprocess.Popen(
            ["swww", "img", current_wall, "--transition-type", "fade", "--transition-duration", "1.2", "--transition-fps", "60"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        return False

    def on_key_press(self, widget, event):
        key = event.keyval
        state = event.state

        is_shift = bool(state & Gdk.ModifierType.SHIFT_MASK)

        if key in (Gdk.KEY_Tab, Gdk.KEY_Right, Gdk.KEY_l, Gdk.KEY_j):
            if is_shift and key == Gdk.KEY_Tab:
                self.navigate(-1)
            else:
                self.navigate(1)
            return True
        elif key in (Gdk.KEY_ISO_Left_Tab, Gdk.KEY_Left, Gdk.KEY_h, Gdk.KEY_k):
            self.navigate(-1)
            return True
        elif key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_space):
            self.apply_and_close()
            return True
        elif key in (Gdk.KEY_Escape, Gdk.KEY_q):
            self.cancel_and_close()
            return True
        return False

    def on_scroll(self, widget, event):
        if event.direction in (Gdk.ScrollDirection.UP, Gdk.ScrollDirection.RIGHT):
            self.navigate(1)
            return True
        elif event.direction in (Gdk.ScrollDirection.DOWN, Gdk.ScrollDirection.LEFT):
            self.navigate(-1)
            return True
        return False

    def on_button_press(self, widget, event):
        alloc = self.get_allocation()
        cx = alloc.width / 2.0
        if event.type == Gdk.EventType.BUTTON_PRESS:
            if event.x < cx - CARD_SPACING / 2.0:
                self.navigate(-1)
            elif event.x > cx + CARD_SPACING / 2.0:
                self.navigate(1)
            else:
                # Center card clicked
                if event.type == Gdk.EventType._2BUTTON_PRESS:
                    self.apply_and_close()
            return True
        return False

    def apply_and_close(self):
        self.applied = True
        selected = self.wallpapers[self.current_index]

        # 1. Update symlink
        os.makedirs(os.path.dirname(SYMLINK_PATH), exist_ok=True)
        if os.path.exists(SYMLINK_PATH) or os.path.islink(SYMLINK_PATH):
            os.remove(SYMLINK_PATH)
        os.symlink(selected, SYMLINK_PATH)

        # 2. Run matugen
        subprocess.Popen(["matugen", "image", "--prefer=lightness", selected],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        # 3. Permanent wallpaper set
        subprocess.Popen(["swww", "img", selected, "--transition-type", "fade", "--transition-duration", "1.5", "--transition-fps", "60"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        # 4. Notify
        name = os.path.basename(selected)
        subprocess.Popen(["notify-send", "-u", "low", "Wallpaper Applied", name],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        self.destroy()

    def cancel_and_close(self):
        # Revert desktop to initial wallpaper
        if self.initial_wallpaper and os.path.exists(self.initial_wallpaper):
            subprocess.Popen(["swww", "img", self.initial_wallpaper, "--transition-type", "fade", "--transition-duration", "0.8"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.destroy()

    def on_destroy(self, widget):
        if not self.applied and self.initial_wallpaper:
            subprocess.Popen(["swww", "img", self.initial_wallpaper, "--transition-type", "fade", "--transition-duration", "0.8"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        Gtk.main_quit()

    def on_draw(self, widget, cr):
        alloc = widget.get_allocation()
        width = alloc.width
        height = alloc.height
        cx = width / 2.0
        cy = height / 2.0 - 25

        # 1. Background Window Canvas: Brutalist Dark Glass
        cr.set_source_rgba(THEME["surface"][0], THEME["surface"][1], THEME["surface"][2], 0.90)
        cr.rectangle(0, 0, width, height)
        cr.fill()

        # Window Border
        cr.set_source_rgb(*THEME["outline_variant"])
        cr.set_line_width(1.0)
        cr.rectangle(0.5, 0.5, width - 1, height - 1)
        cr.stroke()

        # 2. Top Header Bar
        cr.set_source_rgb(*THEME["on_surface"])
        cr.select_font_face("JetBrainsMono Nerd Font Propo", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(13.0)
        cr.move_to(28, 36)
        cr.show_text("󰸉  WALLPAPER CAROUSEL")

        # Position counter in header right
        count_str = f"[ {self.current_index + 1:02d} / {len(self.wallpapers):02d} ]"
        extents = cr.text_extents(count_str)
        cr.move_to(width - extents.width - 28, 36)
        cr.set_source_rgb(*THEME["primary"])
        cr.show_text(count_str)

        # Thin header rule
        cr.set_source_rgba(THEME["outline_variant"][0], THEME["outline_variant"][1], THEME["outline_variant"][2], 0.6)
        cr.set_line_width(1.0)
        cr.move_to(20, 50)
        cr.line_to(width - 20, 50)
        cr.stroke()

        # 3. Draw Carousel Cards
        # Render cards from outer to inner so center card is drawn on top
        n = len(self.wallpapers)
        # Sequence: -2, 2, -1, 1, 0 (relative offset)
        render_order = [-2, 2, -1, 1, 0]

        for offset in render_order:
            idx = (self.current_index + offset) % n
            rel_pos = offset + self.anim_progress
            path = self.wallpapers[idx]
            pixbuf = self.get_pixbuf(path)

            self.draw_card(cr, pixbuf, cx, cy, rel_pos, path)

        # 4. Footer Information & Badges
        curr_name = os.path.basename(self.wallpapers[self.current_index])
        
        # Center filename badge
        cr.select_font_face("JetBrainsMono Nerd Font Propo", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(12.0)
        name_extents = cr.text_extents(curr_name)
        badge_w = name_extents.width + 30
        badge_h = 26
        badge_x = cx - badge_w / 2.0
        badge_y = cy + CARD_HEIGHT / 2.0 + 16

        # Badge container
        cr.set_source_rgba(THEME["surface"][0], THEME["surface"][1], THEME["surface"][2], 0.95)
        cr.rectangle(badge_x, badge_y, badge_w, badge_h)
        cr.fill()
        cr.set_source_rgb(*THEME["outline_variant"])
        cr.set_line_width(1.0)
        cr.rectangle(badge_x + 0.5, badge_y + 0.5, badge_w - 1, badge_h - 1)
        cr.stroke()

        # Badge text
        cr.set_source_rgb(*THEME["on_surface"])
        cr.move_to(badge_x + 15, badge_y + 17)
        cr.show_text(curr_name)

        # Bottom Shortcut Bar
        shortcuts = "TAB / 󰁔 NEXT     SHIFT+TAB / 󰁍 PREV     ENTER APPLY     ESC CANCEL"
        cr.select_font_face("JetBrainsMono Nerd Font Propo", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
        cr.set_font_size(10.5)
        sc_extents = cr.text_extents(shortcuts)
        cr.set_source_rgba(THEME["outline"][0], THEME["outline"][1], THEME["outline"][2], 0.75)
        cr.move_to(cx - sc_extents.width / 2.0, height - 20)
        cr.show_text(shortcuts)

    def draw_card(self, cr, pixbuf, cx, cy, rel_pos, path):
        # Card center position
        card_x = cx + rel_pos * CARD_SPACING
        card_y = cy

        # Perspective & scale
        abs_rel = abs(rel_pos)
        scale = 1.0 / (1.0 + abs_rel * 0.38)
        alpha = max(0.0, min(1.0, 1.0 - abs_rel * 0.55))

        if alpha <= 0.01:
            return

        w = CARD_WIDTH
        h = CARD_HEIGHT

        # Tilted / Perspective Shear: outer edges tilt inwards toward center
        shear_y = -math.tanh(rel_pos * 0.6) * 0.085

        cr.save()
        cr.translate(card_x, card_y)
        cr.scale(scale, scale)
        cr.transform(cairo.Matrix(1.0, shear_y, 0.0, 1.0, 0.0, 0.0))

        half_w = w / 2.0
        half_h = h / 2.0

        # Background card placeholder
        cr.set_source_rgba(0.05, 0.07, 0.08, alpha)
        cr.rectangle(-half_w, -half_h, w, h)
        cr.fill()

        # Draw scaled/cropped image
        if pixbuf:
            cr.save()
            cr.rectangle(-half_w, -half_h, w, h)
            cr.clip()
            Gdk.cairo_set_source_pixbuf(cr, pixbuf, -half_w, -half_h)
            cr.paint_with_alpha(alpha)
            cr.restore()

        # Center Card: Brutalist Highlight Border & Corner Brackets
        if abs_rel < 0.35:
            # Highlight border
            cr.set_source_rgba(THEME["primary"][0], THEME["primary"][1], THEME["primary"][2], alpha)
            cr.set_line_width(2.0)
            cr.rectangle(-half_w, -half_h, w, h)
            cr.stroke()

            # Brutalist sharp corner markers
            arm = 18.0
            cr.set_line_width(3.0)
            # Top-Left
            cr.move_to(-half_w - 3, -half_h + arm)
            cr.line_to(-half_w - 3, -half_h - 3)
            cr.line_to(-half_w + arm, -half_h - 3)
            # Top-Right
            cr.move_to(half_w + 3 - arm, -half_h - 3)
            cr.line_to(half_w + 3, -half_h - 3)
            cr.line_to(half_w + 3, -half_h + arm)
            # Bottom-Left
            cr.move_to(-half_w - 3, half_h - arm)
            cr.line_to(-half_w - 3, half_h + 3)
            cr.line_to(-half_w + arm, half_h + 3)
            # Bottom-Right
            cr.move_to(half_w + 3 - arm, half_h + 3)
            cr.line_to(half_w + 3, half_h + 3)
            cr.line_to(half_w + 3, half_h - arm)
            cr.stroke()
        else:
            # Side Card: Subtle brutalist border
            cr.set_source_rgba(THEME["outline"][0], THEME["outline"][1], THEME["outline"][2], 0.5 * alpha)
            cr.set_line_width(1.2)
            cr.rectangle(-half_w, -half_h, w, h)
            cr.stroke()

        cr.restore()

def main():
    app = WallpaperCarousel()
    app.show_all()
    Gtk.main()

if __name__ == "__main__":
    main()
