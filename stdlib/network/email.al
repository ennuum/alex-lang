# ALEX STANDARD LIBRARY — network.email
#
# Courriels (RFC 5322, MIME) : construction d'un message complet (texte, HTML, pièces jointes, images intégrées),
# analyse d'un message reçu, adresses, dates, identifiants. L'envoi se fait par network.smtp, la réception par
# network.imap / network.pop3.
#
#   m := EmailMessage("Ada <ada@exemple.org>", ["bob@exemple.org"], "Objet accentué")
#   m.set_text("Bonjour") ; m.set_html("<p>Bonjour</p>") ; m.attach(att.from_file("a.pdf"))
#   octets := m.to_bytes()                        message prêt à envoyer (CRLF ; Bcc retiré)
#   r := parse(octets)                            EmailMessage : sender, to, subject, text, html, attachments...
#   parse_address("Ada <ada@x.org>") -> Address  parse_address_list, format_address, is_valid_email
#   format_date(ts) / parse_date(texte)           make_msgid(domaine)          reply(message, texte)
#
# Structure produite : text/plain seul ; ou multipart/alternative (texte + HTML) ; images intégrées dans un
# multipart/related ; pièces jointes dans un multipart/mixed englobant.
#
# Erreurs : EmailError (adresse ou message invalide), MimeError.
#
# Exemple
#   use network.email as em
#   m := em.EmailMessage("moi@exemple.org", "toi@exemple.org", "Réunion")
#   m.set_text("Rendez-vous à 14 h.")
#   smtp.send_message(m)

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use time as _time
use os as _os
use network.mime as _mime
use network.encoding as _enc
use network.http_headers as _hh
use network.email_attachments as _att
use network.utils as _u
use network.ipaddress as _ip
use network.html as _html

func _fail(message):
    raise("EmailError", "email : " + message)

# ---------------------------------------------------------------- adresses

class Address:
    func init(name, email):
        self.name = name          # nom affiché (décodé) ou ""
        self.email = email        # « local@domaine »

    func local_part():
        k := _s.find(self.email, "@")
        if k < 0:
            return self.email
        return _s.substring(self.email, 0, k)

    func domain():
        k := len(self.email) - 1
        while k >= 0 and self.email[k] != '@':
            k -= 1
        if k < 0:
            return ""
        return _s.substring(self.email, k + 1, len(self.email))

    # Forme d'en-tête (« "Ada, L." <ada@x.org> », nom encodé en RFC 2047 si besoin).
    func str():
        return format_address(self.name, self.email)

    func __str__():
        return self.str()

    func __eq__(other):
        if isinstance(other, Address):
            return _s.lower(other.email) == _s.lower(self.email)
        if type(other) == "str":
            return _s.lower(other) == _s.lower(self.email)
        return false

const _SPECIALS := "()<>[]:;@\\,.\""

func _needs_quotes(name):
    for c in name:
        for x in _SPECIALS:
            if c == x:
                return true
    return false

# « Nom <adresse> » pour un en-tête : nom entre guillemets s'il contient des caractères spéciaux, encodé
# (RFC 2047) s'il n'est pas en ASCII.
func format_address(name, email):
    _u.check_single_line(email, "adresse")
    if name == null or name == "":
        return email
    _u.check_single_line(name, "nom")
    ascii := true
    for c in name:
        if _s.ord(c) >= 128:
            ascii = false
    n := name
    if not ascii:
        n = _mime.encode_header(name)
    elif _needs_quotes(name):
        n = "\"" + _s.replace(_s.replace(name, "\\", "\\\\"), "\"", "\\\"") + "\""
    return n + " <" + email + ">"

# Découpe une liste d'adresses sur les virgules hors guillemets, crochets et commentaires.
func _split_addresses(text):
    out := []
    cur := []
    inq := false
    angle := 0
    paren := 0
    esc := false
    for c in text:
        if esc:
            append(cur, str(c))
            esc = false
            continue
        if c == '\\' and inq:
            append(cur, str(c))
            esc = true
            continue
        if c == '"' and paren == 0:
            inq = not inq
        elif not inq:
            if c == '<':
                angle += 1
            elif c == '>':
                angle -= 1
            elif c == '(':
                paren += 1
            elif c == ')':
                paren -= 1
            elif c == ',' and angle == 0 and paren == 0:
                append(out, _s.join("", cur))
                cur = []
                continue
        append(cur, str(c))
    append(out, _s.join("", cur))
    return out

