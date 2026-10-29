-- macOS adapter. The pure model owns scheduling; storage owns durable records.
local Config = require("study.config")
local Materials = require("study.materials")
local Allocation = require("study.allocation")
local Model = require("study.model")
local Storage = require("study.storage")
local M = {}
local function copy(t) local r={} for k,v in pairs(t or {}) do r[k]=v end return r end
local function sameFrame(a,b,tolerance)
  if not a or not b then return false end
  for _,k in ipairs({"x","y","w","h"}) do
    if math.abs(a[k]-b[k])>tolerance then return false end
  end
  return true
end
local function normalizedTitle(title)
  return (title or ""):gsub(" %- Google Chrome.*$", "")
end

function M.new(hs,root)
  local self={hs=hs,root=root,cfg=Config,timers={},hotkeys={},generation=0,
    model=nil,store=nil,meta=nil,mask=nil,mouseTap=nil,windowID=nil,
    approvedFrame=nil,setupApproved=false,calibrationCorner={},fatal=false}
  return setmetatable(self,{__index=M})
end
function M:now() return self.hs.timer.absoluteTime()/1e9 end
function M:wall() return self.hs.timer.secondsSinceEpoch() end
function M:guard(fn,...)
  local args=table.pack(...)
  local ok,result=xpcall(function() return fn(table.unpack(args,1,args.n)) end,debug.traceback)
  if ok then return result end
  self.fatal=true
  -- Best-effort synchronous cleanup even if one native API itself failed.
  pcall(function()self:cancelTimers()end)
  pcall(function()self:stopSound()end)
  pcall(function()self:unlock()end)
  pcall(function()self:hideMask()end)
  self.setupApproved=false
  if self.store and self.model and self.model.phase~="SESSION_COMPLETE" then
    pcall(function()self.store:checkpoint(self.model:snapshot())end)
    pcall(function()self.store:markInterrupted("Controller exception: "..tostring(result))end)
  end
  print("[HCI2000] STOP: "..tostring(result))
  pcall(function()self:notice("Controller stopped after an error. Input released; review records before restarting.")end)
  return nil,result
end
function M:notice(message)
  print("[HCI2000] "..tostring(message))
  self.hs.alert.show(tostring(message),3)
end
function M:context()
  local model=self.model
  local b=model and model:currentBlock()
  local t=model and model:currentTrial()
  return {block=model and model.blockIndex,condition=b and b.name,
    orientation=b and b.orientation,tab_load=b and b.tabLoad,
    content_set=b and b.contentSet,trial=t and t.id,target_id=t and t.targetID,
    target_title=t and t.targetTitle,phase=model and model.phase or "NO_SESSION",
    wall_epoch=self:wall(),monotonic_s=self:now()}
end
function M:event(name,extra)
  if not self.store then return true end
  local ctx=self:context()
  for k,v in pairs(extra or {}) do ctx[k]=v end
  local ok,err=self.store:event(name,ctx)
  if not ok then self:storageFailure(err) end
  return ok
end
function M:checkpoint()
  if not self.store or not self.model then return true end
  local s=self.model:snapshot()
  s.window_id=self.windowID; s.approved_frame=self.approvedFrame
  s.pointer_start=self.hs.settings.get(self.cfg.settingsPrefix.."pointer")
  s.mask_calibrations={
    H=self.hs.settings.get(self.cfg.settingsPrefix.."mask_H"),
    V=self.hs.settings.get(self.cfg.settingsPrefix.."mask_V"),
  }
  local ok,err=self.store:checkpoint(s)
  if not ok then self:storageFailure(err) end
  return ok
end
function M:storageFailure(err)
  if self.fatal then return end
  self.fatal=true
  self:cancelTimers(); self:stopSound(); self:unlock(); self:hideMask()
  self.setupApproved=false
  self:notice("STOP: recording file error. Do not restart or replay. "..tostring(err))
end
function M:cancelTimers()
  self.generation=self.generation+1
  for _,t in pairs(self.timers) do t:stop() end
  self.timers={}
end
function M:after(key,delay,fn)
  if self.timers[key] then self.timers[key]:stop() end
  local generation=self.generation
  self.timers[key]=self.hs.timer.doAfter(delay,function()
    self.timers[key]=nil
    if not self.fatal and self.generation==generation then self:guard(fn) end
  end)
