# ALEX STANDARD LIBRARY — ui V0.3
# Public facade. Implementation is split into dedicated .al modules.

from core use type
use _native_ui as _native
use ui.window as _window
use ui.widget as _widget
use ui.button as _button
use ui.label as _label
use ui.text_input as _text_input
use ui.checkbox as _checkbox
use ui.radio_button as _radio
use ui.combo_box as _combo
use ui.progress_bar as _progress
use ui.scroll_view as _scroll
use ui.event as _event
use ui.layout as _layout
use ui.layout.layout_core as _layout_core
use ui.layout.vbox as _layout_vbox
use ui.layout.hbox as _layout_hbox
use ui.layout.grid as _layout_grid
use ui.layout.stack as _layout_stack
use ui.layout.anchor as _layout_anchor
use ui.layout.responsive as _layout_responsive
use ui.layout.padding as _layout_padding
use ui.layout.margin as _layout_margin
use ui.layout.alignment as _layout_alignment
use ui.color as _color
use ui.font as _font
use ui.style as _style
use ui.theme as _theme
use ui.application as _application
use ui.notification as _notification
use ui.clipboard as _clipboard
use ui.shortcut as _shortcut
use ui.dragdrop as _dragdrop
use ui.menu as _menu
use ui.file_dialog as _file_dialog
use ui.screen as _screen
use ui.dpi as _dpi
use ui.animation as _animation

const VERSION := "0.7.0"

func version():
    return VERSION
func available():
    return _native.available()
func backend():
    return _native.backend()

# Window
func window(title="ALEX Application", width=900, height=600, resizable=true):
    return _window.window(title, width, height, resizable)
func show(handle):
    return _window.show(handle)
func hide(handle):
    return _window.hide(handle)
func close(handle):
    return _window.close(handle)
func set_title(handle, title):
    return _window.set_title(handle, title)
func set_size(handle, width, height):
    return _window.set_size(handle, width, height)
func poll(handle):
    return _window.poll(handle)
func run(handle):
    return _window.run(handle)

# Base widget
func widget_set_text(handle, text):
    return _widget.set_text(handle, text)
func widget_get_text(handle):
    return _widget.get_text(handle)
func widget_set_visible(handle, value):
    return _widget.set_visible(handle, value)
func widget_set_enabled(handle, value):
    return _widget.set_enabled(handle, value)
func widget_set_position(handle, x, y):
    return _widget.set_position(handle, x, y)
func widget_set_size(handle, width, height):
    return _widget.set_size(handle, width, height)
func widget_set_checked(handle, value):
    return _widget.set_checked(handle, value)
func widget_get_checked(handle):
    return _widget.checked(handle)

# Controls
func button(parent, text, x=0, y=0, width=120, height=36):
    return _button.create(parent, text, x, y, width, height)
func label(parent, text, x=0, y=0, width=240, height=32):
    return _label.create(parent, text, x, y, width, height)
func input_field(parent, text="", x=0, y=0, width=260, height=32):
    return _text_input.create(parent, text, x, y, width, height)
func checkbox(parent, text, x=0, y=0, width=180, height=28):
    return _checkbox.create(parent, text, x, y, width, height)
func radio_button(parent, text, x=0, y=0, width=180, height=28):
    return _radio.create(parent, text, x, y, width, height)
func combo_box(parent, text="", x=0, y=0, width=220, height=120):
    return _combo.create(parent, text, x, y, width, height)
func combo_add_item(handle, text):
    return _combo.add_item(handle, text)
func progress_bar(parent, x=0, y=0, width=240, height=22):
    return _progress.create(parent, x, y, width, height)
func progress_set_value(handle, value):
    return _progress.set_value(handle, value)
func scroll_view(parent, x=0, y=0, width=320, height=240):
    return _scroll.create(parent, x, y, width, height)

# Events
func event_type(event):
    return _event.type(event)
func event_window(event):
    return _event.window(event)
func event_widget(event):
    return _event.widget(event)
func is_close_event(event):
    return _event.is_close(event)
func is_button_event(event):
    return _event.is_button(event)
func is_change_event(event):
    return _event.is_change(event)
func is_check_event(event):
    return _event.is_check(event)
func is_radio_event(event):
    return _event.is_radio(event)
func is_key_down_event(event):
    return _event.is_key_down(event)
func loop(window_handle, on_event):
    return _event.loop(window_handle, on_event)

# Layouts V0.3
func layout_item(widget, width=100, height=30, flex=0, margin=0):
    return _layout_core.item(widget, width, height, flex, margin)
func vbox(children, width, height, gap=0, padding=0, alignment="start"):
    return _layout_vbox.apply(children, width, height, gap, padding, alignment)
func hbox(children, width, height, gap=0, padding=0, alignment="start"):
    return _layout_hbox.apply(children, width, height, gap, padding, alignment)
func grid(children, width, height, columns=2, gap=0, padding=0):
    return _layout_grid.apply(children, width, height, columns, gap, padding)
func stack(children, width, height, padding=0):
    return _layout_stack.apply(children, width, height, padding)
func anchor(children, width, height, padding=0):
    return _layout_anchor.apply(children, width, height, padding)
func anchor_item(widget, width=100, height=30, left=0, top=0, right=null, bottom=null):
    return _layout_anchor.item(widget, width, height, left, top, right, bottom)
