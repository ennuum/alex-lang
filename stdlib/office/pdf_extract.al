# ALEX STANDARD LIBRARY — office.pdf_extract
# Extraction depuis les PDF : texte (ordre de lecture reconstitué, ou mise en page conservée), segments et mots
# positionnés, lignes, recherche, images (JPEG telles quelles, autres converties en PNG), liens, polices,
# métadonnées, tracés vectoriels (traits et rectangles, utilisés par pdf_tables).
#
#   use office.pdf_extract as ex
#   print(ex.text("rapport.pdf"))                         # tout le texte ; pages séparées par un saut de page \f
#   ex.text("rapport.pdf", [0, 2], true)                  # pages 1 et 3, mise en page conservée
#   for w in ex.words(doc.page(0)):                       # {"text", "x0", "y0", "x1", "y1", "size", "font"}
#       ...
#   for img in ex.images("rapport.pdf"):                  # {"page", "name", "width", "height", "format", "data"}
#       io.write_bytes(img["name"] + "." + img["format"], img["data"])
#   ex.search("rapport.pdf", "chiffre d'affaires")        # [{"page", "line"}]
#
# Interprétation des contenus : matrices (cm, Tm, Td...), états graphique et texte (q/Q, Tc, Tw, Tz, TL, Ts),
#   formulaires XObject imbriqués, images en ligne ; polices simples (Type1, TrueType, Type3 : encodages Standard,
#   WinAnsi, MacRoman, Symbol, ZapfDingbats, Differences avec noms de glyphes Adobe), composites (Type0, CMap
#   Identity-H/V ou incorporée), tables ToUnicode (bfchar / bfrange). Rotation de page prise en compte.
#
# DOCUMENT  open(src, password="") -> pdf_reader.PdfFile (src : chemin, octets ou PdfFile)
# TEXTE     text(src, pages=null, layout=false, password="") -> str   page_text(page, layout=false)
#           chunks(page) -> segments {"text", "x", "y", "x1", "size", "font", "widths"} (coordonnées de la page
#           affichée : origine en haut à gauche, y vers le bas)   lines(page) -> [{"text", "x0", "x1", "y", "size", "chunks"}]
#           words(page) -> mots avec boîte   search(src, motif, ignore_case=true) -> [{"page", "line"}]
# GRAPHISME graphics(page) -> {"lines": [[x0, y0, x1, y1]...], "rects": [[x0, y0, x1, y1]...]} (même repère)
# AUTRES    images(src, pages=null) -> liste   links(src) -> [{"page", "rect", "uri" | "target_page"}]
#           fonts(src) -> [{"name", "type", "embedded", "pages"}]   metadata(src) -> {"info", "xmp", "pages",
#           "version", "encrypted"}   png_encode(pixels, largeur, hauteur, canaux, profondeur=8, palette=null) -> octets
# Erreurs : PDFError, UnsupportedError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use math
use office.errors as errors
use office.utils as u
use office.compression as compression
use office.pdf_reader as pr
use office.pdf_writer as pw