end
function M:stopSound()
  local sound=self.sound; self.sound=nil
  if sound then sound:setCallback(nil); sound:stop() end
end
function M:window()
  if not self.windowID then return nil end
  local win=self.hs.window.get(self.windowID)
  if not win then return nil end
  local app=win:application()
  if not app or app:name()~=self.cfg.chromeAppName then return nil end
  return win
end
function M:validWindow(requireForeground)
  local win=self:window()
  if not win then return nil,"Selected study window is missing" end
  if win:isMinimized() then return nil,"Study window is minimized" end
  if not sameFrame(win:frame(),self.approvedFrame,self.cfg.windowTolerancePixels) then
    return nil,"Study window moved/resized; restore it in Setup"
  end
  if requireForeground then
    local front=self.hs.window.frontmostWindow()
    if not front or front:id()~=self.windowID then return nil,"Study window lost focus" end
  end
  return win
end
function M:unlock()
  if self.mouseTap then self.mouseTap:stop();self.mouseTap=nil end
  if self.timers.lock then self.timers.lock:stop();self.timers.lock=nil end
end
function M:lock()
  self:unlock()
  local types=self.hs.eventtap.event.types
  local events={}
  for _,key in ipairs({"leftMouseDown","leftMouseUp","rightMouseDown","rightMouseUp",
    "otherMouseDown","otherMouseUp","mouseMoved","leftMouseDragged",
    "rightMouseDragged","otherMouseDragged","scrollWheel"}) do
    if types[key] then events[#events+1]=types[key] end
  end
  self.mouseTap=self.hs.eventtap.new(events,function() return true end)
  self.mouseTap:start()
  if self.mouseTap.isEnabled and not self.mouseTap:isEnabled() then
    self:unlock(); return nil,"Mouse lock unavailable: check Accessibility/Input Monitoring"
  end
  self:after("lock",self.cfg.lockWatchdogSeconds,function()
    self:emergency("Input-lock watchdog expired")
  end)
  return true
end
function M:maskSpec()
  local b=self.model and self.model:currentBlock()
  if not b then return nil end
  return self.hs.settings.get(self.cfg.settingsPrefix.."mask_"..b.orientation)
end
function M:hideMask()
  if self.mask then self.mask:delete(0);self.mask=nil end
end
function M:showMask()
  local win,err=self:validWindow(false)
  if not win then return nil,err end
  local s=self:maskSpec()
  if not s then return nil,"Calibrate the current orientation's mask first" end
  local f=win:frame()
  if not s.frame_w or not s.frame_h or math.abs(s.frame_w-f.w)>self.cfg.windowTolerancePixels
    or math.abs(s.frame_h-f.h)>self.cfg.windowTolerancePixels then
    return nil,"Browser size changed since mask calibration; recalibrate this orientation"
  end
  if s.screen_id and tostring(win:screen():id())~=s.screen_id then
    return nil,"Display changed: recalibrate masks/pointer"
  end
  self:hideMask()
  self.mask=self.hs.canvas.new({x=f.x+s.x,y=f.y+s.y,w=s.w,h=s.h})
  self.mask:appendElements({type="rectangle",action="fill",fillColor=self.cfg.maskColor})
  self.mask:clickActivating(false)
  if self.mask.level and self.hs.canvas.windowLevels then
    self.mask:level(self.hs.canvas.windowLevels.overlay)
  end
  self.mask:show(0)
  self.mask:bringToFront(true)
  return true
end
function M:inSetup()
  return not self.model or self.model.phase=="SETUP"
end
function M:captureFrame()
  if not self:inSetup() then return self:notice("Enter Setup before calibration") end
  local app=self.hs.application.get(self.cfg.chromeAppName)
  local win=app and app:mainWindow()
  if not win then return self:notice("Open the dedicated Chrome study window") end
  self.windowID=win:id();self.approvedFrame=copy(win:frame())
  self.hs.settings.set(self.cfg.settingsPrefix.."frame",self.approvedFrame)
  self:notice("Study window/frame saved. Calibrate H and V masks in this same frame.")
end
function M:capturePointer()
  if not self:inSetup() then return self:notice("Enter Setup before calibration") end
  self.hs.settings.set(self.cfg.settingsPrefix.."pointer",self.hs.mouse.absolutePosition())
  self:notice("Common absolute pointer position saved")
end
function M:calibrateMask(orientation)
  if not self:inSetup() then return self:notice("Enter Setup before calibration") end
  local win=self:window()
  if not win then return self:notice("Save the study window/frame first") end
  if not sameFrame(win:frame(),self.approvedFrame,self.cfg.windowTolerancePixels) then
    return self:notice("Restore the saved frame before calibrating")
  end
  local p=self.hs.mouse.absolutePosition()
  if not self.calibrationCorner[orientation] then
    self.calibrationCorner[orientation]={x=p.x,y=p.y}
    return self:notice(orientation..": top-left saved; point to bottom-right and press again")
  end
  local first=self.calibrationCorner[orientation];self.calibrationCorner[orientation]=nil
  if p.x<=first.x or p.y<=first.y then return self:notice("Invalid corners; start again at top-left") end
  local f=win:frame()
  self.hs.settings.set(self.cfg.settingsPrefix.."mask_"..orientation,
    {x=first.x-f.x,y=first.y-f.y,w=p.x-first.x,h=p.y-first.y,
      frame_w=f.w,frame_h=f.h,screen_id=tostring(win:screen():id())})
  self:notice(orientation.." mask calibrated; verify full tab coverage in OBS")
end
function M:text(prompt,default)
  local button,value=self.hs.dialog.textPrompt("HCI2000 researcher setup",prompt,default or "","OK","Cancel")
  if button~="OK" then return nil end
  return value and value:match("^%s*(.-)%s*$")
end
function M:newSession()
  if self.model and self.model.phase~="SESSION_COMPLETE" then
    return self:notice("An existing session is loaded. Finish it or use End session; no silent restart.")
  end
  local mode=self:text("Mode: test, pilot, or main","pilot")
  if not mode then return end
  if mode~="test" and mode~="pilot" and mode~="main" then return self:notice("Invalid mode") end
  if mode=="main" and not self.cfg.mainStudyEnabled then
    return self:notice("Main mode is disabled until the Mac checklist is completed in config.lua")
  end
  if mode=="main" then
    for key,value in pairs(self.cfg.recordingProfile) do
      if tostring(value):find("UNVERIFIED",1,true) then
        return self:notice("Complete the study configuration first: "..key)
      end
    end
  end
  local participant=self:text("Participant code (letters/numbers, no names)",mode=="main" and "" or "TEST001")
  if not participant then return end
  if not participant:match("^[A-Z][A-Z0-9_%-]*$") or #participant>32 then
    return self:notice("Use a short uppercase code, e.g. P001 or PILOT001")
  end
  local entry=mode=="main" and Allocation[participant]
  if mode=="main" and not entry then return self:notice("Code is absent from the frozen main allocation") end
  local group=entry and entry.group or tonumber(self:text("Allocated group: 1, 2, 3, or 4", ""))
  if not group or group%1~=0 or group<1 or group>4 then return self:notice("Group must be 1-4") end
  local plan=Materials.buildPlan(group)
  local lines={"Mode: "..mode,"Participant: "..participant,"Group: "..group}
  if entry then lines[#lines+1]="Practice first: "..entry.practiceFirst end
  for i,b in ipairs(plan) do lines[#lines+1]=i..". "..b.name.." / "..b.contentSet.." ("..b.topic..")" end
  local confirm=self.hs.dialog.blockAlert("Confirm session",table.concat(lines,"\n"),"Create session","Cancel")
  if confirm~="Create session" then return end
  for _,b in ipairs(plan) do for _,t in ipairs(b.trials) do
    if not self.hs.fs.attributes(self.root.."/orlando_audio/"..t.audio) then
      return self:notice("Missing audio: "..t.audio..". No session created.")
    end
  end end
  local run=os.date("!%Y%m%dT%H%M%SZ").."-"..string.format("%.0f",self.hs.timer.absoluteTime())
  local meta={schema_version="2.0",mode=mode,participant=participant,group=group,session_id=run,
    plan=plan,practice_first=entry and entry.practiceFirst or "not-main-allocation",
    versions={controller=self.cfg.version,materials=Materials.version,manifest_sha256=Materials.manifestSha256,
      original_zip_sha256=Materials.sourceZipSha256,expected_audio_sha256=Materials.audioSha256},
    settings=copy(self.cfg),start_cue="mask_disappearance",recording_status="REQUIRES_MAC_AND_VIDEO_VERIFICATION"}
  local store,err=Storage.create(self.root.."/records",meta,self.hs)
  if not store then return self:notice("Session not created: "..tostring(err)) end
  self:cancelTimers();self:stopSound();self:unlock();self:hideMask()
  self.store=store;self.meta=meta;self.model=Model.new(plan);self.fatal=false
  self.windowID=nil;self.approvedFrame=self.hs.settings.get(self.cfg.settingsPrefix.."frame")
  self.setupApproved=false
  if not self:event("SESSION_CREATED",{detail="Awaiting researcher setup; final measurements are video-coded"}) then return end
  if not self:checkpoint() then return end
  self:notice("Session created. Prepare block, save study window, then approve setup (Ctrl+Alt+Cmd+A).")
end
function M:setup()
  if not self.model or self.fatal then return self:notice("Create a session first, or review the stopped session") end
  if self.model.phase=="PAUSED" then
    local ok,err=self.model:resume();if not ok then return self:notice(err) end
  end
  if self.model.phase=="BLOCK_COMPLETE" then return self:notice("Collect workload ratings, then Next block") end
  if self.model.phase~="SETUP" and self.model.phase~="READY" then
    return self:notice("Pause/interrupt the exposed trial before entering Setup")
  end
  self:cancelTimers();self:stopSound();self:unlock();self:hideMask()
  if self.model.phase~="SETUP" then self.model:resetPreflight() end
  self.setupApproved=false
  if not self:event("RESEARCHER_SETUP",{detail="Participant must not watch preparation; restore viewport/order manually"}) then return end
  if not self:checkpoint() then return end
  self:notice("Setup: restore scroll/order/orientation, keep preparation out of participant view, then approve")
end
function M:approveSetup()
  if not self.model or self.model.phase~="SETUP" or self.fatal then return self:notice("Enter Setup first") end
  if not self.windowID then return self:notice("Save the Chrome study window/frame with Ctrl+Alt+Cmd+W") end
  local win,err=self:validWindow(false)
  if not win then return self:notice(err) end
  if not self.hs.settings.get(self.cfg.settingsPrefix.."pointer") then return self:notice("Calibrate the pointer first") end
  if not self:maskSpec() then return self:notice("Calibrate this orientation's mask first") end
  local b=self.model:currentBlock()
  local message=string.format("%s / %s (%s)\nExactly %d total tabs; Study Start LAST (rightmost/bottom).\nVerify actual order, orientation, fixed panel width, scroll reset, hover aids OFF.\nOBS must record the mask, pointer and audio. Preparation must be hidden from the participant.\nConfirm these checks for this trial.",b.name,b.contentSet,b.topic,b.expectedTabCount)
  local answer=self.hs.dialog.blockAlert("Researcher preflight",message,"Checks complete","Cancel")
  if answer~="Checks complete" then return end
  local ok,why=self.model:ready();if not ok then return self:notice(why) end
  self.setupApproved=true
  win:focus()
  local masked,maskErr=self:showMask()
  if not masked then self.model:resetPreflight();self.setupApproved=false;return self:notice(maskErr) end
  local locked,lockErr=self:lock()
  if not locked then self:emergency(lockErr);return end
  if not self:event("PREFLIGHT_APPROVED",{detail="Orientation/order/scroll/recording manually confirmed"}) then return end
  if not self:checkpoint() then return end
  self:notice("Ready. Press Ctrl+Alt+Cmd+Return to start this trial")
end
function M:startTrial()
  if not self.model or self.fatal then return self:notice("No usable session") end
  if self.model.phase~="READY" or not self.setupApproved then return self:notice("Enter Setup and approve this trial first") end
  local win,err=self:validWindow(true)
  if not win then return self:emergency(err) end
  self:cancelTimers()
  local ok,why=self.model:prepare();if not ok then return self:notice(why) end
  self.setupApproved=false
  if not self:checkpoint() then return end
  local masked,maskErr=self:showMask();if not masked then return self:emergency(maskErr) end
  local locked,lockErr=self:lock();if not locked then return self:emergency(lockErr) end
  local focusOK=false
  -- Study Start is the LAST tab (6 at low load, 16 at high load).
  -- Chrome's Cmd+9 always selects the last tab, whatever the tab count.
  local lastTab=self.model:currentBlock().expectedTabCount
  local callOK,result=pcall(function() return win:focusTab(lastTab) end)
  focusOK=callOK and result==true
  if not focusOK then self.hs.eventtap.keyStroke({"cmd"},"9",0,win:application()) end
  local deadline=self:now()+self.cfg.neutralWaitSeconds
  local function check()
    if self.model.phase~="PREPARING" then return end
    local current,reason=self:validWindow(true)
    if not current then return self:emergency(reason) end
    if normalizedTitle(current:title())==self.cfg.neutralTitle then
      local p=self.hs.settings.get(self.cfg.settingsPrefix.."pointer")
      self.hs.mouse.absolutePosition(p)
      local actual=self.hs.mouse.absolutePosition()
      if math.abs(actual.x-p.x)>2 or math.abs(actual.y-p.y)>2 then return self:emergency("Pointer reset failed") end
      self.lastTitle=self.cfg.neutralTitle
      self.aux={selections=0,incorrect=0,first=nil,pages={}}
      if not self:event("START_STATE_VERIFIED",{detail="Neutral title/frame/pointer checked; native order/scroll manually checked"}) then return end
      return self:playPrompt()
    end
    if self:now()>=deadline then return self:emergency("Study Start could not be verified") end
    self:after("neutral",0.05,check)
  end
  check()
end
function M:playPrompt()
  local trial=self.model:currentTrial()
  local sound=self.hs.sound.getByFile(self.root.."/orlando_audio/"..trial.audio)
  if not sound then return self:emergency("Audio could not be decoded before exposure: "..trial.audio) end
  local ok,err=self.model:prompt();if not ok then return self:emergency(err) end
  self.sound=sound
  if not self:checkpoint() then return end -- Exposure intent persisted before playback.
  if not self:event("PROMPT_PLAY_REQUESTED",{detail=trial.audio}) then return end
  sound:setCallback(function(completed)self:guard(function()
    if self.sound~=sound or self.fatal then return end
    self.sound=nil
    if not completed then return self:emergency("Audio interrupted; prompt may have been exposed") end
    if self.model.phase~="PROMPT" then return end
    self.model:waitReveal()
    if not self:event("PROMPT_FINISHED") then return end
    if not self:checkpoint() then return end
    self:after("reveal",self.cfg.postPromptDelaySeconds,function() self:reveal() end)
  end)end)
  local started=sound:play()
  if not started then return self:emergency("Audio playback failed; exposure is conservatively retained") end
  self:watchConfiguration()
end
function M:watchConfiguration()
  if self.timers.monitor then self.timers.monitor:stop() end
  self.timers.monitor=self.hs.timer.doEvery(0.10,function()self:guard(function()
    if self.fatal or not self.model then return end
    local phase=self.model.phase
    if phase=="PROMPT" or phase=="WAIT_REVEAL" or phase=="RUNNING" then
      local _,err=self:validWindow(true)
      if err then self:emergency(err) end
    end
  end)end)
end
function M:reveal()
  if self.fatal or self.model.phase~="WAIT_REVEAL" then return end
  local win,err=self:validWindow(true)
  if not win then return self:emergency(err) end
  if normalizedTitle(win:title())~=self.cfg.neutralTitle then return self:emergency("Neutral page changed before reveal") end
  self.lastTitle=self.cfg.neutralTitle -- Known baseline established BEFORE input release.
  local ok,why=self.model:reveal();if not ok then return self:emergency(why) end
  self.revealTime=self:now()
  self.model.currentRecord.reveal_command_monotonic_s=self.revealTime
  if not self:checkpoint() then return end
  if not self:event("REVEAL_COMMAND",{detail="Software marker, not the first recorded visible frame"}) then return end
  self:hideMask();self:unlock()
  self:after("timeout",self.cfg.timeoutSeconds,function() self:finish("timeout") end)
  if self.cfg.autoDetectTarget then
    self.timers.poll=self.hs.timer.doEvery(self.cfg.pollIntervalSeconds,function() self:guard(function()self:poll()end) end)
  end
end
function M:poll()
  if self.fatal or not self.model or self.model.phase~="RUNNING" then return end
  local win,err=self:validWindow(true)
  if not win then return self:emergency(err) end
  local title=normalizedTitle(win:title())
  if title==self.lastTitle then return end
  self.lastTitle=title
  local target=self.model:currentTrial().targetTitle
  local correct=title==target
  self.aux.selections=self.aux.selections+1
  if self.aux.first==nil then self.aux.first=correct and 1 or 0 end
  if not correct then self.aux.incorrect=self.aux.incorrect+1;self.aux.pages[#self.aux.pages+1]=title end
  self:event("TITLE_CHANGE_OBSERVED",{observed_title=title,elapsed_s=self:now()-self.revealTime,
    aux_selection_count=self.aux.selections,aux_incorrect_count=self.aux.incorrect,
    aux_first_correct=self.aux.first,detail="Polling observation; verify all selections against video"})
  if correct and not self.fatal then self:finish("completed_auto") end
end
function M:recordOutcome(record,source)
  if not record or not self.store then return true end
  local b=self.meta.plan[record.block_index]
  local row=copy(record)
  row.block=record.block_index;row.trial=record.trial_id
  row.orientation=b.orientation;row.tab_load=b.tabLoad
  row.timed_started=record.timed_interval_started
  row.reason=record.detail
  row.verification_required=true
  if self.revealTime and record.timed_interval_started then
    row.reveal_command_monotonic_s=self.revealTime
    if source=="completed_auto" then row.auto_detection_elapsed_s=self:now()-self.revealTime end
    if source=="completed_manual" then row.manual_ack_elapsed_s=self:now()-self.revealTime end
  end
  if self.aux and record.timed_interval_started then
    row.aux_selection_count=self.aux.selections
    row.aux_incorrect_count=self.aux.incorrect
    row.aux_first_correct=self.aux.first
  end
  local ok,err=self.store:trial(row)
  if not ok then self:storageFailure(err) end
  return ok
end
function M:finish(status)
  if not self.model or self.fatal or self.model.phase~="RUNNING" then return end
  local ok,record=self.model:finish(status,"Final outcome measurements require video coding")
  if not ok then return self:notice(record) end
  self:cancelTimers()
  if not self:recordOutcome(record,status) then return end
  self:event("TRIAL_OUTCOME",{detail=status});if self.fatal then return end
  if not self:checkpoint() then return end
  local locked,err=self:lock();if not locked then return self:emergency(err) end
  -- Retain the completed page for OBS, excluding this hold from the endpoint.
  self:after("outcome",self.cfg.outcomeHoldSeconds,function()
    local masked,why=self:showMask()
    if not masked then return self:emergency(why) end
    self.model:settleOutcome();self.setupApproved=false;self.revealTime=nil
    if not self:checkpoint() then return end
    if self.model.phase=="BLOCK_COMPLETE" then
      self:notice("Block finished. Collect workload ratings, then use Next block.")
    else
      self:notice("Trial finished. Enter Setup to reset viewport and approve the next trial.")
    end
  end)
end
function M:emergency(reason)
  self:cancelTimers();self:stopSound();self:unlock();self:hideMask()
  self.setupApproved=false
  if self.model and self.model.phase=="SESSION_COMPLETE" then
    return self:notice("Session is already complete; no active trial to interrupt")
  end
  if self.model and not self.fatal then
    local phase=self.model.phase
    if phase=="OUTCOME" then
      self.model:settleOutcome()
      if self.model.phase=="READY" then self.model:pause() end
    elseif phase=="READY" then self.model:pause()
    elseif phase=="SETUP" or phase=="PAUSED" or phase=="BLOCK_COMPLETE" or phase=="SESSION_COMPLETE" then
      -- Already safe/non-running; do not create a second outcome.
    else
      local ok,record=self.model:interrupt(reason)
      if ok and record then self:recordOutcome(record,"interrupted") end
    end
    self:event("PAUSE_OR_INTERRUPTION",{detail=reason})
    self:checkpoint()
  end
  self.revealTime=nil
  self:notice("Stopped: "..tostring(reason)..". No prompt will restart automatically. Review, then enter Setup.")
end
function M:nextBlock()
  if not self.model or self.fatal or self.model.phase~="BLOCK_COMPLETE" then return self:notice("Finish the current block first") end
  self:cancelTimers();self:unlock();self:hideMask()
  local answer=self.hs.dialog.blockAlert("Block transition","Have the workload ratings been completed? Prepare the next block with the participant not watching.","Continue","Cancel")
  if answer~="Continue" then return end
  self.model:nextBlock();self.setupApproved=false
  if not self:event("BLOCK_ADVANCED") then return end
  if not self:checkpoint() then return end
  if self.model.phase=="SESSION_COMPLETE" then
    local ok,err=self.store:close("completed")
    if not ok then return self:storageFailure(err) end
    return self:notice("Four blocks finished. Complete TLX weighting/interview. Video coding remains required.")
  end
  self.model:resetPreflight()
  if not self:event("NEXT_BLOCK_SETUP") then return end
  if not self:checkpoint() then return end
  self:notice("Prepare "..self.model:currentBlock().name.." / Set "..self.model:currentBlock().contentSet)
end
function M:endSession()
  if not self.store or not self.model then return end
  if self.model.phase=="SESSION_COMPLETE" then return self:notice("Session is already complete") end
  self:emergency("Session ended by facilitator")
  if self.fatal then return end
  local status=#self.model.outcomes==0 and not self.model.exposed and "cancelled_unexposed" or "interrupted"
  local ok,err
  if status=="cancelled_unexposed" then ok,err=self.store:close(status)
  else ok,err=self.store:markInterrupted("Facilitator ended session; review required before reuse") end
  if not ok then return self:storageFailure(err) end
  self.model=nil;self.store=nil;self.meta=nil
  self:notice("Session stopped. Exposed/interrupted sessions retain their review guard.")
end
function M:status()
  if not self.model then return self:notice("No session. New session: Ctrl+Alt+Cmd+B") end
  local b=self.model:currentBlock()
  self:notice(string.format("%s | group %d | block %d | trial %d | %s | %s",self.meta.participant,
    self.meta.group,self.model.blockIndex,self.model.trialIndex,self.model.phase,b and b.name or "finished"))
end
function M:install()
  local bindings={
    {"b",function()self:newSession()end}, {"s",function()self:setup()end},
    {"a",function()self:approveSetup()end}, {"return",function()self:startTrial()end},
    {".",function()self:finish("completed_manual")end},
    {"p",function()self:emergency("Participant break / facilitator pause")end},
    {"i",function()self:emergency("Trial invalidated by facilitator")end},
    {"escape",function()self:emergency("Emergency release")end},
    {"n",function()self:nextBlock()end}, {"c",function()self:capturePointer()end},
    {"w",function()self:captureFrame()end}, {"h",function()self:calibrateMask("H")end},
    {"v",function()self:calibrateMask("V")end}, {"t",function()self:status()end},
    {"e",function()self:endSession()end},
  }
  for _,b in ipairs(bindings) do
    local action=b[2]
    self.hotkeys[#self.hotkeys+1]=self.hs.hotkey.bind(self.cfg.modifiers,b[1],function()self:guard(action)end)
  end
  self.menu=self.hs.menubar.new()
  if self.menu then
    self.menu:setTitle("HCI")
    local items={
      {title="New session (Ctrl+Alt+Cmd+B)",fn=function()self:newSession()end},
      {title="Setup/reset viewport (S)",fn=function()self:setup()end},
      {title="Approve setup (A)",fn=function()self:approveSetup()end},
      {title="Start trial (Return)",fn=function()self:startTrial()end},
      {title="Correct target observed (.)",fn=function()self:finish("completed_manual")end},
      {title="Pause / interrupt (P)",fn=function()self:emergency("Facilitator pause")end},
      {title="Next block (N)",fn=function()self:nextBlock()end},
      {title="Status (T)",fn=function()self:status()end},
      {title="End session (E)",fn=function()self:endSession()end},
    }
    for _,item in ipairs(items) do
      local action=item.fn;item.fn=function()self:guard(action)end
    end
    self.menu:setMenu(items)
  end
  self:notice("HCI controller loaded. New session: Ctrl+Alt+Cmd+B. Use test/pilot mode first.")
end
function M:shutdown(reason)
  if self.shutdownCalled then return end
  self.shutdownCalled=true
  self:cancelTimers();self:stopSound();self:unlock();self:hideMask()
  if self.store and self.model and self.model.phase~="SESSION_COMPLETE" then
    if not self.fatal then
      self:emergency(reason or "Controller stopped")
      self.store:markInterrupted(reason or "Controller stopped; review before restarting")
    end
  end
  for _,key in ipairs(self.hotkeys) do key:delete() end
  self.hotkeys={}
  if self.menu then self.menu:delete();self.menu=nil end
end
return M