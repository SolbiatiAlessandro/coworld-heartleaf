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
replay.applyReplaySeek(sim,850)
let initialHash = sim.gameHash()
let first = sim.replayViewerFrame(replay,state,true)
var glyphHeights: seq[int]
for msg in parseSpritePacket(first):
  if msg.kind == spkSprite and msg.sprite.id >= 15000 and msg.sprite.id < 17000:
    if msg.sprite.height notin glyphHeights:glyphHeights.add(msg.sprite.height)
  if msg.kind == spkObject:
    doAssert msg.objectDef.id != 50_001, "removed right panel must not render"
doAssert 7 in glyphHeights and 8 in glyphHeights
for size in [(1280,720),(1440,900),(1920,1080)]:
  let layout = frameLayout(0,0,748,941,size[0],size[1],true,true,sidebars=true)
  doAssert layout.railWidth == ViewerRailWidth
  doAssert layout.scene.height == layout.canvasHeight
  doAssert layout.stage.width == layout.canvasWidth - ViewerRailWidth
  doAssert layout.scene.x >= ViewerRailWidth
  doAssert layout.scene.x + layout.scene.width <= layout.canvasWidth
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
echo "Left rail, intermediate fonts, narrow toggle, sprite reuse and unchanged game state passed"
