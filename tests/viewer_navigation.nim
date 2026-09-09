## Exercise actual sprite-client clicks through the shared replay entrypoint.
import std/[importutils, os, tables]
import heartleaf, heartleaf/[viewer_layout, encounters], replays
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
replay.looping = false
sim.buildConversationQueue(replay.replayMaxTick())
doAssert sim.convQueue.len == 3
for span in sim.convQueue: doAssert span.spokenTurns == 6
var state = newReplayViewerState()
privateAccess(typeof(state.viewerActions[0]))
state.setViewerSize(1280,720)
replay.applyReplaySeek(sim,0)
discard sim.replayViewerFrame(replay,state,true)
proc click(index: int) =
  var found = false
  for action in state.viewerActions:
    if action.conversationIndex != index: continue
    let x = action.rect.x + action.rect.width div 2
    let y = action.rect.y + action.rect.height div 2
    let message = char(0x82) & char(x and 255) & char(x shr 8) &
      char(y and 255) & char(y shr 8) & char(7) &
      char(0x83) & char(1) & char(1) & char(0x83) & char(1) & char(0)
    state.handleReplayViewerPacket(message)
    found = true
    break
  doAssert found, "requested control must have a rendered hit target"
  discard sim.replayViewerFrame(replay,state,true)
# Same-time births: the second card selects its own encounter, not the first.
click(1)
doAssert replay.playing and sim.convQueueIndex == 1
doAssert sim.directorCommitEncounter == sim.convQueue[1].id
for _ in 0..<230: sim.advanceReplayPresentation(replay)
discard sim.replayViewerFrame(replay,state,true)
doAssert not replay.hashValidationFailed
let selectedHash = sim.gameHash()
replay.applyReplayCommand(sim,'P')
click(-1)
doAssert not replay.playing
let closedTick = sim.tickCount
doAssert selectedHash == sim.gameHash()
for _ in 0..<120: sim.advanceReplayPresentation(replay)
doAssert sim.directorOverviewOnly and not sim.directorFocusActive
doAssert sim.directorFrameBlend == 0 and sim.directorSceneMap == 0
doAssert sim.tickCount == closedTick
# Play and scrub keep overview selected. Selecting a card restores director.
replay.applyReplayCommand(sim,'p')
for _ in 0..<120: sim.advanceReplayPresentation(replay)
doAssert sim.directorOverviewOnly and not sim.convQueueCommitted
replay.applyReplaySeek(sim,900)
sim.advanceReplayPresentation(replay)
doAssert sim.directorOverviewOnly and not sim.directorFocusActive
click(2)
doAssert not sim.directorOverviewOnly and sim.convQueueIndex == 2
# Dinner must not immediately override X and put the viewer back indoors.
replay.applyReplaySeek(sim,2600)
sim.advanceReplayPresentation(replay)
doAssert sim.directorSceneMap != 0
replay.applyReplayConversation(sim,-1)
sim.advanceReplayPresentation(replay)
doAssert sim.directorSceneMap == 0 and sim.directorFrameBlend == 0
replay.applyReplayCommand(sim,'p')
for _ in 0..<120: sim.advanceReplayPresentation(replay)
doAssert sim.directorSceneMap == 0 and not replay.hashValidationFailed
# Long recordings paginate; the final card remains selectable by exact index.
let original = sim.convQueue
for i in 3..<20:
  sim.convQueue.add(ConversationSpan(id: i+20,birthTick:800,deathTick:1200,members: @[0,1]))
discard sim.replayViewerFrame(replay,state,true)
for _ in 0..<6: click(-3)
click(19)
doAssert sim.convQueueIndex == 19
replay.applyReplayConversation(sim,-1)
sim.convQueue = original
# Small screens can open either panel, then dismiss it again.
state.setViewerSize(390,844)
discard sim.replayViewerFrame(replay,state,true)
click(-4)
doAssert state.openPanel == 1
click(-5)
doAssert state.openPanel == 2
click(-5)
doAssert state.openPanel == 0
for size in [(1280,720),(1440,900),(1920,1080)]:
  let layout = frameLayout(0,0,748,941,size[0],size[1],true,true,sidebars=true)
  doAssert layout.railWidth == ViewerRailWidth
  doAssert layout.scene.height == layout.canvasHeight
  doAssert layout.scene.x >= ViewerRailWidth
  doAssert layout.scene.x + layout.scene.width <= layout.canvasWidth-ViewerRailWidth
# No whole-panel/glyph textures are re-sent for an unchanged paused frame.
replay.applyReplayCommand(sim,'P')
discard sim.replayViewerFrame(replay,state,true)
let steady = sim.replayViewerFrame(replay,state,true)
for msg in parseSpritePacket(steady):
  doAssert msg.kind != spkSprite, "stationary UI must reuse all sprite components"
echo "Conversation selection, overview exit, paging, narrow layout and sprite reuse passed"
