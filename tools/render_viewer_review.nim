## Offline review captures from actual protocol packets. This mirrors the
## pinned Bitworld layer composition; it does not exercise a browser/GPU.
## Run from the repo root: nim r tools/render_viewer_review.nim OUTPUT_DIR
import std/[importutils, os, tables]
import heartleaf
import heartleaf/[common, viewer_layout]

privateAccess(SimServer)
let sim = initSimServer(42)
privateAccess(typeof(sim.players[0]))
privateAccess(typeof(sim.chatFeed[0]))
privateAccess(typeof(sim.chatFeed[0].hearers[0]))
privateAccess(typeof(sim.homeMaps[0]))
privateAccess(typeof(sim.conversationCircles[0]))

import viewer_review_render

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
sim.directorTweenFromBlend=sim.directorFrameBlend
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
