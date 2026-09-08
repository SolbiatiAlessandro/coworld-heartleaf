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
  cardHeight = 0,
  conversation = false,
  worldWidth = 0, worldHeight = 0
): ViewerLayout =
  ## The full village fits the available height. Conversation shots
  ## fill the window with a wider camera crop and overlay their card.
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
  if conversation:
    result.scene = ViewerRect(width: cw, height: ch)
    let
      innerWidth = float(cw - ViewerBorder * 2)
      # A room's circular exterior must remain wholly visible above
      # the transport even though its surrounding frame is full-screen.
      roomTransport = if worldHeight == 0 and replayControls: 50 else: 0
      innerHeight = float(ch - ViewerBorder * 2 - roomTransport)
    var scale = min(innerWidth / max(1.0, cropWidth),
      innerHeight / max(1.0, cropHeight))
    # Near a village edge, pan within the actual art. Very wide
    # windows may need a tighter crop to avoid exposing empty space.
    if worldWidth > 0: scale = max(scale, innerWidth / float(worldWidth))
    if worldHeight > 0: scale = max(scale, innerHeight / float(worldHeight))
    scale = max(scale, max(float(cw), float(ch)) / 8192.0)
    var
      left = cropX + cropWidth / 2 - innerWidth / scale / 2
      top = cropY + cropHeight / 2 - innerHeight / scale / 2
    if worldWidth > 0: left = clamp(left, 0.0, max(0.0, float(worldWidth) - innerWidth / scale))
    if worldHeight > 0: top = clamp(top, 0.0, max(0.0, float(worldHeight) - innerHeight / scale))
    result.width = max(1, int(ceil(float(cw) / scale)))
    result.height = max(1, int(ceil(float(ch) / scale)))
    result.x = int(round(left - float(ViewerBorder) / scale))
    result.y = int(round(top - float(ViewerBorder) / scale))
    if cardHeight > 0:
      result.card = ViewerRect(width: 158, height: cardHeight)
      if cw >= 480 and cw > ch:
        result.card.x = cw - 158 - 14
        result.card.y = (ch - cardHeight) div 2
      else:
        result.card.x = (cw - 158) div 2
        result.card.y = ch - bottom - cardHeight - 4
    return
  let
    availableWidth = max(32, cw - 16)
    availableHeight = max(32, ch - top - bottom)
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
