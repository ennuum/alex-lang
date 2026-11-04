# ALEX STANDARD LIBRARY — ui.animation facade V0.6
use ui.animation.animation as _animation
use ui.animation.easing as _easing

func create(widget, property, from_value, to_value, duration=0.3, easing="ease_out", fps=60, repeat=0, yoyo=false):
    return _animation.create(widget, property, from_value, to_value, duration, easing, fps, repeat, yoyo)

func play(animation):
    return _animation.play(animation)

func move(widget, from_x, from_y, to_x, to_y, duration=0.3, easing="ease_out", fps=60):
    return _animation.move(widget, from_x, from_y, to_x, to_y, duration, easing, fps)

func resize(widget, from_width, from_height, to_width, to_height, duration=0.3, easing="ease_out", fps=60):
    return _animation.resize(widget, from_width, from_height, to_width, to_height, duration, easing, fps)

func pulse(widget, min_width, min_height, max_width, max_height, duration=0.18, cycles=2, easing="ease_in_out", fps=60):
    return _animation.pulse(widget, min_width, min_height, max_width, max_height, duration, cycles, easing, fps)

func state(animation):
    return _animation.state(animation)

func reset(animation):
    return _animation.reset(animation)

func easing(name):
    return _easing.resolve(name)

func linear(t):
    return _easing.linear(t)
func ease_in(t):
    return _easing.ease_in(t)
func ease_out(t):
    return _easing.ease_out(t)
func ease_in_out(t):
    return _easing.ease_in_out(t)
func smoothstep(t):
    return _easing.smoothstep(t)
func smootherstep(t):
    return _easing.smootherstep(t)
func cubic_in(t):
    return _easing.cubic_in(t)
func cubic_out(t):
    return _easing.cubic_out(t)
func cubic_in_out(t):
    return _easing.cubic_in_out(t)
func back_in(t):
    return _easing.back_in(t)
func back_out(t):
    return _easing.back_out(t)
func bounce_in(t):
    return _easing.bounce_in(t)
func bounce_out(t):
    return _easing.bounce_out(t)
func bounce_in_out(t):
    return _easing.bounce_in_out(t)
