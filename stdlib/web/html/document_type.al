# ALEX STANDARD LIBRARY — web.html.document_type
#
# DocumentType : la déclaration « <!DOCTYPE html> » (WHATWG HTML §13.1.1). Un document HTML5 n'a besoin que de
# celle-ci ; les identifiants publics / système des anciennes versions sont reconnus à l'analyse pour déterminer le
# mode de rendu (standards, presque standards, quirks).
#
#   use web.html.document_type as dt
#   dt.html5().to_html()                       # <!DOCTYPE html>
#   d := dt.DocumentType("html", "-//W3C//DTD HTML 4.01 Transitional//EN")
#   d.mode()                                    # quirks (pas d'identifiant système)
#   d.is_html5()                                # false

from core use len, type
use string as _s

const NODE_TYPE := "doctype"

const STANDARDS := "standards"
const LIMITED_QUIRKS := "limited-quirks"
const QUIRKS := "quirks"

const _QUIRKS_PREFIXES := ["+//silmaril//dtd html pro v0r11 19970101//", "-//as//dtd html 3.0 aswedit + extensions//", "-//advasoft ltd//dtd html 3.0 aswedit + extensions//", "-//ietf//dtd html 2.0", "-//ietf//dtd html 3", "-//ietf//dtd html level", "-//ietf//dtd html strict", "-//ietf//dtd html//", "-//metrius//dtd metrius presentational//", "-//microsoft//dtd internet explorer", "-//netscape comm. corp.//dtd", "-//o'reilly and associates//dtd html", "-//softquad", "-//spyglass//dtd html 2.0 extended//", "-//sun microsystems corp.//dtd hotjava html//", "-//w3c//dtd html 3", "-//w3c//dtd html 4.0 frameset//", "-//w3c//dtd html 4.0 transitional//", "-//w3c//dtd html experimental", "-//w3c//dtd w3 html//", "-//w3o//dtd w3 html", "-//webtechs//dtd mozilla html"]

class DocumentType:
    func init(name="html", public_id="", system_id=""):
        self.node_type = NODE_TYPE
        self.name = _s.lower(name)
        self.public_id = public_id if public_id != null else ""
        self.system_id = system_id if system_id != null else ""
        self.parent = null

    func is_html5():
        return self.name == "html" and self.public_id == "" and (self.system_id == "" or self.system_id == "about:legacy-compat")

    # Mode de rendu qu'un navigateur choisirait (WHATWG §13.2.6.4.1, simplifié aux cas usuels).
    func mode():
        if self.name != "html":
            return QUIRKS
        p := _s.lower(self.public_id)
        if p == "-//w3o//dtd w3 html strict 3.0//en//" or p == "-/w3c/dtd html 4.0 transitional/en" or p == "html":
            return QUIRKS
        for prefix in _QUIRKS_PREFIXES:
            if _s.starts_with(p, prefix):
                return QUIRKS
        if self.system_id == "" and (_s.starts_with(p, "-//w3c//dtd html 4.01 frameset//") or _s.starts_with(p, "-//w3c//dtd html 4.01 transitional//")):
            return QUIRKS
        if _s.starts_with(p, "-//w3c//dtd xhtml 1.0 frameset//") or _s.starts_with(p, "-//w3c//dtd xhtml 1.0 transitional//"):
            return LIMITED_QUIRKS
        if self.system_id != "" and (_s.starts_with(p, "-//w3c//dtd html 4.01 frameset//") or _s.starts_with(p, "-//w3c//dtd html 4.01 transitional//")):
            return LIMITED_QUIRKS
        return STANDARDS

    func to_html():
        out := "<!DOCTYPE " + self.name
        if self.public_id != "":
            out = out + " PUBLIC \"" + self.public_id + "\""
            if self.system_id != "":
                out = out + " \"" + self.system_id + "\""
        elif self.system_id != "":
            out = out + " SYSTEM \"" + self.system_id + "\""
        return out + ">"

    func text_content():
        return ""

    func clone():
        return DocumentType(self.name, self.public_id, self.system_id)

    func __str__():
        return self.to_html()

    func __eq__(other):
        return isinstance(other, DocumentType) and other.name == self.name and other.public_id == self.public_id and other.system_id == self.system_id

func html5():
    return DocumentType("html")

# Analyse le contenu d'une déclaration (« html PUBLIC "…" "…" », sans « <!DOCTYPE » ni « > »).
func parse(text):
    t := _s.trim(text)
    words := []
    cur := ""
    quote := null
    for c in t:
        if quote != null:
            if c == quote:
                words = words + [cur]
                cur = ""
                quote = null
            else:
                cur = cur + str(c)
        elif c == '"' or c == '\'':
            quote = c
        elif c == ' ' or c == '\t' or c == '\n' or c == '\r':
            if cur != "":
                words = words + [cur]
                cur = ""
        else:
            cur = cur + str(c)
    if cur != "":
        words = words + [cur]
    if len(words) == 0:
        return DocumentType("html")
    name := words[0]
    if len(words) >= 3 and _s.upper(words[1]) == "PUBLIC":
        sys := words[3] if len(words) >= 4 else ""
        return DocumentType(name, words[2], sys)
    if len(words) >= 3 and _s.upper(words[1]) == "SYSTEM":
        return DocumentType(name, "", words[2])
    return DocumentType(name)
