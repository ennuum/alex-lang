# Configuration de {{Nom}} : identité, fenêtre, emplacement des données de l'utilisateur.
use os

const NOM := "{{Nom}}"
const IDENTIFIANT := "{{nom}}"
const VERSION := "0.1.0"
const LARGEUR := 720
const HAUTEUR := 480

# Dossier des données : %APPDATA%\{{nom}} (Windows), $XDG_DATA_HOME/{{nom}} ou ~/.local/share/{{nom}} (Linux).
func dossier_donnees():
    if os.platform() == "windows":
        base := os.getenv("APPDATA", "")
        if base != "":
            return os.join(base, IDENTIFIANT)
    xdg := os.getenv("XDG_DATA_HOME", "")
    if xdg != "":
        return os.join(xdg, IDENTIFIANT)
    return os.join(os.home(), ".local", "share", IDENTIFIANT)

func fichier_donnees():
    return os.join(dossier_donnees(), "taches.json")
