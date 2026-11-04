# Modules de projet : use / from ... use, arguments nommés vers un export, enum et classe importés.
use lib.sh_geo as geo
from lib.sh_geo use Vec, scale, Dir

v := Vec(y=5)
w := scale(v, k=3)
print(v.dot(w), geo.ORIGIN)
print(geo.step(geo.Dir.East(7)), geo.step(Dir.North))
print(isinstance(w, Vec), isinstance(w, geo.Vec))
u := geo.scale(geo.Vec(2, 3), k=10)
print(u.x, u.y)
