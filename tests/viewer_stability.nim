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
  if msg.kind == spkSprite: labels[msg.sprite.id] = msg.sprite.label
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
