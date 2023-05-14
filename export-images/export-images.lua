-- config export folder
local exportFolder = "/Users/chakkapanrapeepunpienpen/Desktop"
--

-- require
local fcp = require("cp.apple.finalcutpro")
local destinations = require("cp.apple.finalcutpro.export.destinations")
local just = require "cp.just"
local dialog = require "cp.dialog"
local fnutils = require "hs.fnutils"
local tools = require "cp.tools"

-- prepare util method
local doUntil = just.doUntil
local wait = just.wait
local incrementFilename = tools.incrementFilename

-- prepare fcp
local displayErrorMessage = dialog.displayErrorMessage
local displayMessage = dialog.displayMessage
local exportDialog = fcp.exportDialog
local timelineContents = fcp.timeline.contents
local initPlayhead = fcp:timeline().contents:playheadClipsUI()

if not timelineContents or not initPlayhead then
    displayErrorMessage("❌ Please make sure timeline is visible")
    return
end

-- prepare input
local button, whatToExport = hs.dialog.textPrompt("What to Export ?", "Export only marker which contains (Leave it empty to export all): ", "", "Export", "Cancel", false);
if button == 'Cancel' then
    return
end
print('export marker that contains: ' .. whatToExport)

-- export location
local FILES = hs.dialog.chooseFileOrFolder("Please select a folder to export:", "~/Desktop", false, true, false, { "txt" }, true)
if FILES == nil or FILES["1"] == nil then
    dialog.displayMessage("Please select a folder.")
    return
end
local exportFolder = FILES["1"]
print(exportFolder)

local saveCurrentFrameDestinationNumber = (function (clips)
	local destinationsName = destinations:names()
  	for i, name in ipairs(destinationsName) do
        if name == "Save Current Frame"
      	then
      		return i
    	end
	end
end)()
local _existingClipNames = {}