func _strip_comments(text):
    out := []
    depth := 0
    inq := false
    for c in text:
        if c == '"' and depth == 0:
            inq = not inq
            append(out, str(c))
        elif c == '(' and not inq:
            depth += 1
        elif c == ')' and not inq and depth > 0:
            depth -= 1
        elif depth == 0:
            append(out, str(c))
    return _s.join("", out)

func _comment_of(text):
    a := _s.find(text, "(")
    b := _s.find(text, ")")
    if a >= 0 and b > a:
        return _s.trim(_s.substring(text, a + 1, b))
    return ""

func _unquote_name(n):
    t := _s.trim(n)
    if len(t) >= 2 and t[0] == '"' and t[len(t) - 1] == '"':
        inner := _s.substring(t, 1, len(t) - 1)
        out := []
        esc := false
        for c in inner:
            if esc:
                append(out, str(c))
                esc = false
            elif c == '\\':
                esc = true
            else:
                append(out, str(c))
        t = _s.join("", out)
    return _mime.decode_header(t)

# Adresse d'un texte « Nom <a@b> », « a@b (Nom) » ou « a@b ». Rend null si le texte est vide.
func parse_address(text):
    if text == null:
        return null
    t := _s.trim(text)
    if t == "":
        return null
    lt := -1
    i := len(t) - 1
    while i >= 0:
        if t[i] == '<':
            lt = i
            break
        i -= 1
    if lt >= 0:
        gt := _s.find(_s.substring(t, lt, len(t)), ">")
        if gt < 0:
            _fail("adresse sans « > » : " + text)
        email := _s.trim(_s.substring(t, lt + 1, lt + gt))
        # route source obsolète « <@a,@b:x@y> »
        colon := _s.find(email, ":")
        if _s.starts_with(email, "@") and colon > 0:
            email = _s.substring(email, colon + 1, len(email))
        name := _unquote_name(_strip_comments(_s.substring(t, 0, lt)))
        return Address(_s.trim(name), email)
    name := _comment_of(t)
    email := _s.trim(_strip_comments(t))
    return Address(_mime.decode_header(name), email)

# Liste d'adresses (groupes « nom: a@b, c@d; » aplatis).
func parse_address_list(text):
    out := []
    if text == null:
        return out
    t := text
    if type(t) == "list":
        for x in t:
            for a in parse_address_list(x):
                append(out, a)
        return out
    if isinstance(t, Address):
        return [t]
    for part in _split_addresses(t):
        p := _s.trim(part)
        # groupe : « Équipe: a@b, c@d; »
        colon := _s.find(p, ":")
        if colon > 0 and not _s.contains(_s.substring(p, 0, colon), "<") and not _s.contains(_s.substring(p, 0, colon), "\""):
            p = _s.trim(_s.substring(p, colon + 1, len(p)))
        if _s.ends_with(p, ";"):
            p = _s.trim(_s.substring(p, 0, len(p) - 1))
        a := parse_address(p)
        if a != null and a.email != "":
            append(out, a)
    return out

func _atext(c):
    if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9'):
        return true
    for x in "!#$%&'*+-/=?^_`{|}~":
        if c == x:
            return true
    return _s.ord(c) >= 128

# Vrai si l'adresse est syntaxiquement valide : partie locale « dot-atom » (ou entre guillemets), domaine aux
# étiquettes valides (noms internationaux acceptés) ou littéral IP « [1.2.3.4] ».
func is_valid_email(address):
    if type(address) != "str" or len(address) > 254 or _u.has_control_breaks(address):
        return false
    k := len(address) - 1
    while k >= 0 and address[k] != '@':
        k -= 1
    if k <= 0 or k == len(address) - 1:
        return false
    local := _s.substring(address, 0, k)
    domain := _s.substring(address, k + 1, len(address))
    if len(local) > 64:
        return false
    if local[0] == '"' and local[len(local) - 1] == '"' and len(local) >= 2:
        pass
    else:
        if _s.starts_with(local, ".") or _s.ends_with(local, ".") or _s.contains(local, ".."):
            return false
        for c in local:
            if not (_atext(c) or c == '.'):
                return false
    if _s.starts_with(domain, "[") and _s.ends_with(domain, "]"):
        inner := _s.substring(domain, 1, len(domain) - 1)
        if _s.starts_with(_s.lower(inner), "ipv6:"):
            return _ip_ok(_s.substring(inner, 5, len(inner)), 6)
        return _ip_ok(inner, 4)
    if not _s.contains(domain, "."):
        return false
    try:
        return _u.is_valid_hostname(_enc.idna_encode(domain))
    catch e:
        return false

