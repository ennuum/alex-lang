# ALEX STANDARD LIBRARY — ui.state facade V1.1 (état réactif)
# Store observable, valeurs calculées à dépendances automatiques, lots, liaisons widgets, boucle réactive.
# Voir stdlib/ui/state/store.al et binding.al pour la sémantique détaillée.
use ui.state.store as _store
use ui.state.binding as _binding

const VERSION := "1.1.0"
func version_string():
    return VERSION

func create(initial=null, strict=true):
    return _store.create(initial, strict)
func has(store, key):
    return _store.has(store, key)
func is_computed(store, key):
    return _store.is_computed(store, key)
func get(store, key):
    return _store.get(store, key)
func get_or(store, key, fallback=null):
    return _store.get_or(store, key, fallback)
func set(store, key, value):
    return _store.set(store, key, value)
func define(store, key, value=null):
    return _store.define(store, key, value)
func update(store, key, fn_value):
    return _store.update(store, key, fn_value)
func touch(store, key):
    return _store.touch(store, key)
func batch_begin(store):
    return _store.batch_begin(store)
func batch_end(store):
    return _store.batch_end(store)
func transaction(store, fn_value, ctx=null):
    return _store.transaction(store, fn_value, ctx)
func set_many(store, values):
    return _store.set_many(store, values)
func computed(store, key, fn_value):
    return _store.computed(store, key, fn_value)
func watch(store, key, fn_value, ctx=null, immediate=false):
    return _store.watch(store, key, fn_value, ctx, immediate)
func watch_all(store, fn_value, ctx=null):
    return _store.watch_all(store, fn_value, ctx)
func unwatch(store, id):
    return _store.unwatch(store, id)
func flush(store):
    return _store.flush(store)
func version(store):
    return _store.version(store)
func is_dirty(store):
    return _store.is_dirty(store)
func clear_dirty(store):
    return _store.clear_dirty(store)
func invalidate(store):
    return _store.invalidate(store)
func errors(store):
    return _store.errors(store)
func clear_errors(store):
    return _store.clear_errors(store)
func snapshot(store):
    return _store.snapshot(store)
func restore(store, snap):
    return _store.restore(store, snap)
func to_dict(store):
    return _store.to_dict(store)

func bind_prop(store, key, target, prop, transform=null):
    return _binding.bind_prop(store, key, target, prop, transform)
func bind_text(store, key, handle, transform=null):
    return _binding.bind_text(store, key, handle, transform)
func bind_checked(store, key, handle, transform=null):
    return _binding.bind_checked(store, key, handle, transform)
func bind_progress(store, key, handle, scale=1.0, transform=null):
    return _binding.bind_progress(store, key, handle, scale, transform)
func bind_enabled(store, key, handle, transform=null):
    return _binding.bind_enabled(store, key, handle, transform)
func bind_visible(store, key, handle, transform=null):
    return _binding.bind_visible(store, key, handle, transform)
func link_input(store, key, handle):
    return _binding.link_input(store, key, handle)
func link_checkbox(store, key, handle):
    return _binding.link_checkbox(store, key, handle)
func unlink(store, handle):
    return _binding.unlink(store, handle)
func on(store, handle, fn_value, ctx=null):
    return _binding.on(store, handle, fn_value, ctx)
func on_command(store, command_id, fn_value, ctx=null):
    return _binding.on_command(store, command_id, fn_value, ctx)
func on_shortcut(store, shortcut_id, fn_value, ctx=null):
    return _binding.on_shortcut(store, shortcut_id, fn_value, ctx)
func handle_event(store, ev):
    return _binding.handle_event(store, ev)
func link_widget(store, key, w):
    return _binding.link_widget(store, key, w)
func run(win, store, render=null, handler=null, ctx=null, idle=0.002):
    return _binding.run(win, store, render, handler, ctx, idle)
func animator(store):
    return _binding.animator(store)
func animate(store, key, end_value, duration, start_value=null, easing="ease_out", delay=0.0, repeat=0, yoyo=false):
    return _binding.animate(store, key, end_value, duration, start_value, easing, delay, repeat, yoyo)
func spring(store, key, end_value, start_value=null, stiffness=170.0, damping=26.0, mass=1.0, velocity=null):
    return _binding.spring(store, key, end_value, start_value, stiffness, damping, mass, velocity)
func play(store, node, tag=null, speed=1.0):
    return _binding.play(store, node, tag, speed)
func on_tick(store, fn_value, ctx=null):
    return _binding.on_tick(store, fn_value, ctx)
func on_close_request(store, fn_value, ctx=null):
    return _binding.on_close_request(store, fn_value, ctx)