const STANDARD_ENCODING := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 8217, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 8216, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 8260, 165, 402, 167, 164, 39, 8220, 171, 8249, 8250, 64257, 64258, 176, 8211, 8224, 8225, 183, 181, 182, 8226, 8218, 8222, 8221, 187, 8230, 8240, 190, 191, 192, 96, 180, 710, 732, 175, 728, 729, 168, 201, 730, 184, 204, 733, 731, 711, 8212, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 198, 226, 170, 228, 229, 230, 231, 321, 216, 338, 186, 236, 237, 238, 239, 240, 230, 242, 243, 244, 305, 246, 247, 322, 248, 339, 223, 252, 253, 254, 255]
const MAC_ROMAN_ENCODING := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 196, 197, 199, 201, 209, 214, 220, 225, 224, 226, 228, 227, 229, 231, 233, 232, 234, 235, 237, 236, 238, 239, 241, 243, 242, 244, 246, 245, 250, 249, 251, 252, 8224, 176, 162, 163, 167, 8226, 182, 223, 174, 169, 8482, 180, 168, 8800, 198, 216, 8734, 177, 8804, 8805, 165, 181, 8706, 8721, 8719, 960, 8747, 170, 186, 937, 230, 248, 191, 161, 172, 8730, 402, 8776, 8710, 171, 187, 8230, 160, 192, 195, 213, 338, 339, 8211, 8212, 8220, 8221, 8216, 8217, 247, 9674, 255, 376, 8260, 8364, 8249, 8250, 64257, 64258, 8225, 183, 8218, 8222, 8240, 194, 202, 193, 203, 200, 205, 206, 207, 204, 211, 212, 63743, 210, 218, 219, 217, 305, 710, 732, 175, 728, 729, 730, 184, 733, 731, 711]
const SYMBOL_ENCODING := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 8704, 35, 8707, 37, 38, 8715, 40, 41, 8727, 43, 44, 8722, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 8773, 913, 914, 935, 916, 917, 934, 915, 919, 921, 977, 922, 923, 924, 925, 927, 928, 920, 929, 931, 932, 933, 962, 937, 926, 936, 918, 91, 8756, 93, 8869, 95, 63717, 945, 946, 967, 948, 949, 966, 947, 951, 953, 981, 954, 955, 181, 957, 959, 960, 952, 961, 963, 964, 965, 982, 969, 958, 968, 950, 123, 124, 125, 8764, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 8364, 978, 8242, 8804, 8260, 8734, 402, 9827, 9830, 9829, 9824, 8596, 8592, 8593, 8594, 8595, 176, 177, 8243, 8805, 215, 8733, 8706, 8226, 247, 8800, 8801, 8776, 8230, 63718, 63719, 8629, 8501, 8465, 8476, 8472, 8855, 8853, 8709, 8745, 8746, 8835, 8839, 8836, 8834, 8838, 8712, 8713, 8736, 8711, 63194, 63193, 63195, 8719, 8730, 8901, 172, 8743, 8744, 8660, 8656, 8657, 8658, 8659, 9674, 9001, 63720, 63721, 63722, 8721, 63723, 63724, 63725, 63726, 63727, 63728, 63729, 63730, 63731, 63732, 240, 9002, 8747, 8992, 63733, 8993, 63734, 63735, 63736, 63737, 63738, 63739, 63740, 63741, 63742, 255]
const ZAPF_ENCODING := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 9985, 9986, 9987, 9988, 9742, 9990, 9991, 9992, 9993, 9755, 9758, 9996, 9997, 9998, 9999, 10000, 10001, 10002, 10003, 10004, 10005, 10006, 10007, 10008, 10009, 10010, 10011, 10012, 10013, 10014, 10015, 10016, 10017, 10018, 10019, 10020, 10021, 10022, 10023, 9733, 10025, 10026, 10027, 10028, 10029, 10030, 10031, 10032, 10033, 10034, 10035, 10036, 10037, 10038, 10039, 10040, 10041, 10042, 10043, 10044, 10045, 10046, 10047, 10048, 10049, 10050, 10051, 10052, 10053, 10054, 10055, 10056, 10057, 10058, 10059, 9679, 10061, 9632, 10063, 10064, 10065, 10066, 9650, 9660, 9670, 10070, 9687, 10072, 10073, 10074, 10075, 10076, 10077, 10078, 127, 63703, 63704, 63705, 63706, 63707, 63708, 63709, 63710, 63711, 63712, 63713, 63714, 63715, 63716, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 10081, 10082, 10083, 10084, 10085, 10086, 10087, 9827, 9830, 9829, 9824, 9312, 9313, 9314, 9315, 9316, 9317, 9318, 9319, 9320, 9321, 10102, 10103, 10104, 10105, 10106, 10107, 10108, 10109, 10110, 10111, 10112, 10113, 10114, 10115, 10116, 10117, 10118, 10119, 10120, 10121, 10122, 10123, 10124, 10125, 10126, 10127, 10128, 10129, 10130, 10131, 10132, 8594, 8596, 8597, 10136, 10137, 10138, 10139, 10140, 10141, 10142, 10143, 10144, 10145, 10146, 10147, 10148, 10149, 10150, 10151, 10152, 10153, 10154, 10155, 10156, 10157, 10158, 10159, 240, 10161, 10162, 10163, 10164, 10165, 10166, 10167, 10168, 10169, 10170, 10171, 10172, 10173, 10174, 255]
const GLYPH_NAMES := {"/.notdef": "\u25a1", "/A": "A", "/AE": "\u00c6", "/AEacute": "\u01fc", "/AEmacron": "\u01e2", "/Aacute": "\u00c1", "/Abreve": "\u0102", "/Abrevecyr": "\u04d0", "/Abrevecyrillic": "\u04d0", "/Acaron": "\u01cd", "/Acircumflex": "\u00c2", "/Acyr": "\u0410", "/Acyrillic": "\u0410", "/Adblgrave": "\u0200", "/Adieresis": "\u00c4", "/Adieresiscyr": "\u04d2", "/Adieresiscyrillic": "\u04d2", "/Adieresismacron": "\u01de", "/Adot": "\u0226", "/Adotmacron": "\u01e0", "/Agrave": "\u00c0", "/Agravedbl": "\u0200", "/Aiecyr": "\u04d4", "/Aiecyrillic": "\u04d4", "/Ainvertedbreve": "\u0202", "/Alpha": "\u0391", "/Alphatonos": "\u0386", "/Amacron": "\u0100", "/Aogonek": "\u0104", "/Aring": "\u00c5", "/Aringacute": "\u01fa", "/Astroke": "\u023a", "/Atilde": "\u00c3", "/B": "B", "/Becyr": "\u0411", "/Becyrillic": "\u0411", "/Beta": "\u0392", "/Bhook": "\u0181", "/Bscript": "\u212c", "/Bstroke": "\u0243", "/Btopbar": "\u0182", "/C": "C", "/Cacute": "\u0106", "/Ccaron": "\u010c", "/Ccedilla": "\u00c7", "/Ccircumflex": "\u0108", "/Cdblstruck": "\u2102", "/Cdot": "\u010a", "/Cdotaccent": "\u010a", "/Cfraktur": "\u212d", "/Cheabkhasiancyrillic": "\u04bc", "/Cheabkhcyr": "\u04bc", "/Cheabkhtailcyr": "\u04be", "/Checyr": "\u0427", "/Checyrillic": "\u0427", "/Chedescenderabkhasiancyrillic": "\u04be", "/Chedescendercyrillic": "\u04b6", "/Chedieresiscyr": "\u04f4", "/Chedieresiscyrillic": "\u04f4", "/Chekhakascyr": "\u04cb", "/Chekhakassiancyrillic": "\u04cb", "/Chetailcyr": "\u04b6", "/Chevertcyr": "\u04b8", "/Cheverticalstrokecyrillic": "\u04b8", "/Chi": "\u03a7", "/Chook": "\u0187", "/Cstroke": "\u023b", "/D": "D", "/DZ": "\u01f1", "/DZcaron": "\u01c4", "/Dafrican": "\u0189", "/Dbar": "\u0110", "/Dcaron": "\u010e", "/Dcroat": "\u0110", "/Ddblstruckitalic": "\u2145", "/Decyr": "\u0414", "/Decyrillic": "\u0414", "/Deicoptic": "\u03ee", "/Delta": "\u2206", "/Deltagreek": "\u0394", "/Dhook": "\u018a", "/Digamma": "\u03dc", "/Digammagreek": "\u03dc", "/Digammapamphylian": "\u0376", "/Djecyr": "\u0402", "/Djecyrillic": "\u0402", "/Dslash": "\u0110", "/Dtopbar": "\u018b", "/Dz": "\u01f2", "/Dzcaron": "\u01c5", "/Dzeabkhasiancyrillic": "\u04e0", "/Dzeabkhcyr": "\u04e0", "/Dzecyr": "\u0405", "/Dzecyrillic": "\u0405", "/Dzhecyr": "\u040f", "/Dzhecyrillic": "\u040f", "/E": "E", "/Eacute": "\u00c9", "/Ebreve": "\u0114", "/Ecaron": "\u011a", "/Ecedilla": "\u0228", "/Ecircumflex": "\u00ca", "/Ecyrillic": "\u0404", "/Edblgrave": "\u0204", "/Edieresis": "\u00cb", "/Edot": "\u0116", "/Edotaccent": "\u0116", "/Efcyr": "\u0424", "/Efcyrillic": "\u0424", "/Egrave": "\u00c8", "/Egravedbl": "\u0204", "/Eightroman": "\u2167", "/Einvertedbreve": "\u0206", "/Eiotifiedcyr": "\u0464", "/Eiotifiedcyrillic": "\u0464", "/Elcyr": "\u041b", "/Elcyrillic": "\u041b", "/Elevenroman": "\u216a", "/Elsharptailcyr": "\u04c5", "/Emacron": "\u0112", "/Emcyr": "\u041c", "/Emcyrillic": "\u041c", "/Emsharptailcyr": "\u04cd", "/Encyr": "\u041d", "/Encyrillic": "\u041d", "/Endescendercyrillic": "\u04a2", "/Eng": "\u014a", "/Engecyr": "\u04a4", "/Enghecyrillic": "\u04a4", "/Enhookcyr": "\u04c7", "/Enhookcyrillic": "\u04c7", "/Ensharptailcyr": "\u04c9", "/Entailcyr": "\u04a2", "/Eogonek": "\u0118", "/Eopen": "\u0190", "/Epsilon": "\u0395", "/Epsilontonos": "\u0388", "/Ercyr": "\u0420", "/Ercyrillic": "\u0420", "/Ereversed": "\u018e", "/Ereversedcyr": "\u042d", "/Ereversedcyrillic": "\u042d", "/Ereverseddieresiscyr": "\u04ec", "/Ertickcyr": "\u048e", "/Escript": "\u2130", "/Escyr": "\u0421", "/Escyrillic": "\u0421", "/Esdescendercyrillic": "\u04aa", "/Esh": "\u01a9", "/Estailcyr": "\u04aa", "/Estroke": "\u0246", "/Eta": "\u0397", "/Etatonos": "\u0389", "/Eth": "\u00d0", "/Eukrcyr": "\u0404", "/Euro": "\u20ac", "/Ezh": "\u01b7", "/Ezhcaron": "\u01ee", "/Ezhreversed": "\u01b8", "/F": "F", "/Feicoptic": "\u03e4", "/Fhook": "\u0191", "/Finv": "\u2132", "/Fitacyr": "\u0472", "/Fitacyrillic": "\u0472", "/Fiveroman": "\u2164", "/Fourroman": "\u2163", "/Fscript": "\u2131", "/Fturned": "\u2132", "/G": "G", "/Gacute": "\u01f4", "/Gamma": "\u0393", "/Gammaafrican": "\u0194", "/Gammadblstruck": "\u213e", "/Gangiacoptic": "\u03ea", "/Gbreve": "\u011e", "/Gcaron": "\u01e6", "/Gcedilla": "\u0122", "/Gcircumflex": "\u011c", "/Gcommaaccent": "\u0122", "/Gdot": "\u0120", "/Gdotaccent": "\u0120", "/Gecyr": "\u0413", "/Gecyrillic": "\u0413", "/Gehookcyr": "\u0494", "/Gehookstrokecyr": "\u04fa", "/Gestrokecyr": "\u0492", "/Getailcyr": "\u04f6", "/Geupcyr": "\u0490", "/Ghemiddlehookcyrillic": "\u0494", "/Ghestrokecyrillic": "\u0492", "/Gheupturncyrillic": "\u0490", "/Ghook": "\u0193", "/Gjecyr": "\u0403", "/Gjecyrillic": "\u0403", "/Glottalstop": "\u0241", "/Gmir": "\u2141", "/Gstroke": "\u01e4", "/Gturnedsans": "\u2141", "/H": "H", "/H18533": "\u25cf", "/H18543": "\u25aa", "/H18551": "\u25ab", "/H22073": "\u25a1", "/Haabkhasiancyrillic": "\u04a8", "/Haabkhcyr": "\u04a8", "/Hacyr": "\u0425", "/Hadescendercyrillic": "\u04b2", "/Hahookcyr": "\u04fc", "/Hardcyr": "\u042a", "/Hardsigncyrillic": "\u042a", "/Hastrokecyr": "\u04fe", "/Hbar": "\u0126", "/Hcaron": "\u021e", "/Hcircumflex": "\u0124", "/Hdblstruck": "\u210d", "/Heta": "\u0370", "/Hfraktur": "\u210c", "/Horicoptic": "\u03e8", "/Hscript": "\u210b", "/Hwair": "\u01f6", "/I": "I", "/IAcyrillic": "\u042f", "/IJ": "\u0132", "/IUcyrillic": "\u042e", "/Iacute": "\u00cd", "/Ibreve": "\u012c", "/Icaron": "\u01cf", "/Icircumflex": "\u00ce", "/Icyr": "\u0418", "/Icyrillic": "\u0406", "/Idblgrave": "\u0208", "/Idieresis": "\u00cf", "/Idieresiscyr": "\u04e4", "/Idieresiscyrillic": "\u04e4", "/Idot": "\u0130", "/Idotaccent": "\u0130", "/Iebrevecyr": "\u04d6", "/Iebrevecyrillic": "\u04d6", "/Iecyr": "\u0415", "/Iecyrillic": "\u0415", "/Iegravecyr": "\u0400", "/Ifractur": "\u2111", "/Ifraktur": "\u2111", "/Igrave": "\u00cc", "/Igravecyr": "\u040d", "/Igravedbl": "\u0208", "/Iicyrillic": "\u0418", "/Iinvertedbreve": "\u020a", "/Iishortcyrillic": "\u0419", "/Imacron": "\u012a", "/Imacroncyr": "\u04e2", "/Imacroncyrillic": "\u04e2", "/Iocyr": "\u0401", "/Iocyrillic": "\u0401", "/Iogonek": "\u012e", "/Iota": "\u0399", "/Iotaafrican": "\u0196", "/Iotadieresis": "\u03aa", "/Iotatonos": "\u038a", "/Iscript": "\u2110", "/Ishortcyr": "\u0419", "/Ishortsharptailcyr": "\u048a", "/Istroke": "\u0197", "/Itilde": "\u0128", "/Iukrcyr": "\u0406", "/Izhitsacyr": "\u0474", "/Izhitsacyrillic": "\u0474", "/Izhitsadblgravecyrillic": "\u0476", "/Izhitsagravedblcyr": "\u0476", "/J": "J", "/Jcircumflex": "\u0134", "/Jecyr": "\u0408", "/Jecyrillic": "\u0408", "/Jstroke": "\u0248", "/K": "K", "/Kabashkcyr": "\u04a0", "/Kabashkircyrillic": "\u04a0", "/Kacyr": "\u041a", "/Kacyrillic": "\u041a", "/Kadescendercyrillic": "\u049a", "/Kahookcyr": "\u04c3", "/Kahookcyrillic": "\u04c3", "/Kaisymbol": "\u03cf", "/Kappa": "\u039a", "/Kastrokecyr": "\u049e", "/Kastrokecyrillic": "\u049e", "/Katailcyr": "\u049a", "/Kaverticalstrokecyr": "\u049c", "/Kaverticalstrokecyrillic": "\u049c", "/Kcaron": "\u01e8", "/Kcedilla": "\u0136", "/Kcommaaccent": "\u0136", "/Khacyrillic": "\u0425", "/Kheicoptic": "\u03e6", "/Khook": "\u0198", "/Kjecyr": "\u040c", "/Kjecyrillic": "\u040c", "/Koppa": "\u03de", "/Koppaarchaic": "\u03d8", "/Koppacyr": "\u0480", "/Koppacyrillic": "\u0480", "/Koppagreek": "\u03de", "/Ksicyr": "\u046e", "/Ksicyrillic": "\u046e", "/L": "L", "/LJ": "\u01c7", "/Lacute": "\u0139", "/Lambda": "\u039b", "/Lbar": "\u023d", "/Lcaron": "\u013d", "/Lcedilla": "\u013b", "/Lcommaaccent": "\u013b", "/Ldot": "\u013f", "/Ldotaccent": "\u013f", "/Lj": "\u01c8", "/Ljecyr": "\u0409", "/Ljecyrillic": "\u0409", "/Lreversedsans": "\u2143", "/Lscript": "\u2112", "/Lslash": "\u0141", "/Lturnedsans": "\u2142", "/M": "M", "/Mscript": "\u2133", "/Mturned": "\u019c", "/Mu": "\u039c", "/N": "N", "/NJ": "\u01ca", "/Nacute": "\u0143", "/Ncaron": "\u0147", "/Ncedilla": "\u0145", "/Ncommaaccent": "\u0145", "/Ndblstruck": "\u2115", "/Ng": "\u014a", "/Ngrave": "\u01f8", "/Nhookleft": "\u019d", "/Nineroman": "\u2168", "/Nj": "\u01cb", "/Njecyr": "\u040a", "/Njecyrillic": "\u040a", "/Nlongrightleg": "\u0220", "/Ntilde": "\u00d1", "/Nu": "\u039d", "/O": "O", "/OE": "\u0152", "/Oacute": "\u00d3", "/Obar": "\u019f", "/Obarcyr": "\u04e8", "/Obardieresiscyr": "\u04ea", "/Obarredcyrillic": "\u04e8", "/Obarreddieresiscyrillic": "\u04ea", "/Obreve": "\u014e", "/Ocaron": "\u01d1", "/Ocenteredtilde": "\u019f", "/Ocircumflex": "\u00d4", "/Ocyr": "\u041e", "/Ocyrillic": "\u041e", "/Odblacute": "\u0150", "/Odblgrave": "\u020c", "/Odieresis": "\u00d6", "/Odieresiscyr": "\u04e6", "/Odieresiscyrillic": "\u04e6", "/Odieresismacron": "\u022a", "/Odot": "\u022e", "/Odotmacron": "\u0230", "/Ograve": "\u00d2", "/Ogravedbl": "\u020c", "/Ohm": "\u2126", "/Ohorn": "\u01a0", "/Ohungarumlaut": "\u0150", "/Oi": "\u01a2", "/Oinvertedbreve": "\u020e", "/Omacron": "\u014c", "/Omega": "\u2126", "/Omegacyr": "\u0460", "/Omegacyrillic": "\u0460", "/Omegagreek": "\u03a9", "/Omegainv": "\u2127", "/Omegaroundcyr": "\u047a", "/Omegaroundcyrillic": "\u047a", "/Omegatitlocyr": "\u047c", "/Omegatitlocyrillic": "\u047c", "/Omegatonos": "\u038f", "/Omicron": "\u039f", "/Omicrontonos": "\u038c", "/Oneroman": "\u2160", "/Oogonek": "\u01ea", "/Oogonekmacron": "\u01ec", "/Oopen": "\u0186", "/Oslash": "\u00d8", "/Oslashacute": "\u01fe", "/Ostrokeacute": "\u01fe", "/Otcyr": "\u047e", "/Otcyrillic": "\u047e", "/Otilde": "\u00d5", "/Otildemacron": "\u022c", "/Ou": "\u0222", "/P": "P", "/Palochkacyr": "\u04c0", "/Pdblstruck": "\u2119", "/Pecyr": "\u041f", "/Pecyrillic": "\u041f", "/Pehookcyr": "\u04a6", "/Pemiddlehookcyrillic": "\u04a6", "/Phi": "\u03a6", "/Phook": "\u01a4", "/Pi": "\u03a0", "/Pidblstruck": "\u213f", "/Psi": "\u03a8", "/Psicyr": "\u0470", "/Psicyrillic": "\u0470", "/Q": "Q", "/Qdblstruck": "\u211a", "/Qrotated": "\u213a", "/Qsmallhooktail": "\u024a", "/R": "R", "/Racute": "\u0154", "/Rcaron": "\u0158", "/Rcedilla": "\u0156", "/Rcommaaccent": "\u0156", "/Rdblgrave": "\u0210", "/Rdblstruck": "\u211d", "/Reverseddottedsigmalunatesymbol": "\u03ff", "/Rfractur": "\u211c", "/Rfraktur": "\u211c", "/Rgravedbl": "\u0210", "/Rho": "\u03a1", "/Rinvertedbreve": "\u0212", "/Rscript": "\u211b", "/Rstroke": "\u024c", "/S": "S", "/SF010000": "\u250c", "/SF020000": "\u2514", "/SF030000": "\u2510", "/SF040000": "\u2518", "/SF050000": "\u253c", "/SF060000": "\u252c", "/SF070000": "\u2534", "/SF080000": "\u251c", "/SF090000": "\u2524", "/SF100000": "\u2500", "/SF110000": "\u2502", "/SF190000": "\u2561", "/SF200000": "\u2562", "/SF210000": "\u2556", "/SF220000": "\u2555", "/SF230000": "\u2563", "/SF240000": "\u2551", "/SF250000": "\u2557", "/SF260000": "\u255d", "/SF270000": "\u255c", "/SF280000": "\u255b", "/SF360000": "\u255e", "/SF370000": "\u255f", "/SF380000": "\u255a", "/SF390000": "\u2554", "/SF400000": "\u2569", "/SF410000": "\u2566", "/SF420000": "\u2560", "/SF430000": "\u2550", "/SF440000": "\u256c", "/SF450000": "\u2567", "/SF460000": "\u2568", "/SF470000": "\u2564", "/SF480000": "\u2565", "/SF490000": "\u2559", "/SF500000": "\u2558", "/SF510000": "\u2552", "/SF520000": "\u2553", "/SF530000": "\u256b", "/SF540000": "\u256a", "/SS": "S", "/Sacute": "\u015a", "/Sampi": "\u03e0", "/Sampiarchaic": "\u0372", "/Sampigreek": "\u03e0", "/San": "\u03fa", "/Scaron": "\u0160", "/Scedilla": "\u015e", "/Schwa": "\u018f", "/Schwacyr": "\u04d8", "/Schwacyrillic": "\u04d8", "/Schwadieresiscyr": "\u04da", "/Schwadieresiscyrillic": "\u04da", "/Scircumflex": "\u015c", "/Scommaaccent": "\u0218", "/Semisoftcyr": "\u048c", "/Sevenroman": "\u2166", "/Shacyr": "\u0428", "/Shacyrillic": "\u0428", "/Shchacyr": "\u0429", "/Shchacyrillic": "\u0429", "/Sheicoptic": "\u03e2", "/Shhacyr": "\u04ba", "/Shhacyrillic": "\u04ba", "/Shimacoptic": "\u03ec", "/Sho": "\u03f7", "/Sigma": "\u03a3", "/Sigmalunatesymbol": "\u03f9", "/Sigmalunatesymboldotted": "\u03fe", "/Sigmareversedlunatesymbol": "\u03fd", "/Sixroman": "\u2165", "/Softcyr": "\u042c", "/Softsigncyrillic": "\u042c", "/Stigma": "\u03da", "/Stigmagreek": "\u03da", "/T": "T", "/Tau": "\u03a4", "/Tbar": "\u0166", "/Tcaron": "\u0164", "/Tcedilla": "\u0162", "/Tcommaaccent": "\u0162", "/Tecyr": "\u0422", "/Tecyrillic": "\u0422", "/Tedescendercyrillic": "\u04ac", "/Tenroman": "\u2169", "/Tetailcyr": "\u04ac", "/Tetsecyr": "\u04b4", "/Tetsecyrillic": "\u04b4", "/Theta": "\u0398", "/Thetasymbol": "\u03f4", "/Thook": "\u01ac", "/Thorn": "\u00de", "/Threeroman": "\u2162", "/Tonefive": "\u01bc", "/Tonesix": "\u0184", "/Tonetwo": "\u01a7", "/Tretroflexhook": "\u01ae", "/Tsecyr": "\u0426", "/Tsecyrillic": "\u0426", "/Tshecyr": "\u040b", "/Tshecyrillic": "\u040b", "/Twelveroman": "\u216b", "/Twithdiagonalstroke": "\u023e", "/Tworoman": "\u2161", "/U": "U", "/Uacute": "\u00da", "/Uacutedblcyr": "\u04f2", "/Ubar": "\u0244", "/Ubreve": "\u016c", "/Ucaron": "\u01d3", "/Ucircumflex": "\u00db", "/Ucyr": "\u0423", "/Ucyrillic": "\u0423", "/Udblacute": "\u0170", "/Udblgrave": "\u0214", "/Udieresis": "\u00dc", "/Udieresisacute": "\u01d7", "/Udieresiscaron": "\u01d9", "/Udieresiscyr": "\u04f0", "/Udieresiscyrillic": "\u04f0", "/Udieresisgrave": "\u01db", "/Udieresismacron": "\u01d5", "/Ugrave": "\u00d9", "/Ugravedbl": "\u0214", "/Uhorn": "\u01af", "/Uhungarumlaut": "\u0170", "/Uhungarumlautcyrillic": "\u04f2", "/Uinvertedbreve": "\u0216", "/Ukcyr": "\u0478", "/Ukcyrillic": "\u0478", "/Umacron": "\u016a", "/Umacroncyr": "\u04ee", "/Umacroncyrillic": "\u04ee", "/Uogonek": "\u0172", "/Upsilon": "\u03a5", "/Upsilon1": "\u03d2", "/Upsilonacutehooksymbol": "\u03d3", "/Upsilonacutehooksymbolgreek": "\u03d3", "/Upsilonadieresishooksymbol": "\u03d4", "/Upsilonafrican": "\u01b1", "/Upsilondieresis": "\u03ab", "/Upsilondieresishooksymbolgreek": "\u03d4", "/Upsilonhooksymbol": "\u03d2", "/Upsilontonos": "\u038e", "/Uring": "\u016e", "/Ushortcyr": "\u040e", "/Ushortcyrillic": "\u040e", "/Ustraightcyr": "\u04ae", "/Ustraightcyrillic": "\u04ae", "/Ustraightstrokecyr": "\u04b0", "/Ustraightstrokecyrillic": "\u04b0", "/Utilde": "\u0168", "/V": "V", "/Vecyr": "\u0412", "/Vecyrillic": "\u0412", "/Vhook": "\u01b2", "/Vturned": "\u0245", "/W": "W", "/Wcircumflex": "\u0174", "/Wynn": "\u01f7", "/X": "X", "/Xatailcyr": "\u04b2", "/Xi": "\u039e", "/Y": "Y", "/Yacute": "\u00dd", "/Yacyr": "\u042f", "/Yatcyr": "\u0462", "/Yatcyrillic": "\u0462", "/Ycircumflex": "\u0176", "/Ydieresis": "\u0178", "/Yen": "\u00a5", "/Yericyrillic": "\u042b", "/Yerudieresiscyrillic": "\u04f8", "/Yhook": "\u01b3", "/Yicyrillic": "\u0407", "/Ylongcyr": "\u042b", "/Ylongdieresiscyr": "\u04f8", "/Ymacron": "\u0232", "/Yogh": "\u021c", "/Yot": "\u037f", "/Ystroke": "\u024e", "/Yturnedsans": "\u2144", "/Yucyr": "\u042e", "/Yukrcyr": "\u0407", "/Yusbigcyr": "\u046a", "/Yusbigcyrillic": "\u046a", "/Yusbigiotifiedcyr": "\u046c", "/Yusbigiotifiedcyrillic": "\u046c", "/Yuslittlecyr": "\u0466", "/Yuslittlecyrillic": "\u0466", "/Yuslittleiotifiedcyr": "\u0468", "/Yuslittleiotifiedcyrillic": "\u0468", "/Z": "Z", "/Zacute": "\u0179", "/Zcaron": "\u017d", "/Zdblstruck": "\u2124", "/Zdot": "\u017b", "/Zdotaccent": "\u017b", "/Zecyr": "\u0417", "/Zecyrillic": "\u0417", "/Zedescendercyrillic": "\u0498", "/Zedieresiscyr": "\u04de", "/Zedieresiscyrillic": "\u04de", "/Zeta": "\u0396", "/Zetailcyr": "\u0498", "/Zfraktur": "\u2128", "/Zhebrevecyr": "\u04c1", "/Zhebrevecyrillic": "\u04c1", "/Zhecyr": "\u0416", "/Zhecyrillic": "\u0416", "/Zhedescendercyrillic": "\u0496", "/Zhedieresiscyr": "\u04dc", "/Zhedieresiscyrillic": "\u04dc", "/Zhetailcyr": "\u0496", "/Zhook": "\u0224", "/Zstroke": "\u01b5", "/a": "a", "/a0": "\u0000", "/a1": "\u0001", "/a10": "\u000a", "/a100": "d", "/a101": "e", "/a102": "f", "/a103": "g", "/a104": "h", "/a105": "i", "/a106": "j", "/a107": "k", "/a108": "l", "/a109": "m", "/a11": "\u000b", "/a110": "n", "/a111": "o", "/a112": "p", "/a113": "q", "/a114": "r", "/a115": "s", "/a116": "t", "/a117": "u", "/a118": "v", "/a119": "w", "/a12": "\u000c", "/a120": "x", "/a121": "y", "/a122": "z", "/a123": "{", "/a124": "|", "/a125": "}", "/a126": "~", "/a127": "\u007f", "/a128": "\u0080", "/a129": "\u0081", "/a13": "\u000d", "/a130": "\u0082", "/a131": "\u0083", "/a132": "\u0084", "/a133": "\u0085", "/a134": "\u0086", "/a135": "\u0087", "/a136": "\u0088", "/a137": "\u0089", "/a138": "\u008a", "/a139": "\u008b", "/a14": "\u000e", "/a140": "\u008c", "/a141": "\u008d", "/a142": "\u008e", "/a143": "\u008f", "/a144": "\u0090", "/a145": "\u0091", "/a146": "\u0092", "/a147": "\u0093", "/a148": "\u0094", "/a149": "\u0095", "/a15": "\u000f", "/a150": "\u0096", "/a151": "\u0097", "/a152": "\u0098", "/a153": "\u0099", "/a154": "\u009a", "/a155": "\u009b", "/a156": "\u009c", "/a157": "\u009d", "/a158": "\u009e", "/a159": "\u009f", "/a16": "\u0010", "/a160": "\u00a0", "/a161": "\u00a1", "/a162": "\u00a2", "/a163": "\u00a3", "/a164": "\u00a4", "/a165": "\u00a5", "/a166": "\u00a6", "/a167": "\u00a7", "/a168": "\u00a8", "/a169": "\u00a9", "/a17": "\u0011", "/a170": "\u00aa", "/a171": "\u00ab", "/a172": "\u00ac", "/a173": "\u00ad", "/a174": "\u00ae", "/a175": "\u00af", "/a176": "\u00b0", "/a177": "\u00b1", "/a178": "\u00b2", "/a179": "\u00b3", "/a18": "\u0012", "/a180": "\u00b4", "/a181": "\u00b5", "/a182": "\u00b6", "/a183": "\u00b7", "/a184": "\u00b8", "/a185": "\u00b9", "/a186": "\u00ba", "/a187": "\u00bb", "/a188": "\u00bc", "/a189": "\u00bd", "/a19": "\u0013", "/a190": "\u00be", "/a191": "\u00bf", "/a192": "\u00c0", "/a193": "\u00c1", "/a194": "\u00c2", "/a195": "\u00c3", "/a196": "\u00c4", "/a197": "\u00c5", "/a198": "\u00c6", "/a199": "\u00c7", "/a2": "\u0002", "/a20": "\u0014", "/a200": "\u00c8", "/a201": "\u00c9", "/a202": "\u00ca", "/a203": "\u00cb", "/a204": "\u00cc", "/a205": "\u00cd", "/a206": "\u00ce", "/a207": "\u00cf", "/a208": "\u00d0", "/a209": "\u00d1", "/a21": "\u0015", "/a210": "\u00d2", "/a211": "\u00d3", "/a212": "\u00d4", "/a213": "\u00d5", "/a214": "\u00d6", "/a215": "\u00d7", "/a216": "\u00d8", "/a217": "\u00d9", "/a218": "\u00da", "/a219": "\u00db", "/a22": "\u0016", "/a220": "\u00dc", "/a221": "\u00dd", "/a222": "\u00de", "/a223": "\u00df", "/a224": "\u00e0", "/a225": "\u00e1", "/a226": "\u00e2", "/a227": "\u00e3", "/a228": "\u00e4", "/a229": "\u00e5", "/a23": "\u0017", "/a230": "\u00e6", "/a231": "\u00e7", "/a232": "\u00e8", "/a233": "\u00e9", "/a234": "\u00ea", "/a235": "\u00eb", "/a236": "\u00ec", "/a237": "\u00ed", "/a238": "\u00ee", "/a239": "\u00ef", "/a24": "\u0018", "/a240": "\u00f0", "/a241": "\u00f1", "/a242": "\u00f2", "/a243": "\u00f3", "/a244": "\u00f4", "/a245": "\u00f5", "/a246": "\u00f6", "/a247": "\u00f7", "/a248": "\u00f8", "/a249": "\u00f9", "/a25": "\u0019", "/a250": "\u00fa", "/a251": "\u00fb", "/a252": "\u00fc", "/a253": "\u00fd", "/a254": "\u00fe", "/a255": "\u00ff", "/a26": "\u001a", "/a27": "\u001b", "/a28": "\u001c", "/a29": "\u001d", "/a3": "\u0003", "/a30": "\u001e", "/a31": "\u001f", "/a32": " ", "/a33": "!", "/a34": "\u0022", "/a35": "#", "/a36": "$", "/a37": "%", "/a38": "&", "/a39": "'", "/a4": "\u0004", "/a40": "(", "/a41": ")", "/a42": "*", "/a43": "+", "/a44": ",", "/a45": "-", "/a46": ".", "/a47": "/", "/a48": "0", "/a49": "1", "/a5": "\u0005", "/a50": "2", "/a51": "3", "/a52": "4", "/a53": "5", "/a54": "6", "/a55": "7", "/a56": "8", "/a57": "9", "/a58": ":", "/a59": ";", "/a6": "\u0006", "/a60": "<", "/a61": "=", "/a62": ">", "/a63": "?", "/a64": "@", "/a65": "A", "/a66": "B", "/a67": "C", "/a68": "D", "/a69": "E", "/a7": "\u0007", "/a70": "F", "/a71": "G", "/a72": "H", "/a73": "I", "/a74": "J", "/a75": "K", "/a76": "L", "/a77": "M", "/a78": "N", "/a79": "O", "/a8": "\u0008", "/a80": "P", "/a81": "Q", "/a82": "R", "/a83": "S", "/a84": "T", "/a85": "U", "/a86": "V", "/a87": "W", "/a88": "X", "/a89": "Y", "/a9": "\u0009", "/a90": "Z", "/a91": "[", "/a92": "\u005c", "/a93": "]", "/a94": "^", "/a95": "_", "/a96": "`", "/a97": "a", "/a98": "b", "/a99": "c", "/aacute": "\u00e1", "/abreve": "\u0103", "/abrevecyr": "\u04d1", "/abrevecyrillic": "\u04d1", "/acaron": "\u01ce", "/accountof": "\u2100", "/acircumflex": "\u00e2", "/activatearabicformshaping": "\u206d", "/activatesymmetricswapping": "\u206b", "/acute": "\u00b4", "/acyr": "\u0430", "/acyrillic": "\u0430", "/adblgrave": "\u0201", "/addressedsubject": "\u2101", "/adieresis": "\u00e4", "/adieresiscyr": "\u04d3", "/adieresiscyrillic": "\u04d3", "/adieresismacron": "\u01df", "/adot": "\u0227", "/adotmacron": "\u01e1", "/ae": "\u00e6", "/aeacute": "\u01fd", "/aemacron": "\u01e3", "/afii00208": "\u2015", "/afii08941": "\u20a4", "/afii10017": "\u0410", "/afii10018": "\u0411", "/afii10019": "\u0412", "/afii10020": "\u0413", "/afii10021": "\u0414", "/afii10022": "\u0415", "/afii10023": "\u0401", "/afii10024": "\u0416", "/afii10025": "\u0417", "/afii10026": "\u0418", "/afii10027": "\u0419", "/afii10028": "\u041a", "/afii10029": "\u041b", "/afii10030": "\u041c", "/afii10031": "\u041d", "/afii10032": "\u041e", "/afii10033": "\u041f", "/afii10034": "\u0420", "/afii10035": "\u0421", "/afii10036": "\u0422", "/afii10037": "\u0423", "/afii10038": "\u0424", "/afii10039": "\u0425", "/afii10040": "\u0426", "/afii10041": "\u0427", "/afii10042": "\u0428", "/afii10043": "\u0429", "/afii10044": "\u042a", "/afii10045": "\u042b", "/afii10046": "\u042c", "/afii10047": "\u042d", "/afii10048": "\u042e", "/afii10049": "\u042f", "/afii10050": "\u0490", "/afii10051": "\u0402", "/afii10052": "\u0403", "/afii10053": "\u0404", "/afii10054": "\u0405", "/afii10055": "\u0406", "/afii10056": "\u0407", "/afii10057": "\u0408", "/afii10058": "\u0409", "/afii10059": "\u040a", "/afii10060": "\u040b", "/afii10061": "\u040c", "/afii10062": "\u040e", "/afii10065": "\u0430", "/afii10066": "\u0431", "/afii10067": "\u0432", "/afii10068": "\u0433", "/afii10069": "\u0434", "/afii10070": "\u0435", "/afii10071": "\u0451", "/afii10072": "\u0436", "/afii10073": "\u0437", "/afii10074": "\u0438", "/afii10075": "\u0439", "/afii10076": "\u043a", "/afii10077": "\u043b", "/afii10078": "\u043c", "/afii10079": "\u043d", "/afii10080": "\u043e", "/afii10081": "\u043f", "/afii10082": "\u0440", "/afii10083": "\u0441", "/afii10084": "\u0442", "/afii10085": "\u0443", "/afii10086": "\u0444", "/afii10087": "\u0445", "/afii10088": "\u0446", "/afii10089": "\u0447", "/afii10090": "\u0448", "/afii10091": "\u0449", "/afii10092": "\u044a", "/afii10093": "\u044b", "/afii10094": "\u044c", "/afii10095": "\u044d", "/afii10096": "\u044e", "/afii10097": "\u044f", "/afii10098": "\u0491", "/afii10099": "\u0452", "/afii10100": "\u0453", "/afii10101": "\u0454", "/afii10102": "\u0455", "/afii10103": "\u0456", "/afii10104": "\u0457", "/afii10105": "\u0458", "/afii10106": "\u0459", "/afii10107": "\u045a", "/afii10108": "\u045b", "/afii10109": "\u045c", "/afii10110": "\u045e", "/afii10145": "\u040f", "/afii10146": "\u0462", "/afii10147": "\u0472", "/afii10148": "\u0474", "/afii10193": "\u045f", "/afii10194": "\u0463", "/afii10195": "\u0473", "/afii10196": "\u0475", "/afii10846": "\u04d9", "/afii299": "\u200e", "/afii300": "\u200f", "/afii301": "\u200d", "/afii57636": "\u20aa", "/afii61248": "\u2105", "/afii61289": "\u2113", "/afii61352": "\u2116", "/afii61573": "\u202c", "/afii61574": "\u202d", "/afii61575": "\u202e", "/afii61664": "\u200c", "/agrave": "\u00e0", "/agravedbl": "\u0201", "/aiecyr": "\u04d5", "/aiecyrillic": "\u04d5", "/ainvertedbreve": "\u0203", "/aktieselskab": "\u214d", "/aleph": "\u2135", "/allequal": "\u224c", "/almostequalorequal": "\u224a", "/alpha": "\u03b1", "/alphatonos": "\u03ac", "/amacron": "\u0101", "/ampersand": "&", "/ampersandturned": "\u214b", "/angle": "\u2220", "/anglearcright": "\u22be", "/angstrom": "\u212b", "/anoteleia": "\u0387", "/aogonek": "\u0105", "/approaches": "\u2250", "/approacheslimit": "\u2250", "/approxequal": "\u2248", "/approxequalorimage": "\u2252", "/approximatelybutnotactuallyequal": "\u2246", "/approximatelyequal": "\u2245", "/approximatelyequalorimage": "\u2252", "/approxorequal": "\u224a", "/archleftdown": "\u21b6", "/archrightdown": "\u21b7", "/aring": "\u00e5", "/aringacute": "\u01fb", "/arrowNE": "\u2197", "/arrowNW": "\u2196", "/arrowSE": "\u2198", "/arrowSW": "\u2199", "/arrowanticlockwiseopencircle": "\u21ba", "/arrowanticlockwisesemicircle": "\u21b6", "/arrowboth": "\u2194", "/arrowbothv": "\u2195", "/arrowbt": "\u2193", "/arrowclockwiseopencircle": "\u21bb", "/arrowclockwisesemicircle": "\u21b7", "/arrowdashdown": "\u21e3", "/arrowdashleft": "\u21e0", "/arrowdashright": "\u21e2", "/arrowdashup": "\u21e1", "/arrowdblboth": "\u21d4", "/arrowdblbothv": "\u21d5", "/arrowdblbt": "\u21d3", "/arrowdbldown": "\u21d3", "/arrowdblleft": "\u21d0", "/arrowdblright": "\u21d2", "/arrowdbltp": "\u21d1", "/arrowdblup": "\u21d1", "/arrowdown": "\u2193", "/arrowdowndashed": "\u21e3", "/arrowdownfrombar": "\u21a7", "/arrowdownleft": "\u2199", "/arrowdownright": "\u2198", "/arrowdowntwoheaded": "\u21a1", "/arrowdownwhite": "\u21e9", "/arrowdownzigzag": "\u21af", "/arrowhookleft": "\u21aa", "/arrowhookright": "\u21a9", "/arrowleft": "\u2190", "/arrowleftbothalf": "\u21bd", "/arrowleftdashed": "\u21e0", "/arrowleftdbl": "\u21d0", "/arrowleftdblstroke": "\u21cd", "/arrowleftdowncorner": "\u21b5", "/arrowleftdowntip": "\u21b2", "/arrowleftfrombar": "\u21a4", "/arrowlefthook": "\u21a9", "/arrowleftloop": "\u21ab", "/arrowleftoverright": "\u21c6", "/arrowleftoverrighttobar": "\u21b9", "/arrowleftright": "\u2194", "/arrowleftrightstroke": "\u21ae", "/arrowleftrightwave": "\u21ad", "/arrowleftsquiggle": "\u21dc", "/arrowleftstroke": "\u219a", "/arrowlefttail": "\u21a2", "/arrowlefttobar": "\u21e4", "/arrowlefttophalf": "\u21bc", "/arrowlefttwoheaded": "\u219e", "/arrowleftuptip": "\u21b0", "/arrowleftwave": "\u219c", "/arrowleftwhite": "\u21e6", "/arrowlongNWtobar": "\u21b8", "/arrownortheast": "\u2197", "/arrownorthwest": "\u2196", "/arrowparrleftright": "\u21c6", "/arrowparrrightleft": "\u21c4", "/arrowright": "\u2192", "/arrowrightbothalf": "\u21c1", "/arrowrightdashed": "\u21e2", "/arrowrightdblstroke": "\u21cf", "/arrowrightdowncorner": "\u21b4", "/arrowrightdowntip": "\u21b3", "/arrowrightfrombar": "\u21a6", "/arrowrightheavy": "\u279e", "/arrowrighthook": "\u21aa", "/arrowrightloop": "\u21ac", "/arrowrightoverleft": "\u21c4", "/arrowrightsmallcircle": "\u21f4", "/arrowrightsquiggle": "\u21dd", "/arrowrightstroke": "\u219b", "/arrowrighttail": "\u21a3", "/arrowrighttobar": "\u21e5", "/arrowrighttophalf": "\u21c0", "/arrowrighttwoheaded": "\u21a0", "/arrowrightwave": "\u219d", "/arrowrightwhite": "\u21e8", "/arrowsoutheast": "\u2198", "/arrowsouthwest": "\u2199", "/arrowspaireddown": "\u21ca", "/arrowspairedleft": "\u21c7", "/arrowspairedright": "\u21c9", "/arrowspairedup": "\u21c8", "/arrowtableft": "\u21e4", "/arrowtabright": "\u21e5", "/arrowtailleft": "\u21a2", "/arrowtailright": "\u21a3", "/arrowtp": "\u2191", "/arrowtripleleft": "\u21da", "/arrowtripleright": "\u21db", "/arrowup": "\u2191", "/arrowupdashed": "\u21e1", "/arrowupdn": "\u2195", "/arrowupdnbse": "\u21a8", "/arrowupdown": "\u2195", "/arrowupdownbase": "\u21a8", "/arrowupdownwithbase": "\u21a8", "/arrowupfrombar": "\u21a5", "/arrowupleft": "\u2196", "/arrowupleftofdown": "\u21c5", "/arrowupright": "\u2197", "/arrowuprighttip": "\u21b1", "/arrowuptwoheaded": "\u219f", "/arrowupwhite": "\u21e7", "/asciicircum": "^", "/asciitilde": "~", "/assertion": "\u22a6", "/asterisk": "*", "/asteriskcentered": "\u2217", "/asteriskmath": "\u2217", "/asterism": "\u2042", "/asympticallyequal": "\u2243", "/asymptoticallyequal": "\u2243", "/at": "@", "/atilde": "\u00e3", "/austral": "\u20b3", "/b": "b", "/backslash": "\u005c", "/backslashBig": "\u005c", "/backslashBigg": "\u005c", "/backslashbig": "\u005c", "/backslashbigg": "\u005c", "/bar": "|", "/bardbl": "\u2225", "/because": "\u2235", "/becyr": "\u0431", "/becyrillic": "\u0431", "/beta": "\u03b2", "/betasymbol": "\u03d0", "/betasymbolgreek": "\u03d0", "/beth": "\u2136", "/between": "\u226c", "/bitcoin": "\u20bf", "/blackcircle": "\u25cf", "/blackdiamond": "\u25c6", "/blackdownpointingtriangle": "\u25bc", "/blackleftpointingpointer": "\u25c4", "/blackleftpointingtriangle": "\u25c0", "/blacklowerlefttriangle": "\u25e3", "/blacklowerrighttriangle": "\u25e2", "/blackrectangle": "\u25ac", "/blackrightpointingpointer": "\u25ba", "/blackrightpointingtriangle": "\u25b6", "/blacksmallsquare": "\u25aa", "/blacksquare": "\u25a0", "/blackupperlefttriangle": "\u25e4", "/blackupperrighttriangle": "\u25e5", "/blackuppointingsmalltriangle": "\u25b4", "/blackuppointingtriangle": "\u25b2", "/blackwardsbulletleft": "\u204c", "/blackwardsbulletright": "\u204d", "/block": "\u2588", "/braceleft": "{", "/braceleftBig": "{", "/braceleftBigg": "{", "/braceleftbig": "{", "/braceleftbigg": "{", "/braceright": "}", "/bracerightBig": "}", "/bracerightBigg": "}", "/bracerightbig": "}", "/bracerightbigg": "}", "/bracketleft": "[", "/bracketleftBig": "[", "/bracketleftBigg": "[", "/bracketleftbig": "[", "/bracketleftbigg": "[", "/bracketleftsquarequill": "\u2045", "/bracketright": "]", "/bracketrightBig": "]", "/bracketrightBigg": "]", "/bracketrightbig": "]", "/bracketrightbigg": "]", "/bracketrightsquarequill": "\u2046", "/brokenbar": "\u00a6", "/bstroke": "\u0180", "/btopbar": "\u0183", "/bullet": "\u2022", "/bulletinverse": "\u25d8", "/bulletoperator": "\u2219", "/bullseye": "\u25ce", "/c": "c", "/cacute": "\u0107", "/cadauna": "\u2106", "/capslock": "\u21ea", "/careof": "\u2105", "/caret": "\u2038", "/caretinsertionpoint": "\u2041", "/carriagereturn": "\u21b5", "/ccaron": "\u010d", "/ccedilla": "\u00e7", "/ccircumflex": "\u0109", "/cdot": "\u010b", "/cdotaccent": "\u010b", "/cedi": "\u20b5", "/cedilla": "\u00b8", "/cent": "\u00a2", "/centigrade": "\u2103", "/centreline": "\u2104", "/charactertie": "\u2040", "/cheabkhasiancyrillic": "\u04bd", "/cheabkhcyr": "\u04bd", "/cheabkhtailcyr": "\u04bf", "/check": "\u2713", "/checkmark": "\u2713", "/checyr": "\u0447", "/checyrillic": "\u0447", "/chedescenderabkhasiancyrillic": "\u04bf", "/chedescendercyrillic": "\u04b7", "/chedieresiscyr": "\u04f5", "/chedieresiscyrillic": "\u04f5", "/chekhakascyr": "\u04cc", "/chekhakassiancyrillic": "\u04cc", "/chetailcyr": "\u04b7", "/chevertcyr": "\u04b9", "/cheverticalstrokecyrillic": "\u04b9", "/chi": "\u03c7", "/chook": "\u0188", "/circle": "\u25cb", "/circleR": "\u00ae", "/circleallbutupperquadrantleftblack": "\u25d5", "/circleasterisk": "\u229b", "/circleblack": "\u25cf", "/circledasteriskoperator": "\u229b", "/circleddash": "\u229d", "/circleddivisionslash": "\u2298", "/circleddotoperator": "\u2299", "/circledequals": "\u229c", "/circledivide": "\u2298", "/circledminus": "\u2296", "/circledot": "\u2299", "/circledotted": "\u25cc", "/circledringoperator": "\u229a", "/circleequal": "\u229c", "/circlehalfleftblack": "\u25d0", "/circlehalfrightblack": "\u25d1", "/circleinversewhite": "\u25d9", "/circlelowerhalfblack": "\u25d2", "/circlelowerquadrantleftwhite": "\u25f5", "/circlelowerquadrantrightwhite": "\u25f6", "/circleminus": "\u2296", "/circlemultiply": "\u2297", "/circleot": "\u2299", "/circleplus": "\u2295", "/circlering": "\u229a", "/circleupperhalfblack": "\u25d3", "/circleupperquadrantleftwhite": "\u25f4", "/circleupperquadrantrightblack": "\u25d4", "/circleupperquadrantrightwhite": "\u25f7", "/circleverticalfill": "\u25cd", "/circlewhite": "\u25cb", "/circlewithlefthalfblack": "\u25d0", "/circlewithrighthalfblack": "\u25d1", "/clickalveolar": "\u01c2", "/clickdental": "\u01c0", "/clicklateral": "\u01c1", "/clickretroflex": "\u01c3", "/closeup": "\u2050", "/colon": ":", "/colonequals": "\u2254", "/colonmonetary": "\u20a1", "/colonsign": "\u20a1", "/comma": ",", "/commercialminussign": "\u2052", "/complement": "\u2201", "/compwordmark": "\u200c", "/congruent": "\u2245", "/containsasmembersmall": "\u220d", "/containsasnormalsubgroorequalup": "\u22b5", "/containsasnormalsubgroup": "\u22b3", "/containslonghorizontalstroke": "\u22fa", "/containsoverbar": "\u22fd", "/containsoverbarsmall": "\u22fe", "/containssmallverticalbarhorizontalstroke": "\u22fc", "/containsverticalbarhorizontalstroke": "\u22fb", "/contintegraldisplay": "\u222e", "/contintegraltext": "\u222e", "/contourintegral": "\u222e", "/controlACK": "\u0006", "/controlBEL": "\u0007", "/controlBS": "\u0008", "/controlCAN": "\u0018", "/controlCR": "\u000d", "/controlDC1": "\u0011", "/controlDC2": "\u0012", "/controlDC3": "\u0013", "/controlDC4": "\u0014", "/controlDEL": "\u007f", "/controlDLE": "\u0010", "/controlEM": "\u0019", "/controlENQ": "\u0005", "/controlEOT": "\u0004", "/controlESC": "\u001b", "/controlETB": "\u0017", "/controlETX": "\u0003", "/controlFF": "\u000c", "/controlFS": "\u001c", "/controlGS": "\u001d", "/controlHT": "\u0009", "/controlLF": "\u000a", "/controlNAK": "\u0015", "/controlRS": "\u001e", "/controlSI": "\u000f", "/controlSO": "\u000e", "/controlSOT": "\u0002", "/controlSTX": "\u0001", "/controlSUB": "\u001a", "/controlSYN": "\u0016", "/controlUS": "\u001f", "/controlVT": "\u000b", "/coproductarray": "\u2210", "/coproductdisplay": "\u2210", "/coproducttext": "\u2210", "/copyright": "\u00a9", "/corresponds": "\u2258", "/creversed": "\u2184", "/crrn:rupee": "\u20a8", "/cruzeiro": "\u20a2", "/cstroke": "\u023c", "/ct": "c", "/curlyand": "\u22cf", "/curlyleft": "\u21ab", "/curlylogicaland": "\u22cf", "/curlylogicalor": "\u22ce", "/curlyor": "\u22ce", "/curlyright": "\u21ac", "/currency": "\u00a4", "/cwm": "\u200c", "/d": "d", "/d0": "\u2199", "/d1": "\u2199", "/d10": "\u2193", "/d100": "\u2196", "/d101": "\u2196", "/d102": "\u2196", "/d103": "\u2190", "/d104": "\u2190", "/d105": "\u2190", "/d106": "\u2190", "/d107": "\u2190", "/d108": "\u2190", "/d109": "\u2190", "/d11": "\u2193", "/d110": "\u2190", "/d111": "\u2190", "/d112": "\u2190", "/d113": "\u2190", "/d114": "\u2190", "/d115": "\u2190", "/d116": "\u2190", "/d117": "\u2190", "/d118": "\u2190", "/d119": "\u2190", "/d12": "\u2193", "/d120": "\u2199", "/d121": "\u2199", "/d122": "\u2199", "/d123": "\u2199", "/d124": "\u2199", "/d125": "\u2199", "/d126": "\u2199", "/d127": "\u2199", "/d13": "\u2193", "/d14": "\u2193", "/d15": "\u2193", "/d16": "\u2193", "/d17": "\u2193", "/d18": "\u2193", "/d19": "\u2193", "/d2": "\u2199", "/d20": "\u2193", "/d21": "\u2193", "/d22": "\u2193", "/d23": "\u2193", "/d24": "\u2198", "/d25": "\u2198", "/d26": "\u2198", "/d27": "\u2198", "/d28": "\u2198", "/d29": "\u2198", "/d3": "\u2199", "/d30": "\u2198", "/d31": "\u2198", "/d32": "\u2198", "/d33": "\u2198", "/d34": "\u2198", "/d35": "\u2198", "/d36": "\u2198", "/d37": "\u2198", "/d38": "\u2198", "/d39": "\u2192", "/d4": "\u2199", "/d40": "\u2192", "/d41": "\u2192", "/d42": "\u2192", "/d43": "\u2192", "/d44": "\u2192", "/d45": "\u2192", "/d46": "\u2192", "/d47": "\u2192", "/d48": "\u2192", "/d49": "\u2192", "/d5": "\u2199", "/d50": "\u2192", "/d51": "\u2192", "/d52": "\u2192", "/d53": "\u2192", "/d54": "\u2192", "/d55": "\u2192", "/d56": "\u2197", "/d57": "\u2197", "/d58": "\u2197", "/d59": "\u2197", "/d6": "\u2199", "/d60": "\u2197", "/d61": "\u2197", "/d62": "\u2197", "/d63": "\u2197", "/d64": "\u2197", "/d65": "\u2197", "/d66": "\u2197", "/d67": "\u2197", "/d68": "\u2197", "/d69": "\u2197", "/d7": "\u2193", "/d70": "\u2197", "/d71": "\u2191", "/d72": "\u2191", "/d73": "\u2191", "/d74": "\u2191", "/d75": "\u2191", "/d76": "\u2191", "/d77": "\u2191", "/d78": "\u2191", "/d79": "\u2191", "/d8": "\u2193", "/d80": "\u2191", "/d81": "\u2191", "/d82": "\u2191", "/d83": "\u2191", "/d84": "\u2191", "/d85": "\u2191", "/d86": "\u2191", "/d87": "\u2191", "/d88": "\u2196", "/d89": "\u2196", "/d9": "\u2193", "/d90": "\u2196", "/d91": "\u2196", "/d92": "\u2196", "/d93": "\u2196", "/d94": "\u2196", "/d95": "\u2196", "/d96": "\u2196", "/d97": "\u2196", "/d98": "\u2196", "/d99": "\u2196", "/dagger": "\u2020", "/daggerdbl": "\u2021", "/daleth": "\u2138", "/darkShade": "\u2593", "/dasiacmbcyr": "\u0485", "/dasiapneumatacyrilliccmb": "\u0485", "/dbar": "\u0111", "/dbdigraph": "\u0238", "/dblarrowNE": "\u21d7", "/dblarrowNW": "\u21d6", "/dblarrowSE": "\u21d8", "/dblarrowSW": "\u21d9", "/dblarrowdown": "\u21d3", "/dblarrowdwn": "\u21ca", "/dblarrowheadleft": "\u219e", "/dblarrowheadright": "\u21a0", "/dblarrowleft": "\u21d4", "/dblarrowleftright": "\u21d4", "/dblarrowleftrightstroke": "\u21ce", "/dblarrowleftstroke": "\u21cd", "/dblarrowright": "\u21d2", "/dblarrowrightstroke": "\u21cf", "/dblarrowup": "\u21d1", "/dblarrowupdown": "\u21d5", "/dbldnhorz": "\u2566", "/dbldnleft": "\u2557", "/dbldnright": "\u2554", "/dblhorz": "\u2550", "/dblintegral": "\u222c", "/dbllowline": "\u2017", "/dblstrokearrowdown": "\u21df", "/dblstrokearrowup": "\u21de", "/dbluphorz": "\u2569", "/dblupleft": "\u255d", "/dblupright": "\u255a", "/dblvert": "\u2551", "/dblverthorz": "\u256c", "/dblverticalbar": "\u2016", "/dblvertleft": "\u2563", "/dblvertright": "\u2560", "/dcaron": "\u010f", "/dcroat": "\u0111", "/dcurl": "\u0221", "/ddblstruckitalic": "\u2146", "/decyr": "\u0434", "/decyrillic": "\u0434", "/defines": "\u225c", "/degree": "\u00b0", "/degreecelsius": "\u2103", "/degreefahrenheit": "\u2109", "/deicoptic": "\u03ef", "/delta": "\u03b4", "/deltaequal": "\u225c", "/deltaturned": "\u018d", "/dialytikatonos": "\u0385", "/diamondmath": "\u22c4", "/diamondoperator": "\u22c4", "/diamondwhitewithdiamondsmallblack": "\u25c8", "/dieresis": "\u00a8", "/dieresistonos": "\u0385", "/difference": "\u224f", "/differencebetween": "\u224f", "/digamma": "\u03dd", "/digammapamphylian": "\u0377", "/divide": "\u00f7", "/dividemultiply": "\u22c7", "/divides": "\u2223", "/divisionslash": "\u2215", "/divisiontimes": "\u22c7", "/djecyr": "\u0452", "/djecyrillic": "\u0452", "/dkshade": "\u2593", "/dmacron": "\u0111", "/dnblock": "\u2584", "/dndblhorzsng": "\u2565", "/dndblleftsng": "\u2556", "/dndblrightsng": "\u2553", "/dngb:airplane": "\u2708", "/dngb:arrowfeatheredblackNE": "\u27b6", "/dngb:arrowfeatheredblackSE": "\u27b4", "/dngb:arrowfeatheredblackheavyNE": "\u27b9", "/dngb:arrowfeatheredblackheavySE": "\u27b7", "/dngb:arrowheadrightblack": "\u27a4", "/dngb:arrowheadrightthreeDbottomlight": "\u27a3", "/dngb:arrowheadrightthreeDtoplight": "\u27a2", "/dngb:arrowheavyNE": "\u279a", "/dngb:arrowheavySE": "\u2798", "/dngb:arrowrightbacktiltedshadowedwhite": "\u27ab", "/dngb:arrowrightblack": "\u27a1", "/dngb:arrowrightcircledwhiteheavy": "\u27b2", "/dngb:arrowrightcurvedownblackheavy": "\u27a5", "/dngb:arrowrightcurveupblackheavy": "\u27a6", "/dngb:arrowrightfeatheredblack": "\u27b5", "/dngb:arrowrightfeatheredblackheavy": "\u27b8", "/dngb:arrowrightfeatheredwhite": "\u27b3", "/dngb:arrowrightfronttiltedshadowedwhite": "\u27ac", "/dngb:arrowrightheavy": "\u2799", "/dngb:arrowrightleftshadedwhite": "\u27aa", "/dngb:arrowrightoutlinedopen": "\u27be", "/dngb:arrowrightpointed": "\u279b", "/dngb:arrowrightpointedblackheavy": "\u27a8", "/dngb:arrowrightrightshadedwhite": "\u27a9", "/dngb:arrowrightroundheavy": "\u279c", "/dngb:arrowrightsquatblack": "\u27a7", "/dngb:arrowrighttriangle": "\u279d", "/dngb:arrowrighttriangledashed": "\u279f", "/dngb:arrowrighttriangledashedheavy": "\u27a0", "/dngb:arrowrighttriangleheavy": "\u279e", "/dngb:arrowrightwedge": "\u27bc", "/dngb:arrowrightwedgeheavy": "\u27bd", "/dngb:arrowrightwideheavy": "\u2794", "/dngb:arrowshadowrightlowerwhiteheavy": "\u27ad", "/dngb:arrowshadowrightnotchedlowerwhite": "\u27af", "/dngb:arrowshadowrightnotchedupperwhite": "\u27b1", "/dngb:arrowshadowrightupperwhiteheavy": "\u27ae", "/dngb:arrowteardropright": "\u27ba", "/dngb:arrowteardroprightheavy": "\u27bb", "/dngb:asteriskballoon": "\u2749", "/dngb:asteriskballoonfour": "\u2723", "/dngb:asteriskballoonheavyfour": "\u2724", "/dngb:asteriskcentreopen": "\u2732", "/dngb:asteriskclubfour": "\u2725", "/dngb:asteriskheavy": "\u2731", "/dngb:asteriskpointedsixteen": "\u273a", "/dngb:asteriskteardrop": "\u273b", "/dngb:asteriskteardropcentreopen": "\u273c", "/dngb:asteriskteardropfour": "\u2722", "/dngb:asteriskteardropheavy": "\u273d", "/dngb:asteriskteardroppinwheelheavy": "\u2743", "/dngb:asteriskteardroppropellereight": "\u274a", "/dngb:asteriskteardroppropellerheavyeight": "\u274b", "/dngb:ballotx": "\u2717", "/dngb:ballotxheavy": "\u2718", "/dngb:bracketleftpointedangleheavyornament": "\u2770", "/dngb:bracketleftpointedanglemediumornament": "\u276c", "/dngb:bracketrightpointedangleheavyornament": "\u2771", "/dngb:bracketrightpointedanglemediumornament": "\u276d", "/dngb:bracketshellleftlightornament": "\u2772", "/dngb:bracketshellrightlightornament": "\u2773", "/dngb:check": "\u2713", "/dngb:checkheavy": "\u2714", "/dngb:checkwhiteheavy": "\u2705", "/dngb:chevronsnowflakeheavy": "\u2746", "/dngb:circleshadowedwhite": "\u274d", "/dngb:commaheavydoubleornament": "\u275e", "/dngb:commaheavydoubleturnedornament": "\u275d", "/dngb:commaheavyornament": "\u275c", "/dngb:commaheavyturnedornament": "\u275b", "/dngb:compasstarpointedblackeight": "\u2737", "/dngb:compasstarpointedblackheavyeight": "\u2738", "/dngb:cross": "\u274c", "/dngb:crosscentreopen": "\u271b", "/dngb:crosscentreopenheavy": "\u271c", "/dngb:curlybracketleftmediumornament": "\u2774", "/dngb:curlybracketrightmediumornament": "\u2775", "/dngb:curlyloop": "\u27b0", "/dngb:curlyloopdouble": "\u27bf", "/dngb:curvedstemparagraphsignornament": "\u2761", "/dngb:diamondminusxblackwhite": "\u2756", "/dngb:divisionsignheavy": "\u2797", "/dngb:eightnegativecircled": "\u277d", "/dngb:eightsanscircled": "\u2787", "/dngb:eightsansnegativecircled": "\u2791", "/dngb:envelope": "\u2709", "/dngb:exclamationheavy": "\u2757", "/dngb:exclamationheavyornament": "\u2762", "/dngb:exclamationwhiteornament": "\u2755", "/dngb:fivenegativecircled": "\u277a", "/dngb:fivesanscircled": "\u2784", "/dngb:fivesansnegativecircled": "\u278e", "/dngb:floralheart": "\u2766", "/dngb:floralheartbulletrotated": "\u2767", "/dngb:floretteblack": "\u273f", "/dngb:floretteoutlinedpetalledblackeight": "\u2741", "/dngb:florettepetalledblackwhitesix": "\u273e", "/dngb:florettewhite": "\u2740", "/dngb:fournegativecircled": "\u2779", "/dngb:foursanscircled": "\u2783", "/dngb:foursansnegativecircled": "\u278d", "/dngb:greekcrossheavy": "\u271a", "/dngb:greekcrossoutlined": "\u2719", "/dngb:heartblackheavy": "\u2764", "/dngb:heartbulletrotatedblackheavy": "\u2765", "/dngb:heartexclamationheavyornament": "\u2763", "/dngb:hvictory": "\u270c", "/dngb:hwriting": "\u270d", "/dngb:latincross": "\u271d", "/dngb:latincrossoutlined": "\u271f", "/dngb:latincrossshadowedwhite": "\u271e", "/dngb:lowcommaheavydoubleornament": "\u2760", "/dngb:lowcommaheavyornament": "\u275f", "/dngb:maltesecross": "\u2720", "/dngb:minussignheavy": "\u2796", "/dngb:multiplicationx": "\u2715", "/dngb:multiplicationxheavy": "\u2716", "/dngb:nibblack": "\u2712", "/dngb:nibwhite": "\u2711", "/dngb:ninenegativecircled": "\u277e", "/dngb:ninesanscircled": "\u2788", "/dngb:ninesansnegativecircled": "\u2792", "/dngb:onenegativecircled": "\u2776", "/dngb:onesanscircled": "\u2780", "/dngb:onesansnegativecircled": "\u278a", "/dngb:parenthesisleftflattenedmediumornament": "\u276a", "/dngb:parenthesisleftmediumornament": "\u2768", "/dngb:parenthesisrightflattenedmediumornament": "\u276b", "/dngb:parenthesisrightmediumornament": "\u2769", "/dngb:pencil": "\u270f", "/dngb:pencillowerright": "\u270e", "/dngb:pencilupperright": "\u2710", "/dngb:plussignheavy": "\u2795", "/dngb:questionblackornament": "\u2753", "/dngb:questionwhiteornament": "\u2754", "/dngb:quotationleftpointedangleheavyornament": "\u276e", "/dngb:quotationrightpointedangleheavyornament": "\u276f", "/dngb:raisedfist": "\u270a", "/dngb:raisedh": "\u270b", "/dngb:safetyscissorsblack": "\u2700", "/dngb:scissorsblack": "\u2702", "/dngb:scissorslowerblade": "\u2703", "/dngb:scissorsupperblade": "\u2701", "/dngb:scissorswhite": "\u2704", "/dngb:sevennegativecircled": "\u277c", "/dngb:sevensanscircled": "\u2786", "/dngb:sevensansnegativecircled": "\u2790", "/dngb:sixnegativecircled": "\u277b", "/dngb:sixsanscircled": "\u2785", "/dngb:sixsansnegativecircled": "\u278f", "/dngb:snowflake": "\u2744", "/dngb:snowflaketight": "\u2745", "/dngb:sparkle": "\u2747", "/dngb:sparkleheavy": "\u2748", "/dngb:sparkles": "\u2728", "/dngb:spokedasteriskeight": "\u2733", "/dngb:squaredcrossnegative": "\u274e", "/dngb:squarelowerrightshadowedwhite": "\u2751", "/dngb:squareshadowlowerrightwhite": "\u274f", "/dngb:squareshadowupperrightwhite": "\u2750", "/dngb:squareupperrightshadowedwhite": "\u2752", "/dngb:starcentreblackwhite": "\u272c", "/dngb:starcentreopenblack": "\u272b", "/dngb:starcentreopenpointedcircledeight": "\u2742", "/dngb:starcircledwhite": "\u272a", "/dngb:starofdavid": "\u2721", "/dngb:staroutlinedblack": "\u272d", "/dngb:staroutlinedblackheavy": "\u272e", "/dngb:staroutlinedstresswhite": "\u2729", "/dngb:starpinwheel": "\u272f", "/dngb:starpointedblackeight": "\u2734", "/dngb:starpointedblackfour": "\u2726", "/dngb:starpointedblacksix": "\u2736", "/dngb:starpointedblacktwelve": "\u2739", "/dngb:starpointedpinwheeleight": "\u2735", "/dngb:starpointedwhitefour": "\u2727", "/dngb:starshadowedwhite": "\u2730", "/dngb:tapedrive": "\u2707", "/dngb:telephonelocationsign": "\u2706", "/dngb:tennegativecircled": "\u277f", "/dngb:tensanscircled": "\u2789", "/dngb:tensansnegativecircled": "\u2793", "/dngb:threenegativecircled": "\u2778", "/dngb:threesanscircled": "\u2782", "/dngb:threesansnegativecircled": "\u278c", "/dngb:twonegativecircled": "\u2777", "/dngb:twosanscircled": "\u2781", "/dngb:twosansnegativecircled": "\u278b", "/dngb:verticalbarheavy": "\u275a", "/dngb:verticalbarlight": "\u2758", "/dngb:verticalbarmedium": "\u2759", "/dnheavyhorzlight": "\u2530", "/dnheavyleftlight": "\u2512", "/dnheavyleftuplight": "\u2527", "/dnheavyrightlight": "\u250e", "/dnheavyrightuplight": "\u251f", "/dnheavyuphorzlight": "\u2541", "/dnlighthorzheavy": "\u252f", "/dnlightleftheavy": "\u2511", "/dnlightleftupheavy": "\u2529", "/dnlightrightheavy": "\u250d", "/dnlightrightupheavy": "\u2521", "/dnlightuphorzheavy": "\u2547", "/dnsnghorzdbl": "\u2564", "/dnsngleftdbl": "\u2555", "/dnsngrightdbl": "\u2552", "/doesnotcontainasnormalsubgroorequalup": "\u22ed", "/doesnotcontainasnormalsubgroup": "\u22eb", "/doesnotdivide": "\u2224", "/doesnotforce": "\u22ae", "/doesnotprecede": "\u2280", "/doesnotprecedeorequal": "\u22e0", "/doesnotprove": "\u22ac", "/doesnotsucceed": "\u2281", "/doesnotsucceedorequal": "\u22e1", "/dollar": "$", "/dong": "\u20ab", "/dotlessi": "\u0131", "/dotmath": "\u22c5", "/dotminus": "\u2238", "/dotplus": "\u2214", "/dottedcircle": "\u25cc", "/dottedcross": "\u205c", "/downfall": "\u22ce", "/downwarrowleftofuparrow": "\u21f5", "/drachma": "\u20af", "/dtopbar": "\u018c", "/dz": "\u01f3", "/dzcaron": "\u01c6", "/dzeabkhasiancyrillic": "\u04e1", "/dzeabkhcyr": "\u04e1", "/dzecyr": "\u0455", "/dzecyrillic": "\u0455", "/dzhecyr": "\u045f", "/dzhecyrillic": "\u045f", "/e": "e", "/eacute": "\u00e9", "/ebreve": "\u0115", "/ecaron": "\u011b", "/ecedilla": "\u0229", "/ecircumflex": "\u00ea", "/ecyrillic": "\u0454", "/edblgrave": "\u0205", "/edblstruckitalic": "\u2147", "/edieresis": "\u00eb", "/edot": "\u0117", "/edotaccent": "\u0117", "/efcyr": "\u0444", "/efcyrillic": "\u0444", "/egrave": "\u00e8", "/egravedbl": "\u0205", "/eight": "8", "/eight.roman": "\u2167", "/eight.romansmall": "\u2177", "/eightcircleinversesansserif": "\u2791", "/eightroman": "\u2177", "/einvertedbreve": "\u0207", "/eiotifiedcyr": "\u0465", "/eiotifiedcyrillic": "\u0465", "/elcyr": "\u043b", "/elcyrillic": "\u043b", "/element": "\u2208", "/elementdotabove": "\u22f5", "/elementlonghorizontalstroke": "\u22f2", "/elementoverbar": "\u22f6", "/elementoverbarsmall": "\u22f7", "/elementsmall": "\u220a", "/elementsmallverticalbarhorizontalstroke": "\u22f4", "/elementtwoshorizontalstroke": "\u22f9", "/elementunderbar": "\u22f8", "/elementverticalbarhorizontalstroke": "\u22f3", "/eleven.roman": "\u216a", "/eleven.romansmall": "\u217a", "/elevenroman": "\u217a", "/ellipsis": "\u2026", "/ellipsisdiagonaldownright": "\u22f1", "/ellipsisdiagonalupright": "\u22f0", "/ellipsismidhorizontal": "\u22ef", "/ellipsisvertical": "\u22ee", "/elsharptailcyr": "\u04c6", "/emacron": "\u0113", "/emcyr": "\u043c", "/emcyrillic": "\u043c", "/emdash": "\u2014", "/emptyset": "\u2205", "/emquad": "\u2001", "/emsharptailcyr": "\u04ce", "/emspace": "\u2003", "/encyr": "\u043d", "/encyrillic": "\u043d", "/endash": "\u2013", "/endescendercyrillic": "\u04a3", "/endpro": "\u220e", "/eng": "\u014b", "/engecyr": "\u04a5", "/enghecyrillic": "\u04a5", "/enhookcyr": "\u04c8", "/enhookcyrillic": "\u04c8", "/enquad": "\u2000", "/ensharptailcyr": "\u04ca", "/enspace": "\u2002", "/entailcyr": "\u04a3", "/eogonek": "\u0119", "/epsilon": "\u03b5", "/epsilon1": "\u03f5", "/epsiloninv": "\u03f6", "/epsilonlunatesymbol": "\u03f5", "/epsilonreversedlunatesymbol": "\u03f6", "/epsilontonos": "\u03ad", "/equal": "=", "/equalandparallel": "\u22d5", "/equalbydefinition": "\u225d", "/equaldotleftright": "\u2252", "/equaldotrightleft": "\u2253", "/equalorfollows": "\u22df", "/equalorgreater": "\u22dd", "/equalorless": "\u22dc", "/equalorprecedes": "\u22de", "/equalorsimilar": "\u2242", "/equalorsucceeds": "\u22df", "/equalscolon": "\u2255", "/equalsdots": "\u2251", "/equiangular": "\u225a", "/equivalence": "\u2261", "/equivalent": "\u224d", "/equivasymptotic": "\u224d", "/ercyr": "\u0440", "/ercyrillic": "\u0440", "/ereversedcyr": "\u044d", "/ereversedcyrillic": "\u044d", "/ereverseddieresiscyr": "\u04ed", "/ertickcyr": "\u048f", "/escript": "\u212f", "/escyr": "\u0441", "/escyrillic": "\u0441", "/esdescendercyrillic": "\u04ab", "/eshreversedloop": "\u01aa", "/estailcyr": "\u04ab", "/estimated": "\u212e", "/estimates": "\u2259", "/estroke": "\u0247", "/eta": "\u03b7", "/etatonos": "\u03ae", "/eth": "\u00f0", "/eturned": "\u01dd", "/eukrcyr": "\u0454", "/euler": "\u2107", "/euro": "\u20ac", "/euroarchaic": "\u20a0", "/excess": "\u2239", "/exclam": "!", "/exclamationquestion": "\u2049", "/exclamdbl": "\u203c", "/exclamdown": "\u00a1", "/existential": "\u2203", "/ezhcaron": "\u01ef", "/ezhreversed": "\u01b9", "/ezhtail": "\u01ba", "/f": "f", "/f_f": "\ufb00", "/f_f_i": "\ufb03", "/f_f_l": "\ufb04", "/facsimile": "\u213b", "/fahrenheit": "\u2109", "/feicoptic": "\u03e5", "/ff": "\ufb00", "/ffi": "\ufb03", "/ffl": "\ufb04", "/fhook": "\u0192", "/fi": "\ufb01", "/fifty.roman": "\u216c", "/fifty.romansmall": "\u217c", "/fiftyearlyform.roman": "\u2186", "/fiftythousand.roman": "\u2187", "/figuredash": "\u2012", "/figurespace": "\u2007", "/filledbox": "\u25a0", "/filledrect": "\u25ac", "/finalsigma": "\u03c2", "/firststrongisolate": "\u2068", "/fisheye": "\u25c9", "/fitacyr": "\u0473", "/fitacyrillic": "\u0473", "/five": "5", "/five.roman": "\u2164", "/five.romansmall": "\u2174", "/fivecircleinversesansserif": "\u278e", "/fivedotpunctuation": "\u2059", "/fiveeighths": "\u215d", "/fivehundred.roman": "\u216e", "/fivehundred.romansmall": "\u217e", "/fiveroman": "\u2174", "/fivesixths": "\u215a", "/fivethousand.roman": "\u2181", "/fl": "\ufb02", "/florin": "\u0192", "/flowerpunctuationmark": "\u2055", "/followornoteqvlnt": "\u22e9", "/follows": "\u227b", "/followsorcurly": "\u227d", "/followsorequal": "\u227f", "/forall": "\u2200", "/forces": "\u22a9", "/forcesbar": "\u22aa", "/forsamaritan": "\u214f", "/four": "4", "/four.roman": "\u2163", "/four.romansmall": "\u2173", "/fourcircleinversesansserif": "\u278d", "/fourdotmark": "\u205b", "/fourdotpunctuation": "\u2058", "/fourfifths": "\u2158", "/fourperemspace": "\u2005", "/fourroman": "\u2173", "/fraction": "\u2044", "/franc": "\u20a3", "/fturned": "\u214e", "/fullBlock": "\u2588", "/functionapplication": "\u2061", "/g": "g", "/gacute": "\u01f5", "/gamma": "\u03b3", "/gammadblstruck": "\u213d", "/gangiacoptic": "\u03eb", "/gbreve": "\u011f", "/gcaron": "\u01e7", "/gcedilla": "\u0123", "/gcircumflex": "\u011d", "/gcommaaccent": "\u0123", "/gdot": "\u0121", "/gdotaccent": "\u0121", "/gecyr": "\u0433", "/gecyrillic": "\u0433", "/gehookcyr": "\u0495", "/gehookstrokecyr": "\u04fb", "/geomequivalent": "\u224e", "/geometricallyequal": "\u2251", "/geometricallyequivalent": "\u224e", "/geometricproportion": "\u223a", "/germandbls": "\u00df", "/germanpenny": "\u20b0", "/gestrokecyr": "\u0493", "/getailcyr": "\u04f7", "/geupcyr": "\u0491", "/ghemiddlehookcyrillic": "\u0495", "/ghestrokecyrillic": "\u0493", "/gheupturncyrillic": "\u0491", "/gjecyr": "\u0453", "/gjecyrillic": "\u0453", "/glottalinvertedstroke": "\u01be", "/gmtr:diamondblack": "\u25c6", "/gmtr:diamondwhite": "\u25c7", "/gnrl:hyphen": "\u2010", "/gr:question": "\u037e", "/gradient": "\u2207", "/grave": "`", "/greater": ">", "/greaterbutnotequal": "\u2269", "/greaterbutnotequivalent": "\u22e7", "/greaterdblequal": "\u2267", "/greaterdot": "\u22d7", "/greaterequal": "\u2265", "/greaterequalorless": "\u22db", "/greaterlessequal": "\u22db", "/greatermuch": "\u226b", "/greaterorequivalent": "\u2273", "/greaterorless": "\u2277", "/greaterornotdbleql": "\u2269", "/greaterornotequal": "\u2269", "/greaterorsimilar": "\u2273", "/greateroverequal": "\u2267", "/gstroke": "\u01e5", "/guarani": "\u20b2", "/guillemetleft": "\u00ab", "/guillemetright": "\u00bb", "/guillemotleft": "\u00ab", "/guillemotright": "\u00bb", "/guilsinglleft": "\u2039", "/guilsinglright": "\u203a", "/h": "h", "/haabkhasiancyrillic": "\u04a9", "/haabkhcyr": "\u04a9", "/hacyr": "\u0445", "/hadescendercyrillic": "\u04b3", "/hahookcyr": "\u04fd", "/hairspace": "\u200a", "/halfcircleleftblack": "\u25d6", "/halfcirclerightblack": "\u25d7", "/hardcyr": "\u044a", "/hardsigncyrillic": "\u044a", "/harpoondownbarbleft": "\u21c3", "/harpoondownbarbright": "\u21c2", "/harpoondownleft": "\u21c3", "/harpoondownright": "\u21c2", "/harpoonleftbarbdown": "\u21bd", "/harpoonleftbarbup": "\u21bc", "/harpoonleftright": "\u21cc", "/harpoonrightbarbdown": "\u21c1", "/harpoonrightbarbup": "\u21c0", "/harpoonrightleft": "\u21cb", "/harpoonupbarbleft": "\u21bf", "/harpoonupbarbright": "\u21be", "/harpoonupleft": "\u21bf", "/harpoonupright": "\u21be", "/hastrokecyr": "\u04ff", "/hbar": "\u0127", "/hcaron": "\u021f", "/hcircumflex": "\u0125", "/heavydbldashhorz": "\u254d", "/heavydbldashvert": "\u254f", "/heavydn": "\u257b", "/heavydnhorz": "\u2533", "/heavydnleft": "\u2513", "/heavydnright": "\u250f", "/heavyhorz": "\u2501", "/heavyleft": "\u2578", "/heavyleftlightright": "\u257e", "/heavyquaddashhorz": "\u2509", "/heavyquaddashvert": "\u250b", "/heavyright": "\u257a", "/heavytrpldashhorz": "\u2505", "/heavytrpldashvert": "\u2507", "/heavyup": "\u2579", "/heavyuphorz": "\u253b", "/heavyupleft": "\u251b", "/heavyuplightdn": "\u257f", "/heavyupright": "\u2517", "/heavyvert": "\u2503", "/heavyverthorz": "\u254b", "/heavyvertleft": "\u252b", "/heavyvertright": "\u2523", "/hermitianconjugatematrix": "\u22b9", "/heta": "\u0371", "/homotic": "\u223b", "/horicoptic": "\u03e9", "/horizontalbar": "\u2015", "/horizontalbarwhitearrowonpedestalup": "\u21ec", "/hryvnia": "\u20b4", "/hundredthousandscmbcyr": "\u0488", "/hv": "\u0195", "/hyphen": "-", "/hyphenationpoint": "\u2027", "/hyphenbullet": "\u2043", "/hyphenchar": "-", "/hyphenminus": "-", "/hyphensoft": "\u00ad", "/hyphentwo": "\u2010", "/i": "i", "/iacute": "\u00ed", "/iacyrillic": "\u044f", "/ibreve": "\u012d", "/icaron": "\u01d0", "/icircumflex": "\u00ee", "/icyr": "\u0438", "/icyrillic": "\u0456", "/idblgrave": "\u0209", "/idblstruckitalic": "\u2148", "/idieresis": "\u00ef", "/idieresiscyr": "\u04e5", "/idieresiscyrillic": "\u04e5", "/iebrevecyr": "\u04d7", "/iebrevecyrillic": "\u04d7", "/iecyr": "\u0435", "/iecyrillic": "\u0435", "/iegravecyr": "\u0450", "/igrave": "\u00ec", "/igravecyr": "\u045d", "/igravedbl": "\u0209", "/iicyrillic": "\u0438", "/iinvertedbreve": "\u020b", "/iishortcyrillic": "\u0439", "/ij": "\u0133", "/imacron": "\u012b", "/imacroncyr": "\u04e3", "/imacroncyrillic": "\u04e3", "/image": "\u22b7", "/imageorapproximatelyequal": "\u2253", "/increment": "\u2206", "/indianrupee": "\u20b9", "/infinity": "\u221e", "/information": "\u2139", "/inhibitarabicformshaping": "\u206c", "/inhibitsymmetricswapping": "\u206a", "/integerdivide": "\u2216", "/integral": "\u222b", "/integralclockwise": "\u2231", "/integralcontour": "\u222e", "/integralcontouranticlockwise": "\u2233", "/integralcontourclockwise": "\u2232", "/integraldbl": "\u222c", "/integraldisplay": "\u222b", "/integralsurface": "\u222f", "/integraltext": "\u222b", "/integraltpl": "\u222d", "/integralvolume": "\u2230", "/intercal": "\u22ba", "/intercalate": "\u22ba", "/interrobang": "\u203d", "/intersection": "\u2229", "/intersectionarray": "\u22c2", "/intersectiondbl": "\u22d2", "/intersectiondisplay": "\u22c2", "/intersectionsq": "\u2293", "/intersectiontext": "\u22c2", "/invbullet": "\u25d8", "/invcircle": "\u25d9", "/invertedundertie": "\u2054", "/invisibleplus": "\u2064", "/invisibleseparator": "\u2063", "/invisibletimes": "\u2062", "/iocyr": "\u0451", "/iocyrillic": "\u0451", "/iogonek": "\u012f", "/iota": "\u03b9", "/iotadieresis": "\u03ca", "/iotadieresistonos": "\u0390", "/iotasub": "\u037a", "/iotatonos": "\u03af", "/iotaturned": "\u2129", "/ishortcyr": "\u0439", "/ishortsharptailcyr": "\u048b", "/itilde": "\u0129", "/iucyrillic": "\u044e", "/iukrcyr": "\u0456", "/izhitsacyr": "\u0475", "/izhitsacyrillic": "\u0475", "/izhitsadblgravecyrillic": "\u0477", "/izhitsagravedblcyr": "\u0477", "/j": "j", "/jcaron": "\u01f0", "/jcircumflex": "\u0135", "/jdblstruckitalic": "\u2149", "/jecyr": "\u0458", "/jecyrillic": "\u0458", "/jstroke": "\u0249", "/k": "k", "/kabashkcyr": "\u04a1", "/kabashkircyrillic": "\u04a1", "/kacyr": "\u043a", "/kacyrillic": "\u043a", "/kadescendercyrillic": "\u049b", "/kahookcyr": "\u04c4", "/kahookcyrillic": "\u04c4", "/kaisymbol": "\u03d7", "/kappa": "\u03ba", "/kappa.math": "\u03f0", "/kappasymbolgreek": "\u03f0", "/kastrokecyr": "\u049f", "/kastrokecyrillic": "\u049f", "/katailcyr": "\u049b", "/kaverticalstrokecyr": "\u049d", "/kaverticalstrokecyrillic": "\u049d", "/kcaron": "\u01e9", "/kcedilla": "\u0137", "/kcommaaccent": "\u0137", "/kelvin": "\u212a", "/kgreenlandic": "\u0138", "/khacyrillic": "\u0445", "/kheicoptic": "\u03e7", "/khook": "\u0199", "/kip": "\u20ad", "/kjecyr": "\u045c", "/kjecyrillic": "\u045c", "/koppa": "\u03df", "/koppaarchaic": "\u03d9", "/koppacyr": "\u0481", "/koppacyrillic": "\u0481", "/kra": "\u0138", "/ksicyr": "\u046f", "/ksicyrillic": "\u046f", "/l": "l", "/lacute": "\u013a", "/lambda": "\u03bb", "/lambdastroke": "\u019b", "/largecircle": "\u25ef", "/lari": "\u20be", "/latticetop": "\u22a4", "/lazysinverted": "\u223e", "/lbar": "\u019a", "/lbbar": "\u2114", "/lcaron": "\u013e", "/lcedilla": "\u013c", "/lcommaaccent": "\u013c", "/lcurl": "\u0234", "/ldot": "\u0140", "/ldotaccent": "\u0140", "/leftFiveEighthsBlock": "\u258b", "/leftHalfBlock": "\u258c", "/leftOneEighthBlock": "\u258f", "/leftOneQuarterBlock": "\u258e", "/leftSevenEighthsBlock": "\u2589", "/leftThreeEighthsBlock": "\u258d", "/leftThreeQuartersBlock": "\u258a", "/leftarrowoverrightarrow": "\u21c6", "/leftdnheavyrightuplight": "\u2545", "/leftharpoonoverrightharpoon": "\u21cb", "/leftheavyrightdnlight": "\u252d", "/leftheavyrightuplight": "\u2535", "/leftheavyrightvertlight": "\u253d", "/leftlightrightdnheavy": "\u2532", "/leftlightrightupheavy": "\u253a", "/leftlightrightvertheavy": "\u254a", "/lefttorightembed": "\u202a", "/lefttorightisolate": "\u2066", "/lefttorightmark": "\u200e", "/lefttorightoverride": "\u202d", "/leftupheavyrightdnlight": "\u2543", "/less": "<", "/lessbutnotequal": "\u2268", "/lessbutnotequivalent": "\u22e6", "/lessdblequal": "\u2266", "/lessdot": "\u22d6", "/lessequal": "\u2264", "/lessequalgreater": "\u22da", "/lessequalorgreater": "\u22da", "/lessmuch": "\u226a", "/lessorequivalent": "\u2272", "/lessorgreater": "\u2276", "/lessornotdbleql": "\u2268", "/lessornotequal": "\u2268", "/lessorsimilar": "\u2272", "/lessoverequal": "\u2266", "/lfblock": "\u258c", "/lightShade": "\u2591", "/lightarcdnleft": "\u256e", "/lightarcdnright": "\u256d", "/lightarcupleft": "\u256f", "/lightarcupright": "\u2570", "/lightdbldashhorz": "\u254c", "/lightdbldashvert": "\u254e", "/lightdiagcross": "\u2573", "/lightdiagupleftdnright": "\u2572", "/lightdiaguprightdnleft": "\u2571", "/lightdn": "\u2577", "/lightdnhorz": "\u252c", "/lightdnleft": "\u2510", "/lightdnright": "\u250c", "/lighthorz": "\u2500", "/lightleft": "\u2574", "/lightleftheavyright": "\u257c", "/lightquaddashhorz": "\u2508", "/lightquaddashvert": "\u250a", "/lightright": "\u2576", "/lighttrpldashhorz": "\u2504", "/lighttrpldashvert": "\u2506", "/lightup": "\u2575", "/lightupheavydn": "\u257d", "/lightuphorz": "\u2534", "/lightupleft": "\u2518", "/lightupright": "\u2514", "/lightvert": "\u2502", "/lightverthorz": "\u253c", "/lightvertleft": "\u2524", "/lightvertright": "\u251c", "/lineseparator": "\u2028", "/lira": "\u20a4", "/litre": "\u2113", "/livretournois": "\u20b6", "/lj": "\u01c9", "/ljecyr": "\u0459", "/ljecyrillic": "\u0459", "/logicaland": "\u2227", "/logicalandarray": "\u22c0", "/logicalanddisplay": "\u22c0", "/logicalandtext": "\u22c0", "/logicalnot": "\u00ac", "/logicalor": "\u2228", "/logicalorarray": "\u22c1", "/logicalordisplay": "\u22c1", "/logicalortext": "\u22c1", "/longdbls": "\u017f", "/longs": "\u017f", "/longs_t": "\ufb05", "/longsh": "\u017f", "/longsi": "\u017f", "/longsl": "\u017f", "/longst": "\ufb05", "/lowasterisk": "\u204e", "/lowerFiveEighthsBlock": "\u2585", "/lowerHalfBlock": "\u2584", "/lowerOneEighthBlock": "\u2581", "/lowerOneQuarterBlock": "\u2582", "/lowerSevenEighthsBlock": "\u2587", "/lowerThreeEighthsBlock": "\u2583", "/lowerThreeQuartersBlock": "\u2586", "/lowerhalfcircle": "\u25e1", "/lowerhalfcircleinversewhite": "\u25db", "/lowerquadrantcirculararcleft": "\u25df", "/lowerquadrantcirculararcright": "\u25de", "/lowertriangleleft": "\u25fa", "/lowertriangleleftblack": "\u25e3", "/lowertriangleright": "\u25ff", "/lowertrianglerightblack": "\u25e2", "/lownumeralsign": "\u0375", "/lozenge": "\u25ca", "/lscript": "\u2113", "/lslash": "\u0142", "/lsquare": "\u2113", "/lt:Gamma": "\u0194", "/lt:Iota": "\u0196", "/lt:Upsilon": "\u01b1", "/ltshade": "\u2591", "/lttr:bet": "\u2136", "/lttr:dalet": "\u2138", "/lttr:gimel": "\u2137", "/lttr:gscript": "\u210a", "/m": "m", "/macron": "\u00af", "/maltesecross": "\u2720", "/manat": "\u20bc", "/mapsto": "\u21a6", "/math:bowtie": "\u22c8", "/math:cuberoot": "\u221b", "/math:fourthroot": "\u221c", "/measuredangle": "\u2221", "/measuredby": "\u225e", "/mediumShade": "\u2592", "/mediummathematicalspace": "\u205f", "/middot": "\u00b7", "/mill": "\u20a5", "/millionscmbcyr": "\u0489", "/millisecond": "\u2034", "/millisecondreversed": "\u2037", "/minus": "\u2212", "/minuscircle": "\u2296", "/minusplus": "\u2213", "/minustilde": "\u2242", "/minute": "\u2032", "/minutereversed": "\u2035", "/models": "\u22a7", "/mu": "\u00b5", "/mu.math": "\u00b5", "/mu1": "\u00b5", "/muchgreater": "\u226b", "/muchless": "\u226a", "/mugreek": "\u03bc", "/multicloseleft": "\u22c9", "/multicloseright": "\u22ca", "/multimap": "\u22b8", "/multiopenleft": "\u22cb", "/multiopenright": "\u22cc", "/multiply": "\u00d7", "/multiset": "\u228c", "/multisetmultiplication": "\u228d", "/multisetunion": "\u228e", "/n": "n", "/nabla": "\u2207", "/nacute": "\u0144", "/naira": "\u20a6", "/nand": "\u22bc", "/napostrophe": "\u0149", "/narrownobreakspace": "\u202f", "/nationaldigitshapes": "\u206e", "/nbspace": "\u00a0", "/ncaron": "\u0148", "/ncedilla": "\u0146", "/ncommaaccent": "\u0146", "/ncurl": "\u0235", "/negatedturnstiledblverticalbarright": "\u22af", "/neirapproximatelynoractuallyequal": "\u2247", "/neirasersetnorequalup": "\u2289", "/neirasubsetnorequal": "\u2288", "/neirgreaternorequal": "\u2271", "/neirgreaternorequivalent": "\u2275", "/neirgreaternorless": "\u2279", "/neirlessnorequal": "\u2270", "/neirlessnorequivalent": "\u2274", "/neirlessnorgreater": "\u2278", "/newsheqel": "\u20aa", "/newsheqelsign": "\u20aa", "/ng": "\u014b", "/ngrave": "\u01f9", "/nine": "9", "/nine.roman": "\u2168", "/nine.romansmall": "\u2178", "/ninecircleinversesansserif": "\u2792", "/nineroman": "\u2178", "/nj": "\u01cc", "/njecyr": "\u045a", "/njecyrillic": "\u045a", "/nlegrightlong": "\u019e", "/nlongrightleg": "\u019e", "/nmbr:oneeighth": "\u215b", "/nmbr:onefifth": "\u2155", "/nmbr:onetenth": "\u2152", "/nominaldigitshapes": "\u206f", "/nonbreakinghyphen": "\u2011", "/nonbreakingspace": "\u00a0", "/nor": "\u22bd", "/nordicmark": "\u20bb", "/normalfacrsemidirectproductleft": "\u22c9", "/normalfacrsemidirectproductright": "\u22ca", "/normalsubgroorequalup": "\u22b4", "/normalsubgroup": "\u22b2", "/notalmostequal": "\u2249", "/notapproxequal": "\u2247", "/notarrowboth": "\u21ae", "/notarrowleft": "\u219a", "/notarrowright": "\u219b", "/notasersetup": "\u2285", "/notasympticallyequal": "\u2244", "/notbar": "\u2224", "/notcontains": "\u220c", "/notdblarrowboth": "\u21ce", "/notdblarrowleft": "\u21cd", "/notdblarrowright": "\u21cf", "/notelement": "\u2209", "/notelementof": "\u2209", "/notequal": "\u2260", "/notequivalent": "\u226d", "/notexistential": "\u2204", "/notfollows": "\u2281", "/notforces": "\u22ae", "/notforcesextra": "\u22af", "/notgreater": "\u226f", "/notgreaterdblequal": "\u2267", "/notgreaterequal": "\u2271", "/notgreaternorequal": "\u2271", "/notgreaternorless": "\u2279", "/notidentical": "\u2262", "/notless": "\u226e", "/notlessdblequal": "\u2266", "/notlessequal": "\u2270", "/notlessnorequal": "\u2270", "/notnormalsubgroorequalup": "\u22ec", "/notnormalsubgroup": "\u22ea", "/notparallel": "\u2226", "/notprecedes": "\u2280", "/notsatisfies": "\u22ad", "/notsimilar": "\u2241", "/notsquareimageorequal": "\u22e2", "/notsquareoriginalorequal": "\u22e3", "/notsubset": "\u2284", "/notsubseteql": "\u2288", "/notsubsetoreql": "\u228a", "/notsucceeds": "\u2281", "/notsuperset": "\u2285", "/notsuperseteql": "\u2289", "/notsupersetoreql": "\u228b", "/nottilde": "\u2241", "/nottriangeqlleft": "\u22ec", "/nottriangeqlright": "\u22ed", "/nottriangleleft": "\u22ea", "/nottriangleright": "\u22eb", "/nottrue": "\u22ad", "/notturnstile": "\u22ac", "/ntilde": "\u00f1", "/nu": "\u03bd", "/numbersign": "#", "/numeralsign": "\u0374", "/numeralsigngreek": "\u0374", "/numeralsignlowergreek": "\u0375", "/numero": "\u2116", "/o": "o", "/oacute": "\u00f3", "/obarcyr": "\u04e9", "/obardieresiscyr": "\u04eb", "/obarredcyrillic": "\u04e9", "/obarreddieresiscyrillic": "\u04eb", "/obreve": "\u014f", "/ocaron": "\u01d2", "/ocircumflex": "\u00f4", "/ocyr": "\u043e", "/ocyrillic": "\u043e", "/odblacute": "\u0151", "/odblgrave": "\u020d", "/odieresis": "\u00f6", "/odieresiscyr": "\u04e7", "/odieresiscyrillic": "\u04e7", "/odieresismacron": "\u022b", "/odot": "\u022f", "/odotmacron": "\u0231", "/oe": "\u0153", "/ograve": "\u00f2", "/ogravedbl": "\u020d", "/ohm": "\u2126", "/ohminverted": "\u2127", "/ohorn": "\u01a1", "/ohungarumlaut": "\u0151", "/oi": "\u01a3", "/oinvertedbreve": "\u020f", "/omacron": "\u014d", "/omega": "\u03c9", "/omega1": "\u03d6", "/omegacyr": "\u0461", "/omegacyrillic": "\u0461", "/omegaroundcyr": "\u047b", "/omegaroundcyrillic": "\u047b", "/omegatitlocyr": "\u047d", "/omegatitlocyrillic": "\u047d", "/omegatonos": "\u03ce", "/omicron": "\u03bf", "/omicrontonos": "\u03cc", "/one": "1", "/one.roman": "\u2160", "/one.romansmall": "\u2170", "/onecircleinversesansserif": "\u278a", "/onedotenleader": "\u2024", "/oneeighth": "\u215b", "/onefraction": "\u215f", "/onehalf": "\u00bd", "/onehundred.roman": "\u216d", "/onehundred.romansmall": "\u217d", "/onehundredthousand.roman": "\u2188", "/oneninth": "\u2151", "/onequarter": "\u00bc", "/oneroman": "\u2170", "/oneseventh": "\u2150", "/onesixth": "\u2159", "/onesuperior": "\u00b9", "/onethird": "\u2153", "/onethousand.roman": "\u216f", "/onethousand.romansmall": "\u217f", "/onethousandcd.roman": "\u2180", "/oogonek": "\u01eb", "/oogonekmacron": "\u01ed", "/openbullet": "\u25e6", "/openheadarrowleft": "\u21fd", "/openheadarrowleftright": "\u21ff", "/openheadarrowright": "\u21fe", "/ordfeminine": "\u00aa", "/ordmasculine": "\u00ba", "/original": "\u22b6", "/orthogonal": "\u221f", "/orunderscore": "\u22bb", "/oscript": "\u2134", "/oslash": "\u00f8", "/oslashacute": "\u01ff", "/ostrokeacute": "\u01ff", "/otcyr": "\u047f", "/otcyrillic": "\u047f", "/otilde": "\u00f5", "/otildemacron": "\u022d", "/ou": "\u0223", "/ounce": "\u2125", "/overline": "\u203e", "/overscore": "\u00af", "/owner": "\u220b", "/p": "p", "/pagedown": "\u21df", "/pageup": "\u21de", "/palatalizationcyrilliccmb": "\u0484", "/palatcmbcyr": "\u0484", "/palochkacyr": "\u04cf", "/palochkacyrillic": "\u04c0", "/paragraph": "\u00b6", "/paragraphseparator": "\u2029", "/parallel": "\u2225", "/parallelogramblack": "\u25b0", "/parallelogramwhite": "\u25b1", "/parenleft": "(", "/parenleftBig": "(", "/parenleftBigg": "(", "/parenleftbig": "(", "/parenleftbigg": "(", "/parenright": ")", "/parenrightBig": ")", "/parenrightBigg": ")", "/parenrightbig": ")", "/parenrightbigg": ")", "/partialdiff": "\u2202", "/pecyr": "\u043f", "/pecyrillic": "\u043f", "/pehookcyr": "\u04a7", "/pemiddlehookcyrillic": "\u04a7", "/per": "\u214c", "/percent": "%", "/period": ".", "/periodcentered": "\u00b7", "/perpendicular": "\u22a5", "/pertenthousand": "\u2031", "/pertenthousandsign": "\u2031", "/perthousand": "\u2030", "/peseta": "\u20a7", "/peso": "\u20b1", "/phi": "\u03c6", "/phi.math": "\u03d5", "/phi1": "\u03d5", "/phisymbolgreek": "\u03d5", "/phook": "\u01a5", "/pi": "\u03c0", "/pi.math": "\u03d6", "/pi1": "\u03d6", "/pidblstruck": "\u213c", "/pilcrowsignreversed": "\u204b", "/pisymbolgreek": "\u03d6", "/pitchfork": "\u22d4", "/planck": "\u210e", "/planckover2pi": "\u210f", "/planckover2pi1": "\u210f", "/plancktwopi": "\u210f", "/plus": "+", "/pluscircle": "\u2295", "/plusminus": "\u00b1", "/pointerleftblack": "\u25c4", "/pointerleftwhite": "\u25c5", "/pointerrightblack": "\u25ba", "/pointerrightwhite": "\u25bb", "/pokrytiecmbcyr": "\u0487", "/popdirectionalformatting": "\u202c", "/popdirectionalisolate": "\u2069", "/precedeornoteqvlnt": "\u22e8", "/precedes": "\u227a", "/precedesbutnotequivalent": "\u22e8", "/precedesorcurly": "\u227c", "/precedesorequal": "\u227c", "/precedesorequivalent": "\u227e", "/precedesunderrelation": "\u22b0", "/prescription": "\u211e", "/prime": "\u2032", "/primereverse": "\u2035", "/primereversed": "\u2035", "/product": "\u220f", "/productdisplay": "\u220f", "/producttext": "\u220f", "/propersubset": "\u2282", "/propersuperset": "\u2283", "/propertyline": "\u214a", "/proportion": "\u2237", "/proportional": "\u221d", "/psi": "\u03c8", "/psicyr": "\u0471", "/psicyrillic": "\u0471", "/psilicmbcyr": "\u0486", "/psilipneumatacyrilliccmb": "\u0486", "/punctdash": "\u2014", "/punctuationspace": "\u2008", "/q": "q", "/qhooktail": "\u024b", "/qpdigraph": "\u0239", "/quadrantLowerLeft": "\u2596", "/quadrantLowerRight": "\u2597", "/quadrantUpperLeft": "\u2598", "/quadrantUpperLeftAndLowerLeftAndLowerRight": "\u2599", "/quadrantUpperLeftAndLowerRight": "\u259a", "/quadrantUpperLeftAndUpperRightAndLowerLeft": "\u259b", "/quadrantUpperLeftAndUpperRightAndLowerRight": "\u259c", "/quadrantUpperRight": "\u259d", "/quadrantUpperRightAndLowerLeft": "\u259e", "/quadrantUpperRightAndLowerLeftAndLowerRight": "\u259f", "/quadrupleminute": "\u2057", "/question": "?", "/questiondbl": "\u2047", "/questiondown": "\u00bf", "/questionedequal": "\u225f", "/questionexclamationmark": "\u2048", "/questiongreek": "\u037e", "/quotedbl": "\u0022", "/quotedblbase": "\u201e", "/quotedblleft": "\u201c", "/quotedblreversed": "\u201f", "/quotedblright": "\u201d", "/quoteleft": "\u2018", "/quoteleftreversed": "\u201b", "/quotereversed": "\u201b", "/quoteright": "\u2019", "/quoterightn": "\u0149", "/quotesinglbase": "\u201a", "/quotesingle": "'", "/r": "r", "/racute": "\u0155", "/radical": "\u221a", "/radicalBig": "\u221a", "/radicalBigg": "\u221a", "/radicalbig": "\u221a", "/radicalbigg": "\u221a", "/radicalbt": "\u221a", "/rangedash": "\u2013", "/ratio": "\u2236", "/rcaron": "\u0159", "/rcedilla": "\u0157", "/rcommaaccent": "\u0157", "/rdblgrave": "\u0211", "/rectangleblack": "\u25ac", "/rectangleverticalblack": "\u25ae", "/rectangleverticalwhite": "\u25af", "/rectanglewhite": "\u25ad", "/referencemark": "\u203b", "/reflexsubset": "\u2286", "/reflexsuperset": "\u2287", "/registered": "\u00ae", "/response": "\u211f", "/revasymptequal": "\u22cd", "/reversedonehundred.roman": "\u2183", "/reversedtilde": "\u223d", "/revsimilar": "\u223d", "/rgravedbl": "\u0211", "/rho": "\u03c1", "/rho1": "\u03f1", "/rhostrokesymbol": "\u03fc", "/rhosymbol": "\u03f1", "/rhosymbolgreek": "\u03f1", "/rightHalfBlock": "\u2590", "/rightOneEighthBlock": "\u2595", "/rightangle": "\u221f", "/rightarrowoverleftarrow": "\u21c4", "/rightdnheavyleftuplight": "\u2546", "/rightharpoonoverleftharpoon": "\u21cc", "/rightheavyleftdnlight": "\u252e", "/rightheavyleftuplight": "\u2536", "/rightheavyleftvertlight": "\u253e", "/rightlightleftdnheavy": "\u2531", "/rightlightleftupheavy": "\u2539", "/rightlightleftvertheavy": "\u2549", "/righttoleftembed": "\u202b", "/righttoleftisolate": "\u2067", "/righttoleftmark": "\u200f", "/righttoleftoverride": "\u202e", "/righttriangle": "\u22bf", "/rightupheavyleftdnlight": "\u2544", "/ringequal": "\u2257", "/ringinequal": "\u2256", "/ringoperator": "\u2218", "/rinvertedbreve": "\u0213", "/rstroke": "\u024d", "/rtblock": "\u2590", "/ruble": "\u20bd", "/s": "s", "/s_t": "\ufb06", "/sacute": "\u015b", "/sampi": "\u03e1", "/sampiarchaic": "\u0373", "/san": "\u03fb", "/satisfies": "\u22a8", "/scaron": "\u0161", "/scedilla": "\u015f", "/schwacyr": "\u04d9", "/schwacyrillic": "\u04d9", "/schwadieresiscyr": "\u04db", "/schwadieresiscyrillic": "\u04db", "/scircumflex": "\u015d", "/scommaaccent": "\u0219", "/scruple": "\u2108", "/second": "\u2033", "/secondreversed": "\u2036", "/section": "\u00a7", "/semicolon": ";", "/semicolonreversed": "\u204f", "/semidirectproductleft": "\u22cb", "/semidirectproductright": "\u22cc", "/semisoftcyr": "\u048d", "/sersetdblup": "\u22d1", "/sersetnotequalup": "\u228b", "/servicemark": "\u2120", "/setminus": "\u2216", "/seven": "7", "/seven.roman": "\u2166", "/seven.romansmall": "\u2176", "/sevencircleinversesansserif": "\u2790", "/seveneighths": "\u215e", "/sevenroman": "\u2176", "/sfthyphen": "\u00ad", "/shacyr": "\u0448", "/shacyrillic": "\u0448", "/shade": "\u2592", "/shadedark": "\u2593", "/shadelight": "\u2591", "/shademedium": "\u2592", "/shchacyr": "\u0449", "/shchacyrillic": "\u0449", "/sheicoptic": "\u03e3", "/sheqel": "\u20aa", "/sheqelhebrew": "\u20aa", "/shhacyr": "\u04bb", "/shhacyrillic": "\u04bb", "/shiftleft": "\u21b0", "/shiftright": "\u21b1", "/shimacoptic": "\u03ed", "/sho": "\u03f8", "/sigma": "\u03c3", "/sigma1": "\u03c2", "/sigmafinal": "\u03c2", "/sigmalunatedottedreversedsymbol": "\u037d", "/sigmalunatedottedsymbol": "\u037c", "/sigmalunatereversedsymbol": "\u037b", "/sigmalunatesymbol": "\u03f2", "/sigmalunatesymbolgreek": "\u03f2", "/similar": "\u223c", "/similarequal": "\u2243", "/sinewave": "\u223f", "/six": "6", "/six.roman": "\u2165", "/six.romansmall": "\u2175", "/sixcircleinversesansserif": "\u278f", "/sixlateform.roman": "\u2185", "/sixperemspace": "\u2006", "/sixroman": "\u2175", "/slash": "/", "/slashBig": "/", "/slashBigg": "/", "/slashbig": "/", "/slashbigg": "/", "/slong": "\u017f", "/softcyr": "\u044c", "/softhyphen": "\u00ad", "/softsigncyrillic": "\u044c", "/soundcopyright": "\u2117", "/space": " ", "/spacehackarabic": " ", "/spesmilo": "\u20b7", "/sphericalangle": "\u2222", "/square": "\u25a1", "/squareblack": "\u25a0", "/squarecap": "\u2293", "/squarecup": "\u2294", "/squareddotoperator": "\u22a1", "/squarediagonalcrosshatchfill": "\u25a9", "/squaredminus": "\u229f", "/squaredot": "\u22a1", "/squaredplus": "\u229e", "/squaredtimes": "\u22a0", "/squarehalfleftblack": "\u25e7", "/squarehalfrightblack": "\u25e8", "/squarehorizontalfill": "\u25a4", "/squareimage": "\u228f", "/squareimageorequal": "\u2291", "/squareimageornotequal": "\u22e4", "/squarelowerdiagonalhalfrightblack": "\u25ea", "/squaremediumblack": "\u25fc", "/squaremediumwhite": "\u25fb", "/squareminus": "\u229f", "/squaremultiply": "\u22a0", "/squareoriginal": "\u2290", "/squareoriginalorequal": "\u2292", "/squareoriginalornotequal": "\u22e5", "/squareorthogonalcrosshatchfill": "\u25a6", "/squareplus": "\u229e", "/squaresmallblack": "\u25aa", "/squaresmallmediumblack": "\u25fe", "/squaresmallmediumwhite": "\u25fd", "/squaresmallwhite": "\u25ab", "/squaresolid": "\u25a0", "/squareupperdiagonalhalfleftblack": "\u25e9", "/squareupperlefttolowerrightfill": "\u25a7", "/squareupperrighttolowerleftfill": "\u25a8", "/squareverticalfill": "\u25a5", "/squarewhite": "\u25a1", "/squarewhitebisectinglinevertical": "\u25eb", "/squarewhitelowerquadrantleft": "\u25f1", "/squarewhitelowerquadrantright": "\u25f2", "/squarewhiteround": "\u25a2", "/squarewhiteupperquadrantleft": "\u25f0", "/squarewhiteupperquadrantright": "\u25f3", "/squarewhitewithsmallblack": "\u25a3", "/squarewhitewithsquaresmallblack": "\u25a3", "/squiggleleftright": "\u21ad", "/squiggleright": "\u21dd", "/sswashtail": "\u023f", "/st": "\ufb06", "/star": "\u22c6", "/starequals": "\u225b", "/staroperator": "\u22c6", "/sterling": "\u00a3", "/stigma": "\u03db", "/strictlyequivalent": "\u2263", "/subset": "\u2282", "/subsetdbl": "\u22d0", "/subsetnoteql": "\u228a", "/subsetnotequal": "\u228a", "/subsetorequal": "\u2286", "/subsetsqequal": "\u2291", "/succeeds": "\u227b", "/succeedsbutnotequivalent": "\u22e9", "/succeedsorequal": "\u227d", "/succeedsorequivalent": "\u227f", "/succeedsunderrelation": "\u22b1", "/suchthat": "\u220b", "/summation": "\u2211", "/summationdblstruck": "\u2140", "/summationdisplay": "\u2211", "/summationtext": "\u2211", "/superset": "\u2283", "/supersetdbl": "\u22d1", "/supersetnoteql": "\u228b", "/supersetnotequal": "\u228b", "/supersetorequal": "\u2287", "/supersetsqequal": "\u2292", "/swungdash": "\u2053", "/t": "t", "/tackdown": "\u22a4", "/tackleft": "\u22a3", "/tackright": "\u22a2", "/tackup": "\u22a5", "/tau": "\u03c4", "/tbar": "\u0167", "/tcaron": "\u0165", "/tcedilla": "\u0163", "/tcommaaccent": "\u0163", "/tcurl": "\u0236", "/tecyr": "\u0442", "/tecyrillic": "\u0442", "/tedescendercyrillic": "\u04ad", "/telephone": "\u2121", "/ten.roman": "\u2169", "/ten.romansmall": "\u2179", "/tenge": "\u20b8", "/tenroman": "\u2179", "/tenthousand.roman": "\u2182", "/tetailcyr": "\u04ad", "/tetsecyr": "\u04b5", "/tetsecyrillic": "\u04b5", "/thereexists": "\u2203", "/therefore": "\u2234", "/theta": "\u03b8", "/theta.math": "\u03d1", "/theta1": "\u03d1", "/thetasymbolgreek": "\u03d1", "/thinspace": "\u2009", "/thook": "\u01ad", "/thorn": "\u00fe", "/thousandcyrillic": "\u0482", "/thousandscyr": "\u0482", "/three": "3", "/three.roman": "\u2162", "/three.romansmall": "\u2172", "/threecircleinversesansserif": "\u278c", "/threedotpunctuation": "\u2056", "/threeeighths": "\u215c", "/threefifths": "\u2157", "/threeperemspace": "\u2004", "/threequarters": "\u00be", "/threerightarrows": "\u21f6", "/threeroman": "\u2172", "/threesuperior": "\u00b3", "/tie": "\u2040", "/tildeequalsreversed": "\u22cd", "/tildeoperator": "\u223c", "/tildereversed": "\u223d", "/tildetpl": "\u224b", "/timescircle": "\u2297", "/tironiansignet": "\u204a", "/titlocmbcyr": "\u0483", "/titlocyrilliccmb": "\u0483", "/tocornerarrowNW": "\u21f1", "/tocornerarrowSE": "\u21f2", "/tonefive": "\u01bd", "/tonesix": "\u0185", "/tonetwo": "\u01a8", "/tonos": "\u0384", "/tpalatalhook": "\u01ab", "/trademark": "\u2122", "/triagdn": "\u25bc", "/triaglf": "\u25c4", "/triagrt": "\u25ba", "/triagup": "\u25b2", "/triangle": "\u25b3", "/triangledotupwhite": "\u25ec", "/triangledownblack": "\u25bc", "/triangledownsld": "\u25bc", "/triangledownsmallblack": "\u25be", "/triangledownsmallwhite": "\u25bf", "/triangledownwhite": "\u25bd", "/trianglehalfupleftblack": "\u25ed", "/trianglehalfuprightblack": "\u25ee", "/triangleinv": "\u25bd", "/triangleleft": "\u25c1", "/triangleleftblack": "\u25c0", "/triangleleftequal": "\u22b4", "/triangleleftsld": "\u25c0", "/triangleleftsmallblack": "\u25c2", "/triangleleftsmallwhite": "\u25c3", "/triangleleftwhite": "\u25c1", "/triangleright": "\u22bf", "/trianglerightblack": "\u25b6", "/trianglerightequal": "\u22b5", "/trianglerightsld": "\u25b6", "/trianglerightsmallblack": "\u25b8", "/trianglerightsmallwhite": "\u25b9", "/trianglerightwhite": "\u25b7", "/trianglesolid": "\u25b2", "/triangleupblack": "\u25b2", "/triangleupsmallblack": "\u25b4", "/triangleupsmallwhite": "\u25b5", "/triangleupwhite": "\u25b3", "/triangularbullet": "\u2023", "/tricolon": "\u205d", "/triplearrowleft": "\u21da", "/triplearrowright": "\u21db", "/true": "\u22a8", "/tsecyr": "\u0446", "/tsecyrillic": "\u0446", "/tshecyr": "\u045b", "/tshecyrillic": "\u045b", "/tugrik": "\u20ae", "/turkishlira": "\u20ba", "/turneddigitthree": "\u218b", "/turneddigittwo": "\u218a", "/turnstiledblverticalbarright": "\u22ab", "/turnstileleft": "\u22a2", "/turnstileright": "\u22a3", "/turnstiletplverticalbarright": "\u22aa", "/twelve.roman": "\u216b", "/twelve.romansmall": "\u217b", "/twelveroman": "\u217b", "/two": "2", "/two.roman": "\u2161", "/two.romansmall": "\u2171", "/twoasterisksalignedvertically": "\u2051", "/twocircleinversesansserif": "\u278b", "/twodotenleader": "\u2025", "/twodotleader": "\u2025", "/twodotpunctuation": "\u205a", "/twofifths": "\u2156", "/tworoman": "\u2171", "/twostroke": "\u01bb", "/twosuperior": "\u00b2", "/twothirds": "\u2154", "/u": "u", "/uacute": "\u00fa", "/uacutedblcyr": "\u04f3", "/ubreve": "\u016d", "/ucaron": "\u01d4", "/ucircumflex": "\u00fb", "/ucyr": "\u0443", "/ucyrillic": "\u0443", "/udblacute": "\u0171", "/udblgrave": "\u0215", "/udieresis": "\u00fc", "/udieresisacute": "\u01d8", "/udieresiscaron": "\u01da", "/udieresiscyr": "\u04f1", "/udieresiscyrillic": "\u04f1", "/udieresisgrave": "\u01dc", "/udieresismacron": "\u01d6", "/ugrave": "\u00f9", "/ugravedbl": "\u0215", "/uhorn": "\u01b0", "/uhungarumlaut": "\u0171", "/uhungarumlautcyrillic": "\u04f3", "/uinvertedbreve": "\u0217", "/ukcyr": "\u0479", "/ukcyrillic": "\u0479", "/umacron": "\u016b", "/umacroncyr": "\u04ef", "/umacroncyrillic": "\u04ef", "/underscore": "_", "/underscoredbl": "\u2017", "/undertie": "\u203f", "/union": "\u222a", "/unionarray": "\u22c3", "/uniondbl": "\u22d3", "/uniondisplay": "\u22c3", "/unionmulti": "\u228e", "/unionsq": "\u2294", "/uniontext": "\u22c3", "/universal": "\u2200", "/uogonek": "\u0173", "/uparrowleftofdownarrow": "\u21c5", "/upblock": "\u2580", "/updblhorzsng": "\u2568", "/updblleftsng": "\u255c", "/updblrightsng": "\u2559", "/upheavydnhorzlight": "\u2540", "/upheavyhorzlight": "\u2538", "/upheavyleftdnlight": "\u2526", "/upheavyleftlight": "\u251a", "/upheavyrightdnlight": "\u251e", "/upheavyrightlight": "\u2516", "/uplightdnhorzheavy": "\u2548", "/uplighthorzheavy": "\u2537", "/uplightleftdnheavy": "\u252a", "/uplightleftheavy": "\u2519", "/uplightrightdnheavy": "\u2522", "/uplightrightheavy": "\u2515", "/upperHalfBlock": "\u2580", "/upperOneEighthBlock": "\u2594", "/upperhalfcircle": "\u25e0", "/upperhalfcircleinversewhite": "\u25da", "/upperquadrantcirculararcleft": "\u25dc", "/upperquadrantcirculararcright": "\u25dd", "/uppertriangleleft": "\u25f8", "/uppertriangleleftblack": "\u25e4", "/uppertriangleright": "\u25f9", "/uppertrianglerightblack": "\u25e5", "/uprise": "\u22cf", "/upsilon": "\u03c5", "/upsilondieresis": "\u03cb", "/upsilondieresistonos": "\u03b0", "/upsilontonos": "\u03cd", "/upsnghorzdbl": "\u2567", "/upsngleftdbl": "\u255b", "/upsngrightdbl": "\u2558", "/uring": "\u016f", "/ushortcyr": "\u045e", "/ushortcyrillic": "\u045e", "/ustraightcyr": "\u04af", "/ustraightcyrillic": "\u04af", "/ustraightstrokecyr": "\u04b1", "/ustraightstrokecyrillic": "\u04b1", "/utilde": "\u0169", "/v": "v", "/vecyr": "\u0432", "/vecyrillic": "\u0432", "/versicle": "\u2123", "/vertdblhorzsng": "\u256b", "/vertdblleftsng": "\u2562", "/vertdblrightsng": "\u255f", "/vertheavyhorzlight": "\u2542", "/vertheavyleftlight": "\u2528", "/vertheavyrightlight": "\u2520", "/verticalbar": "|", "/verticalbardbl": "\u2016", "/verticalbarwhitearrowonpedestalup": "\u21ed", "/verticalfourdots": "\u205e", "/verticalsdbltrokearrowleft": "\u21fa", "/verticalsdbltrokearrowleftright": "\u21fc", "/verticalsdbltrokearrowright": "\u21fb", "/verticalstrokearrowleft": "\u21f7", "/verticalstrokearrowleftright": "\u21f9", "/verticalstrokearrowright": "\u21f8", "/vertlighthorzheavy": "\u253f", "/vertlightleftheavy": "\u2525", "/vertlightrightheavy": "\u251d", "/vertsnghorzdbl": "\u256a", "/vertsngleftdbl": "\u2561", "/vertsngrightdbl": "\u255e", "/verymuchgreater": "\u22d9", "/verymuchless": "\u22d8", "/w": "w", "/wcircumflex": "\u0175", "/weierstrass": "\u2118", "/whitearrowdown": "\u21e9", "/whitearrowfromwallright": "\u21f0", "/whitearrowleft": "\u21e6", "/whitearrowonpedestalup": "\u21eb", "/whitearrowright": "\u21e8", "/whitearrowup": "\u21e7", "/whitearrowupdown": "\u21f3", "/whitearrowupfrombar": "\u21ea", "/whitebullet": "\u25e6", "/whitecircle": "\u25cb", "/whitecircleinverse": "\u25d9", "/whitedblarrowonpedestalup": "\u21ef", "/whitedblarrowup": "\u21ee", "/whitediamond": "\u25c7", "/whitediamondcontainingblacksmalldiamond": "\u25c8", "/whitedownpointingsmalltriangle": "\u25bf", "/whitedownpointingtriangle": "\u25bd", "/whiteleftpointingsmalltriangle": "\u25c3", "/whiteleftpointingtriangle": "\u25c1", "/whiterightpointingsmalltriangle": "\u25b9", "/whiterightpointingtriangle": "\u25b7", "/whitesmallsquare": "\u25ab", "/whitesquare": "\u25a1", "/whiteuppointingsmalltriangle": "\u25b5", "/whiteuppointingtriangle": "\u25b3", "/won": "\u20a9", "/wordjoiner": "\u2060", "/wreathproduct": "\u2240", "/wynn": "\u01bf", "/x": "x", "/xatailcyr": "\u04b3", "/xi": "\u03be", "/xor": "\u22bb", "/y": "y", "/yacute": "\u00fd", "/yacyr": "\u044f", "/yatcyr": "\u0463", "/yatcyrillic": "\u0463", "/ycircumflex": "\u0177", "/ydieresis": "\u00ff", "/yen": "\u00a5", "/yericyrillic": "\u044b", "/yerudieresiscyrillic": "\u04f9", "/yhook": "\u01b4", "/yicyrillic": "\u0457", "/ylongcyr": "\u044b", "/ylongdieresiscyr": "\u04f9", "/ymacron": "\u0233", "/yogh": "\u021d", "/yot": "\u03f3", "/yotgreek": "\u03f3", "/ypogegrammeni": "\u037a", "/yr": "\u01a6", "/ystroke": "\u024f", "/yucyr": "\u044e", "/yukrcyr": "\u0457", "/yusbigcyr": "\u046b", "/yusbigcyrillic": "\u046b", "/yusbigiotifiedcyr": "\u046d", "/yusbigiotifiedcyrillic": "\u046d", "/yuslittlecyr": "\u0467", "/yuslittlecyrillic": "\u0467", "/yuslittleiotifiedcyr": "\u0469", "/yuslittleiotifiedcyrillic": "\u0469", "/z": "z", "/zacute": "\u017a", "/zcaron": "\u017e", "/zdot": "\u017c", "/zdotaccent": "\u017c", "/zecyr": "\u0437", "/zecyrillic": "\u0437", "/zedescendercyrillic": "\u0499", "/zedieresiscyr": "\u04df", "/zedieresiscyrillic": "\u04df", "/zero": "0", "/zerothirds": "\u2189", "/zerowidthnonjoiner": "\u200c", "/zerowidthspace": "\u200b", "/zeta": "\u03b6", "/zetailcyr": "\u0499", "/zhebrevecyr": "\u04c2", "/zhebrevecyrillic": "\u04c2", "/zhecyr": "\u0436", "/zhecyrillic": "\u0436", "/zhedescendercyrillic": "\u0497", "/zhedieresiscyr": "\u04dd", "/zhedieresiscyrillic": "\u04dd", "/zhetailcyr": "\u0497", "/zhook": "\u0225", "/znotationbagmembership": "\u22ff", "/zstroke": "\u01b6", "/zswashtail": "\u0240"}


