from decimal import Decimal as D, getcontext, localcontext
getcontext().prec = 60
def lit(x):
    d = D(x) if not isinstance(x, D) else x
    # arrondi à 30 chiffres significatifs, jamais de notation exponentielle
    with localcontext() as c:
        c.prec = 25
        d = +d
    t = format(d, 'f')
    if '.' not in t: t += '.0'
    else:
        t = t.rstrip('0')
        if t.endswith('.'): t += '0'
    return t
V=lambda **k: [k.get(n,0) for n in ("L","M","T","I","TH","N","J")]
def mul(*vs, ):
    return [sum(x) for x in zip(*vs)]
def pw(v,n): return [x*n for x in v]
L=V(L=1); Mm=V(M=1); T=V(T=1); I=V(I=1); TH=V(TH=1); N=V(N=1); J=V(J=1); ONE=V()
A2=pw(L,2); VOL=pw(L,3); FREQ=pw(T,-1); VEL=mul(L,pw(T,-1)); FORCE=mul(Mm,L,pw(T,-2))
PRESS=mul(FORCE,pw(L,-2)); ENERGY=mul(FORCE,L); POWER=mul(ENERGY,pw(T,-1)); CHARGE=mul(I,T)
VOLT=mul(POWER,pw(I,-1)); FARAD=mul(CHARGE,pw(VOLT,-1)); OHM=mul(VOLT,pw(I,-1)); SIEM=pw(OHM,-1)
WB=mul(VOLT,T); TESLA=mul(WB,pw(L,-2)); HENRY=mul(WB,pw(I,-1)); GRAY=mul(A2,pw(T,-2)); LUX=mul(J,pw(L,-2))
ft=D("0.3048"); lb=D("0.45359237"); inch=D("0.0254"); g0=D("9.80665")
lbf=lb*g0
# (nom, scale, dims, offset, prefixable)
U=[]
AFF={}
def u(name,scale,dims,off="0",pre=False,aff=None):
    U.append((name,D(scale) if not isinstance(scale,D) else scale,dims,D(off),pre))
    if aff: AFF[name]=aff
