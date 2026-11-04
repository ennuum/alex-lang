# ALEX STANDARD LIBRARY — ui.view.theme
#
# Thèmes de ui.view : couleurs par rôle (« #rrggbb », nom de couleur du terminal, ou null = couleur par défaut
# du terminal). Le même thème sert à la fenêtre graphique et au terminal ; le thème "terminal" garde les
# couleurs du terminal de l'utilisateur (défaut en mode texte).
#
# Rôles : bg, surface (panneaux, dialogues), field (champs), text, muted, accent, accent_text (texte sur
# accent), border, selection, selection_text, danger, success, warning, disabled.
#
# Accent : le violet du logo d'ALEX (teinte 262°, #6a00fc), éclairci sur fond sombre pour rester lisible
# (contraste WCAG ≥ 4,5 de l'accent employé comme texte sur bg et surface, et du texte posé sur l'accent).

from core use type
from collections use contains_key, keys

const DARK := {"name": "dark", "bg": "#1a1b26", "surface": "#24283b", "field": "#16161e", "text": "#c0caf5", "muted": "#7a82a8", "accent": "#a57cff", "accent_text": "#16161e", "border": "#3b4261", "selection": "#3b2a6e", "selection_text": "#ede6ff", "danger": "#f7768e", "success": "#9ece6a", "warning": "#e0af68", "disabled": "#545c7e", "code_bg": "#16161e", "code_text": "#c0caf5", "gutter": "#16161e", "gutter_text": "#3b4261", "gutter_current": "#a9b1d6", "line_highlight": "#1f2335", "match": "#4b3591", "bracket": "#3b4261", "error_line": "#3a1f2a", "warning_line": "#3a301f", "syn_keyword": "#bb9af7", "syn_string": "#9ece6a", "syn_comment": "#565f89", "syn_number": "#ff9e64", "syn_function": "#7aa2f7", "syn_builtin": "#7dcfff", "syn_constant": "#ff9e64", "syn_type": "#e0af68", "syn_op": "#89ddff"}

const LIGHT := {"name": "light", "bg": "#f6f7fb", "surface": "#ffffff", "field": "#ffffff", "text": "#1f2335", "muted": "#6b7089", "accent": "#6a1fe6", "accent_text": "#ffffff", "border": "#c9cde0", "selection": "#e9ddff", "selection_text": "#24104a", "danger": "#d0364c", "success": "#2e8b3e", "warning": "#b8730c", "disabled": "#a5a9bd", "code_bg": "#ffffff", "code_text": "#1f2335", "gutter": "#f6f7fb", "gutter_text": "#a5a9bd", "gutter_current": "#1f2335", "line_highlight": "#eef2fb", "match": "#fde68a", "bracket": "#dbe2f3", "error_line": "#fde2e4", "warning_line": "#fdf2d8", "syn_keyword": "#7c3aed", "syn_string": "#2e7d32", "syn_comment": "#8a8fa3", "syn_number": "#c2410c", "syn_function": "#1d4ed8", "syn_builtin": "#0e7490", "syn_constant": "#c2410c", "syn_type": "#a16207", "syn_op": "#0369a1"}

const TERMINAL := {"name": "terminal", "bg": null, "surface": null, "field": null, "text": null, "muted": "bright_black", "accent": "bright_magenta", "accent_text": "black", "border": "bright_black", "selection": "magenta", "selection_text": "bright_white", "danger": "red", "success": "green", "warning": "yellow", "disabled": "bright_black", "code_bg": null, "code_text": null, "gutter": null, "gutter_text": "bright_black", "gutter_current": "white", "line_highlight": null, "match": "yellow", "bracket": "bright_black", "error_line": "red", "warning_line": "yellow", "syn_keyword": "magenta", "syn_string": "green", "syn_comment": "bright_black", "syn_number": "yellow", "syn_function": "blue", "syn_builtin": "cyan", "syn_constant": "yellow", "syn_type": "yellow", "syn_op": "cyan"}