# ============================================================================================== polices

func _glyph_unicode(name):
    if contains_key(GLYPH_NAMES, name):
        return GLYPH_NAMES[name]
    base := name
    dot := string.find(base, ".")
    if dot > 0:
        base = _n.str_slice(base, 0, dot)
        if contains_key(GLYPH_NAMES, base):
            return GLYPH_NAMES[base]
    if string.starts_with(base, "uni") and len(base) >= 7:
        out := []
        k := 3
        while k + 4 <= len(base):
            b := _n.hex_decode(_n.str_slice(base, k, k + 4))
            if len(b) == 2:
                append(out, str(string.chr((b[0] << 8) | b[1])))
            k = k + 4
        return string.join("", out)
    if string.starts_with(base, "u") and len(base) >= 5 and len(base) <= 7:
        try:
            b := _n.hex_decode(u.pad_left(_n.str_slice(base, 1, null), 8, "0"))
            v := (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]
            if v > 0 and v < 1114112:
                return str(string.chr(v))
        catch e:
            return ""
    # noms « g123 », « cid123 », « a12 » : inconnus
    return ""

func _win(code):
    if code < 32:
        return ""
    return u.cp1252_decode([code])

func _table_char(tbl, code):
    v := tbl[code] if code < len(tbl) else 0
    if v == 0:
        return ""
    return str(string.chr(v))

