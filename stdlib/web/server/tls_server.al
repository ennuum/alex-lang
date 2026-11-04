# ALEX STANDARD LIBRARY — web.server.tls_server
#
# HTTPS côté serveur : configuration TLS (certificat et clé PEM, ALPN « http/1.1 »), poignée de main sur chaque
# connexion acceptée (avec délai : un client muet ne bloque pas le serveur au-delà), en-tête HSTS, et certificat
# auto-signé de développement (outil openssl requis).
#
#   use web.server.tls_server as ts
#   tls := ts.TlsServerConfig("/etc/ssl/site.pem", "/etc/ssl/site.key")
#   ts.supported()                         # OpenSSL disponible ?
#   ts.hsts(31536000, true)                # « max-age=31536000; includeSubDomains »
#   dev := ts.development_certificate("/tmp/alex-dev")   # TlsServerConfig avec un certificat auto-signé localhost
#
# TLS repose sur network.tls (OpenSSL chargé à l'exécution). Erreurs : ServerConfigError (fichier absent, TLS
# indisponible), TlsError (poignée de main refusée : la connexion est simplement fermée par le serveur).

from core use len, type
use os as _os
use network.tls as _tls
use network.certificates as _certs
use web.server.server_errors as _err

class TlsServerConfig:
    func init(cert_file, key_file, alpn=null, handshake_timeout=10.0):
        if cert_file == null or key_file == null:
            _err.config_error("TlsServerConfig", "cert_file et key_file sont requis")
        for f in [cert_file, key_file]:
            if not _os.exists(f):
                _err.config_error("TlsServerConfig", "fichier introuvable « " + f + " »")
        self.cert_file = cert_file
        self.key_file = key_file
        self.alpn = alpn if alpn != null else ["http/1.1"]
        self.handshake_timeout = handshake_timeout

    # Poignée de main serveur sur un socket accepté ; renvoie le TlsSocket (TlsError en cas d'échec).
    func wrap(sock, timeout=null):
        return _tls.wrap_server(sock, self.cert_file, self.key_file, self.alpn, timeout if timeout != null else self.handshake_timeout)

func supported():
    return _tls.supported()

func why():
    return _tls.why()

# Vérifie que TLS est utilisable ; ServerConfigError sinon.
func require():
    if not _tls.supported():
        _err.config_error("tls_server", "TLS indisponible : " + str(_tls.why()))

# Valeur de Strict-Transport-Security.
func hsts(max_age=31536000, include_subdomains=false, preload=false):
    out := "max-age=" + str(max_age)
    if include_subdomains:
        out = out + "; includeSubDomains"
    if preload:
        out = out + "; preload"
    return out

# Certificat auto-signé (localhost, 127.0.0.1, ::1) créé dans directory s'il n'existe pas ; TlsServerConfig prête.
func development_certificate(directory, names=null):
    if not _os.exists(directory):
        _os.mkdir_all(directory)
    cert := _os.join(directory, "localhost.pem")
    key := _os.join(directory, "localhost.key")
    if not _os.exists(cert) or not _os.exists(key):
        _certs.generate_self_signed(cert, key, "localhost", names if names != null else ["localhost", "127.0.0.1", "::1"])
    return TlsServerConfig(cert, key)
