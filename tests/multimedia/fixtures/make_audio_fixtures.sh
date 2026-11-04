#!/bin/sh
# Corpus audio / conteneurs pour tests/multimedia/test_container.al, produit par ffmpeg (référence indépendante
# du code ALEX). Chaque WAV a une référence .f32 (échantillons flottants 32 bits petit-boutiste, même contenu).
# Relancer : sh tests/multimedia/fixtures/make_audio_fixtures.sh
set -eu
D=$(dirname "$0")/media
rm -rf "$D"; mkdir -p "$D"
F="ffmpeg -hide_banner -loglevel error -y"
SRC="-f lavfi -i sine=frequency=440:sample_rate=8000:duration=0.25"
ST="-f lavfi -i aevalsrc=0.4*sin(2*PI*440*t)|0.3*sin(2*PI*660*t):s=11025:d=0.2"
META="-metadata title=Essai -metadata artist=ALEX -metadata album=Tests -metadata date=2026 -metadata track=3/12 -metadata comment=Bonjour"
for fmt in u8 s16le s24le s32le f32le; do
    $F $ST -c:a pcm_$fmt -bitexact "$D/st_$fmt.wav"
    $F -i "$D/st_$fmt.wav" -f f32le -c:a pcm_f32le "$D/st_$fmt.f32"
done
$F $SRC $META -c:a pcm_s16le "$D/tags.wav"
$F $SRC -c:a pcm_s16le -rf64 auto "$D/plain.wav"
$F $SRC $META -c:a flac "$D/tone.flac"
$F $SRC $META -c:a libmp3lame -id3v2_version 3 "$D/tone_v23.mp3"
$F $SRC $META -c:a libmp3lame -id3v2_version 4 -write_id3v1 1 "$D/tone_v24.mp3"
$F $SRC -c:a libvorbis "$D/tone.ogg"
$F $SRC -c:a aac "$D/tone.m4a"
$F $SRC -c:a libopus "$D/tone.mka"
$F $SRC -c:a pcm_s16be "$D/tone.aiff"
$F $SRC -c:a pcm_mulaw "$D/mulaw.wav"
$F $SRC -c:a pcm_s16le -f avi "$D/tone.avi"
ls "$D" | wc -l