# Analyse d'un flux CMap (ToUnicode ou encodage de police composite).
class CMap:
    func init():
        self.ranges = []
        self.map = {}
        self.cid = {}
        self.cid_ranges = []

    func code_length(first_byte):
        for r in self.ranges:
            if first_byte >= r[0] and first_byte <= r[1]:
                return r[2]
        return 0

func _hex_int(b):
    v := 0
    for x in b:
        v = (v << 8) | x
    return v

func _utf16(b):
    if len(b) == 1:
        return str(string.chr(b[0]))
    return u.utf16_decode(b, true)

func parse_cmap(data, cm=null):
    c := cm if cm != null else CMap()
    toks := _n.pdf_tokens(data, 0, null)[0]
    n := len(toks)
    i := 0
    mode := ""
    while i < n:
        t := toks[i]
        if t[0] == "k":
            w := t[1]
            if w == "begincodespacerange":
                mode = "cs"
            elif w == "beginbfchar":
                mode = "bfchar"
            elif w == "beginbfrange":
                mode = "bfrange"
            elif w == "begincidrange":
                mode = "cidrange"
            elif w == "begincidchar":
                mode = "cidchar"
            elif string.starts_with(w, "end"):
                mode = ""
            i = i + 1
            continue
        if mode == "cs" and t[0] == "x" and i + 1 < n and toks[i + 1][0] == "x":
            lo := t[1]
            hi := toks[i + 1][1]
            append(c.ranges, [lo[0] if len(lo) > 0 else 0, hi[0] if len(hi) > 0 else 255, len(lo)])
            i = i + 2
            continue
        if mode == "bfchar" and t[0] == "x" and i + 1 < n:
            dst := toks[i + 1]
            if dst[0] == "x" or dst[0] == "s":
                c.map[str(len(t[1])) + ":" + str(_hex_int(t[1]))] = _utf16(dst[1])
            elif dst[0] == "/":
                c.map[str(len(t[1])) + ":" + str(_hex_int(t[1]))] = _glyph_unicode(dst[1])
            i = i + 2
            continue
        if mode == "bfrange" and t[0] == "x" and i + 2 < n and toks[i + 1][0] == "x":
            lo := _hex_int(t[1])
            hi := _hex_int(toks[i + 1][1])
            ln := len(t[1])
            if hi - lo > 65535:
                hi = lo + 65535
            dst := toks[i + 2]
            if dst[0] == "x":
                base := dst[1]
                k := 0
                while lo + k <= hi:
                    b := []
                    for x in base:
                        append(b, x)
                    # incrémente le dernier octet (avec retenue)
                    carry := k
                    j := len(b) - 1
                    while j >= 0 and carry > 0:
                        s := b[j] + carry
                        b[j] = s & 255
                        carry = s >> 8
                        j = j - 1
                    c.map[str(ln) + ":" + str(lo + k)] = _utf16(b)
                    k = k + 1
                i = i + 3
                continue
            if dst[0] == "[":
                j := i + 3
                k := 0
                while j < n and toks[j][0] != "]":
                    if toks[j][0] == "x":
                        c.map[str(ln) + ":" + str(lo + k)] = _utf16(toks[j][1])
                    k = k + 1
                    j = j + 1
                i = j + 1
                continue
            i = i + 3
            continue
        if mode == "cidrange" and t[0] == "x" and i + 2 < n and toks[i + 1][0] == "x" and toks[i + 2][0] == "n":
            append(c.cid_ranges, [_hex_int(t[1]), _hex_int(toks[i + 1][1]), toks[i + 2][1], len(t[1])])
            i = i + 3
            continue
        if mode == "cidchar" and t[0] == "x" and i + 1 < n and toks[i + 1][0] == "n":
            c.cid[str(len(t[1])) + ":" + str(_hex_int(t[1]))] = toks[i + 1][1]
            i = i + 2
            continue
        i = i + 1
    return c

