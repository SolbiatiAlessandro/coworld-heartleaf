## Presentation geometry. World coordinates and gameplay stay unchanged.
import std/math

const ViewerBorder* = 10

type
  ViewerRect* = object
    x*, y*, width*, height*: int
  ViewerLayout* = object
    width*, height*, x*, y*: int
    canvasWidth*, canvasHeight*: int
    scene*, card*: ViewerRect

proc frameLayout*(
  cropX, cropY, cropWidth, cropHeight: float,
  frameWidth, frameHeight: int,
  hasPlayers, replayControls: bool,
  cardHeight = 0
): ViewerLayout =
  ## The map has its own leafy frame. A director card sits beside it
  ## in landscape, or below it in portrait, clear of the other UI.
  let
    fw = float(if frameWidth > 0: frameWidth else: 1280)
    fh = float(if frameHeight > 0: frameHeight else: 720)
  var uiZoom = 1.0
  for zoom in countdown(3, 2):
    if fw >= 320.0 * float(zoom) * 1.5 and
        fh >= 128.0 * float(zoom) * 1.5:
      uiZoom = float(zoom)
      break
  result.canvasWidth = int(fw / uiZoom)
  result.canvasHeight = int(fh / uiZoom)
  let
    cw = result.canvasWidth
    ch = result.canvasHeight
    top = if hasPlayers and cw < ch: 106 else: 18
    bottom = if replayControls: 50 else: 8
  var
    availableWidth = max(32, cw - 16)
    availableHeight = max(32, ch - top - bottom)
  if cardHeight > 0:
    result.card.width = 158
    result.card.height = cardHeight
    if cw >= 480 and cw > ch:
      availableWidth = max(32, availableWidth - 166)
      result.card.x = cw - 166
      result.card.y = max(top, top + (availableHeight - cardHeight) div 2)
    else:
      availableHeight = max(32, availableHeight - cardHeight - 8)
      result.card.x = (cw - 158) div 2
      result.card.y = ch - bottom - cardHeight
  let
    scale = max(max(float(cw), float(ch)) / 8192.0,
      min(float(max(1, availableWidth - ViewerBorder * 2)) / max(1.0, cropWidth),
        float(max(1, availableHeight - ViewerBorder * 2)) / max(1.0, cropHeight)))
    sceneWidth = int(round(cropWidth * scale)) + ViewerBorder * 2
    sceneHeight = int(round(cropHeight * scale)) + ViewerBorder * 2
  result.scene = ViewerRect(
    x: 8 + (availableWidth - sceneWidth) div 2,
    y: top + (availableHeight - sceneHeight) div 2,
    width: sceneWidth, height: sceneHeight)
  result.width = max(1, int(ceil(float(cw) / scale)))
  result.height = max(1, int(ceil(float(ch) / scale)))
  result.x = int(round(cropX - float(result.scene.x + ViewerBorder) / scale))
  result.y = int(round(cropY - float(result.scene.y + ViewerBorder) / scale))
