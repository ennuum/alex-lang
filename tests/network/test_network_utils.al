# Test des modules sans réseau de network.* : constants, errors, config, utils, encoding (RFC 4648, 2045, 3492),
# ipaddress, uri (RFC 3986 §5.4, RFC 6570), url, http_headers, http_cookies (RFC 6265), compression,
# http_multipart, mime (RFC 2047), xml_writer / xml_parser / xml, html, xmlrpc, protobuf, security, certificates,
# retry, timeout, connection_pool, firewall, routing.

from core use len, type
from collections use append, keys
use string as s
use _native_net as _n
use network.constants as nc
use network.errors as ne
use network.config as cfg
use network.utils as nu
use network.encoding as enc
use network.ipaddress as ip
use network.uri as uri
use network.url as url
use network.http_headers as hh
use network.http_cookies as ck
use network.compression as nz
use network.http_multipart as mp
use network.mime as mime
use network.xml as xml
use network.xml_parser as xp
use network.html as html
use network.xmlrpc as rpc
use network.protobuf as pb
use network.security as sec
use network.retry as rt
use network.timeout as to
use network.firewall as fwm
use network.routing as routing

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check(cond, label):
    check_eq(cond, true, label)

func error_of(f):
    try:
        f()
    catch e:
        return e.type
    return "aucune erreur"

func strs(xs):
    out := []
    for x in xs:
        append(out, x.str())
    return out

# ---------------------------------------------------------------- constants, errors, config, utils
check_eq([nc.default_port("IMAPS"), nc.default_port("inconnu"), nc.status_reason(418), nc.status_class(503)], [993, null, "I'm a teapot", "server_error"], "constants")
check_eq(ne.lineage("CertificateError"), ["CertificateError", "TlsError", "NetworkError"], "errors : hiérarchie")
try:
    raise("NetworkError", "connect : refusé [ECONNREFUSED]")
catch e:
    check_eq([ne.errno_of(e), ne.is_transient(e), ne.is_a(e, ne.NETWORK)], ["ECONNREFUSED", true, true], "errors : errno et classement")
try:
    raise("SmtpError", "smtp : 550 boîte inconnue")
catch e:
    check_eq([ne.reply_code(e), ne.is_transient(e)], [550, false], "errors : code de réponse")
c := cfg.Config()
c.set("timeout", 5.0)
check_eq(c.get("timeout"), 5.0, "config : set / get")
check_eq(error_of(() => c.set("timeout", "x")), "TypeError", "config : type contrôlé")
check_eq(cfg.matches_no_proxy("api.exemple.org", cfg.parse_no_proxy("localhost, .exemple.org, 10.0.0.0/8")), true, "config : NO_PROXY suffixe")
check_eq(cfg.matches_no_proxy("10.2.3.4", ["10.0.0.0/8"]), true, "config : NO_PROXY CIDR")
check_eq([nu.split_host_port("[::1]:8080"), nu.split_host_port("a.b:21"), nu.split_host_port("fe80::1", 7)], [("::1", 8080), ("a.b", 21), ("fe80::1", 7)], "utils : hôte:port")
check_eq([nu.unpack_u16(nu.pack_u16(513)), nu.unpack_u32(nu.pack_u32(258, true), 0, true), nu.unpack_u64(nu.pack_u64(-5))], [513, 258, -5], "utils : entiers réseau")
check_eq([nu.human_bytes(1536), nu.human_rate(1250000)], ["1.5 Kio", "10.0 Mbit/s"], "utils : tailles lisibles")
check_eq([nu.float_repr(0.1 + 0.2), nu.float_repr(100.0), nu.float_repr(1e16)], ["0.30000000000000004", "100.0", "1e+16"], "utils : float_repr")
check_eq([nu.is_valid_hostname("ex-ample.org"), nu.is_valid_hostname("-x.org"), nu.has_control_breaks("a\r\nb")], [true, false, true], "utils : noms d'hôte")