func responsive(children, width, height, breakpoint=700, gap=8, padding=8, alignment="start"):
    return _layout_responsive.apply(children, width, height, breakpoint, gap, padding, alignment)
func padding_all(value):
    return _layout_padding.all(value)
func padding_symmetric(horizontal=0, vertical=0):
    return _layout_padding.symmetric(horizontal, vertical)
func margin_all(value):
    return _layout_margin.all(value)
func alignment_start():
    return _layout_alignment.start()
func alignment_center():
    return _layout_alignment.center()
func alignment_end():
    return _layout_alignment.end()

# Appearance V0.4
func color(value):
    return _color.color(value)
func rgb(r, g, b):
    return _color.rgb(r, g, b)
func font(family="Segoe UI", size=10, weight="normal"):
    return _font.font(family, size, weight)
func style(background=null, foreground=null, font=null, padding=0, margin=0, radius=0):
    return _style.style(background, foreground, font, padding, margin, radius)
func apply_style(widget, value):
    return _style.apply(widget, value)
func theme(name="modern-dark", options=null):
    return _theme.theme(name, options)
func modern_dark():
    return _theme.modern_dark()
func modern_light():
    return _theme.modern_light()
func high_contrast():
    return _theme.high_contrast()


# Animations V0.6
func animation(widget, property, from_value, to_value, duration=0.3, easing="ease_out", fps=60, repeat=0, yoyo=false):
    return _animation.create(widget, property, from_value, to_value, duration, easing, fps, repeat, yoyo)
func animate(animation_value):
    return _animation.play(animation_value)
func move(widget, from_x, from_y, to_x, to_y, duration=0.3, easing="ease_out", fps=60):
    return _animation.move(widget, from_x, from_y, to_x, to_y, duration, easing, fps)
func resize_animation(widget, from_width, from_height, to_width, to_height, duration=0.3, easing="ease_out", fps=60):
    return _animation.resize(widget, from_width, from_height, to_width, to_height, duration, easing, fps)
func pulse(widget, min_width, min_height, max_width, max_height, duration=0.18, cycles=2, easing="ease_in_out", fps=60):
    return _animation.pulse(widget, min_width, min_height, max_width, max_height, duration, cycles, easing, fps)
func animation_state(animation_value):
    return _animation.state(animation_value)

# Applications V0.5
func application(title="ALEX Application", width=900, height=600, resizable=true):
    return _application.create(title, width, height, resizable)
func application_add(app, window_handle):
    return _application.add(app, window_handle)
func application_windows(app):
    return _application.windows(app)
func application_count(app):
    return _application.count(app)

# Notifications
func notify(title, message):
    return _notification.show(title, message)

# Clipboard
func clipboard_set(text):
    return _clipboard.set_text(text)
func clipboard_get():
    return _clipboard.get_text()

# Shortcuts
func shortcut_register(window, id, modifiers, key):
    return _shortcut.register(window, id, modifiers, key)
func shortcut_unregister(window, id):
    return _shortcut.unregister(window, id)

# Drag & drop
func drop_event(event):
    return _dragdrop.is_drop(event)
func drop_data(event):
    return _dragdrop.path(event)

# System menus
func menu(window):
    return _menu.create(window)
func menu_item(menu_handle, id, text):
    return _menu.item(menu_handle, id, text)
func menu_attach(window, menu_handle):
    return _menu.attach(window, menu_handle)

# File dialogs
func open_file(filter="Tous les fichiers\0*.*\0"):
    return _file_dialog.open(filter)
func save_file(filter="Tous les fichiers\0*.*\0"):
    return _file_dialog.save(filter)

# Screen / DPI
func screen_info():
    return _screen.info()
func dpi(window):
    return _dpi.get(window)
func scale(window):
    return _dpi.scale(window)

# Automatisation / tests / capture (backends portables : x11, headless)
# inject_mouse : kind = "move" | "down" | "up" | "click" ; coordonnées client.
func inject_mouse(window, kind, x, y, button=1, modifiers=0):
    return _native.inject_mouse(window, kind, x, y, button, modifiers)
# Molette : dy > 0 = vers le haut, dx > 0 = vers la droite (en crans).
func inject_wheel(window, x, y, dx, dy, modifiers=0):
    return _native.inject_wheel(window, x, y, dx, dy, modifiers)
# Simule la demande de fermeture du gestionnaire de fenêtres (croix, Alt+F4).
func inject_close(window):
    return _native.inject_close(window)
func inject_key(window, key, modifiers=0):
    return _native.inject_key(window, key, modifiers)
func inject_text(window, text):
    return _native.inject_text(window, text)
func screenshot(window, path):
    return _native.window_screenshot(window, path)

# V1.3 — fermeture avec confirmation, curseurs, mesure de texte
# Avec set_confirm_close(win, true), la croix n'exécute plus la fermeture : l'événement "close_request" est émis
# et l'application décide (ui.close(win) pour fermer réellement).
func set_confirm_close(window, enabled):
    return _native.window_set_confirm_close(window, enabled)
# Curseurs : arrow, text, pointer, grab, grabbing, move, resize_h, resize_v, wait, not_allowed, crosshair.
func set_cursor(window, name):
    return _native.window_set_cursor(window, name)
func get_cursor(window):
    return _native.window_get_cursor(window)
# {"width","height","ascent"} en pixels pour une police de taille `size` (police de l'interface).
func measure_text(text, size):
    return _native.text_measure(text, size)
