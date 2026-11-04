# ALEX STANDARD LIBRARY — network.network_errors
#
# Diagnostic des erreurs réseau, en complément de network.errors (types et hiérarchie, dont ce module
# reprend les noms) : fiche structurée d'une erreur (classify), explications en français des codes errno, statuts
# HTTP traduits en type d'erreur et en décision « réessayer ? », délai d'attente conseillé (Retry-After), et
# exécution protégée qui renvoie un résultat au lieu de lever.
#
#   use network.network_errors as nerr
#   try:
#       tcp.connect("hôte", 80, 2.0)
#   catch e:
#       f := nerr.classify(e)
#       print(f["kind"], f["errno"], f["transient"], f["explanation"])
#       # « NetworkError ECONNREFUSED true Connexion refusée : aucun service n'écoute sur ce port. »
#   print(nerr.http_status_info(503))      # {"type": "HttpError", "transient": true, "category": "serveur", ...}
#   r := nerr.attempt(() => http_client.get(url))   # {"ok": false, "error": {...}} ou {"ok": true, "value": ...}
#   print(nerr.retry_after_seconds("120"), nerr.explain_errno("EHOSTUNREACH"))
#
# Erreurs : aucune levée par classify / attempt ; raise_for_status lève HttpError.

from core use len, type, to_int
from collections use append
use string as _s
use network.errors as _e

const NETWORK := "NetworkError"
const TIMEOUT := "TimeoutError"
const DNS := "DnsError"
const TLS := "TlsError"
const CERTIFICATE := "CertificateError"
const PROXY := "ProxyError"
const POOL := "PoolError"
const FIREWALL := "FirewallError"
const PROTOCOL := "ProtocolError"
const HTTP := "HttpError"
const URL := "UrlError"

const ERRNO_FR := {
    "ECONNREFUSED": "Connexion refusée : aucun service n'écoute sur ce port (ou un pare-feu rejette activement).",
    "ECONNRESET": "Connexion réinitialisée par le pair (fermeture brutale côté distant).",
    "ECONNABORTED": "Connexion interrompue localement.",
    "ETIMEDOUT": "Délai dépassé : l'hôte ne répond pas (filtré, éteint ou réseau saturé).",
    "EHOSTUNREACH": "Hôte injoignable : aucune route vers cette machine.",
    "ENETUNREACH": "Réseau injoignable : aucune route vers ce réseau (interface ou passerelle absente).",
    "ENETDOWN": "Le réseau local est désactivé.",
    "EADDRINUSE": "Adresse déjà utilisée : un autre programme écoute déjà sur ce port.",
    "EADDRNOTAVAIL": "Adresse locale indisponible sur cette machine.",
    "EACCES": "Permission refusée (port privilégié < 1024, ou règle de sécurité).",
    "EPERM": "Opération non permise par le système.",
    "EPIPE": "Écriture sur une connexion déjà fermée par le pair.",
    "EAGAIN": "Ressource temporairement indisponible : réessayer.",
    "EMFILE": "Trop de fichiers / sockets ouverts par ce processus.",
    "ENFILE": "Trop de fichiers ouverts sur le système.",
    "ENOBUFS": "Mémoire tampon réseau épuisée.",
    "EINVAL": "Argument invalide (adresse, option ou taille).",
    "EAFNOSUPPORT": "Famille d'adresses non prise en charge (IPv6 désactivé ?).",
    "ENOTCONN": "Le socket n'est pas connecté.",
    "EISCONN": "Le socket est déjà connecté.",
    "EHOSTDOWN": "L'hôte est éteint."}

const HTTP_REASONS := {400: "requête invalide", 401: "authentification requise", 403: "accès interdit",
    404: "ressource introuvable", 405: "méthode non autorisée", 408: "délai de requête dépassé",
    409: "conflit", 410: "ressource supprimée", 413: "corps trop volumineux", 415: "type de contenu non pris en charge",
    422: "entité non traitable", 425: "trop tôt", 429: "trop de requêtes", 500: "erreur interne du serveur",
    501: "non implémenté", 502: "passerelle invalide", 503: "service indisponible", 504: "délai de passerelle dépassé"}

func explain_errno(name):
    if name in ERRNO_FR:
        return ERRNO_FR[name]
    return null

func is_a(e, kind):
    return _e.is_a(e, kind)

func is_transient(e):
    return _e.is_transient(e)

# Fiche d'une erreur : kind, lineage, errno, transient, explanation, message, reply_code.
func classify(e):
    en := _e.errno_of(e)
    expl := null
    if en != null:
        expl = explain_errno(en)
    if expl == null:
        if e.type == TIMEOUT:
            expl = "Délai dépassé."
        elif e.type == DNS:
            expl = "Nom d'hôte introuvable (faute de frappe, DNS injoignable, ou pas d'accès réseau)."
        elif e.type == CERTIFICATE:
            expl = "Certificat refusé (expiré, autosigné, ou ne correspondant pas au nom)."
        elif e.type == TLS:
            expl = "Échec de la négociation TLS."
        elif e.type == PROXY:
            expl = "Le mandataire (proxy) a refusé ou est injoignable."
    return {"kind": e.type, "lineage": _e.lineage(e), "errno": en, "transient": _e.is_transient(e),
            "explanation": expl, "message": e.message, "reply_code": _e.reply_code(e), "network": _e.is_network_error(e)}

func http_status_info(status):
    cat := "information"
    if status >= 200 and status < 300:
        cat = "succès"
    elif status >= 300 and status < 400:
        cat = "redirection"
    elif status >= 400 and status < 500:
        cat = "client"
    elif status >= 500:
        cat = "serveur"
    reason := null
    if status in HTTP_REASONS:
        reason = HTTP_REASONS[status]
    transient := status == 408 or status == 425 or status == 429 or status == 502 or status == 503 or status == 504
    t := null
    if status >= 400:
        t = HTTP
    return {"status": status, "category": cat, "reason": reason, "transient": transient, "type": t,
            "auth": status == 401 or status == 407}

# Lève HttpError si la réponse (objet avec .status, .reason, .url) n'est pas un succès.
func raise_for_status(response):
    st := response.status
    if st >= 400:
        info := http_status_info(st)
        r := info["reason"]
        if r == null:
            r = str(response.reason)
        raise(HTTP, "HTTP " + str(st) + " (" + r + ") pour " + str(response.url) + " [" + str(st) + "]")
    return response

# Retry-After : secondes (nombre) ou date HTTP ; null si illisible.
func retry_after_seconds(value, now=null):
    if value == null:
        return null
    t := _s.trim(str(value))
    ok := len(t) > 0
    for c in t:
        if c < '0' or c > '9':
            ok = false
    if ok:
        return to_int(t)
    return null

# fn() sans lever : {"ok": true, "value": v} ou {"ok": false, "error": classify(e)}.
func attempt(fn):
    try:
        return {"ok": true, "value": fn(), "error": null}
    catch e:
        return {"ok": false, "value": null, "error": classify(e)}

func describe(e):
    f := classify(e)
    out := f["kind"] + " : " + f["message"]
    if f["explanation"] != null:
        out += " — " + f["explanation"]
    if f["transient"]:
        out += " (passagère : réessayer)"
    return out
