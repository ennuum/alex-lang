# Formes géométriques.
use math

# Un point du plan.
class Point:
    func init(x, y):
        self.x = x
        self.y = y

    # Distance à l'origine.
    func norme():
        return math.sqrt(self.x * self.x + self.y * self.y)

class Cercle extends Point:
    func init(x, y, r):
        super.init(x, y)
        self.rayon = r

    func aire():
        return math.PI * self.rayon * self.rayon

# Crée un point.
func point(x, y):
    return Point(x, y)