# ---------------------------------------------------------------- encoding
check_eq([enc.base64_encode(""), enc.base64_encode("f"), enc.base64_encode("fo"), enc.base64_encode("foo"), enc.base64_encode("foob"), enc.base64_encode("fooba"), enc.base64_encode("foobar")], ["", "Zg==", "Zm8=", "Zm9v", "Zm9vYg==", "Zm9vYmE=", "Zm9vYmFy"], "base64 (RFC 4648 §10)")
check_eq(enc.base64_decode("Zm9vYmE="), "fooba", "base64 : décodage")
check_eq([enc.base32_encode("foobar"), enc.base32_decode("MZXW6YTBOI======")], ["MZXW6YTBOI======", "foobar"], "base32")
check_eq(enc.percent_encode("a b/é", "/"), "a%20b/%C3%A9", "pourcentage")
check_eq(enc.qp_decode("caf=C3=A9 =3D ok=20\r\nligne=\r\nsuite"), "café = ok \r\nlignesuite", "quoted-printable")
check_eq([enc.punycode_encode("bücher"), enc.punycode_decode("egbpdaj6bu4bxfgehfvwxn"), enc.punycode_encode("他们为什么不说中文")], ["bcher-kva", "ليهمابتكلموشعربي؟", "ihqwcrb4cv8a8dqg056pqjye"], "punycode (RFC 3492 §7.1)")
check_eq([enc.idna_encode("Bücher.Example"), enc.idna_decode("xn--bcher-kva.example")], ["xn--bcher-kva.example", "bücher.example"], "IDNA")
check_eq(enc.decode_charset(enc.encode_charset("café €", "windows-1252"), "cp1252"), "café €", "windows-1252")
check_eq(enc.decode_charset(enc.encode_charset("a😀é", "utf-16"), "utf-16"), "a😀é", "UTF-16 (paires de substitution)")
check_eq(enc.to_text(enc.hex_decode("41ff42")), "A\u{FFFD}B", "UTF-8 réparé")

# ---------------------------------------------------------------- ipaddress
check_eq(ip.ip_address("2001:0db8:0000:0000:0000:0000:0000:0001").str(), "2001:db8::1", "IPv6 canonique (RFC 5952)")
check_eq([ip.ip_address("1:0:0:2:0:0:0:3").str(), ip.ip_address("::ffff:1.2.3.4").str()], ["1:0:0:2::3", "::ffff:1.2.3.4"], "IPv6 : plus longue suite, IPv4 mappée")
n := ip.ip_network("192.168.1.0/24")
check_eq([n.contains("192.168.1.42"), n.broadcast().str(), n.num_addresses(), n.netmask().str()], [true, "192.168.1.255", 256, "255.255.255.0"], "réseau IPv4")
check_eq(strs(n.subnets(2)), ["192.168.1.0/26", "192.168.1.64/26", "192.168.1.128/26", "192.168.1.192/26"], "sous-réseaux")
check_eq(strs(ip.collapse(["10.0.0.0/25", "10.0.0.128/25", "10.0.1.0/24", "11.0.0.1"])), ["10.0.0.0/23", "11.0.0.1/32"], "collapse")
check_eq(strs(ip.summarize_range("192.0.2.0", "192.0.2.130")), ["192.0.2.0/25", "192.0.2.128/31", "192.0.2.130/32"], "summarize_range")
check_eq(len(ip.ip_network("10.0.0.0/8").address_exclude("10.1.1.0/24")), 16, "address_exclude")
check_eq([ip.ip_address("8.8.8.8").is_global(), ip.ip_address("10.1.1.1").is_private(), ip.ip_address("169.254.169.254").is_link_local(), ip.ip_address("2001:db8::1").is_documentation()], [true, true, true, true], "classification")
check_eq(ip.ip_address("1.2.3.4").reverse_pointer(), "4.3.2.1.in-addr.arpa", "reverse_pointer")
check_eq(error_of(() => ip.ip_network("10.0.0.1/8")), "ValueError", "bits d'hôte refusés en mode strict")
check_eq([ip.is_ipv4("01.2.3.4"), ip.is_ipv6("1::2::3"), ip.netmask_to_prefix("255.255.240.0")], [false, false, 20], "validation")

