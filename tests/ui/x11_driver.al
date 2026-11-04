# Pilote de test X11 écrit en ALEX : envoie de vrais événements X (SendEvent) à une fenêtre ALEX identifiée par
# son titre, en parlant directement le protocole X11 sur le socket du serveur. Utilisé par les tests X11 sous Xvfb
# (tests/ui/run_x11_test.sh, run_x11_gestures.sh, tests/window/run_x11_window.sh, tests/ui_view/run_x11_view.sh).
#
#   alex run tests/ui/x11_driver.al <titre> <commande>...
#   commandes : wait <ms> | click <x> <y> | rclick <x> <y> | dclick <x> <y> | move <x> <y>
#               down <x> <y> [b] | up <x> <y> [b] | drag <x1> <y1> <x2> <y2> | wheel <x> <y> <±n> (n>0 = haut)
#               type <texte> | key <[ctrl+][shift+][alt+]Nom> | close
use os
use io
use string as s
from core use len, to_int
from collections use append
use network.socket as sk

func p8(v):
    return [v & 255]

func p16(v):
    return [v & 255, (v >> 8) & 255]

func p32(v):
    return [v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]

func pad(l):
    out := l
    while len(out) % 4 != 0:
        out = out + [0]
    return out

func u16(b, i):
    return b[i] | (b[i + 1] << 8)

func u32(b, i):
    return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)

func be16(b, i):
    return (s.byte_at(b, i) << 8) | s.byte_at(b, i + 1)

