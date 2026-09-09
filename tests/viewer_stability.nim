## Presentation regressions, independent of browser timing or external replays.
import std/[importutils, json, math, os, strutils, tables]
import heartleaf, heartleaf/[viewer_layout, pixel_emotes, encounters], replays
import heartleaf/common
import bitworld/[spriteprotocol, sprites]
import pixie

privateAccess(SimServer)
privateAccess(PlayerViewerState)
let sim = initSimServer(42)
privateAccess(typeof(sim.players[0]))
privateAccess(typeof(sim.homeMaps[0]))

for size in [(1280,720), (1024,768), (768,1024), (390,844)]:
  let layout = frameLayout(0, 0, 748, 941, size[0], size[1], true, true)
  let scale = min(float(size[0])/float(layout.width),
    float(size[1])/float(layout.height))
  doAssert abs(float(layout.width) * scale - float(size[0])) < 2
  doAssert abs(float(layout.height) * scale - float(size[1])) < 2
  doAssert layout.y <= 0
  let framed = frameLayout(100, 100, 250, 314, size[0], size[1], true, true, 128,
    conversation=true, worldWidth=748, worldHeight=941)
  doAssert framed.card.y >= 18
  doAssert framed.card.y + framed.card.height <= framed.canvasHeight - 42
  doAssert framed.scene.x == 0 and framed.scene.y == 0
  doAssert framed.scene.width == framed.canvasWidth
  doAssert framed.scene.height == framed.canvasHeight
  if size[0] >= size[1]:
    doAssert layout.scene.y == 0
    doAssert layout.scene.height == layout.canvasHeight,
      "the overview must use the full height, with UI overlaid"
  else:
    doAssert layout.scene.width == layout.canvasWidth,
      "narrow windows must keep the whole village visible"
  let liveOverview = frameLayout(0, 0, 748, 941, size[0], size[1], true, false)
  doAssert liveOverview.scene == layout.scene,
    "replay transport must not shrink the overview"
  let roomView = frameLayout(0,0,250,250,size[0],size[1],true,true,96,
    conversation=true)
  let roomScale = min(float(roomView.canvasWidth)/float(roomView.width),
    float(roomView.canvasHeight)/float(roomView.height))
  doAssert (250.0-float(roomView.y))*roomScale <= float(roomView.canvasHeight-42),
    "the circular room must clear playback controls"

# Full-screen crops stay within outdoor artwork even at map edges or
# in an ultrawide window, rather than exposing a band of empty space.
for size in [(1280,720), (2560,720), (390,844)]:
  for focus in [(0.0,0.0), (623.0,784.0)]:
    let view = frameLayout(focus[0],focus[1],250,314,size[0],size[1],true,true,96,
      conversation=true, worldWidth=748, worldHeight=941)
    let scale = min(float(view.canvasWidth)/float(view.width),
      float(view.canvasHeight)/float(view.height))
    doAssert float(view.x)+float(ViewerBorder)/scale >= -2
    doAssert float(view.y)+float(ViewerBorder)/scale >= -2
    doAssert float(view.x)+(float(view.canvasWidth)-float(ViewerBorder))/scale <= 750
    doAssert float(view.y)+(float(view.canvasHeight)-float(ViewerBorder))/scale <= 943

discard sim.addPlayer("host", 0)
discard sim.addPlayer("guest", 1)
for player in sim.players:
  player.mapIndex = 1
  player.x = 110
  player.y = 85
let before = sim.gameHash()
sim.updateDirectorCamera()
doAssert sim.directorSceneMap == 1, "a host and one guest is a party"
for _ in 0 ..< 120: sim.updateDirectorCamera()
doAssert abs(sim.directorCamW - float(sim.homeMaps[0].width)) < 1
let room = sim.homeMaps[0].bottomSprite
doAssert room.rgbaSpriteAt(0, 0).a == 0, "room corners must be transparent"
doAssert room.rgbaSpriteAt(125, 123).a == 255, "room floor must stay opaque"
for tint in sim.homeMaps[0].bottomTints:
  doAssert tint.rgbaSpriteAt(0,0).a == 0, "night must not restore the room matte"
doAssert sim.gameHash() == before, "presentation cannot change game state"
sim.players[0].mapIndex = 0
sim.updateDirectorCamera()
doAssert sim.directorSceneMap == 0, "guests alone do not qualify as a party"

var state = newReplayViewerState()
state.setViewerSize(768, 1024)
state.setViewerBackground(true)
for i, player in sim.players:
  player.mapIndex = 0
  player.x = 310 + i * 15
  player.y = 310 - i * 35