# sans dimension
u("1","1",ONE); u("%","0.01",ONE); u("ppm","0.000001",ONE); u("ppb","0.000000001",ONE)
u("rad","1",ONE,pre=True); u("sr","1",ONE)
PI=D("3.14159265358979323846264338327950288")
u("deg",PI/180,ONE); u("°",PI/180,ONE); u("grad",PI/200,ONE); u("turn",2*PI,ONE)
u("arcmin",PI/10800,ONE); u("arcsec",PI/648000,ONE)
# longueur
u("m","1",L,pre=True); u("in",inch,L); u("ft",ft,L); u("yd","0.9144",L); u("mi","1609.344",L); u("nmi","1852",L)
u("angstrom","0.0000000001",L); u("Å","0.0000000001",L); u("au","149597870700",L); u("ly","9460730472580800",L)
u("pc",D("149597870700")*648000/PI,L,pre=True); u("thou","0.0000254",L); u("mil","0.0000254",L)
# masse
u("kg","1",Mm); u("g","0.001",Mm,pre=True); u("t","1000",Mm); u("lb",lb,Mm); u("oz",lb/16,Mm); u("st",lb*14,Mm)
u("u","1.66053906660e-27",Mm); u("Da","1.66053906660e-27",Mm); u("ct","0.0002",Mm)
# temps
u("s","1",T,pre=True); u("min","60",T); u("h","3600",T); u("d","86400",T); u("wk","604800",T); u("yr","31557600",T)
# courant, température, quantité, lumière
u("A","1",I,pre=True); u("K","1",TH,pre=True); u("degC","1",TH,"273.15",aff=("0","1","1")); u("°C","1",TH,"273.15",aff=("0","1","1"))
u("degF",D(5)/9,TH,D("459.67")*5/9,aff=("32","5","9")); u("°F",D(5)/9,TH,D("459.67")*5/9,aff=("32","5","9")); u("degR",D(5)/9,TH)
u("mol","1",N,pre=True); u("cd","1",J,pre=True); u("lm","1",J,pre=True); u("lx","1",LUX,pre=True)
# fréquence & radioactivité
u("Hz","1",FREQ,pre=True); u("rpm",D(1)/60,FREQ); u("Bq","1",FREQ,pre=True)
# force, pression, énergie, puissance
u("N","1",FORCE,pre=True); u("lbf",lbf,FORCE); u("kgf",g0,FORCE); u("dyn","0.00001",FORCE)
u("Pa","1",PRESS,pre=True); u("bar","100000",PRESS,pre=True); u("atm","101325",PRESS); u("mmHg","133.322387415",PRESS)
u("torr",D(101325)/760,PRESS); u("psi",lbf/(inch*inch),PRESS)
u("J","1",ENERGY,pre=True); u("eV","1.602176634e-19",ENERGY,pre=True); u("cal","4.184",ENERGY,pre=True); u("erg","0.0000001",ENERGY)
u("Wh","3600",ENERGY,pre=True); u("BTU","1055.05585262",ENERGY)
u("W","1",POWER,pre=True); u("hp",D(550)*ft*lbf,POWER)
# électricité
u("C","1",CHARGE,pre=True); u("Ah","3600",CHARGE,pre=True); u("V","1",VOLT,pre=True); u("F","1",FARAD,pre=True)
u("ohm","1",OHM,pre=True); u("Ω","1",OHM,pre=True); u("S","1",SIEM,pre=True); u("Wb","1",WB,pre=True)
u("T","1",TESLA,pre=True); u("H","1",HENRY,pre=True); u("Gy","1",GRAY,pre=True); u("Sv","1",GRAY,pre=True)
# surface, volume
u("ha","10000",A2); u("acre","4046.8564224",A2)
u("L","0.001",VOL,pre=True); u("l","0.001",VOL,pre=True)
gal=D("0.003785411784"); u("gal",gal,VOL); u("qt",gal/4,VOL); u("pt",gal/8,VOL); u("cup",gal/16,VOL); u("floz",gal/128,VOL)
u("tbsp",gal/256,VOL); u("tsp",gal/768,VOL)
# vitesse
u("kn",D(1852)/3600,VEL)
PREF=[("Y","1000000000000000000000000"),("Z","1000000000000000000000"),("E","1000000000000000000"),("P","1000000000000000"),
("T","1000000000000"),("G","1000000000"),("M","1000000"),("k","1000"),("h","100"),("da","10"),("d","0.1"),("c","0.01"),
("m","0.001"),("µ","0.000001"),("u","0.000001"),("n","0.000000001"),("p","0.000000000001"),("f","0.000000000000001"),
("a","0.000000000000000001"),("z","0.000000000000000000001"),("y","0.000000000000000000000001")]
NAMED={
 ():"dimensionless",(1,0,0,0,0,0,0):"length",(0,1,0,0,0,0,0):"mass",(0,0,1,0,0,0,0):"time",(0,0,0,1,0,0,0):"current",
 (0,0,0,0,1,0,0):"temperature",(0,0,0,0,0,1,0):"amount of substance",(0,0,0,0,0,0,1):"luminous intensity",
}
for nm,v in [("area",A2),("volume",VOL),("frequency",FREQ),("velocity",VEL),("acceleration",mul(L,pw(T,-2))),("force",FORCE),
 ("pressure",PRESS),("energy",ENERGY),("power",POWER),("electric charge",CHARGE),("voltage",VOLT),("capacitance",FARAD),
 ("resistance",OHM),("conductance",SIEM),("magnetic flux",WB),("magnetic flux density",TESLA),("inductance",HENRY),
 ("momentum",mul(Mm,VEL)),("density",mul(Mm,pw(L,-3))),("absorbed dose",GRAY),("illuminance",LUX),
 ("angular momentum",mul(Mm,A2,pw(T,-1))),("dynamic viscosity",mul(Mm,pw(L,-1),pw(T,-1))),("molar concentration",mul(N,pw(L,-3))),
 ("entropy",mul(ENERGY,pw(TH,-1))),("electric field",mul(VOLT,pw(L,-1)))]:
    NAMED[tuple(v)]=nm
NAMED[(0,0,0,0,0,0,0)]="dimensionless"
out=[]
w=out.append
w("# --- Registre des unités : nom -> [facteur vers l'unité SI cohérente, dimensions, décalage (K), préfixable] ---")
w("# Dimensions : [longueur, masse, temps, courant, température, quantité de matière, intensité lumineuse].")
w("# Unités à décalage (°C, °F) : 5e élément = [valeur de l'unité à 0 °C, numérateur, dénominateur] : K = (x - zéro) * num / den + 273,15.")
w("# Facteurs EXACTS en décimal (générés mécaniquement à partir des définitions légales : ne pas éditer à la main).")
w("const _UNITS := {")
rows=[]
for name,sc,dims,off,pre in U:
    extra = ""
    if name in AFF:
        z,nu,de = AFF[name]
        extra = f", [{lit(z)}, {lit(nu)}, {lit(de)}]"
    rows.append(f'    "{name}": [{lit(sc)}, {dims}, {lit(off)}, {"true" if pre else "false"}{extra}]')
w(",\n".join(rows))
w("}\n")
w("# Préfixes SI, du plus long au plus court (« da » avant « d »).")
w("const _PREFIXES := [")
order=sorted(PREF,key=lambda p:-len(p[0]))
w(",\n".join(f'    ["{p}", {lit(v)}]' for p,v in order))
w("]\n")
w("# Noms usuels des dimensions : clé = dimensions séparées par des virgules.")
w("const _DIM_NAMES := {")
w(",\n".join(f'    "{",".join(map(str,k)) if k else "0,0,0,0,0,0,0"}": "{v}"' for k,v in NAMED.items()))
w("}\n")
open("units_registry.al","w",encoding="utf8").write("\n".join(out)+"\n")
print(len(U),"unités")
