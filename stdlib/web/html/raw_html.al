# ALEX STANDARD LIBRARY — web.html.raw_html
#
# RawHtml : balisage DE CONFIANCE inséré tel quel, sans échappement (un fragment produit par un autre moteur, un
# SVG en ligne, un widget). C'est la seule façon d'insérer du HTML non échappé : à ne jamais utiliser avec une
# donnée fournie par un utilisateur (risque XSS) — pour cela, analyser puis assainir (web.html.html_parser).
#
#   use web.html.raw_html as raw
#   r := raw.RawHtml("<svg viewBox=\"0 0 10 10\"><circle cx=\"5\" cy=\"5\" r=\"4\"/></svg>")
#   r.to_html()                  # le balisage, inchangé
#   raw.trusted(markup)          # synonyme explicite
#   raw.nbsp()                   # &nbsp;
#
# text_content() rend le texte approximatif (balises retirées).

from core use len, type
use web.html.html_escape as _esc

const NODE_TYPE := "raw"

class RawHtml:
    func init(markup=""):
        self.node_type = NODE_TYPE
        self.markup = str(markup)
        self.parent = null

    func to_html():
        return self.markup

    func text_content():
        return _esc.strip_tags(self.markup)

    func clone():
        return RawHtml(self.markup)

    func __str__():
        return self.markup

    func __eq__(other):
        return isinstance(other, RawHtml) and other.markup == self.markup

func raw(markup):
    return RawHtml(markup)

func trusted(markup):
    return RawHtml(markup)

# Référence de caractère nommée (« nbsp », « copy »...) comme balisage.
func entity(name):
    if _esc.entity(name) == null:
        raise("HtmlError", "raw_html.entity : référence inconnue « " + str(name) + " »")
    return RawHtml("&" + name + ";")

func nbsp():
    return RawHtml("&nbsp;")