class X:
    func init():
        disp := os.get_env("DISPLAY", "")
        k := s.find(disp, ":")
        if k < 0:
            raise("OSError", "pas d'affichage")
        num := s.split(s.slice(disp, k + 1, len(disp)), ".")[0]
        self.sock = sk.Socket(1, "tcp")
        self.sock.connect("/tmp/.X11-unix/X" + num, 0, 5.0)
        self.inb = []
        self.seq = 0
        cookie := self.cookie(num)
        name := s.byte_unpack("MIT-MAGIC-COOKIE-1") if len(cookie) > 0 else []
        req := [108, 0] + p16(11) + p16(0) + p16(len(name)) + p16(len(cookie)) + [0, 0] + pad(name) + pad(cookie)
        self.send(req)
        hd := self.read(8)
        body := self.read(4 * u16(hd, 6))
        if hd[0] != 1:
            raise("OSError", "connexion X11 refusée")
        b := hd + body
        self.base = u32(b, 12)
        self.mask = u32(b, 16)
        self.next = 1
        vlen := u16(b, 24)
        nformats := b[29]
        self.min_kc = b[34]
        self.max_kc = b[35]
        o := 40 + ((vlen + 3) // 4) * 4 + 8 * nformats
        self.root = u32(b, o)
        r := self.request(101, 0, [self.min_kc, self.max_kc - self.min_kc + 1, 0, 0])
        self.per = r[1]
        self.syms = [u32(r, 32 + 4 * i) for i in 0..(len(r) - 32) // 4]

    func cookie(num):
        path := os.get_env("XAUTHORITY", "")
        if path == "":
            path = os.get_env("HOME", "") + "/.Xauthority"
        d := ""
        try:
            d = io.read_file(path)
        catch e:
            return []
        i := 0
        n := s.byte_len(d)
        while i + 2 <= n:
            i += 2
            f := []
            for k in 0..4:
                ln := be16(d, i)
                append(f, s.byte_slice(d, i + 2, i + 2 + ln))
                i += 2 + ln
            if f[2] == "MIT-MAGIC-COOKIE-1" and (f[1] == num or f[1] == ""):
                return s.byte_unpack(f[3])
        return []

    func send(l):
        self.sock.send(s.byte_pack(l), 5.0)

    func read(n):
        while len(self.inb) < n:
            got := self.sock.recv(65536, 10.0)
            if got == "":
                raise("OSError", "connexion X11 fermée")
            self.inb = self.inb + s.byte_unpack(got)
        out := self.inb[0:n]
        self.inb = self.inb[n:len(self.inb)]
        return out

    func id():
        v := self.base | (self.next & self.mask)
        self.next += 1
        return v

    # Requête sans réponse.
    func emit(op, b1, data):
        body := pad(data)
        self.send([op, b1] + p16(1 + len(body) // 4) + body)
        self.seq += 1

    # Requête avec réponse (les événements reçus entre-temps sont ignorés ; une erreur renvoie null).
    func request(op, b1, data):
        self.emit(op, b1, data)
        while true:
            p := self.read(32)
            if p[0] == 1:
                p = p + self.read(4 * u32(p, 4))
            if (p[0] == 0 or p[0] == 1) and u16(p, 2) == (self.seq & 65535):
                return p if p[0] == 1 else null

    func sync():
        self.request(43, 0, [])

    func name_of(w):
        r := self.request(20, 0, p32(w) + p32(39) + p32(0) + p32(0) + p32(1024))
        if r == null or u32(r, 8) == 0:
            return null
        return s.byte_pack(r[32:32 + u32(r, 16)])

    func find(w, title):
        if self.name_of(w) == title:
            return w
        r := self.request(15, 0, p32(w))
        if r == null:
            return 0
        n := u16(r, 16)
        for i in 0..n:
            f := self.find(u32(r, 32 + 4 * i), title)
            if f != 0:
                return f
        return 0

    func atom(name):
        nb := s.byte_unpack(name)
        r := self.request(16, 0, p16(len(nb)) + [0, 0] + nb)
        return u32(r, 8)

    func keycode(ks):
        for kc in self.min_kc..self.max_kc + 1:
            for col in 0..(2 if self.per >= 2 else self.per):
                if self.syms[(kc - self.min_kc) * self.per + col] == ks:
                    return kc
        return 0

    func base_sym(kc):
        return self.syms[(kc - self.min_kc) * self.per]

    func send_event(w, mask, ev):
        self.emit(25, 0, p32(w) + p32(mask) + ev)
        self.sync()
        os.sleep(0.06)

# Événement d'entrée (KeyPress 2, KeyRelease 3, ButtonPress 4, ButtonRelease 5, MotionNotify 6).
func input_event(t, detail, x, root, w, ex, ey, state):
    return [t | 128, detail] + p16(0) + p32(0) + p32(root) + p32(w) + p32(0) + p16(ex) + p16(ey) + p16(ex) + p16(ey) + p16(state) + [1, 0]

func mouse(x, w, ex, ey, down, button=1):
    masks := {1: 256, 2: 512, 3: 1024}
    m := masks[button] if button in masks else 0
    t := 4 if down else 5
    x.send_event(w, 4 if down else 8, input_event(t, button, x, x.root, w, ex, ey, 0 if down else m))

func motion(x, w, ex, ey):
    x.send_event(w, 64, input_event(6, 0, x, x.root, w, ex, ey, 0))

func key(x, w, ks, state=0):
    kc := x.keycode(ks)
    if kc == 0:
        print("keysym " + str(ks) + " sans keycode")
        return
    x.send_event(w, 1, input_event(2, kc, x, x.root, w, 0, 0, state))
    x.send_event(w, 2, input_event(3, kc, x, x.root, w, 0, 0, state))

NAMED := {"space": 32, "BackSpace": 65288, "Tab": 65289, "Return": 65293, "Escape": 65307, "Delete": 65535,
    "Home": 65360, "Left": 65361, "Up": 65362, "Right": 65363, "Down": 65364, "Prior": 65365, "Page_Up": 65365,
    "Next": 65366, "Page_Down": 65366, "End": 65367, "Insert": 65379, "Shift_L": 65505, "Control_L": 65507,
    "Alt_L": 65513, "KP_Enter": 65421}

func keysym(n):
    if n in NAMED:
        return NAMED[n]
    if len(n) >= 2 and n[0] == 'F':
        try:
            k := to_int(s.slice(n, 1, len(n)))
            if k >= 1 and k <= 12:
                return 65469 + k
        catch e:
            return 0
    if s.byte_len(n) == 1:
        return s.byte_at(n, 0)
    return 0

argv := os.args()
if len(argv) < 2:
    os.exit(2)
x := X()
w := 0
for i in 0..100:
    w = x.find(x.root, argv[0])
    if w != 0:
        break
    os.sleep(0.1)
if w == 0:
    print("fenêtre '" + argv[0] + "' introuvable")
    os.exit(1)
i := 1
func arg(k):
    return to_int(argv[k])
while i < len(argv):
    c := argv[i]
    if c == "wait":
        os.sleep(arg(i + 1) / 1000.0)
        i += 2
    elif c == "click" or c == "rclick" or c == "dclick":
        ex := arg(i + 1)
        ey := arg(i + 2)
        motion(x, w, ex, ey)
        b := 3 if c == "rclick" else 1
        for k in 0..(2 if c == "dclick" else 1):
            mouse(x, w, ex, ey, true, b)
            mouse(x, w, ex, ey, false, b)
        i += 3
    elif c == "move":
        motion(x, w, arg(i + 1), arg(i + 2))
        i += 3
    elif c == "down" or c == "up":
        b := 1
        n := 3
        if i + 3 < len(argv) and len(argv[i + 3]) == 1 and s.byte_at(argv[i + 3], 0) >= 49 and s.byte_at(argv[i + 3], 0) <= 51:
            b = arg(i + 3)
            n = 4
        mouse(x, w, arg(i + 1), arg(i + 2), c == "down", b)
        i += n
    elif c == "drag":
        x1 := arg(i + 1)
        y1 := arg(i + 2)
        x2 := arg(i + 3)
        y2 := arg(i + 4)
        motion(x, w, x1, y1)
        mouse(x, w, x1, y1, true)
        for k in 1..13:
            motion(x, w, x1 + (x2 - x1) * k // 12, y1 + (y2 - y1) * k // 12)
        mouse(x, w, x2, y2, false)
        i += 5
    elif c == "wheel":
        ex := arg(i + 1)
        ey := arg(i + 2)
        n := arg(i + 3)
        motion(x, w, ex, ey)
        b := 4 if n > 0 else 5
        for k in 0..(n if n > 0 else 0 - n):
            mouse(x, w, ex, ey, true, b)
            mouse(x, w, ex, ey, false, b)
        i += 4
    elif c == "type":
        for ch in s.byte_unpack(argv[i + 1]):
            kc := x.keycode(ch)
            shifted := kc != 0 and x.base_sym(kc) != ch
            key(x, w, ch, 1 if shifted else 0)
        i += 2
    elif c == "key":
        n := argv[i + 1]
        st := 0
        more := true
        while more:
            more = false
            if s.starts_with(n, "ctrl+"):
                st = st | 4
                n = s.slice(n, 5, len(n))
                more = true
            elif s.starts_with(n, "shift+"):
                st = st | 1
                n = s.slice(n, 6, len(n))
                more = true
            elif s.starts_with(n, "alt+"):
                st = st | 8
                n = s.slice(n, 4, len(n))
                more = true
        ks := keysym(n)
        if ks == 0:
            print("touche inconnue " + n)
            os.exit(1)
        key(x, w, ks, st)
        i += 2
    elif c == "close":
        proto := x.atom("WM_PROTOCOLS")
        dele := x.atom("WM_DELETE_WINDOW")
        ev := [33 | 128, 32] + p16(0) + p32(w) + p32(proto) + p32(dele) + p32(0) + p32(0) + p32(0) + p32(0)
        x.send_event(w, 0, ev)
        i += 1
    else:
        print("commande inconnue " + c)
        os.exit(2)
x.sock.close()
