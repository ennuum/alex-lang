# ALEX UI V0.8 — 2D transforms
from core use type

func identity():
    return {"m11":1.0,"m12":0.0,"m21":0.0,"m22":1.0,"dx":0.0,"dy":0.0}

func matrix(m11,m12,m21,m22,dx,dy):
    return {"m11":m11,"m12":m12,"m21":m21,"m22":m22,"dx":dx,"dy":dy}

func translate(x,y):
    return matrix(1.0,0.0,0.0,1.0,x,y)

func scale(x,y):
    return matrix(x,0.0,0.0,y,0.0,0.0)

func rotate(degrees, cx=0.0, cy=0.0):
    return {"kind":"rotate","degrees":degrees,"cx":cx,"cy":cy}

func skew(x_degrees,y_degrees):
    return {"kind":"skew","x":x_degrees,"y":y_degrees}
