# ALEX STANDARD LIBRARY — multimedia
#
# Bibliothèque multimédia d'ALEX : API publique au-dessus des paquets audio, microphone et camera existants.
# Tout est écrit en ALEX ; les accès matériels passent par les outils du système (lecture, capture, caméra).
#
# | Module                          | Contenu                                                                   |
# |---------------------------------|---------------------------------------------------------------------------|
# | multimedia.core.*               | erreurs, Result, horodatages exacts, formats, Packet / Frame / RingBuffer, |
# |                                 | descriptions de pistes (StreamInfo, MediaInfo), annulation                 |
# | multimedia.container.*          | sondage (probe), démultiplexage et multiplexage WAV, étiquettes RIFF /     |
# |                                 | ID3 / FLAC                                                                 |
# | multimedia.codec.*              | registre des codecs et capacités déclarées                                 |
# | multimedia.image.*              | Image, décodage PNG / BMP / PNM, encodage, conversions, redimensionnement, |
# |                                 | métadonnées                                                                |
# | multimedia.pipeline.*           | nœuds, graphe, planificateur, contre-pression, reprise, horloges, synchro  |
# | multimedia.playback.*           | lecteur audio, listes M3U / PLS, recherche, sous-titres, commandes         |
# | multimedia.metadata.*           | étiquettes normalisées, chapitres, sous-titres SRT / WebVTT                |
# | multimedia.security.*           | limites de ressources, lecture bornée des données non fiables             |
# | multimedia.diagnostics.*        | mesures de performance, journal, capacités réelles de la machine           |
# | multimedia.codec.audio.flac     | décodeur FLAC en ALEX pur ; multimedia.container.ogg : conteneur Ogg       |
# | multimedia.audio.*              | rééchantillonnage sinc, spatialisation, sonie EBU R128                     |
# | multimedia.video.*              | images vidéo, mise à l'échelle, couleur, composition, cadence, capture,    |
# |                                 | lecteur vidéo synchronisé                                                  |
# | multimedia.recording.*          | enregistreur, microphone, capture d'écran, export / transcodage            |
# | multimedia.streaming.*          | flux AMS1 sur UDP / TCP, tampon de gigue, reconnexion                       |
# | multimedia.effects.*            | effets audio en continu, effets vidéo, transitions, montage                 |
# | multimedia.platform.*           | Linux, Windows, Android, ALEX OS : dorsaux et matrice de compatibilité      |
# | multimedia.backends.*           | ffmpeg (codecs, conteneurs), audio, vidéo, GPU du système                  |
# | multimedia.testing.*            | vérifications, faux périphériques, fichiers de test sains et hostiles      |
#
#   use multimedia
#   info := multimedia.probe("chanson.wav")
#   print(info.describe(), info.tags)
#   p := multimedia.player()
#   p.open("chanson.wav")
#   p.play()
#   p.run()
#   img := multimedia.load_image("photo.png")
#   multimedia.save_image(multimedia.thumbnail(img, 128), "vignette.png")
#   print(multimedia.capabilities())
#
# Voir docs/MULTIMEDIA.md.

use multimedia.container.probe as _probe
use multimedia.container.demux as _dmx
use multimedia.container.mux as _mux
use multimedia.image.decode as _idec
use multimedia.image.encode as _ienc
use multimedia.image.resize as _irs
use multimedia.metadata.subtitles as _subs
use multimedia.playback.player as _player
use multimedia.playback.playlist as _pl
use multimedia.diagnostics.capabilities as _caps
use multimedia.security.limits as _lim
use multimedia.video.playback as _vp
use multimedia.recording.recorder as _rec
use multimedia.recording.export as _ex
use multimedia.backends.codecs.ffmpeg as _ff

const VERSION := "1.0.0"

func probe(path, limits=null):
    return _probe.probe(path, limits)

func open(path, limits=null):
    return _dmx.open(path, limits)

func writer(path, fmt, tags=null):
    return _rec.open_destination(path, fmt, tags)

func player(output=null, limits=null):
    return _player.Player(output, limits)

func play(path, volume=1.0):
    return _player.play_file(path, volume)

func playlist(path):
    return _pl.load(path)

func load_image(path, limits=null):
    return _idec.load(path, limits)

func save_image(img, path, meta=null):
    return _ienc.save(img, path, meta)

func thumbnail(img, size=128):
    return _irs.thumbnail(img, size)

func load_subtitles(path):
    return _subs.load(path)

func capabilities():
    return _caps.report()

func limits(strict=false):
    if strict:
        return _lim.strict()
    return _lim.defaults()

func video_player(sink, audio_output=null, scaler=null, realtime=true):
    return _vp.VideoPlayer(sink, audio_output, scaler, realtime)

func recorder(source, fmt, path, tags=null):
    return _rec.Recorder(source, fmt, path, tags)

func convert(src, dst, fmt=null, progress=null):
    return _ex.transcode(src, dst, fmt, progress)

# Déclare les codecs du système (ffmpeg) dans le registre ; renvoie leur nombre (0 sans ffmpeg).
func install_system_codecs():
    return _ff.install()
