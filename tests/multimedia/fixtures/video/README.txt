blocks.png : 12 aplats de 16x16 points (64x48). frame.<fmt> : conversion par ffmpeg en yuv420p, nv12, yuyv422
(BT.601, plage limitée) ; frame.<fmt>.rgb : retour en rgb24 par ffmpeg (référence de
multimedia.video.color.from_planes, comparée hors des bords des aplats, où l'interpolation de chrominance diffère).
  ffmpeg -i blocks.png -pix_fmt <fmt> -f rawvideo frame.<fmt>
  ffmpeg -f rawvideo -pix_fmt <fmt> -s 64x48 -i frame.<fmt> -pix_fmt rgb24 -f rawvideo frame.<fmt>.rgb
