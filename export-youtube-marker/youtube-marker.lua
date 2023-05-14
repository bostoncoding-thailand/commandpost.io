-- require
local fcp = require("cp.apple.finalcutpro")
local destinations = require("cp.apple.finalcutpro.export.destinations")
local just = require "cp.just"
local dialog = require "cp.dialog"
local fnutils = require "hs.fnutils"
local tools = require "cp.tools"
local pasteboard = require "hs.pasteboard"

-- prepare util method
local doUntil = just.doUntil
local wait = just.wait
local incrementFilename = tools.incrementFilename

-- prepare fcp
local displayErrorMessage = dialog.displayErrorMessage
local displayMessage = dialog.displayMessage
local exportDialog = fcp.exportDialog
local timelineContents = fcp.timeline.contents
local playhead = fcp:timeline().contents:playheadClipsUI()

if not timelineContents or not playhead then
    displayErrorMessage("❌ Please make sure timeline is visible")
    return
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

-- prepare input
local FILES = hs.dialog.chooseFileOrFolder("Please select a folder or a file to export tag:", "~/Desktop", true, true, false, {"txt"}, true)
if FILES == nil or FILES["1"] == nil then
    dialog.displayMessage("Please select a folder or a file.")
    return
end
local OUTPUT_FILE = FILES["1"]
if not string.find(OUTPUT_FILE, ".txt") then
    OUTPUT_FILE = OUTPUT_FILE .. "/youtube-marker.txt"
end
print(OUTPUT_FILE)

local start = function ()
    if not wait_fcpActive() then
        return false
    end
    -- FIRST ACTIVATE INDEX TOOL --
    local projectName = fcp:timeline().toolbar.title:getValue()
    fcp:timeline().toolbar.index:checked(true)
    fcp:timeline():index().tags.activate:checked(true)
    fcp:timeline():index().tags.all:checked(true)
    local tags = fcp:timeline():index().tags.list

    local tagNameColumnId, tagColumnIdex = (function()
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
    local positionColumnId, positionColumnIdex = (function()
        local cols = tags:columnsUI()
        for i, col in ipairs(cols) do
            local identifier = col:attributeValue('AXIdentifier')
            local button = col:attributeValue('AXHeader')
            if button:attributeValue('AXTitle') == 'Position' then
                return identifier, i
            end
        end
        return nil
    end)()

    local fetchCellData = function(row, rowNumber, columnId, columnIndex)
        local cell = tags:findCellUI(rowNumber, columnId)
        if cell
        then
            return cell:attributeValue('AXValue')
        else
            local child = row:attributeValue('AXChildren')
            for j, n in ipairs(child) do
                if j == columnIndex then
                    return n:attributeValue('AXValue')
                end
            end
        end
    end

    local fetchMarkerData = function (rowNumber, row)
        local tagName = fetchCellData(row, rowNumber, tagNameColumnId, tagColumnIdex)
        local postion = fetchCellData(row, rowNumber, positionColumnId, positionColumnIdex)
        return tagName, postion
    end

    local convertTagPostionToYoutubeMarker = function (position)
        local  t = {}
        for token in string.gmatch(position, '([^:]+)') do
            table.insert(t, token)
        end
        return t[1] .. ':' .. t[2] .. ':' .. t[3]
    end

    local saveToFile = function(filePath, text)
        local file, err = io.open(filePath,'w')
        if file then
            file:write(tostring(text))
            file:close()
        else
            print("error:", err) -- not so hard?
        end
    end

    -- LOOP THROUGH ALL TAGS
    local fileContents = ''
    for i, row in ipairs(tags:rowsUI()) do
        local tagName, position = fetchMarkerData(i, row)
        local youtubeMarker = convertTagPostionToYoutubeMarker(position)
        local exportName = youtubeMarker .. ' ' .. tagName
        fileContents = fileContents .. exportName .. '\r\n'
    end
    saveToFile(OUTPUT_FILE, fileContents)
    pasteboard.setContents(fileContents)
    displayMessage('✅ Export Completed. Output: ' .. OUTPUT_FILE )
end

start()

