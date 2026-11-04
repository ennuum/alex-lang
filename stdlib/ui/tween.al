# ALEX STANDARD LIBRARY — ui.tween facade V1.2 (animation / tweening avancé)
# Tweens non bloquants (nombres, couleurs, vecteurs), ressorts amortis analytiques, séquences, parallèles,
# cascades, pilotage (pause/seek/vitesse), remplacement des animations concurrentes, intégration ui.state.
# Sémantique détaillée : stdlib/ui/tween/core.al et animator.al ; guide : docs/UI_TWEEN.md.
use ui.tween.core as _core
use ui.tween.animator as _animator
use ui.tween.interp as _interp
use ui.animation.easing as _easing

const VERSION := "1.2.0"

func target_state(store, key):
    return _core.target_state(store, key)
func target_dict(obj, prop):
    return _core.target_dict(obj, prop)
func target_native(handle, prop):
    return _core.target_native(handle, prop)
func target_fn(fn_value, ctx):
    return _core.target_fn(fn_value, ctx)
func tween(target, end_value, duration, start_value=null, easing="ease_out", delay=0.0, repeat=0, yoyo=false):
    return _core.tween(target, end_value, duration, start_value, easing, delay, repeat, yoyo)
func spring(target, end_value, start_value=null, stiffness=170.0, damping=26.0, mass=1.0, velocity=null, delay=0.0):
    return _core.spring(target, end_value, start_value, stiffness, damping, mass, velocity, delay)
func wait(seconds):
    return _core.wait(seconds)
func call(fn_value, ctx=null):
    return _core.call(fn_value, ctx)
func sequence(nodes, delay=0.0):
    return _core.sequence(nodes, delay)
func parallel(nodes, delay=0.0):
    return _core.parallel(nodes, delay)
func stagger(nodes, each, delay=0.0):
    return _core.stagger(nodes, each, delay)
func callbacks(node, on_start=null, on_update=null, on_complete=null, ctx=null):
    return _core.callbacks(node, on_start, on_update, on_complete, ctx)
func total_duration(node):
    return _core.total_duration(node)
func reset(node):
    return _core.reset(node)
func create(fps=60, strict=true):
    return _animator.create(fps, strict)
func attach(anim, store):
    return _animator.attach(anim, store)
func track_native(anim, handle, x, y, width, height):
    return _animator.track_native(anim, handle, x, y, width, height)
func play(anim, node, tag=null, speed=1.0):
    return _animator.play(anim, node, tag, speed)
func tick(anim, dt):
    return _animator.tick(anim, dt)
func update(anim):
    return _animator.update(anim)
func pause(anim, id):
    return _animator.pause(anim, id)
func resume(anim, id):
    return _animator.resume(anim, id)
func cancel(anim, id):
    return _animator.cancel(anim, id)
func finish(anim, id):
    return _animator.finish(anim, id)
func seek(anim, id, t):
    return _animator.seek(anim, id, t)
func set_speed(anim, id, speed):
    return _animator.set_speed(anim, id, speed)
func reverse(anim, id):
    return _animator.reverse(anim, id)
func set_time_scale(anim, scale):
    return _animator.set_time_scale(anim, scale)
func state(anim, id):
    return _animator.state(anim, id)
func is_active(anim, id=null):
    return _animator.is_active(anim, id)
func active_count(anim):
    return _animator.active_count(anim)
func clear(anim):
    return _animator.clear(anim)
func errors(anim):
    return _animator.errors(anim)
func clear_errors(anim):
    return _animator.clear_errors(anim)
func animate_state(anim, store, key, end_value, duration, start_value=null, easing="ease_out", delay=0.0, repeat=0, yoyo=false):
    return _animator.animate_state(anim, store, key, end_value, duration, start_value, easing, delay, repeat, yoyo)
func animate_prop(anim, obj, prop, end_value, duration, start_value=null, easing="ease_out", delay=0.0, repeat=0, yoyo=false):
    return _animator.animate_prop(anim, obj, prop, end_value, duration, start_value, easing, delay, repeat, yoyo)
func animate_native(anim, handle, prop, end_value, duration, start_value=null, easing="ease_out", delay=0.0, repeat=0, yoyo=false):
    return _animator.animate_native(anim, handle, prop, end_value, duration, start_value, easing, delay, repeat, yoyo)
func spring_state(anim, store, key, end_value, start_value=null, stiffness=170.0, damping=26.0, mass=1.0, velocity=null):
    return _animator.spring_state(anim, store, key, end_value, start_value, stiffness, damping, mass, velocity)
func spring_prop(anim, obj, prop, end_value, start_value=null, stiffness=170.0, damping=26.0, mass=1.0, velocity=null):
    return _animator.spring_prop(anim, obj, prop, end_value, start_value, stiffness, damping, mass, velocity)
func spring_native(anim, handle, prop, end_value, start_value=null, stiffness=170.0, damping=26.0, mass=1.0, velocity=null):
    return _animator.spring_native(anim, handle, prop, end_value, start_value, stiffness, damping, mass, velocity)
func bezier(x1, y1, x2, y2):
    return _easing.bezier(x1, y1, x2, y2)
func steps(n, jump="end"):
    return _easing.steps(n, jump)
func ease(spec, t):
    return _easing.evaluate(spec, t)
func interpolate(a, b, t):
    return _interp.interpolate(a, b, t)
