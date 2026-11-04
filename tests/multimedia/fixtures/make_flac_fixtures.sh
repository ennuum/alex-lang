#!/bin/sh
# Corpus FLAC pour tests/multimedia/test_flac.al, encodé par ffmpeg (référence indépendante). Chaque <nom>.flac a
# sa référence <nom>.pcm : entiers 32 bits signés petit-boutistes, entrelacés, décodés par ffmpeg.
# Relancer : sh tests/multimedia/fixtures/make_flac_fixtures.sh
set -eu
D=$(dirname "$0")/flac
rm -rf "$D"; mkdir -p "$D"
F="ffmpeg -hide_banner -loglevel error -y"
MUS="aevalsrc=0.5*sin(2*PI*440*t)+0.3*sin(2*PI*1234*t*t)|0.4*sin(2*PI*660*t)+0.2*sin(2*PI*90*t)"
NOISE="anoisesrc=color=pink:amplitude=0.8:seed=7"
enc() {  # nom source fréquence canaux format durée options...
    n=$1; src=$2; rate=$3; ch=$4; fmt=$5; dur=$6; shift 6
    $F -f lavfi -i "$src" -t "$dur" -ar "$rate" -ac "$ch" -sample_fmt "$fmt" -c:a flac "$@" "$D/$n.flac"
    $F -i "$D/$n.flac" -f s32le -c:a pcm_s32le -ac "$ch" "$D/$n.pcm"
}
for lvl in 0 2 5 8 12; do enc "st16_l$lvl" "$MUS" 44100 2 s16 0.3 -compression_level $lvl; done
for mode in indep left_side right_side mid_side; do enc "st16_$mode" "$MUS" 22050 2 s16 0.2 -ch_mode $mode; done
enc mono16 "$MUS" 8000 1 s16 0.4
enc st24 "$MUS" 48000 2 s32 0.2 -bits_per_raw_sample 24
enc st32 "$MUS" 44100 2 s32 0.1 -bits_per_raw_sample 32 -strict experimental
enc noise24 "$NOISE" 32000 1 s32 0.2 -bits_per_raw_sample 24 -compression_level 8
enc noise16 "$NOISE" 16000 2 s16 0.25 -compression_level 0
enc silence "anullsrc=r=8000:cl=mono" 8000 1 s16 0.3
enc small_blocks "$MUS" 11025 1 s16 0.2 -frame_size 192
enc odd_blocks "$MUS" 11025 2 s16 0.21 -frame_size 1000
enc lpc32 "$MUS" 44100 1 s16 0.15 -compression_level 12 -max_prediction_order 32 -lpc_type cholesky
enc ch6 "aevalsrc=0.1*sin(2*PI*(200+100*0)*t)|0.1*sin(2*PI*300*t)|0.1*sin(2*PI*400*t)|0.1*sin(2*PI*500*t)|0.1*sin(2*PI*600*t)|0.1*sin(2*PI*700*t)" 16000 6 s16 0.1
enc rate_odd "$MUS" 37800 1 s16 0.1
enc long "$MUS" 8000 1 s16 3.0 -compression_level 5
python3 "$(dirname "$0")/add_seektable.py" "$D/long.flac" "$D/long_seek.flac"
cp "$D/long.pcm" "$D/long_seek.pcm"
ls "$D"/*.flac | wc -l
