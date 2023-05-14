-- require
local fcp = require("cp.apple.finalcutpro")
local just = require "cp.just"
local dialog = require "cp.dialog"
local fnutils = require "hs.fnutils"
local tools = require "cp.tools"
local pasteboard = require "hs.pasteboard"

-- prepare util method
local doUntil = just.doUntil
local wait = just.wait

-- prepare fcp
local timelineContents = fcp.timeline.contents
local playhead = fcp:timeline().contents:playheadClipsUI()
local goToTimeCodeShortcuts = fcp:getCommandShortcuts("PasteTimecode")
if goToTimeCodeShortcuts == nil or #goToTimeCodeShortcuts == 0 then
    print("❌ Please set shortcut for command: PasteTimecode")
    return
end

local INPUT_FILE = "/Volumes/iDekBackUp/one piece timestamp/5 marker-2023-01-28_22-50-21.txt"

local splitStringBy = function(inputstr, sep)
	local  t = {}
    for token in string.gmatch(inputstr, "[^%s]+") do
       table.insert(t, token)
	end
    -- table contents from input: "elapse times: xx:xx:xx text: yyyy"
    -- 1 = elaspe
    -- 2 = times:
    -- 3 = xx:xx:xx
    -- 4 = text:
    -- 5 = yyyy
    return t[3], t[5]
end

local wait_fcpActive = function()
    if not doUntil(function()
        fcp:launch()
        return fcp:isFrontmost()
    end, 5, 0.1) then
        displayErrorMessage("Failed to activate Final Cut Pro. Batch Export aborted.")
        return false
    end
    return true
end

local wait_timelineFocussed = function()
    if not doUntil(function()
        fcp:selectMenu({"Window", "Go To", "Timeline"})
        return fcp.timeline.contents:isFocused()
	end, 5, 0.1) then
		displayErrorMessage("Failed to focus on timeline.")
      	return false
    end
    return true
end

local wait_selectClip = function (clip)
    if not doUntil(function()
		timelineContents:selectClip(clip)
        local selectedClips = timelineContents:selectedClipsUI(true)
        return selectedClips and #selectedClips == 1 and selectedClips[1] == clip
    end, 5, 0.1) then
      	displayErrorMessage("Failed to select clip.")
	    return false
    end
    return true
end

local wait_playhead = function()
    if isOnPrimaryStoryline then
    	local playheadUI = playhead and playhead:UI()
      	local playheadFrame = playheadUI and playheadUI:attributeValue("AXFrame")
      	local center = playheadFrame and geometry(playheadFrame).center
      	if center then
        	ninjaMouseClick(center)
        	wait(1)
	    end
    end
end

local wait_timeline = function()
    if not doUntil(function()
    	fcp:selectMenu({"Window", "Go To", "Timeline"})
        return timelineContents:isFocused()
    end, 5, 0.1) then
    	displayErrorMessage("Failed to focus on timeline.")
      	return false
    end
  	return true
end

local moveCursorToTimeCode = function(timecode)
    print('    Move cursor to time: ' .. timecode)
    pasteboard.setContents(timecode)

    --------------------------------------------------------------------------------
    -- Wait until the timecode is on the pasteboard:
    --------------------------------------------------------------------------------
    local pasteboardReady = doUntil(function()
        return pasteboard.getContents() == timecode
    end, 5, 0.1)

    if not pasteboardReady then
        print("cp.apple.finalcutpro.viewer.Viewer.timecode: Failed to add timecode to pasteboard.")
        return
    else
        local app = fcp:application()
        goToTimeCodeShortcuts[1]:trigger(app)

        doUntil(function()
            return tostring(fcp.viewer.controlBar.timecode) == "timecode: " .. timecode
        end, 5, 0.1)
    end
end

local addMarker = function(text)
    print('    Add marker with text: ' .. text)
    pasteboard.setContents(text)

    --------------------------------------------------------------------------------
    -- Wait until the timecode is on the pasteboard:
    --------------------------------------------------------------------------------
    local pasteboardReady = doUntil(function()
        return pasteboard.getContents() == text
    end, 5)

    if not pasteboardReady then
        print("cp.apple.finalcutpro.viewer.Viewer.timecode: Failed to add marker name to pasteboard.")
        return
    else
        local browser = fcp.browser.markerPopover:show()
        doUntil(function()
            return browser.name.isShowing
        end, 5, 0.1)
        fcp:keyStroke({ "cmd" }, 'V')
        wait(0.1)
        fcp:keyStroke({  }, 'return')
        wait(0.1)

        -- if not wait_fcpActive() then
        --     return false
        -- end
    end
end

local processLine = function(line)
    print('Process Line:')
    local time, text = splitStringBy(line, " ")
    moveCursorToTimeCode(time .. ':00')
    addMarker(text)
end

local run = function()
    for _, clip in pairs(playhead) do
        if not wait_fcpActive() then
            return false
        end
        if not wait_timelineFocussed() then
            return false
        end
        if not wait_selectClip(clip) then
            return false
        end

        wait_playhead()

        if not wait_timeline() then
            return false
        end

        local file = io.open(INPUT_FILE, "r")
        local lines = file:lines()
        for line in lines do
            processLine(line)
        end
        file:close()
        return
    end
end

run()