## Presentation regressions, independent of browser timing or external replays.
import std/[importutils, json, math, os, strutils, tables]
import heartleaf, heartleaf/[viewer_layout, pixel_emotes, encounters], replays
import bitworld/[spriteprotocol, sprites]

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
doAssert sim.gameHash() == before, "presentation cannot change game state"
sim.players[0].mapIndex = 0
sim.updateDirectorCamera()
doAssert sim.directorSceneMap == 0, "guests alone do not qualify as a party"

var state = newReplayViewerState()
state.setViewerSize(768, 1024)
state.setViewerBackground(true)
sim.queueDelayChat("Ivan", "A complete line stays readable while the portrait and parchment are reused.")
sim.advanceChatFeed(1)
var next: PlayerViewerState
let first = sim.buildGlobalPacket(state, next, replayControls=true)
var labels = initTable[int,string]()
for msg in parseSpritePacket(first):
  if msg.kind == spkSprite: labels[msg.sprite.id] = msg.sprite.label
  if msg.kind == spkSprite:
    doAssert not msg.sprite.label.startsWith("director card")
var next2: PlayerViewerState
let second = sim.buildGlobalPacket(next, next2, replayControls=true)
var glyphs, backgrounds: int
for msg in parseSpritePacket(second):
  if msg.kind == spkSprite:
    doAssert msg.sprite.label != "chat banner"
    doAssert not msg.sprite.label.startsWith("banner glyph")
    doAssert not msg.sprite.label.startsWith("portrait")
    doAssert not msg.sprite.label.startsWith("forest surround")
  elif msg.kind == spkObject:
    let label = labels.getOrDefault(msg.objectDef.spriteId)
    if label.startsWith("banner glyph"): inc glyphs
    if label == "chat banner":
      inc backgrounds
      doAssert msg.objectDef.layer == 4
    if label.startsWith("banner glyph"):
      doAssert msg.objectDef.y >= 0 and msg.objectDef.y < 64
      doAssert msg.objectDef.x >= 0 and msg.objectDef.x < 320
doAssert glyphs > 20 and backgrounds == 1
# Every tint including un-tinted daytime must be safe in forest mode.
for tick in countup(0, 4320, 240):
  sim.tickCount = tick
  discard sim.buildGlobalPacket(next2, next, replayControls=true)

for tier in 0..2:
  let sprite = pixelEmote(tier)
  doAssert sprite.width == 32 and sprite.height == 32
  for y in countup(0,30,2):
    for x in countup(0,30,2):
      let color = sprite.rgbaSpriteAt(x,y)
      doAssert color.a in [0'u8,255'u8], "pixel icons have no smooth alpha edges"
      doAssert color == sprite.rgbaSpriteAt(x+1,y)
      doAssert color == sprite.rgbaSpriteAt(x,y+1)
      doAssert color == sprite.rgbaSpriteAt(x+1,y+1)
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
