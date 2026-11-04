# ALEX STANDARD LIBRARY — web.client.user_agent
#
# En-tête User-Agent (RFC 9110 §10.1.5) : « produit/version (commentaire) … ». Le client s'identifie par défaut
# comme « Alex-web-client/1.0 (Linux; x86_64) Alex/<version du langage> ».
#
#   use web.client.user_agent as ua
#   ua.default()                                        # Alex-web-client/1.0 (Linux; x86_64) Alex/1.3.0
#   ua.build("MonRobot", "2.1", "+https://exemple.org/robot")   # MonRobot/2.1 (+https://exemple.org/robot)
#   ua.with_product(ua.default(), "MonApp", "0.9")      # MonApp/0.9 Alex-web-client/1.0 (…)
#   ua.parse("Mozilla/5.0 (X11; Linux) Firefox/128.0")  # [("Mozilla", "5.0", "X11; Linux"), ("Firefox", "128.0", null)]
#
# Erreurs : ClientError (produit ou version qui ne sont pas des tokens).

from core use len, type
from collections use append
use string as _s
use os as _os
use web.http.method as _token
use web.client.client_errors as _err

const PRODUCT := "Alex-web-client"
const VERSION := "1.0"

func _platform():
    name := "Unknown"
    arch := ""
    try:
        name = _s.capitalize(str(_os.name()))
    catch e:
        name = "Unknown"
    try:
        arch = str(_os.arch())
    catch e:
        arch = ""
    if arch == "":
        return name
    return name + "; " + arch

func _language_version():
    try:
        return str(_os.alex_version())
    catch e:
        return null

# « produit/version (commentaire) » ; commentaire null : omis.
func build(product, version=null, comment=null):
    if not _token.is_token(product):
        _err.client_error("user_agent.build", "nom de produit invalide « " + str(product) + " »")
    out := product
    if version != null:
        if not _token.is_token(str(version)):
            _err.client_error("user_agent.build", "version invalide « " + str(version) + " »")
        out = out + "/" + str(version)
    if comment != null:
        out = out + " (" + _s.replace(_s.replace(str(comment), "(", "["), ")", "]") + ")"
    return out

# User-Agent par défaut du client.
func default():
    out := build(PRODUCT, VERSION, _platform())
    v := _language_version()
    if v != null and _token.is_token(v):
        out = out + " Alex/" + v
    return out

# Préfixe un produit applicatif à un User-Agent existant.
func with_product(user_agent, product, version=null, comment=null):
    return build(product, version, comment) + " " + user_agent

# Découpe « Produit/version (commentaire) … » en triplets (produit, version, commentaire).
func parse(value):
    out := []
    i := 0
    n := len(value)
    while i < n:
        while i < n and value[i] == ' ':
            i += 1
        if i >= n:
            break
        if value[i] == '(':
            j := _s.find(value[i:n], ")")
            end := n if j < 0 else i + j
            comment := value[i + 1:end]
            if len(out) > 0 and out[len(out) - 1][2] == null:
                last := out[len(out) - 1]
                out[len(out) - 1] = (last[0], last[1], comment)
            i = end + 1
            continue
        j := i
        while j < n and value[j] != ' ' and value[j] != '(':
            j += 1
        tok := value[i:j]
        slash := _s.find(tok, "/")
        if slash >= 0:
            append(out, (tok[0:slash], tok[slash + 1:len(tok)], null))
        else:
            append(out, (tok, null, null))
        i = j
    return out

# Vrai si l'User-Agent ressemble à celui d'un robot d'indexation (bot, crawler, spider…).
func is_bot(value):
    if value == null:
        return false
    v := _s.lower(value)
    for word in ["bot", "crawler", "spider", "slurp", "curl/", "wget/", "python-requests", "httpclient"]:
        if _s.contains(v, word):
            return true
    return false
