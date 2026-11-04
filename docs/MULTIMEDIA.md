# Bibliothèque multimédia : `multimedia`

API multimédia d'ALEX, écrite **en ALEX**, au-dessus des paquets existants `audio`, `microphone`, `camera`
(docs/MEDIA.md). Elle réalise les **sept phases** du document d'architecture « ALEX audio, vidéo, multimédia ».
Les codecs compressés autres que FLAC (MP3, AAC, Opus, Vorbis, H.264, VP9, AV1, JPEG…) passent par un
**adaptateur système isolé** vers ffmpeg, comme le prévoit le document (« adaptateurs natifs isolés pour les
codecs ») : ils sont déclarés d'origine « système », ne fonctionnent que si ffmpeg est installé, et lèvent sinon
une `UnsupportedError` explicite. Rien n'est simulé.

```
use multimedia
info := multimedia.probe("chanson.flac")          # conteneur, pistes, durée, étiquettes, décodable ?
p := multimedia.player()                          # sortie : lecteur du système (aplay, pw-play, paplay, ffplay)
p.open("chanson.flac")
p.play()
p.run()
v := multimedia.video_player((f) => afficher(f.image), sortie_audio)
v.open("film.mp4")                                # vidéo : adaptateur ffmpeg, synchronisée sur le son
multimedia.convert("concert.flac", "concert.opus") # transcodage
print(multimedia.capabilities())                  # ce que la machine permet réellement
```

Outils : `alexc run tools/alex-media/alex-media.al -- probe | convert | record | benchmark | capabilities`.
Exemples (`examples/multimedia/`) : `audio_player`, `audio_recorder`, `video_player`, `webcam_preview`,
`screen_recorder`, `media_converter`, `live_stream`, `media_info.al`, `audio_converter.al`.
Tests : `make test-multimedia` (15 suites, ~3 min) ; `make test-multimedia-display` (capture d'écran réelle sous
Xvfb ; sous Windows, `tests/multimedia/test_screen.al` capture le bureau) ; `ALEX_MEDIA_REAL=1` ajoute aux tests
`tests/media` la vraie carte son (bip court), le vrai micro (1 s) et la vraie caméra (une image).

## Ce qui est pris en charge