# Thème d'ALEX Studio : nuit violette et dégradé violet → magenta du logo (#6a00fc, #7e00ff).
const STUDIO := {"name": "studio", "bg": "#0b0716", "surface": "#140d26", "field": "#0f0a1e", "text": "#e4ddf7", "muted": "#8b80ad", "accent": "#a57cff", "accent_text": "#0b0716", "border": "#2a1f47", "selection": "#3a2470", "selection_text": "#f3eeff", "danger": "#ff5c7a", "success": "#3ddc97", "warning": "#ffc25a", "disabled": "#4f4570", "code_bg": "#0d0919", "code_text": "#e4ddf7", "gutter": "#0d0919", "gutter_text": "#4a3d6e", "gutter_current": "#c2b5e6", "line_highlight": "#160f2b", "match": "#4b2f8f", "bracket": "#3a2a63", "error_line": "#2a1222", "warning_line": "#2a2414", "syn_keyword": "#a57cff", "syn_string": "#7fe0a7", "syn_comment": "#74699c", "syn_number": "#ffb86c", "syn_function": "#e08cff", "syn_builtin": "#c9a8ff", "syn_constant": "#ff9f6e", "syn_type": "#7fd4ff", "syn_op": "#b7a6ff", "exec_line": "#3a2f0e", "exec_arrow": "#ffc25a", "breakpoint": "#ff4d6d", "word_highlight": "#2a1d52", "tooltip": "#120c22", "menubar": "#0f0a1e", "header": "#140d26", "tabbar": "#0d0919", "hover": "#221640", "accent2": "#7e00ff"}
const STUDIO_LIGHT := {"name": "studio_light", "bg": "#f7f5fd", "surface": "#ffffff", "field": "#ffffff", "text": "#1b1433", "muted": "#6a6189", "accent": "#6a1fe6", "accent_text": "#ffffff", "border": "#ddd5f0", "selection": "#e9ddff", "selection_text": "#24104a", "danger": "#d42f50", "success": "#1f8f5c", "warning": "#b8730c", "disabled": "#aaa3c2", "code_bg": "#ffffff", "code_text": "#1b1433", "gutter": "#f9f7fe", "gutter_text": "#aaa3c2", "gutter_current": "#1b1433", "line_highlight": "#f3eefd", "match": "#fde68a", "bracket": "#e4dbf7", "error_line": "#fde3e8", "warning_line": "#fdf2d8", "syn_keyword": "#5b16d8", "syn_string": "#15803d", "syn_comment": "#8a84a3", "syn_number": "#c2410c", "syn_function": "#a21caf", "syn_builtin": "#0e7490", "syn_constant": "#c2410c", "syn_type": "#1d4ed8", "syn_op": "#4c3a8a", "exec_line": "#fff4cc", "exec_arrow": "#c68a00", "breakpoint": "#e0244a", "word_highlight": "#ece4fd", "tooltip": "#ffffff", "menubar": "#ffffff", "header": "#ffffff", "tabbar": "#f1edf9", "hover": "#efe8fc", "accent2": "#7e00ff"}

# Thème par son nom ("dark", "light", "terminal") ou dict (les rôles absents viennent de base).
func resolve(theme, fallback="dark"):
    if theme == null:
        theme = fallback
    if type(theme) == "str":
        if theme == "dark":
            return DARK
        if theme == "light":
            return LIGHT
        if theme == "terminal":
            return TERMINAL
        if theme == "studio":
            return STUDIO
        if theme == "studio_light":
            return STUDIO_LIGHT
        raise("ArgumentError", "ui.view : thème inconnu '" + theme + "' (dark, light, terminal, studio, studio_light)")
    if type(theme) != "dict":
        raise("TypeError", "ui.view : thème (nom ou dict) attendu")
    base := DARK
    if contains_key(theme, "base"):
        base = resolve(theme["base"])
    out := {}
    for k in keys(base):
        out[k] = base[k]
    for k in keys(theme):
        out[k] = theme[k]
    return out

# Rôles dérivés : à défaut d'une couleur propre dans le thème, celle d'un rôle de base.
const DERIVED := {"button": "border", "button_primary": "selection", "field_focus": "selection", "field_disabled": "bg", "selection_focus": "accent", "selection_focus_text": "accent_text", "header": "surface", "header_text": "accent", "menubar": "surface", "menubar_text": "text", "tabbar": "bg", "hover": "selection", "accent_hover": "accent", "accent_pressed": "accent", "track": "border", "focus_bg": "selection", "shadow": "field", "code_bg": "field", "code_text": "text", "gutter": "field", "gutter_text": "muted", "gutter_current": "text", "line_highlight": "surface", "match": "selection", "bracket": "border", "error_line": "danger", "warning_line": "warning", "syn_keyword": "accent", "syn_string": "success", "syn_comment": "muted", "syn_number": "warning", "syn_function": "accent", "syn_builtin": "accent", "syn_constant": "warning", "syn_type": "warning", "syn_op": "text", "exec_line": "warning_line", "exec_arrow": "warning", "breakpoint": "danger", "word_highlight": "line_highlight", "tooltip": "surface", "squiggle_error": "danger", "squiggle_warning": "warning", "squiggle_info": "accent", "accent2": "accent"}

# Couleur d'un rôle dans un thème résolu (null : couleur par défaut du terminal).
func color(theme, role):
    if contains_key(theme, role):
        return theme[role]
    if contains_key(DERIVED, role):
        return color(theme, DERIVED[role])
    return theme["text"]
