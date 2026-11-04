# Test de network.mime, email, email_attachments, smtp, pop3, imap et ftp : construction et analyse de courriels
# (vérifiées aussi par le module email de Python), puis chaque client contre un serveur de référence en Python
# (tests/network/mail_ftp_servers.py) avec montée en TLS (STARTTLS / STLS / AUTH TLS).

from core use len, type
from collections use append, keys
use string as s
use json
use io
use os
use process as proc
use network.mime as mime
use network.email as em
use network.email_attachments as att
use network.smtp as smtp
use network.pop3 as pop3
use network.imap as imap
use network.ftp as ftp
use network.certificates as certs
use network.utils as nu

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

const CERT := "/tmp/alex_mail_cert.pem"
const KEY := "/tmp/alex_mail_key.pem"

func start(mode):
    p := proc.Command("python3").args(["tests/network/mail_ftp_servers.py", mode, CERT, KEY, "/tmp/alex_" + mode + ".json"]).stdout("pipe").stderr("null").spawn()
    port := s.trim(p.read_line("stdout", 10.0))
    return [p, port]

func finish(srv, mode):
    srv[0].wait(10.0)
    srv[0].close()
    return json.parse(io.read_file("/tmp/alex_" + mode + ".json"))

func error_of(f):
    try:
        f()
    catch e:
        return e.type
    return "aucune erreur"

# ---------------------------------------------------------------- courriels
m := em.EmailMessage("Ada Lovelace <ada@exemple.org>", "Bob <bob@exemple.org>, carl@exemple.org", "Réunion — ordre du jour", null, null, "secret@exemple.org")
m.set_text("Bonjour,\n.ligne qui commence par un point\nÀ demain.\n")
m.set_html("<p>Bonjour <img src=\"cid:logo\"></p>")
m.attach(att.from_bytes(nu.from_bytes([0, 1, 2, 255]), "données.bin"))
m.attach(att.Attachment("logo.png", "PNGDATA", "image/png", "inline", "logo"))
raw := m.to_bytes()
check(not s.contains(raw, "secret@exemple.org"), "Bcc absent des en-têtes")
check_eq(m.recipients(), ["bob@exemple.org", "carl@exemple.org", "secret@exemple.org"], "destinataires de l'enveloppe")
r := em.parse(raw)
check_eq([r.sender.email, r.subject, len(r.to)], ["ada@exemple.org", "Réunion — ordre du jour", 2], "analyse : en-têtes")
check_eq(r.text, "Bonjour,\n.ligne qui commence par un point\nÀ demain.\n", "analyse : texte")
check(s.contains(r.html, "cid:logo"), "analyse : HTML")
names := []
for a in r.attachments:
    append(names, a.filename + ":" + a.disposition + ":" + str(a.size()))
check_eq(names, ["logo.png:inline:7", "données.bin:attachment:4"], "analyse : pièces jointes")
check_eq(em.parse_address("\"Lovelace, Ada\" <ada@x.org>").name, "Lovelace, Ada", "adresse entre guillemets")
check_eq(em.parse_address("=?UTF-8?Q?=C3=89lodie?= <e@x.fr>").name, "Élodie", "nom encodé RFC 2047")
check_eq(len(em.parse_address_list("a@b.c, \"X, Y\" <c@d.e>, G: f@g.h;")), 3, "liste d'adresses")
check_eq([em.is_valid_email("a.b+c@sous.exemple.org"), em.is_valid_email("a..b@x.org"), em.is_valid_email("a@x")], [true, false, false], "validation d'adresses")
check_eq(em.parse_date(em.format_date(784111777, -300)), 784111777, "dates RFC 5322 aller-retour")
check_eq(mime.decode_header(mime.encode_header("Ça marche ✓ " * 4)), "Ça marche ✓ " * 4, "mots encodés longs")
rp := em.reply(r, "Merci")
check_eq([rp.subject, rp.to[0].email, rp.in_reply_to], ["Re: Réunion — ordre du jour", "ada@exemple.org", m.message_id], "réponse")
tmpd := "/tmp/alex_mail_pj"
if os.exists(tmpd):
    for f in os.list_dir(tmpd):
        os.remove(os.join(tmpd, f))