func _ip_ok(text, version):
    if version == 4:
        return _ip.is_ipv4(text)
    return _ip.is_ipv6(text)

# ---------------------------------------------------------------- dates

const _DAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

func _two(n):
    if n < 10:
        return "0" + str(n)
    return str(n)

# Date RFC 5322 (« Sun, 11 Oct 2026 17:03:39 +0200 ») d'un horodatage (défaut : maintenant), décalage en minutes
# (défaut : celui du système).
func format_date(ts=null, offset_minutes=null):
    t := ts
    if t == null:
        t = _time.time()
    off := offset_minutes
    if off == null:
        off = to_int(_time.local_utc_offset() // 60)
    local := to_int(t) + off * 60
    days := local // 86400
    rem := local - days * 86400
    ymd := _time.civil_from_days(days)
    sign := "+"
    a := off
    if off < 0:
        sign = "-"
        a = -off
    return _DAYS[_time.weekday_of_days(days)] + ", " + str(ymd[2]) + " " + _MONTHS[ymd[1] - 1] + " " + str(ymd[0]) + " " + _two(rem // 3600) + ":" + _two((rem % 3600) // 60) + ":" + _two(rem % 60) + " " + sign + _two(a // 60) + _two(a % 60)

_ZONES := {"UT": 0, "UTC": 0, "GMT": 0, "Z": 0, "EST": -300, "EDT": -240, "CST": -360, "CDT": -300, "MST": -420, "MDT": -360, "PST": -480, "PDT": -420, "CET": 60, "CEST": 120}

# Horodatage Unix d'une date RFC 5322 (tolérante : jour de semaine facultatif, secondes facultatives, zones
# nommées), ou null si elle est illisible.
func parse_date(text):
    if text == null:
        return null
    t := _strip_comments(_s.replace(str(text), ",", " "))
    parts := []
    for p in _s.split(_s.replace(t, "\t", " "), " "):
        if p != "":
            append(parts, p)
    if len(parts) > 0 and not (parts[0][0] >= '0' and parts[0][0] <= '9'):
        parts = parts[1:len(parts)]
    if len(parts) < 4:
        return null
    day := _digits(parts[0])
    month := -1
    i := 0
    while i < 12:
        if _s.lower(_s.substring(parts[1], 0, 3)) == _s.lower(_MONTHS[i]):
            month = i + 1
        i += 1
    year := _digits(parts[2])
    if day == null or month < 0 or year == null:
        return null
    if year < 50:
        year += 2000
    elif year < 1000:
        year += 1900
    hms := _s.split(parts[3], ":")
    if len(hms) < 2:
        return null
    h := _digits(hms[0])
    mi := _digits(hms[1])
    sec := 0
    if len(hms) > 2:
        sec = _digits(hms[2])
    if h == null or mi == null or sec == null:
        return null
    off := 0
    if len(parts) > 4:
        z := parts[4]
        if (z[0] == '+' or z[0] == '-') and len(z) == 5 and _digits(_s.substring(z, 1, 5)) != null:
            v := _digits(_s.substring(z, 1, 3)) * 60 + _digits(_s.substring(z, 3, 5))
            off = v
            if z[0] == '-':
                off = -v
        elif contains_key(_ZONES, _s.upper(z)):
            off = _ZONES[_s.upper(z)]
    return _time.days_from_civil(year, month, day) * 86400 + h * 3600 + mi * 60 + sec - off * 60

func _digits(t):
    if t == "":
        return null
    for c in t:
        if c < '0' or c > '9':
            return null
    return to_int(t)

# Identifiant de message unique « <aléa.horodatage@domaine> ».
func make_msgid(domain=null):
    d := domain
    if d == null:
        d = _os.hostname()
        if d == null or d == "" or not _s.contains(d, "."):
            d = "alex.localdomain"
    return "<" + _enc.hex_encode(_n.random_bytes(12)) + "." + str(to_int(_time.time())) + "@" + d + ">"

# ---------------------------------------------------------------- message

class EmailMessage:
    # sender : str ou Address ; to / cc / bcc : str (liste séparée par des virgules), Address ou liste.
    func init(sender=null, to=null, subject="", text=null, cc=null, bcc=null):
        self.sender = null
        if sender != null:
            self.sender = _one(sender)
        self.to = parse_address_list(to)
        self.cc = parse_address_list(cc)
        self.bcc = parse_address_list(bcc)
        self.reply_to = []
        self.subject = subject
        self.date = null              # horodatage ; null : maintenant à la construction
        self.message_id = null
        self.in_reply_to = null
        self.references = []
        self.text = text
        self.html = null
        self.attachments = []         # network.email_attachments.Attachment
        self.headers = _hh.Headers()  # en-têtes supplémentaires
        self.mime = null              # arbre MIME d'un message analysé
        self.charset = "utf-8"

    func set_text(text):
        self.text = text
        return self

    func set_html(html):
        self.html = html
        return self

    # Ajoute une pièce jointe : Attachment, chemin de fichier, ou (nom, octets[, type]).
    func attach(a, data=null, content_type=null):
        if isinstance(a, _att.Attachment):
            append(self.attachments, a)
        elif data != null:
            append(self.attachments, _att.Attachment(a, data, content_type))
        else:
            append(self.attachments, _att.from_file(a, content_type))
        return self

    # Image intégrée au HTML : <img src="cid:CID">.
    func embed(path, cid):
        append(self.attachments, _att.inline_image(path, cid))
        return self

    func add_header(name, value):
        self.headers.add(name, value)
        return self

    func header(name, default=null):
        v := self.headers.get(name)
        if v == null:
            return default
        return _mime.decode_header(v)

    # Tous les destinataires de l'enveloppe SMTP (To, Cc, Bcc), sans doublon.
    func recipients():
        out := []
        seen := {}
        for lst in [self.to, self.cc, self.bcc]:
            for a in lst:
                k := _s.lower(a.email)
                if not contains_key(seen, k):
                    seen[k] = true
                    append(out, a.email)
        return out

    func _body_part():
        txt := self.text
        if txt == null and self.html == null:
            txt = ""
        cs := "; charset=" + self.charset
        parts := []
        if txt != null:
            append(parts, _mime.leaf(_enc.encode_charset(_u.to_crlf(txt), self.charset), "text/plain" + cs))
        if self.html != null:
            hp := _mime.leaf(_enc.encode_charset(_u.to_crlf(self.html), self.charset), "text/html" + cs)
            inl := []
            for a in self.attachments:
                if a.is_inline():
                    append(inl, a.to_part())
            if len(inl) > 0:
                hp = _mime.multipart("related", [hp] + inl)
            append(parts, hp)
        if len(parts) == 1:
            return parts[0]
        return _mime.multipart("alternative", parts)

    # Arbre MIME du message (en-têtes compris).
    func build():
        if self.sender == null:
            _fail("expéditeur (From) manquant")
        if len(self.to) == 0 and len(self.cc) == 0 and len(self.bcc) == 0:
            _fail("aucun destinataire")
        root := self._body_part()
        files := []
        for a in self.attachments:
            if not a.is_inline() or self.html == null:
                append(files, a.to_part())
        if len(files) > 0:
            root = _mime.multipart("mixed", [root] + files)
        body_headers := root.headers
        h := _hh.Headers()
        h.add("From", self.sender.str())
        if len(self.to) > 0:
            h.add("To", _join(self.to))
        if len(self.cc) > 0:
            h.add("Cc", _join(self.cc))
        if len(self.reply_to) > 0:
            h.add("Reply-To", _join(self.reply_to))
        h.add("Subject", _mime.encode_header(self.subject))
        d := self.date
        if d == null:
            d = _time.time()
        h.add("Date", format_date(d))
        mid := self.message_id
        if mid == null:
            mid = make_msgid(self.sender.domain())
            self.message_id = mid
        h.add("Message-ID", mid)
        if self.in_reply_to != null:
            h.add("In-Reply-To", self.in_reply_to)
        if len(self.references) > 0:
            h.add("References", _s.join(" ", self.references))
        h.add("MIME-Version", "1.0")
        for e in self.headers.entries:
            lk := _s.lower(e[0])
            if lk != "bcc":
                h.add(e[0], e[1])
        for e in body_headers.entries:
            h.add(e[0], e[1])
        root.headers = h
        return root

    # Message complet (octets, CRLF), sans en-tête Bcc.
    func to_bytes():
        return self.build().to_bytes()

    func str():
        return self.to_bytes()

    # Corps texte, ou le texte tiré du HTML s'il n'y en a pas.
    func body_text():
        if self.text != null:
            return self.text
        if self.html != null:
            return _html_to_text(self.html)
        return ""

func _html_to_text(h):
    return _html.to_text(h)

func _join(addrs):
    out := []
    for a in addrs:
        append(out, a.str())
    return _s.join(", ", out)

func _one(x):
    if isinstance(x, Address):
        return x
    a := parse_address(x)
    if a == null:
        _fail("adresse vide")
    return a

# ---------------------------------------------------------------- analyse

# Message reçu (octets bruts) -> EmailMessage (adresses, objet, date, corps texte / HTML, pièces jointes ; arbre
# MIME complet dans .mime).
func parse(raw):
    data := raw
    if type(raw) == "list":
        data = _n.from_bytes(raw)
    root := _mime.parse(data)
    m := EmailMessage()
    m.mime = root
    h := root.headers
    m.headers = h
    froms := parse_address_list(_mime.decode_header(h.get("from")))
    if len(froms) > 0:
        m.sender = froms[0]
    m.to = parse_address_list(_decoded_list(h.get_all("to")))
    m.cc = parse_address_list(_decoded_list(h.get_all("cc")))
    m.bcc = parse_address_list(_decoded_list(h.get_all("bcc")))
    m.reply_to = parse_address_list(_decoded_list(h.get_all("reply-to")))
    m.subject = _mime.decode_header(h.get("subject", ""))
    m.date = parse_date(h.get("date"))
    m.message_id = h.get("message-id")
    m.in_reply_to = h.get("in-reply-to")
    refs := h.get("references")
    if refs != null:
        for r in _s.split(_s.replace(_s.replace(refs, "\r", " "), "\n", " "), " "):
            if _s.trim(r) != "":
                append(m.references, _s.trim(r))
    tp := root.find_type("text/plain")
    if tp != null:
        m.text = _normalize_newlines(tp.text())
    hp := root.find_type("text/html")
    if hp != null:
        m.html = _normalize_newlines(hp.text())
    if not root.is_multipart() and root.content_type() != "text/plain" and root.content_type() != "text/html":
        m.text = null
    m.attachments = _att.extract(root, true)
    return m

func _decoded_list(values):
    out := []
    for v in values:
        append(out, _mime.decode_header(v))
    return _s.join(", ", out)

func _normalize_newlines(t):
    return _s.replace(t, "\r\n", "\n")

# Réponse à un message : destinataire = Reply-To (sinon From), objet « Re: », In-Reply-To et References.
func reply(original, text, sender=null, reply_all=false):
    to := original.reply_to
    if len(to) == 0 and original.sender != null:
        to = [original.sender]
    m := EmailMessage(sender, to)
    if reply_all:
        me := ""
        if sender != null:
            me = _s.lower(_one(sender).email)
        for a in original.to + original.cc:
            if _s.lower(a.email) != me:
                append(m.cc, a)
    subj := original.subject
    if subj == null:
        subj = ""
    if not _s.starts_with(_s.lower(subj), "re:"):
        subj = "Re: " + subj
    m.subject = subj
    m.text = text
    if original.message_id != null:
        m.in_reply_to = original.message_id
        for r in original.references:
            append(m.references, r)
        append(m.references, original.message_id)
    return m