# ---------------------------------------------------------------- uri, url
base := "http://a/b/c/d;p?q"
cases := [["g:h", "g:h"], ["g", "http://a/b/c/g"], ["./g", "http://a/b/c/g"], ["g/", "http://a/b/c/g/"], ["/g", "http://a/g"], ["//g", "http://g"], ["?y", "http://a/b/c/d;p?y"], ["g?y", "http://a/b/c/g?y"], ["#s", "http://a/b/c/d;p?q#s"], ["g#s", "http://a/b/c/g#s"], [";x", "http://a/b/c/;x"], ["", "http://a/b/c/d;p?q"], [".", "http://a/b/c/"], ["..", "http://a/b/"], ["../g", "http://a/b/g"], ["../..", "http://a/"], ["../../../g", "http://a/g"], ["/./g", "http://a/g"], ["g.", "http://a/b/c/g."], ["..g", "http://a/b/c/..g"], ["./../g", "http://a/b/g"], ["g/./h", "http://a/b/c/g/h"], ["g/../h", "http://a/b/c/h"], ["g;x=1/../y", "http://a/b/c/y"], ["g?y/../x", "http://a/b/c/g?y/../x"], ["g#s/../x", "http://a/b/c/g#s/../x"], ["http:g", "http:g"]]
bad := 0
for cs in cases:
    if uri.resolve(base, cs[0]) != cs[1]:
        bad += 1
        append(notes, "uri.resolve " + cs[0] + " -> " + uri.resolve(base, cs[0]))
check_eq(bad, 0, "RFC 3986 §5.4 : résolutions de référence")
vars := {"var": "value", "hello": "Hello World!", "path": "/foo/bar", "list": ["red", "green", "blue"], "keys": {"semi": ";", "dot": ".", "comma": ","}, "x": "1024", "y": "768", "empty": ""}
tpl := [["{var}", "value"], ["{hello}", "Hello%20World%21"], ["{+path}/here", "/foo/bar/here"], ["{;x,y,empty}", ";x=1024;y=768;empty"], ["{?x,y,empty}", "?x=1024&y=768&empty="], ["{var:3}", "val"], ["{/list*}", "/red/green/blue"], ["{keys*}", "semi=%3B,dot=.,comma=%2C"], ["{?keys*}", "?semi=%3B&dot=.&comma=%2C"]]
bad = 0
for t in tpl:
    if uri.expand(t[0], vars) != t[1]:
        bad += 1
        append(notes, "uri.expand " + t[0] + " -> " + uri.expand(t[0], vars))
check_eq(bad, 0, "RFC 6570 : gabarits")
check_eq(uri.normalize("HTTP://www.Example.COM:80/a/./b/../c/%7euser").str(), "http://www.example.com/a/c/~user", "normalisation (RFC 3986 §6)")
check_eq([uri.parse_data("data:text/plain;charset=utf-8;base64,QWxleA==").data, uri.parse_mailto("mailto:a@b.org?subject=Bonjour%20!").subject(), uri.parse_urn("urn:ISBN:0451450523").nid], ["Alex", "Bonjour !", "isbn"], "data:, mailto:, urn:")
u := url.parse("https://Bücher.example/a b/c?x=1&y=é#top")
check_eq([u.host, u.effective_port(), u.path, u.query, u.param("y"), u.origin()], ["xn--bcher-kva.example", 443, "/a%20b/c", "x=1&y=%C3%A9", "é", "https://xn--bcher-kva.example"], "url : analyse")
check_eq(u.join("../d?z=2").str(), "https://xn--bcher-kva.example/d?z=2", "url : join")
check_eq([url.urlencode({"q": "chat noir", "n": [1, 2]}), url.parse_qs("a=1&a=2")], ["q=chat+noir&n=1&n=2", {"a": ["1", "2"]}], "url : requêtes")
check_eq(url.parse("http://user:p%40ss@[::1]:8080/./x/../y").password, "p@ss", "url : identifiants")
check_eq(error_of(() => url.parse("http://ex ample.com/")), "UrlError", "url : hôte invalide")

