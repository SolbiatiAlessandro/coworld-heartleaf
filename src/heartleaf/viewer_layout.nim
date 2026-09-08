## Presentation geometry. World coordinates and gameplay stay unchanged.
import std/math

type ViewerLayout* = object
  width*, height*, x*, y*: int

proc frameLayout*(
  cropX, cropY, cropWidth, cropHeight: float,
  frameWidth, frameHeight: int,
  hasPlayers, replayControls: bool
): ViewerLayout =
  ## Fit the selected scene above the dialogue/transport. Portrait
  ## windows also reserve the scoreboard's top strip. The declared
  ## map viewport covers the entire window, including the surround.
  let
    fw = float(if frameWidth > 0: frameWidth else: 1280)
    fh = float(if frameHeight > 0: frameHeight else: 720)
  var uiZoom = 1.0
  for zoom in countdown(3, 2):
    if fw >= 320.0 * float(zoom) * 1.5 and
        fh >= 128.0 * float(zoom) * 1.5:
      uiZoom = float(zoom)
      break
  let
    top = if hasPlayers and fw < fh: 106.0 * uiZoom else: 0.0
    bottom = (if replayControls: 106.0 else: 64.0) * uiZoom
    usableHeight = max(64.0, fh - top - bottom)
    # Bound the map texture even for a very wide/short embed.
    scale = max(max(fw, fh) / 8192.0,
      min(fw / max(1.0, cropWidth), usableHeight / max(1.0, cropHeight)))
  result.width = max(1, int(ceil(fw / scale)))
  result.height = max(1, int(ceil(fh / scale)))
  result.x = int(round(cropX + cropWidth / 2 - fw / scale / 2))
  result.y = int(round(cropY + cropHeight / 2 -
    (top + usableHeight / 2) / scale))
