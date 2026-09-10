## Left leaderboard geometry, narrow toggle, glyph caching and presentation isolation.
import std/[importutils, tables]
import heartleaf, heartleaf/viewer_layout, replays
import bitworld/spriteprotocol
privateAccess(SimServer)
privateAccess(PlayerViewerState)
let path = "docs/viewer-stability/local-viewer-scenario.replay"
let data = loadReplay(path)
let cfg = data.replaySimConfig()
let sim = initSimServer(cfg.seed,cfg.dayTicks)
sim.attachConversationTimeline(data,path)
var replay = initReplayPlayer(data)
replay.buildReplayKeyframes(cfg.seed,cfg.dayTicks)
sim.buildConversationQueue(replay.replayMaxTick())
replay.looping = false
var state = newReplayViewerState()
state.setViewerSize(1280,720)
replay.applyReplaySeek(sim,799)
let initialHash = sim.gameHash()
let first = sim.replayViewerFrame(replay,state,true)
var glyphHeights: seq[int]
for msg in parseSpritePacket(first):
  if msg.kind == spkSprite and msg.sprite.id >= 8720 and msg.sprite.id <= 8814:
    if msg.sprite.height notin glyphHeights:glyphHeights.add(msg.sprite.height)
  if msg.kind == spkObject:
    doAssert msg.objectDef.id != 50_001, "removed right panel must not render"
doAssert glyphHeights == @[6], "use the original unscaled font glyphs"
for size in [(1280,720),(1440,900),(1920,1080),(1468,798),(1366,1024)]:
  let layout = frameLayout(0,0,748,941,size[0],size[1],true,true,sidebars=true)
  doAssert layout.railWidth == ViewerRailWidth
  doAssert layout.scene.height == layout.canvasHeight
  doAssert layout.stage.width == layout.canvasWidth - ViewerRailWidth
  let centeredX = (layout.canvasWidth - layout.scene.width) div 2
  if centeredX >= ViewerRailWidth:
    let rightMargin = layout.canvasWidth - layout.scene.x - layout.scene.width
    doAssert abs(layout.scene.x-rightMargin) <= 1, "equal margins around the village"
  let start = frameLayout(0,0,748,941,size[0],size[1],true,true,
    conversation=true,worldWidth=748,worldHeight=941,focusBlend=0.001,sidebars=true)
  doAssert start.scene == layout.scene, "the zoom must start at the centered overview"
  doAssert layout.scene.x >= ViewerRailWidth
  doAssert layout.scene.x + layout.scene.width <= layout.canvasWidth
  let zoom = frameLayout(200,200,250,314,size[0],size[1],true,true,100,
    conversation=true,worldWidth=748,worldHeight=941,sidebars=true)
  doAssert zoom.railWidth == 0
  doAssert zoom.scene.x == 0 and zoom.scene.y == 0
  doAssert zoom.scene.width == zoom.canvasWidth and zoom.scene.height == zoom.canvasHeight

# The rail and its hit target disappear from actual conversation packets.
replay.applyReplaySeek(sim,850)
let zoomPacket = sim.replayViewerFrame(replay,state,true)
for msg in parseSpritePacket(zoomPacket):
  if msg.kind == spkObject:
    doAssert msg.objectDef.id notin [50_000,50_003,50_005]
doAssert state.leaderboardButton.width == 0
replay.applyReplaySeek(sim,799)
state.setViewerSize(390,844)
discard sim.replayViewerFrame(replay,state,true)
proc toggle() =
  let r = state.leaderboardButton
  let x = r.x+r.width div 2
  let y = r.y+r.height div 2
  state.handleReplayViewerPacket(char(0x82)&char(x and 255)&char(x shr 8)&
    char(y and 255)&char(y shr 8)&char(7)&
    char(0x83)&char(1)&char(1)&char(0x83)&char(1)&char(0))
  discard sim.replayViewerFrame(replay,state,true)
toggle()
doAssert state.openPanel == 1
toggle()
doAssert state.openPanel == 0
let steady = sim.replayViewerFrame(replay,state,true)
for msg in parseSpritePacket(steady):
  doAssert msg.kind != spkSprite, "stationary UI must reuse all sprite components"
doAssert sim.gameHash() == initialHash
echo "Left rail, original font, narrow toggle, sprite reuse and unchanged game state passed"
