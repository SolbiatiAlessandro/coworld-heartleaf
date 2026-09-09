## Offline review captures from actual protocol packets. This mirrors the
## pinned Bitworld layer composition; it does not exercise a browser/GPU.
## Run from the repo root: nim r tools/render_viewer_review.nim OUTPUT_DIR
import std/[algorithm, importutils, math, os, tables]
import pixie, supersnappy, heartleaf
import heartleaf/[common, viewer_layout]
import bitworld/[sprites, spriteprotocol]

privateAccess(SimServer)
let sim = initSimServer(42)
privateAccess(typeof(sim.players[0]))
privateAccess(typeof(sim.chatFeed[0]))
privateAccess(typeof(sim.chatFeed[0].hearers[0]))
privateAccess(typeof(sim.homeMaps[0]))
privateAccess(typeof(sim.conversationCircles[0]))

type Layer = object
  width, height, kind, flags: int

proc render(packet: seq[uint8], width, height: int, path: string) =
  var
    sprites = initTable[int, RgbaSprite]()
    layers = initTable[int, Layer]()
    objects: seq[SpritePacketObject]
  for msg in parseSpritePacket(packet):
    case msg.kind
    of spkSprite:
      sprites[msg.sprite.id] = RgbaSprite(width: msg.sprite.width,
        height: msg.sprite.height, pixels: uncompress(msg.sprite.compressedPixels))
    of spkLayer:
      layers.mgetOrPut(msg.layer.layer, Layer()).kind = msg.layer.kind
      layers[msg.layer.layer].flags = msg.layer.flags
    of spkViewport:
      layers.mgetOrPut(msg.viewport.layer, Layer()).width = msg.viewport.width
      layers[msg.viewport.layer].height = msg.viewport.height
    of spkObject: objects.add(msg.objectDef)
    of spkClearObjects: objects.setLen(0)
    else: discard
  var uiZoom = 3
  for layer in layers.values:
    if (layer.flags and 2) == 0: continue
    let fit = min(float(width) / float(layer.width), float(height) / float(layer.height))
    var zoom = 1
    for scale in countdown(3,2):
      if fit >= float(scale) * 1.5:
        zoom = scale
        break
    uiZoom = min(uiZoom, zoom)
  var order: seq[int]
  for id in layers.keys: order.add(id)
  proc rank(layer: Layer): int =
    if layer.kind == 0: 0 elif layer.kind == 9: 1 else: 2
  order.sort(proc(a,b: int): int = cmp(
    (rank(layers[a]), layers[a].kind, a), (rank(layers[b]), layers[b].kind, b)))
  objects.sort(proc(a,b: SpritePacketObject): int = cmp((a.z,a.y,a.id),(b.z,b.y,b.id)))
  var canvas = solidRgbaSprite(width,height,rgba(0,0,0,255))
  for id in order:
    let layer = layers[id]
    if layer.width <= 0 or layer.height <= 0: continue
    var buffer = newRgbaSprite(layer.width,layer.height)
    # Bitworld overwrites nontransparent sprite pixels within a layer,
    # then alpha-composites each complete layer with nearest sampling.
    for obj in objects:
      if obj.layer != id or obj.spriteId notin sprites: continue
      let sprite = sprites[obj.spriteId]
      for y in max(0,-obj.y) ..< min(sprite.height,layer.height-obj.y):
        for x in max(0,-obj.x) ..< min(sprite.width,layer.width-obj.x):
          let pixel = sprite.rgbaSpriteAt(x,y)
          if pixel.a > 0: buffer.putPixel(obj.x+x,obj.y+y,pixel)
    let scale = if layer.kind in [0,9]:
      min(float(width)/float(layer.width),float(height)/float(layer.height))
      else: float(uiZoom)
    let w = float(layer.width)*scale
    let h = float(layer.height)*scale
    var x0,y0: float
    case layer.kind
    of 0,9: x0=floor((float(width)-w)/2); y0=floor((float(height)-h)/2)
    of 2: x0=float(width)-w
    of 3: x0=float(width)-w; y0=float(height)-h
    of 4: y0=float(height)-h
    of 5: x0=(float(width)-w)/2
    of 8: x0=(float(width)-w)/2; y0=float(height)-h
    else: discard
    for y in max(0,int(y0)) ..< min(height,int(ceil(y0+h))):
      for x in max(0,int(x0)) ..< min(width,int(ceil(x0+w))):
        let pixel = buffer.rgbaSpriteAt(int((float(x)-x0)/scale),int((float(y)-y0)/scale))
        if pixel.a == 0: continue
        let old = canvas.rgbaSpriteAt(x,y)
        let a = int(pixel.a)
        canvas.putPixel(x,y,rgba(
          uint8((int(pixel.r)*a+int(old.r)*(255-a)) div 255),
          uint8((int(pixel.g)*a+int(old.g)*(255-a)) div 255),
          uint8((int(pixel.b)*a+int(old.b)*(255-a)) div 255),255))
  let image = newImage(width,height)
  for y in 0..<height:
    for x in 0..<width: image[x,y]=canvas.rgbaSpriteAt(x,y)
  image.writeFile(path)