sim.players[0].score = 27
sim.heartLinks = @[(0, 1, 9)]
sim.directorFocusActive = true
sim.directorFrameBlend = 1
sim.directorFocusX = 335
sim.directorFocusY = 325
sim.directorFocusRadius = 48
sim.directorCamX = 210
sim.directorCamY = 168
sim.directorCamW = 250
sim.directorCamH = 314
sim.directorTweenLeft = 0
sim.queueDelayChat(sim.players[0].playerName,
  "A complete line stays readable while the portrait and parchment are reused.")
privateAccess(typeof(sim.chatFeed[0]))
sim.advanceChatFeed(1)
var next: PlayerViewerState
let first = sim.buildGlobalPacket(state, next, replayControls=true)
doAssert sim.viewerBrown.rgbaSpriteAt(0,0) == rgba(213,176,114,255)
let frame = frameLayout(210,168,250,314,768,1024,true,true,96,
  conversation=true, worldWidth=sim.mainMap.width, worldHeight=sim.mainMap.height)
doAssert sim.viewerFrame.rgbaSpriteAt(frame.scene.x + 20,frame.scene.y + 20).a == 0
var labels = initTable[int,string]()
for msg in parseSpritePacket(first):
  if msg.kind == spkSprite:
    labels[msg.sprite.id] = msg.sprite.label
    if msg.sprite.label.startsWith("director portrait"):
      doAssert msg.sprite.width == 54 and msg.sprite.height == 54,
        "portrait must use the full native pixel art"
  if msg.kind == spkSprite:
    doAssert not msg.sprite.label.startsWith("director card 0")
sim.chatFeed[0].message = "A different sentence updates the letters without resending the empty card."
var next2: PlayerViewerState
let second = sim.buildGlobalPacket(next, next2, replayControls=true)
var glyphs, backgrounds, portraits: int
var cardText = ""
for msg in parseSpritePacket(second):
  if msg.kind == spkSprite:
    doAssert msg.sprite.label != "chat banner"
    doAssert not msg.sprite.label.startsWith("banner glyph")
    doAssert not msg.sprite.label.startsWith("portrait")
    doAssert not msg.sprite.label.startsWith("forest surround")
    doAssert not msg.sprite.label.startsWith("director empty card")
    doAssert not msg.sprite.label.startsWith("director portrait")
    doAssert not msg.sprite.label.startsWith("viewer parchment frame")
  elif msg.kind == spkObject:
    let label = labels.getOrDefault(msg.objectDef.spriteId)
    if label.startsWith("banner glyph"): inc glyphs
    doAssert msg.objectDef.id != 25_000, "director never shows the old bottom dialogue banner"
    if label.startsWith("director empty card"):
      inc backgrounds
      doAssert msg.objectDef.layer == 7
    if label.startsWith("director portrait"): inc portraits
    if msg.objectDef.id >= 48_000 and msg.objectDef.id < 49_000:
      cardText.add(char(msg.objectDef.spriteId - 8720 + 32))
doAssert glyphs > 20 and backgrounds == 1 and portraits == 1
doAssert "Points: 27" in cardText and "Connections: 9" in cardText
doAssert "A different sentence" in cardText
# A wide shot or an unfinished zoom has no dialogue card.
for transitioning in [true, false]:
  sim.directorTweenLeft = if transitioning: 10 else: 0
  sim.directorFocusActive = transitioning
  for msg in parseSpritePacket(sim.buildGlobalPacket(next2, next, replayControls=true)):
    if msg.kind == spkObject:
      doAssert msg.objectDef.id notin [25_000, 28_000]
sim.directorFocusActive = true
sim.directorTweenLeft = 0
# Every tint including un-tinted daytime must be safe in forest mode.
for tick in countup(0, 4320, 240):
  sim.tickCount = tick
  discard sim.buildGlobalPacket(next2, next, replayControls=true)

# Every phase of an emote clears all gnome bodies, including a nearby
# gnome standing above its owner. This catches the old top-anchored icon.
var emotes = 0
for tick in 0 ..< 72:
  sim.tickCount = tick
  let layout = frameLayout(sim.directorCamX, sim.directorCamY,
    sim.directorCamW, sim.directorCamH, 768, 1024, true, true, 96,
    conversation=true, worldWidth=sim.mainMap.width, worldHeight=sim.mainMap.height)
  for msg in parseSpritePacket(sim.buildGlobalPacket(next2, next, replayControls=true)):
    if msg.kind == spkObject and msg.objectDef.id in 27_000 ..< 27_040:
      inc emotes
      let x = msg.objectDef.x + layout.x
      let y = msg.objectDef.y + layout.y
      for player in sim.players:
        doAssert x + PixelEmoteSize <= player.x or x >= player.x + GnomeSpriteSize or
          y + PixelEmoteSize <= player.y or y >= player.y + GnomeSpriteSize,
          "emoji must not overlap any gnome's body"
