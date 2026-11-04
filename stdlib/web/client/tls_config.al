# ALEX STANDARD LIBRARY — web.client.tls_config
#
# Configuration TLS des connexions HTTPS du client. Par défaut tout est vérifié : chaîne de certificats du serveur
# contre les autorités du système (ou ca_file), nom d'hôte, TLS 1.2 minimum (network.tls, OpenSSL chargé à
# l'exécution).
#
#   use web.client.tls_config as tc
#   tc.TlsConfig()                                    # vérification complète (défaut)
#   tc.TlsConfig(true, "/etc/ssl/interne-ca.pem")     # autorité privée
#   tc.TlsConfig(true, null, "client.pem", "client.key")   # authentification par certificat client (mTLS)
#   tc.insecure()                                     # AUCUNE vérification : tests uniquement
#   tc.supported()                                    # false si OpenSSL est absent (why() dit pourquoi)
#
# Erreurs : ClientError (fichier absent, combinaison invalide).

from core use len, type
use os as _os
use network.tls as _tls
use web.client.client_errors as _err

class TlsConfig:
    # verify : vérifier certificat et nom ; ca_file : autorités supplémentaires (PEM) ; cert_file / key_file :
    # certificat client ; alpn : protocoles proposés ; server_name : nom SNI imposé (sinon l'hôte de l'URL).
    func init(verify=true, ca_file=null, cert_file=null, key_file=null, alpn=null, server_name=null):
        self.verify = verify
        self.ca_file = ca_file
        self.cert_file = cert_file
        self.key_file = key_file
        self.alpn = alpn if alpn != null else ["http/1.1"]
        self.server_name = server_name
        if (cert_file == null) != (key_file == null):
            _err.client_error("TlsConfig", "cert_file et key_file vont ensemble")
        for f in [ca_file, cert_file, key_file]:
            if f != null and not _os.exists(f):
                _err.client_error("TlsConfig", "fichier introuvable « " + f + " »")

    func copy():
        return TlsConfig(self.verify, self.ca_file, self.cert_file, self.key_file, self.alpn, self.server_name)

    # Nom à présenter (SNI) et à vérifier pour host.
    func name_for(host):
        if self.server_name != null:
            return self.server_name
        return host

func default():
    return TlsConfig()

# Sans aucune vérification (certificat auto-signé de test) : ne jamais utiliser en production.
func insecure():
    return TlsConfig(false)

func supported():
    return _tls.supported()

func why():
    return _tls.why()