let output = if paramCount()>0: paramStr(1) else: "out/viewer-review"
createDir(output)
discard sim.addPlayer("host",0)
discard sim.addPlayer("guest",1)
for player in sim.players: player.mapIndex=0
sim.players[0].score=27
sim.players[0].x=405
sim.players[0].y=305
sim.players[1].x=445
sim.players[1].y=315
sim.heartLinks = @[(0,1,9)]
sim.tickCount=25
sim.updateDirectorCamera()
proc capture(name: string, width=1280, height=720, forest=false) =
  var state=newReplayViewerState()
  state.setViewerSize(width,height)
  state.setViewerBackground(forest)
  var next: PlayerViewerState
  render(sim.buildGlobalPacket(state,next,replayControls=true,
    replayTick=sim.tickCount,replayMaxTick=9120),width,height,output/name)
capture("rendered-wide.png")
capture("rendered-wide-portrait.png",768,1024)
capture("rendered-forest.png",forest=true)
sim.directorFocusActive=true
sim.directorFocusX=440
sim.directorFocusY=339
sim.directorFocusRadius=36
sim.directorCommitEncounter=1
sim.conversationAnchors[1] = typeof(sim.conversationAnchors[1])(x:440,y:339)
sim.conversationCircles = @[(x:440,y:339,radius:36)]
sim.queueDelayChat(sim.players[0].playerName,
  "Come to dinner at my house. I have cabbage and carrots ready to share with you.")
sim.chatFeed[0].hearers = @[typeof(sim.chatFeed[0].hearers[0])(
  name: sim.players[1].playerName, gnomeIndex: sim.players[1].gnomeIndex)]
sim.advanceChatFeed(1)
sim.directorTweenLeft=48
sim.directorTweenFromX=sim.directorCamX
sim.directorTweenFromY=sim.directorCamY
sim.directorTweenFromW=sim.directorCamW
sim.directorTweenFromH=sim.directorCamH
for _ in 0..<24: sim.updateDirectorCamera()
capture("rendered-zoom-mid.png")
for _ in 0..<60: sim.updateDirectorCamera()
capture("rendered-director-card.png")
capture("rendered-director-portrait.png",768,1024)
sim.players[0].x=sim.mainMap.width-45
sim.players[1].x=sim.mainMap.width-80
sim.directorFocusX=sim.players[0].x+16
sim.conversationAnchors[1].x=sim.directorFocusX
sim.conversationCircles[0].x=sim.directorFocusX
for _ in 0..<120: sim.updateDirectorCamera()
capture("rendered-card-edge.png")
for i, player in sim.players:
  player.mapIndex=1
  player.x=92+i*48
  player.y=90
sim.chatFeed[0].mapIndex=1
sim.directorCommitEncounter=0
sim.updateDirectorCamera()
sim.chatFeedIndex=0
capture("rendered-room-zoom-start.png")
for _ in 0..<120: sim.updateDirectorCamera()
capture("rendered-room-day.png")
capture("rendered-room-portrait.png",768,1024)
sim.dayTick=sim.dayTicks-1
capture("rendered-room-night.png")
echo "Saved offline protocol renders to ", output