doAssert emotes > 0
doAssert sim.heartEmoteFaded.len >= 4
for sprite in sim.heartEmoteFaded.values:
  for i in countup(3,sprite.pixels.high,4):
    doAssert sprite.pixels[i] in [0'u8,255'u8], "emotes cannot erase the map with partial alpha"

for tier in 0..2:
  let sprite = pixelEmote(tier)
  doAssert sprite.width == 16 and sprite.height == 16
  doAssert sprite.width == GnomeSpriteSize div 2
  for y in 0..<sprite.height:
    for x in 0..<sprite.width:
      let color = sprite.rgbaSpriteAt(x,y)
      doAssert color.a in [0'u8,255'u8], "pixel icons have no smooth alpha edges"

# A conversation at the right edge would sit underneath the default
# right-hand card. The card must relocate to a clear side of the shot.
sim.players[0].x=sim.mainMap.width-45
sim.players[0].y=315
sim.players[1].x=sim.mainMap.width-80
sim.players[1].y=325
sim.directorFocusX=sim.players[0].x+16
sim.directorFocusY=340
sim.directorCamX=float(sim.mainMap.width-250)
sim.directorCamY=183
var edgeState=newReplayViewerState()
edgeState.setViewerSize(1280,720)
var relocated=false
for msg in parseSpritePacket(sim.buildGlobalPacket(edgeState,next,replayControls=true)):
  if msg.kind==spkObject and msg.objectDef.id==28_000:
    relocated=true
    doAssert msg.objectDef.x < 176, "card must move away from the gnomes at the right edge"
    doAssert msg.objectDef.y >= 106, "left card must clear the leaderboard"
doAssert relocated
echo "Viewer stability checks passed"

# Concurrent conversations must finish, rewind, and resume without a stuck
# playhead. Generate the recording here so CI needs no downloaded fixtures.
block:
  let path = getTempDir() / "heartleaf-viewer-stability.replay"
  let source = initSimServer(42)
  var writer = openReplayWriter(path, $(%*{"seed":42}))
  for seat in 0..3:
    discard source.addPlayer("viewer test " & $seat, seat)
    writer.writeJoin(0, seat, "viewer test " & $seat, seat, "")
  for _ in 0..<240:
    source.step(@[])
    writer.writeHash(uint32(source.tickCount), source.gameHash())
  writer.closeReplayWriter()
  let data = loadReplay(path)
  removeFile(path)
  let replaySim = initSimServer(42)
  var replay = initReplayPlayer(data)
  replay.buildReplayKeyframes(42)
  replay.looping = false
  replaySim.convQueue = @[
    ConversationSpan(id: 1, birthTick: 10, deathTick: 150, members: @[0,1]),
    ConversationSpan(id: 2, birthTick: 20, deathTick: 200, members: @[2,3])
  ]
  var sameTick, lastTick, frames: int
  while replay.playing and frames < 10000:
    replaySim.advanceReplayPresentation(replay)
    if replaySim.tickCount == lastTick: inc sameTick
    else: sameTick = 0
    doAssert sameTick < 300, "replay must not stall during a camera transition"
    lastTick = replaySim.tickCount
    inc frames
    doAssert not replay.hashValidationFailed
  doAssert replaySim.tickCount == 240
  replay.applyReplaySeek(replaySim, 100)
  let pausedHash = replaySim.gameHash()
  for _ in 0..<60: replaySim.advanceReplayPresentation(replay)
  doAssert replaySim.tickCount == 100 and replaySim.gameHash() == pausedHash
  echo "Concurrent playback, pause and seek checks passed"

# The visible window, not just the nominal camera crop, must glide. Check
# the first/last frame, every intervening scale step and village bounds.
for size in [(1280,720), (1422,1080), (2560,720), (390,844)]:
  for forest in [false, true]:
    let wideW = if forest: 941.0 * 1.5 else: 748.0
    let wide = frameLayout(-(wideW-748)/2,0,wideW,941,
      size[0],size[1],true,true)
    var previous = wide
    for f in 0..48:
      let t = float(f)/48.0
      let b = t*t*(3-2*t)
      let h = 941.0+(314.5-941.0)*b
      let w = 748.0+(250.0-748.0)*b
      let cropW = w + (if forest: max(0.0,h*1.5-w)*(1-b) else: 0.0)
      let v = frameLayout(0-(cropW-w)/2,0,cropW,h,
        size[0],size[1],true,true,conversation=true,
        worldWidth=748,worldHeight=941,focusBlend=b,
        overviewAspect=(if forest:1.5 else:0.0))
      let ratio = float(previous.height)/float(v.height)
      doAssert ratio < 1.08 and ratio > 0.98, "zoom must have no sudden scale step"
      if f == 0: doAssert v.scene == wide.scene and abs(v.height-wide.height)<=2
      if f == 1: doAssert abs(ratio-1.0) < 0.02
      let scale = min(float(v.canvasWidth)/float(v.width),float(v.canvasHeight)/float(v.height))
      let boundsW = wideW+(748.0-wideW)*b
      doAssert float(v.x)+float(v.scene.x+ViewerBorder)/scale >= (748-boundsW)/2-3
      doAssert float(v.x)+float(v.scene.x+v.scene.width-ViewerBorder)/scale <= (748+boundsW)/2+3, $size & " forest=" & $forest & " f=" & $f & " view=" & $v & " bounds=" & $boundsW
      previous = v
    doAssert previous.scene.x==0 and previous.scene.y==0
    doAssert previous.scene.width==previous.canvasWidth