| Domaine | En ALEX pur | Par l'adaptateur système (ffmpeg) | Non pris en charge |
|---|---|---|---|
| Conteneurs (lecture) | WAV / RIFF (PCM, EXTENSIBLE, LIST/INFO, tronqué), FLAC natif (fenêtres, SEEKTABLE, recherche exacte), Ogg (pages, CRC, resynchronisation, multi-flux, dichotomie) | MP4 / MOV / M4A, Matroska / WebM, AVI, MPEG-TS, AIFF, MP3… | RF64 natif |
| Conteneurs (écriture) | WAV progressif + étiquettes, **FLAC** (STREAMINFO complété à la fermeture), **Ogg** (pages, segments, débordement, granules, CRC) et **Ogg FLAC** (`.oga`) | Ogg Vorbis, Opus, MP3, M4A, MP4, WebM, MKV… | — |
| Codecs audio | PCM, **FLAC** (décodage bit à bit exact, CRC, MD5 ; **encodage** sans perte : prédicteurs fixes, stéréo décorrélée, Rice partitionné, MD5 — l'équivalent de `flac -1`), **G.711** loi µ / loi A (RTP) | MP3, AAC, Opus, Vorbis, Speex, ALAC, AC-3… (décodage) ; MP3, AAC, Opus, Vorbis (encodage) | encodeur FLAC à prédiction linéaire (LPC) |
| Vidéo | formats, YUV ↔ RGB (BT.601 / 709, plages), mise à l'échelle, composition, cadence, synchronisation A/V, effets, transitions, montage | décodage H.264, HEVC, VP8 / VP9, AV1, Theora, MJPEG… ; encodage H.264, VP9, Theora, MPEG-4 | décodeur vidéo en ALEX pur |
| Images | PNG (tous types, Adam7, 16 bits), BMP, PNM (lecture et écriture), métadonnées | JPEG, GIF, WebP, TIFF (décodage) | — |
| Sous-titres, listes, chapitres | SRT, WebVTT, M3U / M3U8, PLS, chapitres texte et OGM | — | ASS / SSA, XSPF |
| Capture | microphone (outils du système), caméra (paquet camera), sources factices | mire de test, capture d'écran (x11grab, gdigrab, avfoundation), micro et caméra DirectShow (Windows), images d'un fichier | Wayland natif |
| Streaming | **RTP** (RFC 3550 ; L16, L24, PCMU, PCMA ; SDP) et flux AMS1, sur UDP (et TCP pour AMS1), tampon de gigue, reconnexion | — | RTCP, RTSP, HLS |
| Accélération | — | détection des hwaccels ffmpeg (vaapi, cuda, qsv…), options explicites | activation implicite |

## Modules

| Module | Contenu |
|---|---|
| `multimedia` | façade : probe, open, writer, player, play, video_player, recorder, convert, playlist, load_image, save_image, thumbnail, load_subtitles, capabilities, limits, install_system_codecs |
| **core** `errors`, `result`, `timestamp`, `format`, `buffer`, `stream`, `cancellation` | erreurs typées, Result, temps rationnel exact, formats audio / vidéo, Packet / Frame / RingBuffer, StreamInfo / MediaInfo, annulation |
| **audio** `audio`, `resampler`, `spatial`, `meter` | façade vers le paquet audio ; rééchantillonnage sinc polyphasé (rapport rationnel exact, continu) ; panoramique, largeur, 3D (ITD / ILD, distance) ; crête vraie, RMS, sonie EBU R128 (I, M, S, LRA) |
| **video** `frame`, `video_format`, `scaler`, `color`, `compositor`, `frame_rate`, `device`, `capture`, `playback` | VideoFrame, letterbox / fill, YCbCr, plans yuv420p / nv12 / yuyv422, calques et vignette, conversion de cadence sans dérive, caméras, capture (caméra, mire, fichier, factice), VideoPlayer synchronisé |
| **image** `image`, `decode`, `encode`, `resize`, `convert`, `metadata` | Image, PNG / BMP / PNM, redimensionnement, conversions, métadonnées |
| **codec** `registry`, `capabilities`, `audio/flac`, `audio/flac_encoder` | registre intégré / système / optionnel avec notes de licence ; décodeur et encodeur FLAC |
| **container** `probe`, `demux`, `mux`, `metadata`, `flac_demux`, `ogg`, `ogg_mux` | identification par signature, démultiplexeurs WAV / FLAC / Ogg (repli ffmpeg), multiplexeurs WAV / FLAC / Ogg FLAC (`mux.open` d'après l'extension), écrivain de pages Ogg pour tout codec, RIFF INFO / ID3 / FLAC |
| **pipeline** `node`, `graph`, `scheduler`, `clock`, `sync`, `backpressure`, `recovery` | graphe borné, planificateur coopératif, horloges, AVSync |
| **playback** `player`, `playlist`, `seek`, `subtitles`, `controls` | lecteur audio, listes, recherche, sous-titres synchronisés, états, volume sans clic |
| **recording** `recorder`, `microphone`, `screen_capture`, `export` | enregistreur (durée, silence, vumètre), micro, écran, transcodage, export de montage et d'images |
| **streaming** `rtp`, `source`, `sink`, `buffering`, `network_stream`, `live` | RTP standard (émetteur, récepteur, SDP, G.711, séquence étendue à 32 bits) ; AMS1 (CRC-32), émetteurs / récepteurs UDP, TCP, mémoire ; gigue ; session avec reconnexion exponentielle |
| **effects** `audio_effect`, `video_effect`, `transitions`, `timeline` | biquads (Audio EQ Cookbook), égaliseur, écho, compresseur, limiteur à anticipation, porte ; flou, netteté, Sobel, sépia, vignettage, pixellisation ; fondus, volets, dissolution, glissement ; montage audio / vidéo |
| **metadata** `tags`, `chapters`, `subtitles` | étiquettes normalisées, chapitres, SRT / WebVTT |
| **platform** `platform`, `linux`, `windows`, `android`, `alex_os` | détection, dorsaux, matrice de compatibilité |
| **backends** `codecs/ffmpeg`, `audio/system`, `video/system`, `gpu/gpu` | adaptateur ffmpeg (sondage, décodeurs, encodeurs, mire, démultiplexeur), sorties / entrées audio, sources vidéo, accélérations |
| **security** `limits`, `validation`, `sandbox` | limites vérifiées avant allocation, lecture bornée, analyse dans un processus isolé |
| **diagnostics** `metrics`, `logging`, `capabilities` | mesures, journal, capacités réelles |
| **testing** `assertions`, `fake_device`, `fixtures` | Checker, faux périphériques, fichiers sains et hostiles |

## Vérification

Chaque décodeur est comparé à une référence **indépendante** :

- images : 35 fichiers Pillow / ImageMagick, points de référence extraits par ImageMagick ;
- WAV : 21 fichiers ffmpeg, échantillons décodés par ffmpeg ; les WAV écrits sont relus par ffprobe ;
- FLAC : 22 fichiers ffmpeg (niveaux 0 à 12, 4 modes stéréo, 16 / 24 / 32 bits, 1 à 6 canaux, LPC d'ordre 32,
  blocs de 192 et 1000), **identiques au bit près**, MD5 vérifié ; un FLAC écrit par ffmpeg est relu par le
  décodeur ALEX et comparé au décodage de ffmpeg ;
- Ogg : 7 fichiers comparés à ffprobe (codecs, fréquences, canaux, dimensions, durées, étiquettes) ; Ogg FLAC
  identique au bit près, y compris après recherche par dichotomie. Écarts assumés : durée Opus sans le pre-skip
  (RFC 7845, ffprobe ne le retire pas), durée Speex d'après la granule écrite ;
- sonie : intégrée et LRA à 0,15 LU / 0,3 LU du filtre `ebur128` de ffmpeg sur 3 signaux ;
- couleur : plans yuv420p / nv12 / yuyv422 convertis à 4 niveaux près de swscale (intérieur des aplats) ;
- encodeur FLAC : 18 cas (1 à 8 canaux, 8 à 32 bits, constante, silence, bruit blanc en verbatim, bits perdus,
  fréquences hors table, blocs de 5 à 4096) relus **au bit près** par le décodeur ALEX (MD5 compris) et par
  ffmpeg, sans aucun avertissement ; plus compact que `ffmpeg -compression_level 1` sur un signal musical ;
- Ogg et Ogg FLAC écrits : pages relues par le démultiplexeur (CRC, segments nuls, paquet sur deux pages,
  granules), Ogg FLAC décodé à l'identique par ALEX et par ffmpeg ; WAV → FLAC → Ogg FLAC → WAV identique ;
- RTP : ffmpeg → ALEX (L16 type 10 au bit près, PCMU type 0), ALEX → ffmpeg par SDP (L16 type 96 au bit près),
  G.711 sur les valeurs de référence et les 256 codes, perte / désordre / doublon / bouclage simulés ;
- capture d'écran : réelle sous Xvfb (Linux) et par gdigrab (Windows), vidéo relue par ffprobe ;
- Windows 11 : carte son Realtek (lecture par ffplay), réseau de micros Intel (DirectShow, durée exacte à
  l'échantillon), caméra HP HD (image de 320 × 240) ;
- robustesse : 30 fichiers hostiles, 300 mutations WAV / PNG, 60 FLAC, 40 Ogg : seules des erreurs
  multimédias, jamais d'erreur interne ni d'allocation non bornée.

## Performances

Mesurées par `alex-media benchmark` et des mesures ciblées, machine virtuelle ALEX, un cœur. Deux machines :
la VM de test Linux d'origine, et un PC portable Windows 11 (plus rapide : comparer les colonnes entre elles
seulement ligne à ligne).

| Traitement | VM Linux (avant) | Windows 11, avant | Windows 11, après |
|---|---|---|---|
| Décodage FLAC 44,1 kHz stéréo 16 bits | 1,5× le temps réel | 2,3× | 2,3× |
| Encodage FLAC 44,1 kHz stéréo 16 bits (sans / avec MD5) | — | — | 1,2× / 0,6× |
| Rééchantillonnage sinc 32 points 44,1 → 48 kHz, mono (traitement seul) | 0,8× | 1,8× | **14,5×** |
| Rééchantillonnage sinc 32 points 44,1 → 48 kHz, stéréo (traitement seul) | — | 0,8× | **4,1×** |
| Rééchantillonnage, 1 s mono, table polyphasée comprise (banc) | 0,8× | 1,25× | 4,7× |
| Démultiplexage WAV 11 kHz stéréo | 37× | 20× | 11× à 20× |
| Décodage PNG 128 × 128 RGBA | 0,11 Mpoint / s | 0,17 | 0,17 |
| Sonie EBU R128 mono 44,1 kHz | 4× | 6,9× | 7,1× |
| MD5 (crypto) | — | 30 Ko / s | 64 Ko / s |

Le gain du rééchantillonnage vient du produit scalaire **natif** `_native_math.dot` (runtime) : un appel par
échantillon de sortie au lieu de 32 multiplications-additions interprétées, même somme dans le même ordre (résultats
inchangés) ; les tables polyphasées sont en outre partagées entre rééchantillonneurs de même rapport. Le MD5
réécrit (blocs sans branchement, version incrémentale `crypto.Md5`) double son débit. Le décodage FLAC reste en
ALEX interprété (le temps est dans le décodage de Rice et les prédicteurs, le CRC n'en prend que 8 %).
Conséquences : le rééchantillonnage sinc tient désormais le temps réel en stéréo ; la lecture FLAC stéréo 16 bits
aussi ; l'encodage FLAC avec MD5 et le FLAC 48 kHz / 24 bits stéréo restent à préparer à l'avance sur une
machine lente.

## Matrice de compatibilité

| Plateforme | État |
|---|---|
| Linux | **validé** : tout `make test-multimedia` (ALEX pur, ffmpeg, UDP / TCP, processus isolé) ; capture d'écran sous Xvfb ; sortie et entrée audio validées avec des périphériques factices (pas de carte son ici), caméra non validée (aucune caméra) |
| Windows | **validé** sur Windows 11 x64 avec ffmpeg 9 (`winget install Gyan.FFmpeg`) : toutes les suites `tests/multimedia` et `tests/media`, plus **carte son, micro, caméra et écran réels** (`ALEX_MEDIA_REAL=1`). Micro et caméra par DirectShow (`hardware._windows` : liste de ffmpeg, noms internes ASCII), cartes son par WMI, lecture par ffplay sur la sortie par défaut. Le bac à sable n'y applique que le délai et l'environnement (voir les limites) |
| macOS | dorsaux écran / caméra par avfoundation écrits, **non validés** |
| Android | ALEX pur portable ; dorsaux AAudio / Camera2 / MediaCodec **non écrits** (UnsupportedError) |
| ALEX OS | ALEX pur portable (décodeurs WAV / FLAC / Ogg FLAC / PNG / BMP / PNM) ; son, caméra non branchés |
| iOS | non pris en charge (aucune chaîne de construction) |

## Sécurité et licences

- Tout fichier externe passe par `security.limits` (taille, durée, dimensions, points, pistes, canaux, fréquence,
  blocs, texte, entrées de liste) **avant** allocation ; les décodeurs ALEX lisent par `security.validation`.
- `security.sandbox.isolated_probe` / `isolated_check` analysent un fichier dans un processus fils limité (temps
  processeur, mémoire, délai, sans réseau) : un décodeur qui plante ou boucle ne touche pas le programme.
- L'adaptateur ffmpeg vérifie la description ffprobe contre les limites avant de décoder.
- Licences : les codecs à brevets possibles (H.264, HEVC, AAC) portent une note dans le registre ; ffmpeg est un
  outil externe, sa licence (LGPL / GPL selon la compilation) s'applique à sa distribution, pas à la bibliothèque.

## Limites connues

- Aucun décodeur vidéo ni codec audio avec perte **en ALEX pur** : sans ffmpeg, seuls PCM, FLAC et G.711 se
  décodent ; Ogg Vorbis / Opus s'écrivent par ffmpeg.
- Encodeur FLAC sans prédiction linéaire (LPC) : environ 5 % plus gros que `flac -5`. Le MD5 de STREAMINFO coûte
  autant que l'encodage (`md5=false` l'omet, ce que la RFC permet).
- Streaming : RTP sans RTCP (rapports de réception, synchronisation de plusieurs flux), ni RTSP ni HLS ; la
  réception et l'émission sont coopératives, dans un seul fil.
- Windows : `security.sandbox` n'y pose ni limite mémoire / processeur ni isolement réseau (pas de `ulimit` ni
  d'`unshare` ; il faudrait des objets de tâche Windows dans le runtime) ; `enforced` le dit.
- macOS, Android, ALEX OS : non validés (voir la matrice) ; iOS non pris en charge.