--------------------------------------------------------------------------------
-- Make sure Final Cut Pro is Active:
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- Make sure the Timeline is focussed:
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- Select clip:
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- Click on the Playhead (if we haven't already done above), as this
-- seems to be the only way to ensure that the timeline has focus:
--------------------------------------------------------------------------------
local wait_playhead = function(playhead)
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

--------------------------------------------------------------------------------
-- Make sure the Timeline is focused:
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- Make sure Save Window is closed:
--------------------------------------------------------------------------------
local wait_saveWindow = function (saveSheet)
    while saveSheet:isShowing() do
        local replaceAlert = saveSheet.replaceAlert
        if mod.replaceExistingFiles() and replaceAlert:isShowing() then
            replaceAlert:pressReplace()
        else
            replaceAlert:pressCancel()

            local originalFilename = saveSheet:filename()
            if originalFilename == nil then
                displayErrorMessage("❌ Failed to get the original Filename.")
                return false
            end

            local newFilename = incrementFilename(originalFilename)

            saveSheet:filename(newFilename)
            saveSheet:save()
        end
    end
end

local wait_backgroundTasks = function()
    --------------------------------------------------------------------------------
    -- Wait until the "Preparing" modal dialog closes or the
    -- Background Tasks Dialog opens:
    --------------------------------------------------------------------------------
    local backgroundTasksDialog = fcp.backgroundTasksDialog
    if fcp:isModalDialogOpen() then
        doUntil(function()
            return backgroundTasksDialog:isShowing() or fcp:isModalDialogOpen() == false
        end, 15)
    end
end

local wait_backgroundTasksWarning = function ()
    --------------------------------------------------------------------------------
    -- Check for Background Tasks warning:
    --------------------------------------------------------------------------------
    local backgroundTasksDialog = fcp.backgroundTasksDialog
    if backgroundTasksDialog:isShowing() then
        backgroundTasksDialog:cancel()
        displayMessage(i18n("batchExportBackgroundTasksDetected"))
        return false
    end
    return true
end


-- MAIN EXPORTER --
local processSaveDialog = function (tagName, exportFolderWithProjectName)
    --------------------------------------------------------------------------------
    -- If 'Next' has been clicked (as opposed to 'Share'):
    --------------------------------------------------------------------------------
    local saveSheet = exportDialog.saveSheet
    if exportDialog:isShowing() then

        --------------------------------------------------------------------------------
        -- Click 'Save' on the save sheet:
        --------------------------------------------------------------------------------
        if not doUntil(function() return saveSheet:isShowing() end, 5) then
            displayErrorMessage("❌ Failed to open the 'Save' window.")
            return false
        end

        --------------------------------------------------------------------------------
        -- Make sure we don't already have a clip with the same name in the export folder:
        --------------------------------------------------------------------------------
        local newFilename = tagName

        --------------------------------------------------------------------------------
        -- Increment filename is filename already exists in this batch:
        --------------------------------------------------------------------------------
        while fnutils.contains(_existingClipNames, newFilename) do
            newFilename = incrementFilename(newFilename)
        end

        --------------------------------------------------------------------------------
        -- Increment filename is filename already exists in the output directory:
        --------------------------------------------------------------------------------
        while tools.doesFileExist(exportFolderWithProjectName .. "/" .. newFilename .. '.png') do
            newFilename = incrementFilename(newFilename)
        end

        --------------------------------------------------------------------------------
        -- Update the filename and save it for comparison of next clip:
        --------------------------------------------------------------------------------
        if filename ~= newFilename then
            saveSheet:filename(newFilename)
        end
        table.insert(_existingClipNames, newFilename)
        -- end

        --------------------------------------------------------------------------------
        -- Click 'Save' on the save sheet:
        --------------------------------------------------------------------------------
        saveSheet:save()
    end

    wait_saveWindow(saveSheet)
end

local exportStillImage = function (tagName, projectName)
    local playhead = fcp:timeline().contents:playheadClipsUI()
    for i, clip in pairs(playhead) do
        print('# NUMBER OF CLIPS IN THIS PLAYHEAD : ' .. #playhead)
        if i ~= 1 then
            -- need to export just only time for each playhead
            return true
        end
        if not wait_fcpActive() then
            return false
        end
        if not wait_timelineFocussed() then
            return false
        end
        if not wait_selectClip(clip) then
            return false
        end

        wait_playhead(playhead)

        if not wait_timeline() then
            return false
        end

        --------------------------------------------------------------------------------
        -- Set Custom Export Path:
        --------------------------------------------------------------------------------
        local exportFolderWithProjectName = exportFolder .. '/' .. projectName
        local ensureResult = tools.ensureDirectoryExists(exportFolder, projectName)
        fcp.preferences:set("FFShareLastCurrentDirectory", exportFolderWithProjectName)

        --------------------------------------------------------------------------------
        -- Trigger Export:
        --------------------------------------------------------------------------------
        local errorMessage
        _, errorMessage = exportDialog:show(saveCurrentFrameDestinationNumber, true, true, true)
        if errorMessage then
            return false
        end

        --------------------------------------------------------------------------------
        -- Press 'Next':
        --------------------------------------------------------------------------------
        exportDialog:pressNext()

        processSaveDialog(tagName, exportFolderWithProjectName)

        --------------------------------------------------------------------------------
        -- Give Final Cut Pro a chance to show the "Preparing" modal dialog:
        --
        -- NOTE: I tried to avoid doing this, but it seems to be the only way to
        --       ensure the "Preparing" modal dialog actually appears. If I try and
        --       use a just.doUntil(), it seems to block Final Cut Pro from actually
        --       opening the "Preparing" modal dialog.
        --------------------------------------------------------------------------------
        wait(4)

        wait_backgroundTasks()

        if not wait_backgroundTasksWarning() then
            return false
        end
    end
    return true
end

-- START
local start = function ()
    -- FIRST ACTIVATE INDEX TOOL --
    local projectName = fcp:timeline().toolbar.title:getValue()
    fcp:timeline().toolbar.index:checked(true)
    fcp:timeline():index().tags.activate:checked(true)
    fcp:timeline():index().tags.all:checked(true)
    local tags = fcp:timeline():index().tags.list

    local tagNameColumnId, columnIdex = (function()
        local cols = tags:columnsUI()
        for i, col in ipairs(cols) do
            local identifier = col:attributeValue('AXIdentifier')
            local button = col:attributeValue('AXHeader')
            if button:attributeValue('AXTitle') == 'Name' then
                return identifier, i
            end
        end
        return nil
    end)()

    local fetchTagValue = function (rowNumber, row)
        local cell = tags:findCellUI(rowNumber, tagNameColumnId)
        if cell
        then
            return cell:attributeValue('AXValue')
        else
            local child = row:attributeValue('AXChildren')
            for j, n in ipairs(child) do
                if j == columnIdex then
                    return n:attributeValue('AXValue')
                end
            end
        end
        return ''
    end

    -- LOOP THROUGH ALL TAGS
    for i, row in ipairs(tags:rowsUI()) do
        local tagName = fetchTagValue(i, row)
        local exportName = 'Project: '.. projectName .. ' Tag #' .. i .. ' name:' .. tagName
        if string.find(tagName, whatToExport) then
            tags:selectRowAt(i)
            print('⚙️ Start export ' .. exportName)
            local result = exportStillImage(tagName, projectName)
            if not result then
                displayErrorMessage('❌ Error saving ' .. exportName)
            end
        else
            print('⚠️ Skip ' .. exportName)
        end
    end
    displayMessage('✅ Export Completed')
end

start()