# Actual mouse packets pause a mid-glide replay on this frame; no camera,
# speaker hop, room timer or card timer may keep running in the background.
block:
  let frozen = initSimServer(42)
  var replay = initReplayPlayer(ReplayData())
  replay.playing = false
  frozen.updateDirectorCamera()
  frozen.directorCommitEncounter = 999
  frozen.conversationAnchors[999] = typeof(frozen.conversationAnchors[999])(x:440,y:339)
  for _ in 0..<8: frozen.updateDirectorCamera()
  var state = newReplayViewerState()
  state.setViewerSize(1280,720)
  proc click(x,y:int,down:bool):string =
    result = newString(9)
    result[0]=char(0x82); result[1]=char(x and 255); result[2]=char(x shr 8)
    result[3]=char(y and 255); result[4]=char(y shr 8); result[5]=char(4)
    result[6]=char(0x83); result[7]=char(1); result[8]=char(ord(down))
  # Exercise the newly enlarged target at the edge, outside the tiny glyph.
  replay.playing = true
  state.handleReplayViewerPacket(click(50,69,true))
  state.handleReplayViewerPacket(click(50,69,false))
  discard frozen.replayViewerFrame(replay,state,true)
  doAssert not replay.playing
  let camera = (frozen.directorCamX,frozen.directorCamY,frozen.directorCamW,
    frozen.directorCamH,frozen.directorFrameBlend,frozen.directorTweenLeft)
  let time = frozen.replayPresentationTime
  for _ in 0..<60:
    frozen.advanceReplayPresentation(replay)
    doAssert (frozen.directorCamX,frozen.directorCamY,frozen.directorCamW,
      frozen.directorCamH,frozen.directorFrameBlend,frozen.directorTweenLeft) == camera
    doAssert frozen.replayPresentationTime == time
  state.handleReplayViewerPacket(click(50,87,true))
  state.handleReplayViewerPacket(click(50,87,false))
  discard frozen.replayViewerFrame(replay,state,true)
  doAssert replay.playing
  doAssert frozen.directorTweenLeft == camera[5]-1, "resume moves the camera on the first frame"
  # An explicit paused refresh (seek) settles once, then stays still.
  replay.playing = false
  frozen.replayPresentationDirty = true
  frozen.advanceReplayPresentation(replay)
  doAssert frozen.directorTweenLeft == 0
  let settled = (frozen.directorCamX,frozen.directorCamY,frozen.directorCamW,frozen.directorCamH)
  for _ in 0..<60: frozen.advanceReplayPresentation(replay)
  doAssert settled == (frozen.directorCamX,frozen.directorCamY,frozen.directorCamW,frozen.directorCamH)
  # Next conversation at the same birth tick still refreshes while paused.
  frozen.convQueue = @[
    ConversationSpan(id:999,birthTick:0,deathTick:100,members: @[0,1]),
    ConversationSpan(id:1000,birthTick:0,deathTick:100,members: @[2,3])]
  frozen.convQueueCommitted = true
  frozen.convQueueIndex = 0
  frozen.conversationAnchors[1000] = typeof(frozen.conversationAnchors[1000])(x:100,y:200)
  replay.applyReplayCommand(frozen,'n')
  frozen.advanceReplayPresentation(replay)
  doAssert frozen.directorFocusX == 100 and frozen.directorFocusY == 200
  # Indoor zoom and party rotation obey the very same pause.
  discard frozen.addPlayer("host",0)
  discard frozen.addPlayer("guest",1)
  for player in frozen.players: player.mapIndex = 1
  frozen.updateDirectorCamera()
  let room = (frozen.directorCamW,frozen.directorCamH,frozen.directorDinnerTtl,frozen.directorBounce)
  for _ in 0..<60: frozen.advanceReplayPresentation(replay)
  doAssert room == (frozen.directorCamW,frozen.directorCamH,frozen.directorDinnerTtl,frozen.directorBounce)
echo "Smooth framing, complete pause and native portrait checks passed"
