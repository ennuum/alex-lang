# Réseau : `stdlib/network` (53 modules)

```
use network.http_client as hc
use network.http_server as hs

c := hc.Client("https://api.exemple.org/v1/", {"Accept": "application/json"}, 10.0)
for a in c.get("articles", {"page": 2}).raise_for_status().json():
    print(a["titre"])

app := hs.App()
app.get("/salut/{nom}", (req) => {"salut": req.params["nom"]})
hs.Server(app, "127.0.0.1", 8080).serve_forever()
```

Le paquet est organisé en couches : les modules du haut s'appuient sur ceux du bas, jamais l'inverse.

| Couche | Modules |
|---|---|
| Fondations | `core`, `errors`, `config`, `constants`, `utils`, `encoding`, `timeout`, `retry` |
| Transport | `socket`, `tcp`, `udp`, `dns`, `ipaddress`, `tls`, `certificates`, `security` |
| Web | `url`, `uri`, `http`, `http_client`, `http_server`, `http_headers`, `http_cookies`, `http_multipart`, `compression`, `connection_pool`, `proxy`, `websocket`, `webbrowser`, `async_client` |
| Courrier, fichiers | `mime`, `email`, `email_attachments`, `smtp`, `imap`, `pop3`, `ftp` |
| Documents, RPC | `xml`, `xml_parser`, `xml_writer`, `html`, `xmlrpc`, `xmlrpc_client`, `xmlrpc_server`, `protobuf`, `grpc`, `grpc_client`, `grpc_server` |
| Système | `network_interface`, `routing`, `multicast`, `firewall`, `network_monitor` |

## Fondations