class FontDecoder:
    func init(doc, fdict):
        self.doc = doc
        self.d = fdict
        self.subtype = pr.name_of(doc.get(u.get(fdict, "Subtype", "/Type1")))
        self.base = pr.name_of(doc.get(u.get(fdict, "BaseFont", "/Unknown")))
        if self.base == null:
            self.base = "Unknown"
        self.composite = self.subtype == "Type0"
        self.to_unicode = null
        self.cmap = null
        self.widths = {}
        self.default_width = 1000 if self.composite else 500
        self.encoding = []
        self.vertical = false
        tu := doc.get(u.get(fdict, "ToUnicode", null))
        if pr.is_stream(tu):
            try:
                self.to_unicode = parse_cmap(doc.decode(tu))
            catch e:
                self.to_unicode = null
        if self.composite:
            self._init_composite()
        else:
            self._init_simple()
        self.space_width = self._space_width()

    func _init_composite():
        doc := self.doc
        enc := doc.get(u.get(self.d, "Encoding", "/Identity-H"))
        if pr.is_stream(enc):
            try:
                self.cmap = parse_cmap(doc.decode(enc))
            catch e:
                self.cmap = null
            wm := doc.get(u.get(enc.dict, "WMode", 0))
            self.vertical = wm == 1
        elif pr.is_name(enc):
            nm := pr.name_of(enc)
            self.vertical = string.ends_with(nm, "-V")
        desc := doc.get(u.get(self.d, "DescendantFonts", null))
        if type(desc) == "list" and len(desc) > 0:
            df := doc.get(desc[0])
            if type(df) == "dict":
                self.default_width = doc.get(u.get(df, "DW", 1000))
                w := doc.get(u.get(df, "W", null))
                if type(w) == "list":
                    i := 0
                    while i < len(w):
                        first := doc.get(w[i])
                        if i + 1 >= len(w):
                            break
                        nxt := doc.get(w[i + 1])
                        if type(nxt) == "list":
                            k := 0
                            for v in nxt:
                                self.widths[first + k] = to_float(doc.get(v))
                                k = k + 1
                            i = i + 2
                        elif i + 2 < len(w):
                            last := nxt
                            v := to_float(doc.get(w[i + 2]))
                            if last - first <= 65535:
                                c := first
                                while c <= last:
                                    self.widths[c] = v
                                    c = c + 1
                            i = i + 3
                        else:
                            break

    func _init_simple():
        doc := self.doc
        base_tbl := null
        bn := string.lower(self.base)
        symbolic := string.contains(bn, "symbol") or string.contains(bn, "dingbat") or string.contains(bn, "wingding")
        names := {}
        enc := doc.get(u.get(self.d, "Encoding", null))
        enc_name := null
        if pr.is_name(enc):
            enc_name = pr.name_of(enc)
        elif type(enc) == "dict":
            be := doc.get(u.get(enc, "BaseEncoding", null))
            if pr.is_name(be):
                enc_name = pr.name_of(be)
            diffs := doc.get(u.get(enc, "Differences", null))
            if type(diffs) == "list":
                code := 0
                for v in diffs:
                    vv := doc.get(v)
                    if type(vv) == "int":
                        code = vv
                    elif pr.is_name(vv):
                        names[code] = pr.name_of(vv)
                        code = code + 1
        self.enc_name = enc_name
        self.names = names
        self.symbolic = symbolic
        self.std_font = null
        for k in keys(pw.STANDARD_FONTS):
            if k == self.base:
                self.std_font = k
        fc := doc.get(u.get(self.d, "FirstChar", 0))
        ws := doc.get(u.get(self.d, "Widths", null))
        if type(ws) == "list":
            k := 0
            for v in ws:
                self.widths[fc + k] = to_float(doc.get(v))
                k = k + 1
        elif self.std_font != null:
            tbl := pw.STANDARD_FONTS[self.std_font]["widths"]
            c := 32
            while c < 256:
                self.widths[c] = to_float(tbl[c - 32])
                c = c + 1
        if self.subtype == "Type3":
            fm := doc.get(u.get(self.d, "FontMatrix", null))
            if type(fm) == "list" and len(fm) > 0:
                sc := to_float(doc.get(fm[0])) * 1000.0
                for k in keys(self.widths):
                    self.widths[k] = self.widths[k] * sc

    func _space_width():
        if self.composite:
            return to_float(self.default_width) * 0.3
        if contains_key(self.widths, 32) and self.widths[32] > 0:
            return self.widths[32]
        return 250.0

    # Découpe des octets d'une chaîne en codes : liste de [code, nb_octets].
    func codes(data):
        out := []
        n := len(data)
        if not self.composite:
            for b in data:
                append(out, [b, 1])
            return out
        i := 0
        while i < n:
            ln := 2
            if self.cmap != null and len(self.cmap.ranges) > 0:
                l2 := self.cmap.code_length(data[i])
                if l2 > 0:
                    ln = l2
            if i + ln > n:
                ln = n - i
            v := 0
            k := 0
            while k < ln:
                v = (v << 8) | data[i + k]
                k = k + 1
            append(out, [v, ln])
            i = i + ln
        return out

    func unicode(code, ln):
        if self.to_unicode != null:
            key := str(ln) + ":" + str(code)
            if contains_key(self.to_unicode.map, key):
                return self.to_unicode.map[key]
        if self.composite:
            # sans ToUnicode : identité (souvent fausse, mais mieux que rien pour les CID Unicode)
            if code >= 32 and code < 55296:
                return str(string.chr(code))
            return ""
        if contains_key(self.names, code):
            g := _glyph_unicode(self.names[code])
            if g != "":
                return g
        en := self.enc_name
        if en == "WinAnsiEncoding":
            return _win(code)
        if en == "MacRomanEncoding":
            return _table_char(MAC_ROMAN_ENCODING, code)
        if en == "StandardEncoding":
            return _table_char(STANDARD_ENCODING, code)
        b := string.lower(self.base)
        if string.contains(b, "symbol"):
            return _table_char(SYMBOL_ENCODING, code)
        if string.contains(b, "dingbat"):
            return _table_char(ZAPF_ENCODING, code)
        if self.subtype == "TrueType" or en == null:
            return _win(code)
        return _table_char(STANDARD_ENCODING, code)

    func width(code):
        if self.composite:
            cid := code
            if self.cmap != null and (len(self.cmap.cid_ranges) > 0 or len(keys(self.cmap.cid)) > 0):
                cid = self._cid(code)
            if contains_key(self.widths, cid):
                return self.widths[cid]
            return to_float(self.default_width)
        if contains_key(self.widths, code):
            return self.widths[code]
        return 500.0

    func _cid(code):
        for r in self.cmap.cid_ranges:
            if code >= r[0] and code <= r[1]:
                return r[2] + code - r[0]
        return code

