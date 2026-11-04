# ALEX STANDARD LIBRARY — web.html.comment_node
#
# CommentNode : commentaire HTML « <!-- … --> ». Le contenu est neutralisé au rendu (« -- » et « > » initial)
# pour qu'un commentaire ne puisse jamais se fermer avant sa fin ni injecter de balisage.
#
#   use web.html.comment_node as cn
#   c := cn.CommentNode(" généré par Alex ")
#   c.to_html()                    # <!-- généré par Alex -->
#   cn.CommentNode("a --> b").to_html()   # <!--a - -> b-->
#   cn.conditional("lt IE 9", "<script src=\"html5shiv.js\"></script>")   # commentaire conditionnel historique

from core use len, type
use web.html.html_escape as _esc

const NODE_TYPE := "comment"

class CommentNode:
    func init(text=""):
        self.node_type = NODE_TYPE
        self.text = str(text)
        self.parent = null

    func to_html():
        return "<!--" + _esc.escape_comment(self.text) + "-->"

    # Un commentaire ne contribue pas au texte du document.
    func text_content():
        return ""

    func clone():
        return CommentNode(self.text)

    func __str__():
        return self.to_html()

    func __eq__(other):
        return isinstance(other, CommentNode) and other.text == self.text

func comment(text):
    return CommentNode(text)

# Commentaire conditionnel d'Internet Explorer (pages héritées) : <!--[if condition]>…<![endif]-->.
func conditional(condition, markup):
    c := CommentNode("")
    c.text = "[if " + condition + "]>" + markup + "<![endif]"
    return c