# ---------------------------------------------------------------- en-têtes, cookies, compression, multipart, mime
h := hh.Headers()
h.add("Set-Cookie", "a=1")
h.add("set-cookie", "b=2")
check_eq([h.get_all("SET-COOKIE"), h.get("set-cookie")], [["a=1", "b=2"], "a=1"], "en-têtes multiples")
check_eq(hh.parse_value("attachment; filename=\"a.txt\"; filename*=UTF-8''%C3%A9t%C3%A9.txt"), ("attachment", {"filename": "été.txt"}), "RFC 8187 : filename* prioritaire")
check_eq(hh.negotiate("text/*;q=0.5, application/json", ["text/html", "application/json"]), "application/json", "négociation")
check_eq([hh.format_http_date(784111777), hh.parse_http_date("Sunday, 06-Nov-94 08:49:37 GMT"), hh.parse_http_date("Sun Nov  6 08:49:37 1994")], ["Sun, 06 Nov 1994 08:49:37 GMT", 784111777, 784111777], "dates HTTP")
check_eq([hh.parse_range("bytes=0-99,200-,-50", 1000), hh.parse_range("bytes=2000-", 1000)], [[[0, 99], [200, 999], [950, 999]], null], "plages")
check_eq(hh.parse_basic(hh.basic_auth("Aladdin", "open sesame")), ("Aladdin", "open sesame"), "Basic")
check_eq(error_of(() => h.add("X", "a\r\nInjecté: 1")), "HttpError", "injection d'en-tête")
jar := ck.CookieJar()
jar.set_from_header("sid=abc; Path=/; HttpOnly; Max-Age=3600", "https://exemple.org/connexion")
jar.set_from_header("pref=1; Domain=.exemple.org; Path=/compte", "https://www.exemple.org/")
check_eq([jar.set_from_header("x=1; Domain=org", "https://exemple.org/"), jar.set_from_header("s=1; Secure", "http://exemple.org/")], [false, false], "cookies : suffixe public, Secure en clair")
check_eq(jar.header_for("https://exemple.org/compte/x"), "pref=1; sid=abc", "cookies : ordre et correspondance")
check_eq(ck.Cookie("theme", "sombre", null, "/", null, 86400, false, false, "Lax").set_cookie_header(), "theme=sombre; Max-Age=86400; Path=/; SameSite=Lax", "Set-Cookie")
z := nz.encode("bonjour " * 100, "gzip")
check_eq([nz.detect(z), nz.decode(z, "gzip") == "bonjour " * 100, nz.choose_encoding("br;q=1, gzip;q=0.8, *;q=0"), nz.crc32("123456789")], ["gzip", true, "gzip", 3421780262], "compression")
body, ctype := mp.encode({"titre": "Été"}, {"f": mp.File("x.bin", nu.from_bytes([0, 13, 10, 255]))})
form := mp.parse(body, ctype)
check_eq([form.field("titre"), form.file("f").data == nu.from_bytes([0, 13, 10, 255]), mp.safe_filename("../../etc/passwd")], ["Été", true, "passwd"], "multipart")
e := mime.encode_header("Café ☕ et une phrase assez longue pour obliger à couper le mot encodé en plusieurs morceaux")
check_eq(mime.decode_header(e), "Café ☕ et une phrase assez longue pour obliger à couper le mot encodé en plusieurs morceaux", "RFC 2047 : aller-retour")
check_eq(mime.decode_header("(=?ISO-8859-1?Q?a?= =?ISO-8859-1?Q?b?=)"), "(ab)", "RFC 2047 : mots adjacents")
check_eq(mime.guess_type("photo.JPG"), "image/jpeg", "type MIME")

