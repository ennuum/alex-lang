# Tests : network.ip_address, network.network_errors, network.https (serveur HTTPS local si openssl est présent).
from core use len, type
from collections use append
use check as t
use os
use string
use process as proc
use network.ip_address as ipa
use network.network_errors as nerr
use network.https as https
use network.tcp as tcp

# ip_address
e := ipa.parse_endpoint("[2001:db8::1]:8443")
t.check(e.host == "2001:db8::1" and e.port == 8443 and e.version == 6, "endpoint v6")
t.eq(str(e), "[2001:db8::1]:8443", "format v6")
e4 := ipa.parse_endpoint("10.0.0.5:80")
t.check(e4.is_private() and str(e4) == "10.0.0.5:80", "endpoint v4")
t.eq(str(ipa.parse_endpoint("::1", 53)), "[::1]:53", "défaut de port")
t.eq(ipa.parse_endpoint("[fe80::1%eth0]:22").scope, "eth0", "zone")
t.raises(() => ipa.parse_endpoint("1.2.3.4:99999"), "ValueError", "port hors limites")
t.raises(() => ipa.parse_endpoint("1.2.3.4"), "ValueError", "port absent")
t.check(ipa.Endpoint("127.0.0.1", 8080) == "127.0.0.1:8080", "égalité str")
t.check(ipa.Endpoint("127.0.0.1", 8080) == ipa.parse_endpoint("127.0.0.1:8080"), "égalité")
t.eq(ipa.anonymize("192.168.17.42"), "192.168.17.0", "anonymize v4")
t.eq(ipa.anonymize("2001:db8:1234:5678::9"), "2001:db8:1234::", "anonymize v6")
t.eq(ipa.from_bytes([127, 0, 0, 1]), "127.0.0.1", "from_bytes v4")
t.eq(ipa.from_bytes([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]), "::1", "from_bytes v6")
t.eq(len(ipa.to_bytes("::1")), 16, "to_bytes")
t.eq(ipa.reverse_name("8.8.4.4"), "4.4.8.8.in-addr.arpa", "reverse_name")
t.eq(ipa.link_local_from_mac("00:1a:2b:3c:4d:5e"), "fe80::21a:2bff:fe3c:4d5e", "EUI-64")
t.eq(ipa.slaac_address("2001:db8:1:2::/64", "00:1a:2b:3c:4d:5e"), "2001:db8:1:2:21a:2bff:fe3c:4d5e", "SLAAC")
t.raises(() => ipa.link_local_from_mac("00:11"), "ValueError", "MAC invalide")
loc := ipa.resolve_endpoints("localhost", 80)
t.check(len(loc) >= 1 and loc[0].is_loopback(), "resolve_endpoints")
t.check(type(ipa.local_addresses(0, true)) == "list", "local_addresses")

# network_errors
f := null
try:
    tcp.connect("127.0.0.1", 1, 2.0)
catch err:
    f = nerr.classify(err)
t.check(f != null and f["network"], "classify réseau")
t.eq(f["errno"], "ECONNREFUSED", "errno")
t.check(f["transient"], "passagère")
t.check(string.contains(f["explanation"], "Connexion refusée"), "explication")
h := nerr.http_status_info(503)
t.check(h["transient"] and h["category"] == "serveur" and h["type"] == "HttpError", "statut 503")
t.check(not nerr.http_status_info(404)["transient"], "404 non passagère")
t.eq(nerr.retry_after_seconds("120"), 120, "retry_after")
t.eq(nerr.retry_after_seconds("demain"), null, "retry_after illisible")
r := nerr.attempt(() => tcp.connect("127.0.0.1", 1, 1.0))
t.check(not r["ok"] and r["error"]["kind"] == "NetworkError", "attempt échec")
t.eq(nerr.attempt(() => 3)["value"], 3, "attempt succès")

# https
t.raises(() => https.Client("http://exemple.org/"), "SecurityError", "base en clair refusée")
st := https.HstsStore()
t.check(st.observe("exemple.org", "max-age=31536000; includeSubDomains"), "observe")
t.check(st.is_known("api.exemple.org"), "sous-domaine HSTS")
t.check(not st.is_known("autre.org"), "hôte inconnu")
t.eq(https.upgrade("http://api.exemple.org/x?y=1", st), "https://api.exemple.org/x?y=1", "upgrade")
t.eq(https.upgrade("http://autre.org/", st), "http://autre.org/", "pas d'upgrade")
st.add("exemple.org", 0)
t.check(not st.is_known("exemple.org"), "max-age=0 retire")

alex := os.executable()
gen := null
tmp := "/tmp/alex_https_" + str(os.pid())
os.mkdir_all(tmp)
cert := tmp + "/cert.pem"
key := tmp + "/key.pem"
has_openssl := false
try:
    gen = proc.run("openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert, "-days", "2", "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1"], null, 60.0)
    has_openssl = gen.code == 0
catch err2:
    has_openssl = false
if has_openssl and https.supported():
    child := proc.Command(alex).args(["run", "tests/network/https_alex_server.al", cert, key]).stdout("pipe").stderr("pipe").spawn()
    line := child.read_line("stdout", 20.0)
    port := string.trim(line)
    base := "https://127.0.0.1:" + port + "/"
    c := https.Client(base, null, 10.0, cert)
    rr := c.get("bonjour", {"nom": "Ana"})
    t.eq(rr.text(), "Bonjour Ana en TLS !\n", "GET https local")
    t.check(type(https.security_headers(rr)["hsts"]) == "bool", "security_headers")
    info := https.tls_info("127.0.0.1", _port_int(port), 10.0, true, cert)
    t.check(info["verified"] and string.starts_with(info["version"], "TLS"), "tls_info " + str(info))
    t.raises(() => https.Client(base, null, 10.0).get("bonjour"), "TlsError", "certificat inconnu refusé")
    c.get("stop")
    child.wait(15.0)
    child.close()
else:
    print("(openssl absent : partie HTTPS locale ignorée)")
for n in os.list_dir(tmp):
    os.remove(tmp + "/" + n)
os.rmdir(tmp)

func _port_int(p):
    n := 0
    for ch in p:
        n = n * 10 + (string.ord(ch) - 48)
    return n

t.summary("test_network2")
