-- requirement
-- MAKE SURE YOU ACTIVE THE CLIPS IN BROWSER FIRST !!!!

-- require
local fcp = require("cp.apple.finalcutpro")
local just = require "cp.just"
local dialog = require "cp.dialog"
local fnutils = require "hs.fnutils"
local tools = require "cp.tools"
local pasteboard = require "hs.pasteboard"
local geometry = require "hs.geometry"
local ninjaMouseClick   = tools.ninjaMouseClick
local displayErrorMessage = dialog.displayErrorMessage

-- prepare util method
local doUntil = just.doUntil
local wait = just.wait

-- prepare fcp
local goToTimeCodeShortcuts = fcp:getCommandShortcuts("PasteTimecode")
if goToTimeCodeShortcuts == nil or #goToTimeCodeShortcuts == 0 then
    print("❌ Please set shortcut for command: PasteTimecode")
    return
end

-- prepare input
local FILES = hs.dialog.chooseFileOrFolder("Please select a file:", "~/Desktop", true, false, false, {"txt"}, true)
if FILES == nil or FILES["1"] == nil then
    dialog.displayMessage("Please select a file.")
    return
end
local INPUT_FILE = FILES["1"]
print(INPUT_FILE)

local find_table_size = function(t)
	local table_size = 0
  	for _ in pairs(t) 
    do
       table_size = table_size + 1
    end
  	return table_size
end

local join_table = function(t, start)
    local text = ''
    local table_size = find_table_size(t)
    local has_run_once = false
    for i = start, table_size, 1
    do
      if has_run_once then
          text = text .. ' ' .. t[i]
      else
          text = t[i]
          has_run_once = true
      end
    end
    return text
end

local splitStringBy = function(inputstr, sep)
	local  t = {}
    for token in string.gmatch(inputstr, "[^%s]+") do
       table.insert(t, token)
	end
    -- table contents from input: "elapse times: xx:xx:xx text: yyyy zzzz"
    -- 1 = elaspe
    -- 2 = times:
    -- 3 = xx:xx:xx
    -- 4 = text:
    -- 5 = yyyy
    -- 6 = zzzz
    -- append text start from #5 until the end of table
	text = join_table(t, 5)
    return t[3], text
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

local wait_playhead = function()
    -- if isOnPrimaryStoryline then
        local playheadUI = fcp.browser.libraries:playhead():UI()
      	local playheadFrame = playheadUI and playheadUI:attributeValue("AXFrame")
      	local center = playheadFrame and geometry(playheadFrame).center
      	if center then
        	ninjaMouseClick(center)
        	wait(1)
	    end
    -- end
end

local wait_browser = function()
    if not doUntil(function()
        fcp:keyStroke({ "cmd" }, '1')
        return fcp.browser.libraries.list().isShowing()
    end, 5, 0.1) then
    	displayErrorMessage("Failed to focus on browser.")
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
    print('Process Line:' .. line)
    local time, text = splitStringBy(line, " ")
    moveCursorToTimeCode(time .. ':00')
    addMarker(text)
end

local run = function()
    if not wait_fcpActive() then
        return false
    end
    if not wait_browser() then
        return false
    end

    wait_playhead()

    local file = io.open(INPUT_FILE, "r")
    local lines = file:lines()
    for line in lines do
        processLine(line)
    end
    file:close()
    return
end

run()