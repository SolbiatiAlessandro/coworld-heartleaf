## Real replay + shared viewer transport. Optional output directory captures frames.
import std/[importutils, os, strutils, tables]
import heartleaf, replays, heartleaf/connections
import bitworld/spriteprotocol
import ../tools/viewer_review_render
privateAccess(SimServer)
privateAccess(PlayerViewerState)
let path = if paramCount()>0: paramStr(1) else: "out/connections-scenario.replay"
let data = loadReplay(path)
let cfg = data.replaySimConfig()
let sim = initSimServer(cfg.seed,cfg.dayTicks)
sim.attachConversationTimeline(data,path)
var replay = initReplayPlayer(data)
replay.buildReplayKeyframes(cfg.seed,cfg.dayTicks)
replay.looping = false
sim.buildConversationQueue(replay.replayMaxTick())
var state = newReplayViewerState()
state.setViewerSize(1440,900)
proc capture(name:string,w=1440,h=900) =
  var fresh = newReplayViewerState()
  fresh.connectionSelection = state.connectionSelection
  fresh.connectionReflectionPage = state.connectionReflectionPage
  fresh.setViewerSize(w,h)
  var next:PlayerViewerState
  let packet = sim.buildGlobalPacket(fresh,next,replayControls=true,
    replayPlaying=replay.playing,replayTick=sim.tickCount,replayMaxTick=replay.replayMaxTick())
  if name == "10-compact-inspector.png":
    doAssert next.connectionButtons.len == 9, "all nine leaderboard rows fit a short window"
  if paramCount()>1:
    createDir(paramStr(2))
    render(packet,w,h,paramStr(2)/name)
proc seek(tick:int) =
  replay.applyReplaySeek(sim,tick)
  discard sim.replayViewerFrame(replay,state,true)
  doAssert not replay.hashValidationFailed
proc click(layer,x,y:int) =
  state.handleReplayViewerPacket(char(0x82)&char(x and 255)&char(x shr 8)&
    char(y and 255)&char(y shr 8)&char(layer)&char(0x83)&char(1)&char(1)&char(0x83)&char(1)&char(0))

seek(10)
doAssert sim.connectionTimeline.bondsAt(sim.tickCount).connectionScore(0) == 4
capture("01-overview.png")
doAssert state.connectionButtons.len == 9
let button = state.connectionButtons[0]
click(7,button.rect.x+5,button.rect.y+5)
doAssert state.connectionSelection == button.seat+1
capture("02-initial-graph.png")
click(7,button.rect.x+5,button.rect.y+5)
doAssert state.connectionSelection == 0
# Play a conversation through the normal director clock.
replay.applyReplayConversation(sim,0)
replay.applyReplayCommand(sim,'p')
var frames=0
while sim.tickCount < 854 and frames<5000:
  discard sim.replayViewerFrame(replay,state,true)
  inc frames
doAssert frames < 5000 and not replay.hashValidationFailed
capture("03-conversation.png")
replay.applyReplayCommand(sim,'P')
let frozen = (sim.tickCount,sim.directorCamX,sim.directorCamY,
  sim.connectionTimeline.bondsAt(sim.tickCount))
for _ in 0..<30: discard sim.replayViewerFrame(replay,state,true)
doAssert frozen == (sim.tickCount,sim.directorCamX,sim.directorCamY,
  sim.connectionTimeline.bondsAt(sim.tickCount))
capture("04-conversation-laptop.png",1280,720)
capture("05-conversation-narrow.png",768,1024)
seek(4700)
doAssert sim.connectionTimeline.bondsAt(sim.tickCount).strength(0,1) == 1
capture("06-day-two-overview.png")
state.connectionSelection = 1
capture("07-bedtime-results.png")
discard sim.replayViewerFrame(replay,state,true)
let paging = state.connectionNextPage
doAssert paging.width > 0
click(7,paging.x+3,paging.y+3)
doAssert state.connectionReflectionPage == 1
capture("09-more-reflections.png")
capture("10-compact-inspector.png",1280,480)
state.connectionSelection = 0
seek(10)
doAssert sim.connectionTimeline.bondsAt(sim.tickCount).strength(0,1) == 0.5
capture("08-rewound-overview.png")
# Mix pause, next, speed, previous, end, restart after the bond update.
seek(4700)
for command in ['p','n','n','P','1','p','2','N','b','P','e','p']:
  replay.applyReplayCommand(sim,command)
  for _ in 0..<5: discard sim.replayViewerFrame(replay,state,true)
  doAssert not replay.hashValidationFailed
# Replay all simulation hashes, plus random-access snapshots through both days.
for tick in [8880,4000,9000,10,4560,4320,100,9119]:
  seek(tick)
  let strength = sim.connectionTimeline.bondsAt(sim.tickCount).strength(0,1)
  doAssert strength == (if tick>=4320:1.0 else:0.5)
echo "Connection viewer: real replay, selection toggle, pause, mixed transport and backward seeks passed."
