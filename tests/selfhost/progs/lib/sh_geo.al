# Module de projet importé par sh_modules.al (qualifié $mod…, signatures exportées).
const ORIGIN := 0

class Vec:
    x := 0
    func init(x=1, y=2):
        self.x = x
        self.y = y
    func dot(o):
        return self.x * o.x + self.y * o.y

enum Dir:
    North
    East(steps)

func scale(v, k=2, *rest):
    return Vec(v.x * k, v.y * k)

func step(d):
    match d:
        Dir.North:
            return 0
        Dir.East(n):
            return n