| Module | Rôle |
|---|---|
| `network.core` | `supported()`, `features()` (tcp, udp, ipv6, tls, version d'OpenSSL), `open_connection(hôte, port, secure, délai, verify, ca_file, alpn...)` → `tcp.Connection` en clair ou TLS, `start_tls(conn, hôte)` (STARTTLS : refuse les octets reçus en clair avant la négociation), `accept_tls` (côté serveur), `is_secure`, `tls_info`, `Endpoint` / `endpoint("tls://hôte:port")`, `open_counts()` |
| `network.errors` | noms des types d'erreur et leur hiérarchie (`NetworkError` ⊃ `TimeoutError`, `DnsError`, `TlsError` ⊃ `CertificateError`, `ProxyError`, `PoolError`, `FirewallError`, `ProtocolError` ⊃ `HttpError`, `SmtpError`, `ImapError`...), `is_a(e, type)`, `lineage`, `errno_of(e)` (« ECONNRESET »), `is_transient(e)`, `reply_code(e)` (code 550...), `describe`, `wrap` |
| `network.config` | `Config` (délais, User-Agent, TLS, mandataires, NO_PROXY, redirections, tailles, réserve, nouvelles tentatives) avec contrôle des types ; `defaults()` (lu dans l'environnement : `HTTP(S)_PROXY`, `ALL_PROXY`, `NO_PROXY`, `SSL_CERT_FILE`, `ALEX_NET_TIMEOUT`...), `from_env`, `load` / `save` (JSON), `matches_no_proxy` (noms, suffixes, CIDR, ports) |
| `network.constants` | familles, ports bien connus (`PORT_HTTPS`...), `default_port(schéma)`, `is_secure_scheme`, statuts HTTP (`STATUS_NOT_FOUND`...), `status_reason`, `status_class`, `is_redirect_status`, `is_retryable_status`, `response_has_body`, limites par défaut |
| `network.utils` | octets bruts (`raw`, `byte_len`, `byte_slice`, `byte_find`, `chunks`), entiers en ordre réseau (`pack_u16/u32/u64`, `unpack_*`, petit-boutiste en option), `float_repr` (écriture la plus courte, comme `repr` de Python), `hexdump`, `human_bytes`, `human_rate`, `split_host_port` / `join_host_port`, `is_valid_hostname`, `free_port`, `is_port_open`, `wait_for_port`, `local_ip`, `fqdn`, `to_crlf`, `check_single_line` (anti-injection) |
| `network.encoding` | base64 (standard / URL, avec ou sans « = », lignes de 76), base32, hexadécimal, pourcentage (RFC 3986), quoted-printable (RFC 2045 et « Q » de RFC 2047), Punycode (RFC 3492), IDNA (`idna_encode` / `idna_decode`), jeux de caractères (`decode_charset` / `encode_charset` : UTF-8, US-ASCII, ISO-8859-1/15, Windows-1252, UTF-16 avec BOM ; `errors="replace"`), `to_text` (UTF-8 réparé) |
| `network.timeout` | `Deadline(secondes)` (échéance partagée : `remaining()`, `check()`, `expired()`), `Timeouts(connect, read, write, total, pool)`, `normalize`, `smallest`, `with_timeout(tâche, s)` (async), `run_within` |
| `network.retry` | `RetryPolicy(max_attempts, base_delay, max_delay, multiplier, jitter, retry_on, retry_if, statuses, max_total)`, `retry(fn, politique, on_retry)` (relance la dernière erreur ; par défaut seules les erreurs passagères sont retentées), `retry_response` (statuts 429/503... et `Retry-After`), `retry_async`, `schedule`, `parse_retry_after`, `CircuitBreaker(seuil, délai)` (fermé → ouvert → demi-ouvert) |

## Transport

| Module | Rôle |
|---|---|
| `network.socket` | sockets BSD TCP/UDP, IPv4/IPv6/Unix : `Socket` (`connect`, `bind`, `listen`, `accept`, `send`, `recv`, `try_recv`, `send_to`, `recv_from`, `set_option`, `shutdown`, `close`), `wait(sockets, "read"/"write", délai)`, `open_count()` ; options `reuse_address`, `reuse_port`, `no_delay`, `broadcast`, `keep_alive`, tampons, `ttl`, `multicast_ttl`, `multicast_loop` |
| `network.dns` | `lookup(hôte, port, famille, type)` → `Address`, `resolve`, `resolve_one`, `reverse`, `is_ipv4`, `is_ipv6`, `is_ip` |
| `network.tcp` | `connect` → `Connection` (`read`, `read_line`, `read_until`, `read_exact`, `read_all`, `write`...), `listen` → `Listener`, `serve` |
| `network.udp` | `bind` / `open` → `Endpoint` (`send_to`, `receive`, `try_receive`, `set_broadcast`), `send`, `Datagram` |
| `network.ipaddress` | `IPv4Address` / `IPv6Address` (forme canonique RFC 5952, `exploded`, `packed`, `to_int`, arithmétique, comparaisons, `is_private`, `is_loopback`, `is_link_local`, `is_multicast`, `is_global`, `is_documentation`, `is_shared`..., `ipv4_mapped`, `reverse_pointer`), `IPNetwork` (`contains` / `in`, `netmask`, `hostmask`, `broadcast`, `num_addresses`, `hosts`, `subnets`, `supernet`, `overlaps`, `address_exclude`), `IPInterface`, `ip_address`, `ip_network`, `collapse`, `summarize_range`, `sort_addresses`, `prefix_to_netmask`, `netmask_to_prefix` — calculs exacts sur 128 bits |
| `network.tls` | TLS 1.2/1.3 (OpenSSL chargé à l'exécution, ou à défaut TLS 1.3 écrit en ALEX : `network.tls13`) : `connect`, `listen`, `serve`, `wrap_client`, `wrap_server`, `TlsSocket` (`version`, `cipher`, `alpn`, `peer_subject`...), `backend()` (« openssl » / « alex », variable `ALEX_TLS`) |
| `network.tls13` | TLS 1.3 (RFC 8446) en ALEX, sans OpenSSL (exécutables natifs) : serveur (`ServerContext`, `context`, `wrap_server` ; suites AES-GCM et ChaCha20-Poly1305, groupes x25519 / P-256 / P-384 avec HelloRetryRequest, ECDSA et RSA-PSS, ALPN, SNI, KeyUpdate) et client (`wrap_client`, chaîne vérifiée par `crypto.x509`) ; `TlsSocket13` a l'interface de `TlsSocket` ; calcul lourd dans le runtime (`crypto.accel`) |
| `network.certificates` | PEM (`pem_decode`, `pem_encode`), ASN.1 DER (`parse_asn1`, `Node`), X.509 : `Certificate` (sujet, émetteur, série, validité, clé — algorithme, courbe, taille —, SAN DNS / IP / courriel / URI, `is_ca`, `key_usage`, `extended_key_usage`, OCSP, `fingerprint("sha256")`, `matches_hostname` selon RFC 6125, `days_remaining`, `summary`), `load(chemin)`, `parse_pem`, `fetch(hôte, port)` (certificat présenté par un serveur), `check(hôte)` (diagnostic), `generate_self_signed(cert, clé, cn, noms)` (outil `openssl`) |
| `network.security` | aléa (`random_bytes`, `random_token`, `random_hex`, `random_below`, `random_code`), `constant_time_equals`, `digest`, `hmac`, `hmac_sign` / `hmac_verify`, `pbkdf2` (libcrypto si présent, sinon `crypto`), valeurs signées horodatées (`sign_value` / `unsign_value`), jetons CSRF, mots de passe (`hash_password` / `verify_password` / `needs_rehash`, PBKDF2-SHA256 600 000 tours), anti-SSRF (`check_url`, `is_safe_url`, `is_internal_address` : boucle locale, réseaux privés, lien local et métadonnées de nuage, CGNAT...), `is_safe_redirect`, `security_headers` (HSTS, CSP...), `build_csp`, `RateLimiter` (seau à jetons par clé) |

## Web

| Module | Rôle |
|---|---|
| `network.url` | `parse(texte, base)` → `URL` (`scheme`, `username`, `password`, `host` en IDNA, `port`, `path`, `query`, `fragment`, `effective_port`, `origin`, `netloc`, `target`, `join`, `params`, `param`, `with_params`, `set_param`, `without_param`, `with_query`, `redacted`, `path_segments`, `filename`...), encodage des caractères non permis comme un navigateur, `quote`, `quote_plus`, `unquote`, `urlencode`, `parse_qs`, `parse_qsl`, `join`, `normalize`, `same_origin`, `is_url`, `build` |
| `network.uri` | URI génériques RFC 3986 : `parse` (composants bruts), `is_valid` (grammaire stricte, IRI acceptées), `resolve` (§5.2), `remove_dot_segments`, `normalize` / `equivalent` (§6), `data:` (`parse_data`, `make_data`), `mailto:` (`parse_mailto`, `make_mailto`), `urn:` (`parse_urn`), gabarits RFC 6570 niveaux 1 à 4 (`expand`, `template_variables`) |
| `network.http` | client et serveur HTTP/1.1 simples (inchangés), voir plus bas |
| `network.http_client` | `Client(base_url, headers, timeout, verify, ca_file, auth, cookies, follow_redirects, max_redirects, retry, proxy...)` : connexions persistantes (réserve, reprise si le serveur a fermé une connexion inactive), redirections (historique ; `Authorization`, `Cookie` et `Proxy-Authorization` jamais transmis à une autre origine), cookies, Basic / Bearer / Digest (RFC 7616), corps texte, octets, formulaire, JSON, multipart (`File`), réponses gzip / deflate, mandataires HTTP / HTTPS / SOCKS, nouvelles tentatives, flux (`stream=true` : `read_chunk`, `save`), `download`, crochets (`add_hook`) ; `Response` (`status`, `reason`, `headers`, `url`, `history`, `elapsed`, `text`, `json`, `bytes`, `content`, `cookies`, `link`, `ok`, `raise_for_status`) ; raccourcis `get`, `post`, `put`, `patch`, `delete`, `head`, `options` |
| `network.http_server` | `App` (routes `get/post/put/patch/delete/options/any/route("/a/{id:int}/{reste*}")`, types `int`, `float`, `slug`, `uuid`, 404 / 405 avec `Allow`, `static(préfixe, dossier)`, `websocket(chemin, gestionnaire)`, `use_middleware`, `url_for`, `not_found`, `on_error`), `Server(app, hôte, port, cert, clé, max_body, ...)` : boucle d'événements sur toutes les connexions, keep-alive, pipelining, HTTP/1.0, `Expect: 100-continue`, corps chunked, réponses 400 / 408 / 413 / 414 / 431 / 501 / 505 automatiques, refus de `Content-Length` + `Transfer-Encoding` (contrebande) ; `Request` (`params`, `query`, `param`, `header`, `text`, `json`, `form`, `file`, `cookies`, `accepts`...), `Response` (`set_cookie`, `delete_cookie`), `text`, `html`, `json_response`, `redirect`, `file_response` (ETag, Last-Modified, 304, plages 206 / 416, multipart/byteranges) ; intergiciels `logger`, `cors`, `compress`, `security_headers`, `rate_limit`, `basic_auth` ; un gestionnaire peut rendre `Response`, `str`, `dict` / `list` (JSON), `(valeur, statut)` ou `null` (204) |
| `network.http_headers` | `Headers` (ordonnée, insensible à la casse, valeurs multiples, anti-injection), `parse`, `parse_value` / `format_value` (paramètres, RFC 8187), `parse_list`, `parse_accept`, `quality`, `negotiate`, `parse_cache_control`, `max_age`, `format_http_date` / `parse_http_date` (IMF-fixdate, RFC 850, asctime), `parse_content_disposition` / `content_disposition`, `parse_range` / `content_range`, `parse_etags` / `etag_matches`, `parse_link` / `find_link` (RFC 8288), `parse_challenges`, `parse_authorization`, `basic_auth`, `bearer_auth`, `parse_basic`, `canonical_name` |
| `network.http_cookies` | `Cookie` (`set_cookie_header`, expiration Max-Age / Expires), `parse_set_cookie`, `parse_cookie_header`, `format_cookie_header`, `CookieJar` (règles de domaine et de chemin RFC 6265, suffixes publics refusés, `Secure`, préfixes `__Secure-` / `__Host-`, `SameSite`, ordre d'envoi ; `extract`, `header_for`, `get`, `set`, `clear`, `save` / `load` en JSON) |
| `network.http_multipart` | `encode(champs, fichiers)` → (corps, Content-Type), `File`, `file_from_path`, `parse(corps, content_type)` → `FormData` (`field`, `file`, `files`) / `UploadedFile` (`save`, `safe_filename`), `byteranges` |
| `network.compression` | codages de contenu : `encode` / `decode` (gzip, deflate zlib ou brut, chaînes « gzip, deflate »), `gzip`, `gunzip`, `deflate`, `inflate`, `accept_encoding`, `choose_encoding` (négociation, `identity;q=0`), `should_compress`, `crc32`, `adler32`, `detect` ; limite de décompression (bombes) |
| `network.connection_pool` | `ConnectionPool(max_per_key, max_idle_per_key, idle_timeout, max_uses, max_lifetime)` : `acquire`, `release`, `discard`, `lease` (avec `with`), `run(clé, fabrique, fn)`, `keep_alive(valeur, réutilisable)`, `close_idle`, `close_all`, `stats` ; une connexion libre est vérifiée avant d'être reprise (`is_alive`) |
| `network.proxy` | `Proxy(url)` (http, https, socks4, socks4a, socks5, socks5h ; identifiants), `connect(mandataire, hôte, port)` (HTTP CONNECT, SOCKS5 avec ou sans mot de passe, SOCKS4/4a), `proxy_for(url, config)` (variables d'environnement, NO_PROXY ; jamais pour la boucle locale), `relay(a, b)`, `TunnelServer` (mandataire CONNECT minimal, filtre `allow`, authentification) |
| `network.websocket` | RFC 6455 (inchangé), voir plus bas ; aussi intégré à `http_server` (`app.websocket`) |
| `network.webbrowser` | `open(url, new)`, `open_new`, `open_new_tab` (variable `BROWSER`, xdg-open / gio / open / start, navigateurs connus, navigateurs texte sans affichage), `get`, `register`, `available`, `candidates`, `command_for` (sans lancer), `file_url` ; l'URL n'est jamais passée à un interpréteur de commandes ; schémas http, https, file, ftp, mailto seulement |
| `network.async_client` | async / await : `connect(hôte, port, délai, secure)` → `AsyncConnection` (`read`, `read_line`, `read_until`, `read_exact`, `read_all`, `write`), `AsyncServer(hôte, port, gestionnaire_async)` (`serve(n)` : clients servis concurremment), `request` / `get` / `post` / `put` / `delete` (HTTP/1.1, redirections, gzip), `fetch_all(urls, concurrence)`, `run_limited`, `Result`, `gather` |

## Courrier et fichiers

| Module | Rôle |
|---|---|
| `network.mime` | types par extension (`guess_type`, `guess_extension`, `add_type`, `is_text_type`), en-têtes encodés RFC 2047 (`encode_header` en mots de 75 caractères sans couper un caractère, `decode_header`), `fold_header`, encodages de transfert (`choose_transfer_encoding`, `encode_body`, `decode_body`), arbre `MimePart` (`leaf`, `multipart`, `to_bytes`, `walk`, `leaves`, `find_type`, `filename`, `content_id`, `text`...), `parse`, `split_multipart`, `parse_headers`, `mail_disposition` (noms RFC 2231) |
| `network.email` | `EmailMessage(expéditeur, à, objet, texte, cc, bcc)` (`set_text`, `set_html`, `attach`, `embed`, `add_header`, `recipients`, `build`, `to_bytes` — Bcc retiré —, `body_text`) ; structure mixed / alternative / related selon le contenu ; `parse(octets)` (adresses, objet, date, texte, HTML, pièces jointes, arbre `mime`) ; `Address`, `parse_address`, `parse_address_list` (groupes, commentaires, mots encodés), `format_address`, `is_valid_email` (IDN, littéraux IP), `format_date` / `parse_date` (RFC 5322, zones nommées), `make_msgid`, `reply(message, texte, reply_all)` |
| `network.email_attachments` | `Attachment(nom, données, type, disposition, content_id)` (`save` sans écrasement ni sortie du dossier, `to_part`, `text`), `from_file`, `from_bytes`, `inline_image`, `extract(message)`, `save_all`, `safe_name`, `unique_path` |
| `network.smtp` | `SmtpClient(hôte, port, ssl, starttls, ...)` : EHLO / HELO, extensions, STARTTLS (automatique, exigé ou désactivé), TLS implicite (465), `login` (PLAIN, LOGIN, CRAM-MD5, XOAUTH2 ; refusé en clair sauf `allow_plaintext_auth`), `send` (SIZE, 8BITMIME, SMTPUTF8, destinataires refusés rendus, transparence des points), `send_message(EmailMessage)`, `noop`, `rset`, `quit` ; `send_mail` ; `dot_stuff` |
| `network.pop3` | `Pop3Client(hôte, port, ssl, starttls)` : STLS, `login` (USER/PASS, ou APOP en clair), `apop`, `auth_plain`, `capa`, `stat`, `list`, `uidl`, `retr`, `retrieve_message`, `top`, `delete`, `rset`, `noop`, `quit` |
| `network.imap` | `ImapClient(hôte, port, ssl, starttls)` : STARTTLS, `login` / `authenticate_plain` (PLAIN, XOAUTH2, SASL-IR), `capability`, `list` (noms en UTF-7 modifié décodés), `select` / `examine` (EXISTS, UIDVALIDITY, UIDNEXT, drapeaux...), `status`, `search` (UID), `fetch` (littéraux, ENVELOPE décodée), `fetch_raw`, `fetch_message`, `fetch_headers`, `store`, `add_flags`, `remove_flags`, `copy`, `move` (MOVE ou COPY + EXPUNGE), `delete_messages`, `expunge`, `append` (littéraux, LITERAL+), `create`, `delete_mailbox`, `rename`, `subscribe`, `idle(délai)`, `logout` ; `encode_mailbox` / `decode_mailbox`, `parse_values`, `search_date` |
| `network.ftp` | `FtpClient(hôte, port, délai, tls, passive)` : FTPS explicite (AUTH TLS + PBSZ + PROT P) ou implicite (990), `login` (anonyme par défaut), `feat`, `pwd`, `cwd`, `cdup`, `mkd`, `rmd`, `delete`, `rename`, `size`, `mdtm`, `syst`, `retrieve` (reprise `REST`), `download`, `store` (STOR / APPE), `upload`, `list_lines`, `nlst`, `mlsd` (repli sur LIST au format Unix), `listdir`, `exists` ; mode passif EPSV puis PASV (adresse annoncée ignorée : pas de rebond), mode actif EPRT / PORT ; `parse_mlsd_line`, `parse_list_line`, `parse_time`, `fetch_url` |

## Documents et RPC

| Module | Rôle |
|---|---|
| `network.xml_writer` | `escape`, `escape_attr`, `is_name`, `XmlWriter(indent)` (`declaration`, `doctype`, `start`, `end`, `element`, `text`, `cdata`, `comment`, `pi`, `raw`, `to_string` : document toujours bien formé), `serialize(nœud, indent, déclaration)` |
| `network.xml_parser` | analyseur XML 1.0 avec espaces de noms : `parse` → `Document` (`Element` : `tag`, `attrs`, `ns`, `local`, `prefix`, `get`, `set`, `text`, `own_text`, `elements`, `iter`, `find`, `find_all`, `find_text`, `lookup_namespace`, `get_ns`, `to_string`), `parse_events` (SAX), `events`, `is_well_formed`, `select_path` (sous-ensemble d'ElementTree / XPath : `a/b`, `.//c`, `*`, `..`, `[@a='v']`, `[n]`, `[last()]`, `[enfant='t']`, `[contains(text(), 'x')]`, `{uri}local`, préfixes) ; encodage déclaré, BOM, entités internes bornées (pas de « milliard de rires »), entités externes jamais chargées (pas de XXE), erreurs avec ligne et colonne |
| `network.xml` | `parse`, `fromstring`, `load`, `save`, `element`, `sub`, `text_node`, `cdata`, `comment`, `to_string`, `pretty`, `select`, `select_one`, `text_of`, `values`, `to_dict` / `from_dict` (@attributs, #text, listes), `canonicalize`, `escape`, `unescape` |
| `network.html` | `escape`, `unescape` (2125 références nommées de HTML5, règles des références historiques et des numériques C1), `entity`, `parse` tolérant (éléments vides, fermetures implicites p / li / dt / dd / tr / td / th / option, script / style bruts, title / textarea, attributs sans guillemets), `parse_element`, `to_html`, `tag`, `select` / `select_one` / `matches` (sélecteurs CSS : type, `#id`, `.classe`, attributs `= ~= |= ^= $= *=` (et `i`), `:first-child`, `:last-child`, `:nth-child()`, `:nth-of-type()`, `:not()`, `:empty`, `:contains()`, combinateurs ` `, `>`, `+`, `~`, groupes), `get_text`, `to_text`, `strip_tags`, `title`, `meta`, `links` (avec `<base href>`), `images`, `sanitize` (liste blanche de balises et d'attributs, `on*` et URL dangereuses retirés, `rel="noopener noreferrer nofollow"`), `is_safe_url` |
| `network.xmlrpc` | conversion des valeurs (int / `<i8>`, bool, str, double exact, `<nil/>`, array, struct, `DateTime`, `Binary`), `dumps`, `dumps_response`, `dumps_fault`, `loads`, `Fault`, `raise_fault`, `fault_of`, `parse_datetime`, `datetime_from_timestamp`, codes de faute conventionnels |
| `network.xmlrpc_client` | `ServerProxy(url)` (`call`, `call_list`, `method(nom)`, `list_methods`, `method_help`, `method_signature`), `MultiCall` (`add`, `run` → `CallResult`), `call(url, méthode, ...)` |
| `network.xmlrpc_server` | `Dispatcher` (`register`, `register_all`, `register_introspection`, `register_multicall`, contrôle de l'arité, `dispatch`, `handler`, `mount(app, chemin)`), `Server(hôte, port, répartiteur)` (sur `http_server`) |
| `network.protobuf` | format binaire : `Writer` / `Reader` (varint, zigzag, fixed32/64, float, double), `decode_raw` ; schémas : `parse_proto` / `load_proto` (proto2 / proto3 : messages imbriqués, énumérations, `repeated`, `map<K, V>`, `oneof`, services et `stream`), `Schema` (`add_message`, `add_enum`, `add_service`, `encode`, `decode`, `default`, `message`, `enum_type`, `service`), `field`, `map_field` ; champs « packed », fusion des messages répétés, valeurs par défaut |
| `network.grpc` | HTTP/2 (`H2Connection` : préface, SETTINGS, flux, contrôle de flux, PING, GOAWAY, RST_STREAM, CONTINUATION), HPACK (`HpackEncoder`, `HpackDecoder` avec table dynamique, `huffman_encode` / `huffman_decode`), encadrement gRPC (`frame_message`, `unframe_messages`, gzip), statuts (`OK`... `UNAUTHENTICATED`, `fail`, `status_of`), `grpc-timeout`, `grpc-message`, métadonnées (`-bin` en base64) |
| `network.grpc_client` | `Channel(cible, secure, ca_file, verify, metadata, timeout, compression)` (h2c ou TLS + ALPN h2, connexion persistante) : `unary`, `server_stream`, `client_stream`, `bidi_stream`, `call`, `ping`, `last_call` (métadonnées d'en-tête et de fin) ; `Stub(canal, schéma, service)` (`call`, `method`) |
| `network.grpc_server` | `Server(hôte, port, cert, clé)` : `add_service(schéma, service, {méthode: gestionnaire})`, `add_method` (octets), quatre formes d'appel, `Context` (`metadata`, `peer`, `time_remaining`, `send`, `abort`, `set_header_metadata`, `set_trailing_metadata`, `is_cancelled`), UNIMPLEMENTED, DEADLINE_EXCEEDED, exceptions → UNKNOWN |

## Système

| Module | Rôle |
|---|---|
| `network.network_interface` | `interfaces()` → `Interface` (`name`, `index`, `flags`, `is_up`, `is_loopback`, `supports_multicast`, `mac`, `mtu`, `speed`, `addresses` → `InterfaceAddress` avec masque, préfixe et réseau), `get`, `names`, `loopback`, `addresses(famille)`, `interface_for(adresse)`, `default_interface`, `counters` |
| `network.routing` | `routes(famille)` (table du système, Linux), `default_route`, `default_gateway`, `lookup(adresse)` (préfixe le plus long puis métrique), `best_route`, `Route`, `RoutingTable` (`add`, `remove`, `lookup`, `next_hop`), `system_table` |
| `network.multicast` | `MulticastSocket(groupe, port, interface, ttl, loop)` (`join`, `leave`, `send`, `send_to`, `receive`, `try_receive`, `collect`, `set_ttl`, `set_loop`, `set_interface`), `sender`, `is_multicast`, SSDP (`ssdp_search`, `ssdp_announce`, `parse_ssdp`) |
| `network.firewall` | `Firewall(politique)` : règles textuelles (`allow tcp from 10.0.0.0/8 to any port 22,80,8000-8080`), `add`, `insert`, `remove`, `check` → `Decision`, `allows`, `block(adresse, durée)`, `limit_rate`, `guard(écouteur)` → `GuardedListener`, `connect` (sortie contrôlée), `export_rules` / `load_rules`, `stats`, journal ; `Rule`, `parse_rule`, `PortSet`, `AddressSet` |
| `network.network_monitor` | `tcp_ping`, `probe` → `ProbeStats` (min, moyenne, max, gigue, pertes), `http_check`, `dns_check`, `connections("tcp"/"udp"/"all")` (`/proc/net/*`), `listening_ports`, `is_listening`, `tcp_state_counts`, `Bandwidth` (`sample` : débits par interface), `Monitor` (`add_tcp`, `add_http`, `add_dns`, `add_check`, `on_change`, `check_all`, `check_due`, `run`, `summary`) |

## Modules historiques

| Module | Rôle |
|---|---|
| `network.http` | client : `get`, `head`, `post`, `put`, `delete`, `request`, `post_json`, `post_form` → `Response` ; serveur séquentiel `Server(hôte, port)` ; URL : `parse_url`, `resolve_url`, `url_encode`, `url_decode`, `encode_query`, `parse_query` ; `https://`, `basic_auth`, `bearer_auth`. Pour les usages avancés : `http_client` / `http_server` |
| `network.websocket` | RFC 6455, en Alex pur : `connect(url, ...)` → `WebSocket` (`send_text`, `send_binary`, `ping`, `pong`, `receive`, `close`...), `Server`, `accept_connection`, `accept_key`, `Message` |

## Principes

- **Données** : une `str` transporte des octets tels quels (texte UTF-8 ou binaire) ; les variantes `*_bytes`
  prennent ou rendent des `list[int]` d'octets. Les tailles sont en octets. Les fonctions qui acceptent des
  données prennent indifféremment une `str` ou une liste d'octets.
- **Délais** : `null` attend sans limite, un nombre >= 0 au plus ce nombre de secondes (`0` : sans attendre).
  `network.timeout.Deadline` partage un délai global entre plusieurs opérations.
- **Erreurs** : types libres classés par `network.errors` ; les erreurs système finissent par le nom POSIX
  (`[ECONNREFUSED]`). Usage : `TypeError` / `ArgumentError`.
- **Sécurité par défaut** : TLS vérifie certificat et nom ; STARTTLS refuse les octets reçus en clair avant la
  négociation ; SMTP / POP3 / IMAP refusent l'authentification en clair (sauf `allow_plaintext_auth`) ; les en-têtes
  et commandes de protocole refusent CR / LF (injection) ; XML sans entités externes et à expansion bornée ;
  HTML nettoyé par liste blanche ; cookies selon RFC 6265 ; le client HTTP ne transmet jamais d'identifiants à une
  autre origine ; `security.check_url` contre la falsification de requêtes côté serveur (SSRF) ; le serveur HTTP
  refuse les requêtes ambiguës (contrebande).
- **Concurrence** : un seul fil par VM ; les serveurs (`http_server`, `grpc_server`) multiplexent leurs
  connexions par `socket.wait` et traitent une requête à la fois ; `async_client` permet des E/S concurrentes en
  async / await ; les sockets appartiennent au fil qui les a créés (`concurrency.thread`).

## Limites

- TLS passe par OpenSSL (`libssl.so.3` ou `1.1`) chargé à l'exécution ; sans lui (exécutables natifs), par `network.tls13` : TLS 1.3 seulement, sans certificat client, sans reprise de session ni révocation. Pas
  de reprise de session TLS (certains serveurs FTPS l'exigent sur le canal de données), pas de certificat client
  côté serveur.
- HTTP/2 seulement pour gRPC (`network.grpc`) ; le client et le serveur web parlent HTTP/1.1. Pas de HTTP/3.
- Pas d'ICMP ni de sockets bruts (pas de ping ni de traceroute) ; `network_monitor` mesure la latence par TCP.
- `routing`, `network_monitor.connections` et une partie de `network_interface` lisent `/proc` et `/sys` (Linux) ;
  ailleurs ces fonctions rendent des listes vides ou des champs `null`.
- La résolution DNS (`getaddrinfo`) et la poignée de main TLS restent bloquantes dans `async_client`.
- `protobuf` : `uint64` / `fixed64` au-delà de 2^63 - 1 sont lus comme des entiers négatifs (entiers 64 bits
  signés) ; pas de groupes proto2 ni d'extensions.
- POSIX seulement ; VM seulement (`alexc run`), pas dans le sous-ensemble natif.

## Architecture

`stdlib/network/*.al` (Alex) sur deux modules natifs :

- `_native_net` (`runtime/native/net/net_native.cpp`) : sockets non bloquants et délais par `poll`, octets
  (`blen`, `bslice`, `bfind`...), aléa système ; ajouts : options `reuse_port`, `ttl`, `multicast_ttl`,
  `multicast_loop`, abonnement multicast (`multicast(h, "join"|"leave"|"interface", groupe, interface)`), liste des
  interfaces (`interfaces()` par `getifaddrs`), représentation IEEE 754 (`f64_bits`, `bits_f64`, `f32_bits`,
  `bits_f32`) et écriture exacte des réels (`repr_float`).
- `_native_tls` (`runtime/native/tls/tls_native.cpp`) : OpenSSL par `dlopen` ; ajouts : certificat du pair en DER
  (`peer_certificate`), empreintes, HMAC et PBKDF2 de libcrypto (`digest`, `hmac`, `pbkdf2`, `null` si
  indisponibles : `network.security` se replie alors sur le module `crypto`).

Tout le reste — HTTP/1.1, HTTP/2 et HPACK, gRPC, Protocol Buffers, XML, HTML, MIME, SMTP, IMAP, POP3, FTP,
SOCKS, X.509 / ASN.1, Punycode... — est écrit en Alex.

## Tests

`make test-network` :

| Test | Contenu |
|---|---|
| `tests/network/test_network.al`, `test_http.al`, `test_tls.al`, `test_websocket.al` | sockets, DNS, TCP, UDP, HTTP, TLS, WebSocket (voir les en-têtes des fichiers) |
| `tests/network/test_network_utils.al` | 90 vérifications des modules sans réseau : vecteurs des RFC 4648, 3492, 3986 §5.4, 6570, 7541, 6070, 2047, 6265 ; IP, en-têtes, cookies, XML (XXE, « milliard de rires »), HTML, XML-RPC, protobuf, sécurité, nouvelles tentatives, pare-feu, routage |
| `tests/network/test_network_system.al` | interfaces, routes, multicast, surveillance, réserve, pare-feu sur écouteur, SOCKS5 contre un mandataire Python, STARTTLS, async (trois clients concurrents), navigateur |
| `tests/network/test_http_client.al` | client contre un serveur HTTP/1.1 Python multi-fils : keep-alive et reprise, corps, multipart, gzip / deflate, flux et téléchargement, redirections et origines, cookies, Basic et Digest, nouvelles tentatives, délais, injection, crochets, tunnel CONNECT écrit en Alex |
| `tests/network/test_http_server.al` | serveur Alex contre `http_client`, connexions brutes (pipelining, requêtes malformées, contrebande, délais), curl (multipart, `Expect: 100-continue`), WebSocket ; HTTPS avec certificat généré |
| `tests/network/test_xmlrpc.al` | Alex contre `xmlrpc.server` / `xmlrpc.client` de Python, et Alex contre Alex |
| `tests/network/test_grpc.al` | HPACK (RFC 7541), protobuf, client Alex contre un serveur gRPC en Go (`net/http` h2c) et client Go contre le serveur Alex (`tests/network/grpc_peer.go`), Alex contre Alex en h2c et en TLS (ALPN h2) |
| `tests/network/test_mail_ftp.al` | courriels relus par le module `email` de Python ; SMTP, POP3, IMAP et FTP(S) contre des serveurs de référence Python (`tests/network/mail_ftp_servers.py`) avec STARTTLS / STLS / AUTH TLS |

Sans `python3`, `go`, `curl` ou `openssl`, les parties concernées sont ignorées.