# ---------------------------------------------------------------- XML, HTML
doc := xml.parse("<?xml version=\"1.0\"?><!DOCTYPE c [<!ENTITY moi \"Ada &amp; Co\">]><c xmlns=\"urn:c\"><p id=\"1\"><n>Ada</n></p><p id=\"2\"><n>&moi; &#233;</n></p></c>")
check_eq([doc.root.ns, doc.find("p[@id='2']/n").text(), len(doc.find_all("{urn:c}p")), doc.find("p[last()]").get("id")], ["urn:c", "Ada & Co é", 2, "2"], "XML : espaces de noms, entités, chemins")
check_eq(error_of(() => xml.parse("<!DOCTYPE a [<!ENTITY e SYSTEM \"file:///etc/passwd\">]><a>&e;</a>")), "XmlError", "XML : pas de XXE")
lol := "<!DOCTYPE l [<!ENTITY a \"aaaaaaaaaa\"><!ENTITY b \"&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;\"><!ENTITY c \"&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;\"><!ENTITY d \"&c;&c;&c;&c;&c;&c;&c;&c;&c;&c;\"><!ENTITY e \"&d;&d;&d;&d;&d;&d;&d;&d;&d;&d;\"><!ENTITY f \"&e;&e;&e;&e;&e;&e;&e;&e;&e;&e;\"><!ENTITY g \"&f;&f;&f;&f;&f;&f;&f;&f;&f;&f;\">]><l>&g;</l>"
check_eq(error_of(() => xml.parse(lol)), "XmlError", "XML : pas de « milliard de rires »")
check_eq([xp.is_well_formed("<a><b></a>"), xp.is_well_formed("<a x='1'/>")], [false, true], "XML : bien formé")
r := xml.element("commande", {"id": 42}, [xml.element("article", null, ["café & thé"])])
check_eq(xml.to_string(r), "<commande id=\"42\"><article>café &amp; thé</article></commande>", "XML : écriture")
check_eq(xml.to_dict(xml.fromstring("<a x=\"1\"><b>2</b><b>3</b></a>")), {"a": {"@x": "1", "b": ["2", "3"]}}, "XML : to_dict")
check_eq(xml.canonicalize("<a z=\"1\" b='2' xmlns=\"urn:x\"><c/></a>"), "<a xmlns=\"urn:x\" b=\"2\" z=\"1\"><c></c></a>", "XML : forme canonique")
check_eq(html.unescape("&eacute;t&eacute; &amp; &#233;&#x263a; &copy &notit; &#128;"), "été & é☺ © ¬it; €", "HTML : entités (HTML5)")
hd := html.parse("<ul><li>un<li>deux</ul><p>a<p>b<table><tr><td>1<td>2</table><script>if (a<b) x='</p>'</script>")
check_eq(html.to_html(hd), "<ul><li>un</li><li>deux</li></ul><p>a</p><p>b</p><table><tr><td>1</td><td>2</td></tr></table><script>if (a<b) x='</p>'</script>", "HTML : fermetures implicites, script")
check_eq([len(html.select(hd, "li")), len(html.select(hd, "td:not(:first-child)")), len(html.select(hd, "p + p"))], [2, 1, 1], "HTML : sélecteurs CSS")
check_eq(html.sanitize("<p onclick=x>Bonjour <script>alert(1)</script><a href=' JaVa\tScRiPt:x'>ici</a><img src=x onerror=y></p>"), "<p>Bonjour <a>ici</a><img src=\"x\"></p>", "HTML : nettoyage")
check_eq(html.links("<base href='/d/'><a href='x'>1</a><a href='javascript:y'>2</a>", "https://s.fr/a/b"), ["https://s.fr/d/x"], "HTML : liens absolus")

# ---------------------------------------------------------------- XML-RPC, protobuf
xr := rpc.loads(rpc.dumps([1, "a<b", 0.1 + 0.2, true, null, [1], {"k": "v"}, 4294967296], "m"))
check_eq([xr[1], xr[0][0], xr[0][1], xr[0][2], xr[0][4], xr[0][7]], ["m", 1, "a<b", 0.1 + 0.2, null, 4294967296], "XML-RPC : aller-retour")
s2 := pb.parse_proto("syntax = \"proto3\"; package d; message M { string t = 1; int32 n = 2; repeated sint64 z = 3; map<string, int32> m = 4; }")
o := s2.encode("M", {"t": "a", "n": -1, "z": [-2, 2], "m": {"k": 7}})
check_eq(enc.hex_encode(o), "0a016110ffffffffffffffffff011a0203042205" + "0a016b1007", "protobuf : octets (varint négatif, zigzag, map)")
check_eq(s2.decode("M", o), {"t": "a", "n": -1, "z": [-2, 2], "m": {"k": 7}}, "protobuf : décodage")

