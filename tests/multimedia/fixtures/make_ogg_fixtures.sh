#!/bin/sh
# Corpus Ogg pour tests/multimedia/test_ogg.al, produit par ffmpeg. Pour chaque fichier, <nom>.json donne la
# description de référence par ffprobe (pistes, codecs, fréquences, canaux, durées, étiquettes) ; pour l'Ogg FLAC,
# <nom>.pcm contient les échantillons décodés par ffmpeg (entiers 32 bits petit-boutistes).
# Relancer : sh tests/multimedia/fixtures/make_ogg_fixtures.sh
set -eu
D=$(dirname "$0")/ogg
rm -rf "$D"; mkdir -p "$D"
F="ffmpeg -hide_banner -loglevel error -y"
MUS="aevalsrc=0.5*sin(2*PI*440*t)+0.3*sin(2*PI*1234*t*t)|0.4*sin(2*PI*660*t)+0.2*sin(2*PI*90*t)"
META="-metadata title=Essai -metadata artist=ALEX -metadata album=Ogg"
$F -f lavfi -i "$MUS" -t 2.0 -ar 22050 -ac 2 -sample_fmt s16 $META -c:a flac -page_duration 100000 -f ogg "$D/flac.oga"
$F -i "$D/flac.oga" -f s32le -c:a pcm_s32le "$D/flac.pcm"
$F -f lavfi -i "$MUS" -t 0.5 -ar 8000 -ac 1 -sample_fmt s16 -c:a flac -frame_size 512 -f ogg "$D/flac_mono.oga"
$F -i "$D/flac_mono.oga" -f s32le -c:a pcm_s32le "$D/flac_mono.pcm"
$F -f lavfi -i "$MUS" -t 1.5 -ar 44100 -ac 2 $META -c:a libvorbis -q:a 2 "$D/vorbis.ogg"
$F -f lavfi -i "$MUS" -t 1.25 -ar 48000 -ac 2 $META -c:a libopus -b:a 64k "$D/opus.opus"
$F -f lavfi -i "sine=frequency=500:sample_rate=16000" -t 1.0 -c:a libspeex "$D/speex.spx"
$F -f lavfi -i testsrc=size=64x48:rate=10 -f lavfi -i "$MUS" -t 1.0 -ar 22050 -c:v libtheora -q:v 3 -c:a libvorbis "$D/theora.ogv"
$F -f lavfi -i "$MUS" -f lavfi -i "sine=frequency=300:sample_rate=8000" -t 0.8 -map 0:a -map 1:a -ar 16000 -c:a flac -f ogg "$D/two_streams.ogg"
for f in "$D"/*.oga "$D"/*.ogg "$D"/*.opus "$D"/*.spx "$D"/*.ogv; do
    ffprobe -v error -show_entries stream=index,codec_name,sample_rate,channels,width,height,duration:stream_tags:format=duration:format_tags -of json "$f" > "$f.json"
done
ls "$D" | wc -l
