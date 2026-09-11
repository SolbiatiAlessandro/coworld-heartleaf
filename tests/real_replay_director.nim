## Regression for the published real Claude recording: long model gaps and
## missing overnight exits must not trap the director on its first shot.
import std/[importutils, os, sets]
import heartleaf, replays
import ../tools/viewer_review_render
privateAccess(SimServer)
privateAccess(PlayerViewerState)
let path = "docs/connections/claude/two-day.bitreplay"
let data = loadReplay(path)
let cfg = data.replaySimConfig()
let sim = initSimServer(cfg.seed,cfg.dayTicks)
privateAccess(typeof(sim.chatFeed[0]))
privateAccess(typeof(sim.chatFeed[0].speaker))
sim.attachConversationTimeline(data,path)
var replay = initReplayPlayer(data)
replay.buildReplayKeyframes(cfg.seed,cfg.dayTicks)
replay.looping = false
sim.buildConversationQueue(replay.replayMaxTick())
doAssert sim.convQueue.len == 12
for span in sim.convQueue:
  if span.id in [5,6]:
    doAssert span.deathTick == 4560, "old party records must end at the new day"
var state = newReplayViewerState()
state.setViewerSize(1440,900)
var visited: HashSet[int]
var frames, firstShotFrames, currentShotFrames, previousId: int
var captured: HashSet[int]
var aired: HashSet[string]
while replay.playing and frames < 18000:
  discard sim.replayViewerFrame(replay,state,true)
  inc frames
  let id = sim.directorCommitEncounter
  if id != previousId: currentShotFrames = 0
  previousId = id
  inc currentShotFrames
  if id > 0: visited.incl(id)
  if id == 1: inc firstShotFrames
  doAssert firstShotFrames < 24*60,
    "the first conversation must finish within a minute, not 7.5 minutes"
  for item in sim.chatFeed:
    if item.aired: aired.incl(item.speaker.name & ": " & item.message)
  doAssert not replay.hashValidationFailed
  if paramCount()>0 and id in [1,2,5,8] and currentShotFrames==100 and id notin captured:
    createDir(paramStr(1))
    captured.incl(id)
    state.initialized = false
    state.spriteCache.setLen(0)
    var next:PlayerViewerState
    render(sim.buildGlobalPacket(state,next,replayControls=true,
      replayPlaying=replay.playing,replayTick=sim.tickCount,
      replayMaxTick=replay.replayMaxTick()),1440,900,
      paramStr(1)/("conversation-" & $id & ".png"))
    state = next
  if frames==300:
    replay.applyReplayCommand(sim,'P')
    let frozen = (sim.tickCount,sim.directorCamX,sim.directorCamY,sim.replayPresentationTime)
    for _ in 0..<30: discard sim.replayViewerFrame(replay,state,true)
    doAssert frozen == (sim.tickCount,sim.directorCamX,sim.directorCamY,sim.replayPresentationTime)
    replay.applyReplayCommand(sim,'p')
doAssert not replay.playing and sim.tickCount==replay.replayMaxTick()
doAssert visited.len==12, "every recorded conversation must receive a turn"
doAssert sim.convQueueIndex==sim.convQueue.len
doAssert aired.len >= 20, "dialogue must still appear while empty time is compressed"
echo "Real replay director: ",frames," frames, ",visited.len,
  " conversations, ",aired.len," distinct aired lines; first shot ",
  float(firstShotFrames)/24.0,"s. All replay hashes match."

var previousFrames = high(int)
for setting in 0..7:
  let trial = initSimServer(cfg.seed,cfg.dayTicks)
  trial.attachConversationTimeline(data,path)
  var run = initReplayPlayer(data)
  run.keyframes = replay.keyframes
  run.looping = false
  run.speedIndex = setting
  trial.buildConversationQueue(run.replayMaxTick())
  var count = 0
  var seen:HashSet[int]
  while run.playing and count < 96000:
    trial.advanceReplayPresentation(run)
    inc count
    if trial.directorCommitEncounter>0:seen.incl(trial.directorCommitEncounter)
    doAssert not run.hashValidationFailed
  doAssert not run.playing and trial.tickCount==run.replayMaxTick()
  doAssert seen.len==12
  doAssert count<previousFrames, "each faster setting must finish sooner"
  previousFrames=count
  echo "Real replay speed ",setting,": ",count," frames, all 12 conversations"
