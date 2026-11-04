# ALEX STANDARD LIBRARY — web.html.text_node
#
# TextNode : texte d'un document HTML. Le texte est gardé DÉCODÉ (« a < b ») et échappé au rendu (« a &lt; b ») :
# du texte fourni par un utilisateur ne peut donc jamais devenir du balisage.
#
#   use web.html.text_node as tn
#   t := tn.TextNode("Tom & Jerry <3")
#   t.to_html()              # Tom &amp; Jerry &lt;3
#   t.text_content()         # Tom & Jerry <3
#   t.is_whitespace()        # false
#
# Dans un élément à texte brut (script, style), le serializer n'échappe pas le texte mais neutralise la balise
# fermante (web.html.html_escape.escape_script / escape_style).

from core use len, type
use string as _s
use web.html.html_escape as _esc

const NODE_TYPE := "text"

class TextNode:
    func init(text=""):
        self.node_type = NODE_TYPE
        self.text = text if type(text) == "str" else str(text)
        self.parent = null

    func to_html():
        return _esc.escape_text(self.text)

    func text_content():
        return self.text

    func set_text(text):
        self.text = str(text)
        return self

    # Vrai si le texte ne contient que des espaces (espace, tabulation, sauts de ligne, saut de page).
    func is_whitespace():
        for c in self.text:
            if not (c == ' ' or c == '\t' or c == '\n' or c == '\r' or _s.ord(c) == 12):
                return false
        return true

    func is_empty():
        return len(self.text) == 0

    func clone():
        return TextNode(self.text)

    func __str__():
        return self.to_html()

    func __eq__(other):
        return isinstance(other, TextNode) and other.text == self.text

func text(value):
    return TextNode(value)

# Texte aux espaces fusionnés (« a \n  b » -> « a b »), comme le rendu d'un navigateur hors <pre>.
func collapse_whitespace(text):
    out := []
    space := false
    for c in text:
        if c == ' ' or c == '\t' or c == '\n' or c == '\r' or _s.ord(c) == 12:
            if not space:
                out = out + [" "]
            space = true
        else:
            out = out + [str(c)]
            space = false
    return _s.join("", out)