# ---------------------------------------------------------------- sécurité, nouvelles tentatives, délais
hp := sec.hash_password("correct horse", 1000)
check_eq([sec.verify_password("correct horse", hp), sec.verify_password("faux", hp), sec.needs_rehash(hp)], [true, false, true], "mots de passe PBKDF2")
check_eq(enc.hex_encode(sec.pbkdf2("password", "salt", 2, 20, "sha1")), "ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957", "PBKDF2 (RFC 6070)")
check_eq(sec.hmac_sign("key", "The quick brown fox jumps over the lazy dog"), "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8", "HMAC-SHA256")
tok := sec.sign_value("u=42", "k", 1000)
check_eq([sec.unsign_value(tok, "k", 60, 1010), error_of(() => sec.unsign_value(tok, "k", 5, 1010)), error_of(() => sec.unsign_value(tok + "x", "k"))], ["u=42", "SecurityError", "SecurityError"], "valeurs signées")
check_eq([sec.is_safe_url("http://169.254.169.254/"), sec.is_safe_url("http://[::ffff:10.0.0.1]/"), sec.is_safe_url("http://8.8.8.8/")], [false, false, true], "SSRF")
check_eq([sec.is_safe_redirect("/compte"), sec.is_safe_redirect("//evil.com")], [true, false], "redirections ouvertes")
clock := [0.0]
rl := sec.RateLimiter(1, 2, 100, () => clock[0])
check_eq([rl.allow("a"), rl.allow("a"), rl.allow("a")], [true, true, false], "seau à jetons")
cnt := [0]
func flaky():
    cnt[0] += 1
    if cnt[0] < 3:
        raise("NetworkError", "x [ECONNRESET]")
    return "ok"
waits := []
check_eq(rt.retry(flaky, rt.RetryPolicy(5, 0.5, 10.0, 2.0, 0), null, (d) => waits.append(d)), "ok", "retry")
check_eq(waits, [0.5, 1.0], "retry : attente exponentielle")
check_eq(error_of(() => rt.retry(() => raise("HttpError", "x"), rt.RetryPolicy(3, 0.0))), "HttpError", "retry : erreur non passagère")
cb := rt.CircuitBreaker(2, 100.0, null, () => clock[0])
for i in 0..2:
    error_of(() => cb.call(() => raise("NetworkError", "panne")))
check_eq([cb.current_state(), error_of(() => cb.call(() => 1))], ["open", "RetryError"], "disjoncteur")
clock[0] = 200.0
check_eq([cb.current_state(), cb.call(() => 1), cb.current_state()], ["half_open", 1, "closed"], "disjoncteur : demi-ouvert puis fermé")
check_eq([to.smallest(null, 3), to.smallest(2, 3), to.timeouts(5).read], [3, 2, 5], "délais")

# ---------------------------------------------------------------- pare-feu, routage
fw := fwm.Firewall("deny")
fw.add("allow tcp from 10.0.0.0/8 to any port 22,80,8000-8080")
fw.add("deny tcp from 192.168.1.66 to any")
fw.add("allow in tcp from 192.168.1.0/24")
check_eq([fw.allows("tcp", "10.1.2.3", 5000, "10.0.0.1", 80), fw.allows("tcp", "10.1.2.3", 5000, "10.0.0.1", 443), fw.allows("tcp", "192.168.1.66", 1, "x", 80), fw.allows("tcp", "192.168.1.7", 1, "x", 9)], [true, false, false, true], "pare-feu : règles")
fw.block("10.9.9.9", 100)
check_eq(fw.allows("tcp", "10.9.9.9", 1, "10.0.0.1", 80), false, "pare-feu : blocage")
check_eq(fwm.parse_rule("reject out udp to 203.0.113.0/24 port 53").str(), "reject out udp from any to 203.0.113.0/24 port 53", "pare-feu : syntaxe")
t := routing.RoutingTable()
t.add("0.0.0.0/0", "192.168.1.1", "eth0", 100)
t.add("10.0.0.0/8", "10.0.0.1", "vpn0", 10)
t.add("10.1.0.0/16", null, "lan1", 5)
check_eq([t.next_hop("10.1.2.3"), t.next_hop("10.9.9.9"), t.next_hop("8.8.8.8"), t.lookup("10.1.2.3").iface], ["10.1.2.3", "10.0.0.1", "192.168.1.1", "lan1"], "routage : préfixe le plus long")

print(f"network (modules purs) : {stats[0]} vérifications OK, {stats[1]} échec(s)")
for x in notes:
    print("  ÉCHEC " + x)
if stats[1] > 0:
    raise("TestError", "test_network_utils : échecs")