saved := att.save_all(r, tmpd, true)
saved2 := att.save_all(r, tmpd, true)
check_eq(len(saved) + len(saved2), 4, "pièces jointes enregistrées")
check(s.ends_with(saved2[1], "données (1).bin"), "pas d'écrasement : « nom (1).ext »")

if proc.which("python3") != null:
    # le module email de Python relit notre message
    io.write_file("/tmp/alex_mail.eml", raw)
    chk := proc.Command("python3").args(["-c", "import email,email.policy,sys;m=email.message_from_bytes(open('/tmp/alex_mail.eml','rb').read(),policy=email.policy.default);print(m['subject']);print('|'.join(m.get_body(('plain',)).get_content().splitlines())+'|');print(','.join(p.get_filename() or '-' for p in m.iter_attachments()))"]).stdout("pipe").run(null, 20.0)
    lines := s.split(chk.stdout, "\n")
    check_eq(lines[0], "Réunion — ordre du jour", "Python : objet")
    check_eq(lines[1], "Bonjour,|.ligne qui commence par un point|À demain.|", "Python : texte")
    check_eq(lines[2], "données.bin", "Python : pièce jointe")

    cert := CERT
    key := KEY
    have_tls := proc.which("openssl") != null
    if have_tls:
        certs.generate_self_signed(cert, key, "localhost", ["localhost", "127.0.0.1"], 2)

    if have_tls:
        # SMTP : STARTTLS, AUTH, refus partiel, transparence des points
        sv := start("smtp")
        c := smtp.SmtpClient("127.0.0.1", json.parse(sv[1]), null, true, 10.0, "client.test", true, cert)
        check(c.secure and c.has_extension("AUTH"), "SMTP : STARTTLS puis EHLO")
        check_eq(c.auth_mechanisms(), ["PLAIN", "LOGIN", "CRAM-MD5"], "SMTP : mécanismes")
        check_eq(error_of(() => c.login("alice", "faux", "PLAIN")), "SmtpError", "SMTP : mauvais mot de passe")
        c.login("alice", "secret")
        m.to = em.parse_address_list("bob@exemple.org, refuse@exemple.org")
        refused := c.send_message(m)
        check_eq(keys(refused), ["refuse@exemple.org"], "SMTP : destinataire refusé signalé")
        c.quit()
        rep := finish(sv, "smtp")
        check_eq(rep["tls"], true, "SMTP : serveur passé en TLS")
        check_eq(len(rep["messages"]), 1, "SMTP : un message reçu")
        msg := rep["messages"][0]
        check(s.starts_with(msg["from"], "<ada@exemple.org>") and s.contains(msg["from"], "SIZE="), "SMTP : MAIL FROM + SIZE")
        check_eq(msg["rcpt"], ["<bob@exemple.org>", "<secret@exemple.org>"], "SMTP : RCPT (Bcc compris)")
        check_eq(em.parse(msg["data"]).text, "Bonjour,\n.ligne qui commence par un point\nÀ demain.\n", "SMTP : contenu intact (points)")
        for mech in ["LOGIN", "CRAM-MD5"]:
            sv2 := start("smtp")
            c2 := smtp.SmtpClient("127.0.0.1", json.parse(sv2[1]), null, true, 10.0, "client.test", true, cert)
            c2.login("alice", "secret", mech)
            check(c2.authenticated, "SMTP : AUTH " + mech)
            c2.quit()
            finish(sv2, "smtp")
        sv3 := start("smtp")
        c3 := smtp.SmtpClient("127.0.0.1", json.parse(sv3[1]), null, false, 10.0, "client.test")
        check_eq(error_of(() => c3.login("alice", "secret")), "SmtpError", "SMTP : pas d'AUTH en clair")
        c3.quit()
        finish(sv3, "smtp")

        # POP3 : STLS, USER/PASS, STAT, LIST, UIDL, RETR (points), TOP, DELE
        sp := start("pop3")
        p := pop3.Pop3Client("127.0.0.1", json.parse(sp[1]), null, true, 10.0, true, cert)
        check(p.secure, "POP3 : STLS")
        p.login("alice", "secret")
        st := p.stat()
        check_eq(st[0], 3, "POP3 : STAT")
        check_eq(len(keys(p.list())), 3, "POP3 : LIST")
        check_eq(p.uidl()[2], "uid-2", "POP3 : UIDL")
        m2 := p.retrieve_message(2)
        check_eq([m2.subject, m2.text], ["deux été", "Ligne\n.point au debut\nfin\n"], "POP3 : RETR (dot-unstuffing)")
        check(s.contains(p.top(3, 0), "Subject: trois") and not s.contains(p.top(3, 0), "xxxx"), "POP3 : TOP")
        p.delete(1)
        check_eq(p.stat()[0], 2, "POP3 : DELE")
        p.quit()
        rp3 := finish(sp, "pop3")
        check_eq(rp3["deleted"], [1], "POP3 : suppression appliquée au QUIT")
        sp2 := start("pop3")
        p2 := pop3.Pop3Client("127.0.0.1", json.parse(sp2[1]), null, false, 10.0)
        p2.apop("alice", "secret")
        check_eq(p2.stat()[0], 3, "POP3 : APOP")
        p2.quit()
        finish(sp2, "pop3")

        # IMAP : STARTTLS, LOGIN, LIST (UTF-7 modifié), SELECT, SEARCH, FETCH (littéraux), STORE, MOVE, APPEND, IDLE
        si := start("imap")
        ic := imap.ImapClient("127.0.0.1", json.parse(si[1]), null, true, 10.0, true, cert)
        check(ic.secure and ic.has_capability("IDLE"), "IMAP : STARTTLS et capacités")
        ic.login("alice", "secret")
        boxes := []
        for b in ic.list():
            append(boxes, b.name)
        check_eq(boxes, ["INBOX", "Archives", "Été"], "IMAP : LIST + UTF-7 modifié")
        info := ic.select("INBOX")
        check_eq([info["exists"], info["uidvalidity"], info["uidnext"], len(info["flags"])], [3, 42, 104, 5], "IMAP : SELECT")
        check_eq(ic.search("ALL"), [101, 102, 103], "IMAP : UID SEARCH")
        check_eq(ic.search("UNSEEN"), [102, 103], "IMAP : UNSEEN")
        f := ic.fetch([101, 102], "(UID FLAGS RFC822.SIZE ENVELOPE)")
        check_eq([f[101]["FLAGS"], f[102]["FLAGS"]], [["\\Seen"], []], "IMAP : FLAGS")
        check_eq(f[101]["ENVELOPE"]["subject"], "été", "IMAP : ENVELOPE décodée")
        check_eq(f[101]["ENVELOPE"]["from"][0].email, "ada@x.org", "IMAP : adresses de l'ENVELOPE")
        mm := ic.fetch_message(103)
        check_eq(mm.text, "Données {5}\nfin\n", "IMAP : littéral contenant « {5} »")
        check_eq(ic.fetch_message(101).subject, "été", "IMAP : message complet")
        ic.add_flags([102], ["\\Seen", "\\Flagged"])
        ic.move([103], "Archives")
        ic.append("Été", m, ["\\Seen"])
        ev := ic.idle(5.0)
        check_eq(ev, ["4 EXISTS"], "IMAP : IDLE")
        ic.logout()
        ri := finish(si, "imap")
        check_eq(ri["flags"]["102"], ["\\Flagged", "\\Seen"], "IMAP : STORE")
        check_eq(ri["moved"], {"ids": [103], "to": "Archives"}, "IMAP : MOVE")
        check_eq(ri["appended"][0]["box"], "&AMk-t&AOk-", "IMAP : APPEND (nom encodé)")
        check(s.contains(ri["appended"][0]["data"], "Réunion") or s.contains(ri["appended"][0]["data"], "R=C3=A9union"), "IMAP : APPEND (littéral)")
        check_eq(ri["idle_done"], "DONE", "IMAP : fin d'IDLE")

    # FTP : deux sessions (FTPS explicite, puis en clair en mode actif)
    sf := start("ftp")
    fport := json.parse(sf[1])
    if have_tls:
        fc := ftp.FtpClient("127.0.0.1", fport, 10.0, "explicit", true, true, cert)
        fc.login("alice", "secret")
        check(fc.protect_data and fc.has_feature("MLST"), "FTP : AUTH TLS + PROT P + FEAT")
        check_eq(fc.pwd(), "/", "FTP : PWD")
        fc.cwd("pub")
        check_eq(fc.pwd(), "/pub", "FTP : CWD")
        es := fc.mlsd()
        names2 := []
        for e in es:
            append(names2, e.name + ":" + e.type + ":" + str(e.size))
        check_eq(names2, ["données.bin:file:2560", "lisezmoi.txt:file:12"], "FTP : MLSD (canal de données chiffré)")
        check_eq(fc.retrieve("lisezmoi.txt"), "Bonjour FTP\n", "FTP : RETR")
        bin := fc.retrieve("données.bin")
        check_eq([nu.byte_len(bin), nu.byte_at(bin, 255), nu.byte_at(bin, 256)], [2560, 255, 0], "FTP : RETR binaire")
        check_eq(fc.size("données.bin"), 2560, "FTP : SIZE")
        check(fc.mdtm("lisezmoi.txt") > 0, "FTP : MDTM")
        check_eq(fc.store("nouveau.txt", "contenu é"), 10, "FTP : STOR")
        fc.rename("nouveau.txt", "renommé.txt")
        fc.mkd("/pub/dossier")
        check_eq(fc.nlst(), ["données.bin", "dossier", "lisezmoi.txt", "renommé.txt"], "FTP : NLST")
        fc.delete("renommé.txt")
        check_eq(error_of(() => fc.retrieve("absent.txt")), "FtpError", "FTP : fichier absent -> 550")
        fc.quit()
    else:
        ftp.FtpClient("127.0.0.1", fport).quit()
    fa := ftp.FtpClient("127.0.0.1", fport, 10.0, "none", false)
    fa.login()
    check_eq(fa.retrieve("/pub/lisezmoi.txt"), "Bonjour FTP\n", "FTP : mode actif (EPRT), anonyme")
    local := "/tmp/alex_ftp_local.bin"
    io.write_bytes(local, [1, 2, 3, 4, 5])
    check_eq(fa.upload(local, "/pub/envoi.bin"), 5, "FTP : upload")
    fa.passive = true
    check_eq(fa.download("/pub/envoi.bin", "/tmp/alex_ftp_back.bin"), 5, "FTP : download (PASV/EPSV)")
    check_eq(io.read_bytes("/tmp/alex_ftp_back.bin"), [1, 2, 3, 4, 5], "FTP : aller-retour")
    fa.quit()
    rf := finish(sf, "ftp")
    check(not ("exception" in rf), "FTP : serveur sans erreur")
    check(rf["active"], "FTP : le serveur a vu le mode actif")
    if have_tls:
        check_eq(rf["prot"], "P", "FTP : PROT P")
        check("/pub/dossier" in rf["dirs"], "FTP : MKD")
else:
    print("test_mail_ftp : python3 absent, serveurs de référence ignorés")

print(f"mail_ftp : {stats[0]} vérifications OK, {stats[1]} échec(s)")
for n in notes:
    print("  ÉCHEC " + n)
if stats[1] > 0:
    raise("TestError", "test_mail_ftp : échecs")