# ============================================================================================== interpréteur

func _mul(m, n):
    return [m[0] * n[0] + m[1] * n[2], m[0] * n[1] + m[1] * n[3], m[2] * n[0] + m[3] * n[2], m[2] * n[1] + m[3] * n[3], m[4] * n[0] + m[5] * n[2] + n[4], m[4] * n[1] + m[5] * n[3] + n[5]]

func _apply(m, x0, y0):
    return [m[0] * x0 + m[2] * y0 + m[4], m[1] * x0 + m[3] * y0 + m[5]]

func _f(v):
    if type(v) == "int" or type(v) == "float":
        return to_float(v)
    return 0.0

class _Interp:
    func init(doc, page, want_text, want_graphics):
        self.doc = doc
        self.page = page
        self.want_text = want_text
        self.want_graphics = want_graphics
        self.chunks = []
        self.lines = []
        self.rects = []
        self._fonts = {}
        self.depth = 0
        # repère affiché : origine en haut à gauche de la boîte visible, rotation appliquée
        box := page.crop_box()
        rot := page.rotation()
        w := box[2] - box[0]
        h := box[3] - box[1]
        base := [1.0, 0.0, 0.0, 1.0, -box[0], -box[1]]
        flip := [1.0, 0.0, 0.0, -1.0, 0.0, h]
        if rot == 90:
            flip = [0.0, 1.0, 1.0, 0.0, 0.0, 0.0]
        elif rot == 180:
            flip = [-1.0, 0.0, 0.0, 1.0, w, 0.0]
        elif rot == 270:
            flip = [0.0, -1.0, -1.0, 0.0, h, w]
        self.device = _mul(base, flip)

    func font(res, name):
        fonts := self.doc.get(u.get(res, "Font", null))
        if type(fonts) != "dict":
            return null
        ref := u.get(fonts, name, null)
        key := name
        if pr.is_ref(ref):
            key = "r" + str(ref.num)
        if contains_key(self._fonts, key):
            return self._fonts[key]
        fd := self.doc.get(ref)
        dec := null
        if type(fd) == "dict":
            try:
                dec = FontDecoder(self.doc, fd)
            catch e:
                dec = null
        self._fonts[key] = dec
        return dec

    func run(content, res, ctm):
        if self.depth > 12:
            return null
        self.depth = self.depth + 1
        toks := _n.pdf_tokens(content, 0, null)[0]
        n := len(toks)
        stack := []
        gs := {"ctm": ctm}
        gstack := []
        ts := {"font": null, "size": 0.0, "tc": 0.0, "tw": 0.0, "th": 1.0, "tl": 0.0, "rise": 0.0, "fname": ""}
        tm := [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
        tlm := [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
        path := []
        cur := [0.0, 0.0]
        start := [0.0, 0.0]
        i := 0
        while i < n:
            t := toks[i]
            k := t[0]
            if k != "k":
                if k == "[":
                    r := pr.parse_value(toks, i)
                    append(stack, r[0])
                    i = r[1]
                    continue
                if k == "<<":
                    r := pr.parse_value(toks, i)
                    append(stack, r[0])
                    i = r[1]
                    continue
                if k == "n":
                    append(stack, t[1])
                elif k == "/":
                    append(stack, "/" + t[1])
                elif k == "s" or k == "x":
                    append(stack, pr.PdfString(t[1], k == "x"))
                i = i + 1
                continue
            op := t[1]
            i = i + 1
            ns := len(stack)
            if op == "Tj" or op == "'" or op == "\"" or op == "TJ":
                if op == "'" or op == "\"":
                    if op == "\"" and ns >= 3:
                        ts["tw"] = _f(stack[ns - 3])
                        ts["tc"] = _f(stack[ns - 2])
                    tlm = _mul([1.0, 0.0, 0.0, 1.0, 0.0, -ts["tl"]], tlm)
                    tm = tlm
                if self.want_text and ns > 0 and ts["font"] != null:
                    arg := stack[ns - 1]
                    items := arg if type(arg) == "list" else [arg]
                    for it in items:
                        if isinstance(it, pr.PdfString):
                            tm = self._show(it.data, ts, tm, gs["ctm"])
                        elif type(it) == "int" or type(it) == "float":
                            tx := -to_float(it) / 1000.0 * ts["size"] * ts["th"]
                            tm = _mul([1.0, 0.0, 0.0, 1.0, tx, 0.0], tm)
                stack = []
                continue
            if op == "Td" or op == "TD":
                if ns >= 2:
                    tx := _f(stack[ns - 2])
                    ty := _f(stack[ns - 1])
                    if op == "TD":
                        ts["tl"] = -ty
                    tlm = _mul([1.0, 0.0, 0.0, 1.0, tx, ty], tlm)
                    tm = tlm
            elif op == "Tm":
                if ns >= 6:
                    tlm = [_f(stack[ns - 6]), _f(stack[ns - 5]), _f(stack[ns - 4]), _f(stack[ns - 3]), _f(stack[ns - 2]), _f(stack[ns - 1])]
                    tm = tlm
            elif op == "T*":
                tlm = _mul([1.0, 0.0, 0.0, 1.0, 0.0, -ts["tl"]], tlm)
                tm = tlm
            elif op == "BT":
                tm = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
                tlm = tm
            elif op == "Tf":
                if ns >= 2:
                    nm := pr.name_of(stack[ns - 2])
                    ts["font"] = self.font(res, nm) if nm != null else null
                    ts["size"] = _f(stack[ns - 1])
                    ts["fname"] = ts["font"].base if ts["font"] != null else ""
            elif op == "Tc":
                if ns >= 1:
                    ts["tc"] = _f(stack[ns - 1])
            elif op == "Tw":
                if ns >= 1:
                    ts["tw"] = _f(stack[ns - 1])
            elif op == "Tz":
                if ns >= 1:
                    ts["th"] = _f(stack[ns - 1]) / 100.0
            elif op == "TL":
                if ns >= 1:
                    ts["tl"] = _f(stack[ns - 1])
            elif op == "Ts":
                if ns >= 1:
                    ts["rise"] = _f(stack[ns - 1])
            elif op == "q":
                append(gstack, [gs["ctm"], u.merge(ts, null)])
            elif op == "Q":
                if len(gstack) > 0:
                    st := collections.pop(gstack)
                    gs["ctm"] = st[0]
                    ts = st[1]
            elif op == "cm":
                if ns >= 6:
                    m := [_f(stack[ns - 6]), _f(stack[ns - 5]), _f(stack[ns - 4]), _f(stack[ns - 3]), _f(stack[ns - 2]), _f(stack[ns - 1])]
                    gs["ctm"] = _mul(m, gs["ctm"])
            elif op == "Do":
                if ns >= 1:
                    self._do(pr.name_of(stack[ns - 1]), res, gs["ctm"])
            elif self.want_graphics:
                if op == "m" and ns >= 2:
                    cur = [_f(stack[ns - 2]), _f(stack[ns - 1])]
                    start = cur
                elif op == "l" and ns >= 2:
                    p := [_f(stack[ns - 2]), _f(stack[ns - 1])]
                    append(path, ["l", cur, p])
                    cur = p
                elif op == "re" and ns >= 4:
                    x0 := _f(stack[ns - 4])
                    y0 := _f(stack[ns - 3])
                    append(path, ["re", [x0, y0], [x0 + _f(stack[ns - 2]), y0 + _f(stack[ns - 1])]])
                    cur = [x0, y0]
                elif op == "c" and ns >= 6:
                    cur = [_f(stack[ns - 2]), _f(stack[ns - 1])]
                elif (op == "v" or op == "y") and ns >= 4:
                    cur = [_f(stack[ns - 2]), _f(stack[ns - 1])]
                elif op == "h":
                    if cur[0] != start[0] or cur[1] != start[1]:
                        append(path, ["l", cur, start])
                    cur = start
                elif op == "S" or op == "s" or op == "f" or op == "F" or op == "f*" or op == "B" or op == "B*" or op == "b" or op == "b*":
                    self._emit_path(path, gs["ctm"])
                    path = []
                elif op == "n":
                    path = []
            stack = []
        self.depth = self.depth - 1

    func _emit_path(path, ctm):
        m := _mul(ctm, self.device)
        for seg in path:
            a := _apply(m, seg[1][0], seg[1][1])
            b := _apply(m, seg[2][0], seg[2][1])
            if seg[0] == "re":
                c := _apply(m, seg[1][0], seg[2][1])
                d := _apply(m, seg[2][0], seg[1][1])
                xs := [a[0], b[0], c[0], d[0]]
                ys := [a[1], b[1], c[1], d[1]]
                x0 := xs[0]
                x1 := xs[0]
                y0 := ys[0]
                y1 := ys[0]
                for v in xs:
                    if v < x0:
                        x0 = v
                    if v > x1:
                        x1 = v
                for v in ys:
                    if v < y0:
                        y0 = v
                    if v > y1:
                        y1 = v
                append(self.rects, [x0, y0, x1, y1])
            else:
                append(self.lines, [a[0], a[1], b[0], b[1]])

    func _do(name, res, ctm):
        if name == null:
            return null
        xo := self.doc.get(u.get(res, "XObject", null))
        if type(xo) != "dict":
            return null
        obj := self.doc.get(u.get(xo, name, null))
        if not pr.is_stream(obj):
            return null
        st := pr.name_of(self.doc.get(u.get(obj.dict, "Subtype", "")))
        if st != "Form":
            return null
        m := self.doc.get(u.get(obj.dict, "Matrix", null))
        mm := [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
        if type(m) == "list" and len(m) == 6:
            mm = [_f(self.doc.get(m[0])), _f(self.doc.get(m[1])), _f(self.doc.get(m[2])), _f(self.doc.get(m[3])), _f(self.doc.get(m[4])), _f(self.doc.get(m[5]))]
        r2 := self.doc.get(u.get(obj.dict, "Resources", null))
        if type(r2) != "dict":
            r2 = res
        try:
            self.run(self.doc.decode(obj), r2, _mul(mm, ctm))
        catch e:
            if e.type != "PDFError" and e.type != "UnsupportedError" and e.type != "CompressionError":
                raise(e)

    func _show(data, ts, tm, ctm):
        f := ts["font"]
        size := ts["size"]
        th := ts["th"]
        codes := f.codes(data)
        chars := []
        widths := []
        adv := 0.0
        for cl in codes:
            code := cl[0]
            w0 := f.width(code) / 1000.0
            uc := f.unicode(code, cl[1])
            tx := (w0 * size + ts["tc"] + (ts["tw"] if cl[1] == 1 and code == 32 else 0.0)) * th
            append(chars, uc)
            append(widths, tx)
            adv = adv + tx
        trm := _mul(_mul([size * th, 0.0, 0.0, size, 0.0, ts["rise"]], tm), ctm)
        dev := _mul(trm, self.device)
        p0 := _apply(_mul(_mul([1.0, 0.0, 0.0, 1.0, 0.0, ts["rise"]], tm), ctm), 0.0, 0.0)
        p1 := _apply(_mul(_mul([1.0, 0.0, 0.0, 1.0, adv, ts["rise"]], tm), ctm), 0.0, 0.0)
        d0 := _apply(self.device, p0[0], p0[1])
        d1 := _apply(self.device, p1[0], p1[1])
        eff := (dev[2] * dev[2] + dev[3] * dev[3]) ** 0.5
        text := string.join("", chars)
        if text != "":
            scale := 1.0
            if adv > 0:
                dx := d1[0] - d0[0]
                dy := d1[1] - d0[1]
                scale = ((dx * dx + dy * dy) ** 0.5) / adv
            sw := []
            for w in widths:
                append(sw, w * scale)
            append(self.chunks, {"text": text, "x": d0[0], "y": d0[1], "x1": d1[0], "y1": d1[1], "size": eff, "font": ts["fname"], "widths": sw, "chars": chars, "space": f.space_width / 1000.0 * eff})
        return _mul([1.0, 0.0, 0.0, 1.0, adv, 0.0], tm)

func _interp(page, want_text, want_graphics):
    it := _Interp(page.doc, page, want_text, want_graphics)
    content := page.contents()
    try:
        it.run(content, page.resources(), [1.0, 0.0, 0.0, 1.0, 0.0, 0.0])
    catch e:
        if e.type != "PDFError" and e.type != "UnsupportedError" and e.type != "CompressionError":
            raise(e)
    return it

# ============================================================================================== API

func open(src, password=""):
    if isinstance(src, pr.PdfFile):
        return src
    return pr.open(src, password)

func chunks(page):
    return _interp(page, true, false).chunks

func graphics(page):
    it := _interp(page, false, true)
    return {"lines": it.lines, "rects": it.rects}

func _horizontal(c):
    dy := c["y1"] - c["y"]
    dx := c["x1"] - c["x"]
    return (dy if dy >= 0 else -dy) <= (dx if dx >= 0 else -dx) * 0.2 + 0.5

# Regroupe les segments en lignes (même ligne de base, à une demi-hauteur près), triées de haut en bas.
func lines(page, chunk_list=null):
    cs := chunk_list if chunk_list != null else chunks(page)
    hz := []
    other := []
    for c in cs:
        if _horizontal(c):
            append(hz, c)
        else:
            append(other, c)
    hz = u.sort(hz, (c) => c["y"])
    groups := []
    for c in hz:
        placed := false
        tol := c["size"] * 0.5 if c["size"] > 0 else 2.0
        k := len(groups) - 1
        while k >= 0 and k >= len(groups) - 4:
            g := groups[k]
            dy := c["y"] - g["y"]
            if (dy if dy >= 0 else -dy) <= tol:
                append(g["chunks"], c)
                placed = true
                break
            k = k - 1
        if not placed:
            append(groups, {"y": c["y"], "chunks": [c], "size": c["size"]})
    out := []
    for g in groups:
        cl := u.sort(g["chunks"], (c) => c["x"])
        parts := []
        prev := null
        size := 0.0
        for c in cl:
            if c["size"] > size:
                size = c["size"]
            if prev != null:
                # doublons (faux gras par surimpression)
                if c["text"] == prev["text"] and (c["x"] - prev["x"] if c["x"] >= prev["x"] else prev["x"] - c["x"]) < 1.0:
                    continue
                gap := c["x"] - prev["x1"]
                sp := prev["space"] if prev["space"] > 0 else prev["size"] * 0.25
                if gap > sp * 0.45 and not string.ends_with(parts[len(parts) - 1], " ") and not string.starts_with(c["text"], " "):
                    append(parts, " ")
            append(parts, c["text"])
            prev = c
        x0 := cl[0]["x"] if len(cl) > 0 else 0.0
        x1 := cl[len(cl) - 1]["x1"] if len(cl) > 0 else 0.0
        append(out, {"text": string.join("", parts), "x0": x0, "x1": x1, "y": g["y"], "size": size, "chunks": cl})
    for c in other:
        append(out, {"text": c["text"], "x0": c["x"], "x1": c["x1"], "y": c["y"], "size": c["size"], "chunks": [c]})
    return out

func _rstrip(s):
    t := s
    while len(t) > 0 and str(t[len(t) - 1]) == " ":
        t = _n.str_slice(t, 0, len(t) - 1)
    return t

# Texte d'une page. layout=true : positions horizontales conservées (colonnes alignées par des espaces).
func page_text(page, layout=false):
    ls := lines(page)
    if len(ls) == 0:
        return ""
    if layout:
        sizes := []
        total := 0.0
        count := 0
        for l in ls:
            for c in l["chunks"]:
                for w in c["widths"]:
                    if w > 0:
                        total = total + w
                        count = count + 1
        cw := total / to_float(count) if count > 0 else 5.0
        if cw <= 0:
            cw = 5.0
        out := []
        prev_y := null
        for l in ls:
            if prev_y != null and l["y"] - prev_y > l["size"] * 2.2:
                append(out, "")
            buf := ""
            for c in l["chunks"]:
                col := to_int(c["x"] / cw)
                while len(buf) < col:
                    buf = buf + " "
                if len(buf) > col and not string.ends_with(buf, " ") and len(buf) > 0:
                    buf = buf + " "
                buf = buf + c["text"]
            append(out, _rstrip(buf))
            prev_y = l["y"]
        return string.join("\n", out)
    out := []
    prev := null
    for l in ls:
        if prev != null:
            gap := l["y"] - prev["y"]
            lh := prev["size"] if prev["size"] > 0 else 10.0
            if gap > lh * 2.2:
                append(out, "")
        append(out, string.trim(l["text"]))
        prev = l
    return string.join("\n", out)

func _page_list(doc, pages):
    if pages == null:
        return doc.pages()
    out := []
    ps := pages if type(pages) == "list" else [pages]
    for i in ps:
        append(out, doc.page(i))
    return out

func text(src, pages=null, layout=false, password=""):
    doc := open(src, password)
    parts := []
    for p in _page_list(doc, pages):
        append(parts, page_text(p, layout))
    return string.join("\n\x0c", parts)

# Mots avec boîte englobante (coupure aux espaces, positions de chaque caractère).
func words(page):
    out := []
    for c in chunks(page):
        if not _horizontal(c):
            append(out, {"text": c["text"], "x0": c["x"], "y0": c["y"] - c["size"], "x1": c["x1"], "y1": c["y"], "size": c["size"], "font": c["font"]})
            continue
        x := c["x"]
        cur := ""
        wx := x
        k := 0
        for ch in c["chars"]:
            w := c["widths"][k] if k < len(c["widths"]) else 0.0
            if ch == " " or ch == " " or ch == "\t":
                if cur != "":
                    append(out, {"text": cur, "x0": wx, "y0": c["y"] - c["size"] * 0.8, "x1": x, "y1": c["y"] + c["size"] * 0.2, "size": c["size"], "font": c["font"]})
                cur = ""
                wx = x + w
            else:
                if cur == "":
                    wx = x
                cur = cur + ch
            x = x + w
            k = k + 1
        if cur != "":
            append(out, {"text": cur, "x0": wx, "y0": c["y"] - c["size"] * 0.8, "x1": x, "y1": c["y"] + c["size"] * 0.2, "size": c["size"], "font": c["font"]})
    # fusionne les fragments d'un même mot (segments contigus sans espace)
    out = u.sort(out, (w) => to_int(w["y1"] * 2.0) * 100000 + to_int(w["x0"]))
    merged := []
    for w in out:
        if len(merged) > 0:
            p := merged[len(merged) - 1]
            dy := w["y1"] - p["y1"]
            if (dy if dy >= 0 else -dy) < w["size"] * 0.3 and w["x0"] - p["x1"] < w["size"] * 0.08 and w["x0"] >= p["x0"]:
                p["text"] = p["text"] + w["text"]
                p["x1"] = w["x1"]
                continue
        append(merged, w)
    return merged

func search(src, pattern, ignore_case=true, password=""):
    doc := open(src, password)
    out := []
    pat := string.lower(pattern) if ignore_case else pattern
    i := 0
    for p in doc.pages():
        for l in lines(p):
            t := string.lower(l["text"]) if ignore_case else l["text"]
            if string.contains(t, pat):
                append(out, {"page": i, "line": string.trim(l["text"])})
        i = i + 1
    return out

# ============================================================================================== images

func png_encode(pixels, width, height, channels, depth=8, palette=null):
    ctype := 0
    if palette != null:
        ctype = 3
    elif channels == 3:
        ctype = 2
    elif channels == 4:
        ctype = 6
    elif channels == 2:
        ctype = 4
    stride := (width * channels * depth + 7) // 8
    raw := []
    r := 0
    while r < height:
        append(raw, [0])
        append(raw, _n.bytes_slice(pixels, r * stride, r * stride + stride))
        r = r + 1
    data := compression.zlib_compress(u.concat(raw), 6)
    def_chunk := (tag, body) => u.concat([u.pack_u32be(len(body)), _n.latin1_encode(tag), body, u.pack_u32be(_n.crc32(u.concat([_n.latin1_encode(tag), body]), 0))])
    parts := [[137, 80, 78, 71, 13, 10, 26, 10], def_chunk("IHDR", u.concat([u.pack_u32be(width), u.pack_u32be(height), [depth, ctype, 0, 0, 0]]))]
    if palette != null:
        append(parts, def_chunk("PLTE", palette))
    append(parts, def_chunk("IDAT", data))
    append(parts, def_chunk("IEND", []))
    return u.concat(parts)

func _cmyk_to_rgb(d):
    out := []
    n := len(d) - len(d) % 4
    i := 0
    while i < n:
        k := d[i + 3]
        append(out, 255 - (d[i] + k if d[i] + k < 255 else 255))
        append(out, 255 - (d[i + 1] + k if d[i + 1] + k < 255 else 255))
        append(out, 255 - (d[i + 2] + k if d[i + 2] + k < 255 else 255))
        i = i + 4
    return out

func _image_record(doc, obj, name, page_index):
    d := obj.dict
    w := doc.get(u.get(d, "Width", 0))
    h := doc.get(u.get(d, "Height", 0))
    bpc := doc.get(u.get(d, "BitsPerComponent", 8))
    cs := doc.get(u.get(d, "ColorSpace", null))
    rec := {"page": page_index, "name": name, "width": w, "height": h, "bits": bpc, "format": null, "data": null, "colorspace": u.to_text(cs) if pr.is_name(cs) else "complex"}
    r := doc.decode_image(obj)
    data := r[0]
    filt := r[1]
    if filt == "DCTDecode" or filt == "DCT":
        rec["format"] = "jpeg"
        rec["data"] = data
        return rec
    if filt == "JPXDecode":
        rec["format"] = "jp2"
        rec["data"] = data
        return rec
    if filt != null:
        rec["format"] = "raw"
        rec["data"] = data
        rec["filter"] = filt
        return rec
    # couleurs : DeviceGray / RGB / CMYK / Indexed / ICCBased
    ncomp := 3
    palette := null
    csn := pr.name_of(cs) if pr.is_name(cs) else null
    if csn == "DeviceGray" or csn == "CalGray" or csn == "G":
        ncomp = 1
    elif csn == "DeviceCMYK" or csn == "CMYK":
        ncomp = 4
    elif type(cs) == "list" and len(cs) > 0:
        kind := pr.name_of(doc.get(cs[0]))
        if kind == "ICCBased" and len(cs) > 1:
            icc := doc.get(cs[1])
            ncomp = doc.get(u.get(icc.dict, "N", 3)) if pr.is_stream(icc) else 3
        elif kind == "Indexed" and len(cs) >= 4:
            ncomp = 1
            base := doc.get(cs[1])
            lookup := doc.get(cs[3])
            lb := lookup.data if isinstance(lookup, pr.PdfString) else (doc.decode(lookup) if pr.is_stream(lookup) else [])
            bn := pr.name_of(base) if pr.is_name(base) else "DeviceRGB"
            if bn == "DeviceRGB" or bn == null:
                palette = lb
            elif bn == "DeviceGray":
                palette = []
                for x in lb:
                    append(palette, x)
                    append(palette, x)
                    append(palette, x)
            elif bn == "DeviceCMYK":
                palette = _cmyk_to_rgb(lb)
            else:
                palette = lb
        elif kind == "CalRGB" or kind == "Lab":
            ncomp = 3
        elif kind == "Separation":
            ncomp = 1
        elif kind == "DeviceN" and len(cs) > 1:
            names := doc.get(cs[1])
            ncomp = len(names) if type(names) == "list" else 1
    if doc.get(u.get(d, "ImageMask", false)) == true:
        ncomp = 1
        bpc = 1
    expected := ((w * ncomp * bpc + 7) // 8) * h
    if len(data) < expected or w <= 0 or h <= 0:
        rec["format"] = "raw"
        rec["data"] = data
        return rec
    data = _n.bytes_slice(data, 0, expected)
    if ncomp == 4 and bpc == 8:
        data = _cmyk_to_rgb(data)
        ncomp = 3
    if ncomp != 1 and ncomp != 3:
        rec["format"] = "raw"
        rec["data"] = data
        return rec
    if bpc != 8 and bpc != 1 and bpc != 2 and bpc != 4 and not (bpc == 16):
        rec["format"] = "raw"
        rec["data"] = data
        return rec
    if bpc == 16:
        d8 := []
        k := 0
        while k < len(data):
            append(d8, data[k])
            k = k + 2
        data = d8
        bpc = 8
    rec["format"] = "png"
    if palette != null:
        pal := _n.bytes_slice(palette, 0, 768)
        rec["data"] = png_encode(data, w, h, 1, bpc, pal)
    else:
        if bpc == 1 and doc.get(u.get(d, "ImageMask", false)) == true:
            inv := []
            for b in data:
                append(inv, 255 - b)
            data = inv
        rec["data"] = png_encode(data, w, h, ncomp, bpc)
    return rec

func images(src, pages=null, password=""):
    doc := open(src, password)
    out := []
    seen := {}
    for p in _page_list(doc, pages):
        res := p.resources()
        _collect_images(doc, res, p.index, out, seen, 0)
    return out

func _collect_images(doc, res, index, out, seen, depth):
    if depth > 8:
        return null
    xo := doc.get(u.get(res, "XObject", null))
    if type(xo) != "dict":
        return null
    for name in keys(xo):
        ref := xo[name]
        key := "r" + str(ref.num) if pr.is_ref(ref) else name + str(index)
        if contains_key(seen, key):
            continue
        seen[key] = true
        obj := doc.get(ref)
        if not pr.is_stream(obj):
            continue
        st := pr.name_of(doc.get(u.get(obj.dict, "Subtype", "")))
        if st == "Image":
            try:
                append(out, _image_record(doc, obj, "p" + str(index + 1) + "_" + name, index))
            catch e:
                continue
        elif st == "Form":
            r2 := doc.get(u.get(obj.dict, "Resources", null))
            if type(r2) == "dict":
                _collect_images(doc, r2, index, out, seen, depth + 1)

# ============================================================================================== divers

func links(src, password=""):
    doc := open(src, password)
    out := []
    for p in doc.pages():
        for l in p.links():
            rec := {"page": p.index, "rect": l["rect"]}
            if contains_key(l, "uri"):
                rec["uri"] = l["uri"]
            else:
                rec["target_page"] = l["page"]
            append(out, rec)
    return out

func fonts(src, password=""):
    doc := open(src, password)
    found := {}
    order := []
    for p in doc.pages():
        fd := doc.get(u.get(p.resources(), "Font", null))
        if type(fd) != "dict":
            continue
        for k in keys(fd):
            f := doc.get(fd[k])
            if type(f) != "dict":
                continue
            nm := pr.name_of(doc.get(u.get(f, "BaseFont", "/?")))
            if not contains_key(found, nm):
                emb := false
                desc := doc.get(u.get(f, "FontDescriptor", null))
                if pr.name_of(doc.get(u.get(f, "Subtype", ""))) == "Type0":
                    dfs := doc.get(u.get(f, "DescendantFonts", []))
                    if type(dfs) == "list" and len(dfs) > 0:
                        df := doc.get(dfs[0])
                        desc = doc.get(u.get(df, "FontDescriptor", null)) if type(df) == "dict" else null
                if type(desc) == "dict":
                    emb = contains_key(desc, "FontFile") or contains_key(desc, "FontFile2") or contains_key(desc, "FontFile3")
                found[nm] = {"name": nm, "type": pr.name_of(doc.get(u.get(f, "Subtype", "/Type1"))), "embedded": emb, "pages": []}
                append(order, nm)
            pages_list := found[nm]["pages"]
            if len(pages_list) == 0 or pages_list[len(pages_list) - 1] != p.index:
                append(pages_list, p.index)
    out := []
    for nm in order:
        append(out, found[nm])
    return out

func metadata(src, password=""):
    doc := open(src, password)
    return {"info": doc.info(), "xmp": doc.xmp(), "pages": doc.page_count(), "version": doc.version, "encrypted": doc.encrypted, "outlines": doc.outlines()}
