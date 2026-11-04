# Module de test pour tests/lang/test_language.al : exporte des struct, un enum et des fonctions.
# Les fonctions sont volontairement déclarées dans le désordre (hissage) et l'une d'elles est
# mutuellement récursive.

func is_even(n):
    if n == 0:
        return true
    return is_odd(n - 1)

func is_odd(n):
    if n == 0:
        return false
    return is_even(n - 1)

enum Color:
    Red
    Green
    Rgb(r, g, b)

struct Vec:
    func init(x, y=0.0):
        self.x = x
        self.y = y
    func dot(o):
        return self.x * o.x + self.y * o.y
    func scaled(k):
        return Vec(self.x * k, self.y * k)

struct Counter:
    func init(start=0):
        self.n = start
    func bump(step=1):
        self.n = self.n + step
        return self.n

struct Bare:
    func tag():
        return "bare"

func make_vec(a, b=2.0):
    return Vec(a, b)

func norm2(v):
    return v.dot(v)

func color_name(c):
    match c:
        Color.Red:
            return "rouge"
        Color.Rgb(r, g, b):
            return f"rgb({r},{g},{b})"
        other:
            return "autre"

func power(base, exp=2, offset=0):
    return base ** exp + offset
