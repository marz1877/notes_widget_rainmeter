local fileList = {}
local currentIndex = 1
local notesPath = ""
local currentFilePath = ""
local initialized = false

function Initialize()
    -- Initialize on first Update cycle
end

function Update()
    if not initialized then
        initialized = true
        InitializeLogic()
        return "Done"
    end
end

function LogToFile(msg)
    local path = SKIN:GetVariable('CURRENTPATH') .. 'notes_debug.txt'
    local f = io.open(path, 'a')
    if f then
        f:write(os.date('%Y-%m-%d %H:%M:%S') .. ' - ' .. tostring(msg) .. '\n')
        f:close()
    end
end

-- Load configuration from notes-config.ini (if it exists)
-- Falls back silently to existing INI variable values if file not found
function LoadConfig()
    local skinPath = SKIN:GetVariable('CURRENTPATH')
    local configPath = skinPath .. 'notes-config.ini'
    local f = io.open(configPath, 'r')
    if not f then
        LogToFile('Notes: notes-config.ini not found, using INI defaults')
        return
    end

    local paths = {}
    local subfolders = '1'

    for line in f:lines() do
        -- Skip comment lines (;) and blank lines
        if not line:match('^%s*;') and not line:match('^%s*$') then
            local key, val = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
            if key and val then
                -- Trim whitespace and surrounding quotes
                val = val:gsub('^%s*["\']?(.-)["\']?%s*$', '%1')
                if key == 'Subfolders' and val ~= '' then
                    subfolders = val
                elseif val ~= '' then
                    -- Match Folder1..N, File1..N, Path1..N, NotesPath, etc.
                    if key:match('^Folder%d*$') or key:match('^File%d*$') or key:match('^Path%d*$') or key == 'NotesPath' then
                        for p in val:gmatch('[^;]+') do
                            p = p:gsub('^%s*["\']?(.-)["\']?%s*$', '%1')
                            if p ~= '' then
                                table.insert(paths, p)
                            end
                        end
                    end
                end
            end
        end
    end
    f:close()

    local combinedPaths = table.concat(paths, ';')
    if combinedPaths ~= '' then
        SKIN:Bang('!SetVariable', 'NotesPath', combinedPaths)
        SKIN:Bang('!WriteKeyValue', 'Variables', 'NotesPath', combinedPaths)
    end

    SKIN:Bang('!SetVariable', 'Subfolders', subfolders)
    SKIN:Bang('!WriteKeyValue', 'Variables', 'Subfolders', subfolders)

    LogToFile('Notes: Config loaded from notes-config.ini. ' .. #paths .. ' path(s) configured.')
end

function InitializeLogic()
    local status, err = pcall(function()
        LoadConfig()
        local rawPath = SKIN:GetVariable('NotesPath', '')
        LogToFile("Initializing logic. Raw path: [" .. tostring(rawPath) .. "]")
        
        notesPath = rawPath:gsub('"', '')
        if notesPath ~= "" and notesPath:sub(-1) ~= "\\" then
            notesPath = notesPath .. "\\"
        end

        LogToFile("Sanitized path: [" .. notesPath .. "]")
        
        -- Trigger the RunCommand measure to list files
        SKIN:Bang('!CommandMeasure', 'MeasureFileList', 'Run')
    end)
    
    if not status then
        LogToFile("CRITICAL LUA ERROR: " .. tostring(err))
        SafeBang('!SetOption', 'MeterNoteText', 'Text', 'LUA ERROR: ' .. tostring(err))
        SafeBang('!UpdateMeter', 'MeterNoteText')
        SafeBang('!Redraw')
    end
end

-- Called from Rainmeter after MeasureFileList finishes
function ParseFileListFromMeasure()
    local output = SKIN:GetMeasure('MeasureFileList'):GetStringValue()
    LogToFile("Raw output from PS measure: [" .. tostring(output) .. "]")
    
    fileList = {}
    for line in output:gmatch("[^\r\n]+") do
        if line and line:match('%S') then
            -- PS FullName gives absolute paths
            table.insert(fileList, line)
        end
    end
    
    LogToFile("Parsed " .. #fileList .. " absolute paths from measure.")
    
    if #fileList > 0 then
        if currentIndex > #fileList then currentIndex = 1 end
        UpdateRainmeter()
    else
        LogToFile("No files found after parsing.")
        SafeBang('!SetOption', 'MeterTitle', 'Text', 'Notes Viewer (No Files)')
        SafeBang('!SetOption', 'MeterTitle', 'ToolTipText', '')
        SafeBang('!SetOption', 'MeterNoteText', 'Text', 'No notes found. Right-click -> Edit Config to add folders or files.')
        SafeBang('!UpdateMeter', '*')
        SafeBang('!Redraw')
    end
end

local currentLines = {}
local scrollLine = 1

function UpdateRainmeter()
    if #fileList == 0 then return end
    
    currentFilePath = fileList[currentIndex]
    LogToFile("Reading file: " .. currentFilePath)
    
    currentLines = {}
    local f = io.open(currentFilePath, "r")
    if f then
        local raw = f:read("*all")
        f:close()
        for line in (raw .. "\n"):gmatch("(.-)\r?\n") do
            table.insert(currentLines, line)
        end
        if #currentLines == 0 then
            table.insert(currentLines, "")
        end
    else
        LogToFile("Failed to open file for reading.")
        table.insert(currentLines, "Error: Could not read file [*#CRLF#]" .. currentFilePath .. "[*]")
    end

    scrollLine = 1
    RenderCurrentNote()
end

function RenderCurrentNote()
    if #fileList == 0 then return end
    
    local filename = currentFilePath:match("([^\\]+)$") or currentFilePath
    local titleText = filename .. "  (" .. currentIndex .. " / " .. #fileList .. ")"
    titleText = titleText:gsub('%[', '[*'):gsub('%]', '*]')

    local endLine = math.min(#currentLines, scrollLine + 120)
    local slice = {}
    for i = scrollLine, endLine do
        table.insert(slice, currentLines[i])
    end
    local content = table.concat(slice, '#CRLF#')
    content = content:gsub('%[', '[*'):gsub('%]', '*]')

    local tooltipPath = currentFilePath:gsub('%[', '[*'):gsub('%]', '*]')
    SafeBang('!SetOption', 'MeterTitle', 'ToolTipText', tooltipPath)
    SafeBang('!SetOption', 'MeterTitle', 'Text', titleText)
    SafeBang('!SetOption', 'MeterNoteText', 'Text', content)
    SafeBang('!SetVariable', 'CurrentFile', currentFilePath)
    
    SafeBang('!UpdateMeter', 'MeterTitle')
    SafeBang('!UpdateMeter', 'MeterNoteText')
    SafeBang('!Redraw')
end

function ScrollNote(delta)
    local d = tonumber(delta) or 0
    if #currentLines <= 1 or d == 0 then return end
    local newScroll = scrollLine + d
    if newScroll < 1 then newScroll = 1 end
    if newScroll > #currentLines then newScroll = #currentLines end
    if newScroll ~= scrollLine then
        scrollLine = newScroll
        RenderCurrentNote()
    end
end

local dropdownOpen = false
local dropdownScroll = 1
local MAX_DROPDOWN_ITEMS = 10

-- 5-second hover timer for notepad tooltip
local noteHoverActive = false
local noteHoverToken = 0

function StartNoteHover()
    noteHoverActive = true
    noteHoverToken = noteHoverToken + 1
end

function CheckNoteHover()
    if noteHoverActive and not dropdownOpen then
        SafeBang('!SetOption', 'MeterNoteText', 'ToolTipText', 'Double-click to open in Notepad')
        SafeBang('!UpdateMeter', 'MeterNoteText')
    end
end

function CancelNoteHover()
    noteHoverActive = false
    noteHoverToken = noteHoverToken + 1
    SafeBang('!SetOption', 'MeterNoteText', 'ToolTipText', '')
    SafeBang('!UpdateMeter', 'MeterNoteText')
end

function ToggleDropdown()
    if dropdownOpen then
        CloseDropdown()
    else
        OpenDropdown()
    end
end

function OpenDropdown()
    if #fileList == 0 then return end
    dropdownOpen = true
    CancelNoteHover()
    if currentIndex > dropdownScroll + MAX_DROPDOWN_ITEMS - 1 or currentIndex < dropdownScroll then
        dropdownScroll = math.max(1, math.min(currentIndex - 2, #fileList - MAX_DROPDOWN_ITEMS + 1))
    end
    SafeBang('!SetOption', 'MeterDropdownArrow', 'Shape', 'Path ChevronUp | Stroke Color #AccentColor# | StrokeWidth (1.8 * #Scale#) | StrokeLineJoin Round | StrokeLineCap Round')
    SafeBang('!SetOption', 'MeterDropdownArrow', 'MouseLeaveAction', '[!SetOption MeterDropdownArrow Shape "Path ChevronUp | Stroke Color #AccentColor# | StrokeWidth (1.8 * #Scale#) | StrokeLineJoin Round | StrokeLineCap Round"][!SetOption MeterDropdownArrow Shape2 "Rectangle (-6 * #Scale#),(-6 * #Scale#),(22 * #Scale#),(22 * #Scale#),2 | Fill Color 0,0,0,1 | StrokeWidth 0"][!UpdateMeter MeterDropdownArrow][!Redraw]')
    SafeBang('!UpdateMeter', 'MeterDropdownArrow')
    RenderDropdown()
end

function CloseDropdown()
    if not dropdownOpen then return end
    dropdownOpen = false
    SafeBang('!SetOption', 'MeterDropdownArrow', 'Shape', 'Path ChevronDown | Stroke Color #DimColor# | StrokeWidth (1.8 * #Scale#) | StrokeLineJoin Round | StrokeLineCap Round')
    SafeBang('!SetOption', 'MeterDropdownArrow', 'MouseLeaveAction', '[!SetOption MeterDropdownArrow Shape "Path ChevronDown | Stroke Color #DimColor# | StrokeWidth (1.8 * #Scale#) | StrokeLineJoin Round | StrokeLineCap Round"][!SetOption MeterDropdownArrow Shape2 "Rectangle (-6 * #Scale#),(-6 * #Scale#),(22 * #Scale#),(22 * #Scale#),2 | Fill Color 0,0,0,1 | StrokeWidth 0"][!UpdateMeter MeterDropdownArrow][!Redraw]')
    SafeBang('!UpdateMeter', 'MeterDropdownArrow')
    SafeBang('!HideMeterGroup', 'DropdownGroup')
    SafeBang('!Redraw')
end

function RenderDropdown()
    if not dropdownOpen or #fileList == 0 then return end
    
    local scale = tonumber(SKIN:GetVariable('Scale', '1.0')) or 1.0
    local pad = tonumber(SKIN:GetVariable('Padding', '20')) or (20 * scale)
    local width = tonumber(SKIN:GetVariable('Width', '600')) or (600 * scale)
    
    local visibleCount = math.min(#fileList, MAX_DROPDOWN_ITEMS)
    local itemH = 25 * scale
    local bgPadX = pad + (5 * scale)
    local bgPadY = pad + (42 * scale)
    local bgW = width - (bgPadX * 2)
    local bgH = (14 * scale) + (visibleCount * itemH)
    
    local shapeStr = string.format('Rectangle %.1f,%.1f,%.1f,%.1f,%.1f | Fill Color 18,18,22,250 | Stroke Color 255,255,255,40 | StrokeWidth 1', bgPadX, bgPadY, bgW, bgH, 4 * scale)
    SafeBang('!SetOption', 'MeterDropdownBG', 'Shape', shapeStr)

    for i = 1, MAX_DROPDOWN_ITEMS do
        local fileIdx = dropdownScroll + i - 1
        local meterName = 'MeterDropDownItem' .. i
        if fileIdx <= #fileList and i <= visibleCount then
            local path = fileList[fileIdx]
            local fname = path:match("([^\\]+)$") or path
            local isCurrent = (fileIdx == currentIndex)
            local prefix = isCurrent and "  > " or "    "
            local itemText = prefix .. fname
            itemText = itemText:gsub('%[', '[*'):gsub('%]', '*]')
            
            SafeBang('!SetOption', meterName, 'Text', itemText)
            if isCurrent then
                SafeBang('!SetOption', meterName, 'FontColor', '255,255,255')
                SafeBang('!SetOption', meterName, 'StringStyle', 'Bold')
            else
                SafeBang('!SetOption', meterName, 'FontColor', '255,255,255,180')
                SafeBang('!SetOption', meterName, 'StringStyle', 'Normal')
            end
            SafeBang('!ShowMeter', meterName)
        else
            SafeBang('!HideMeter', meterName)
        end
    end
    
    SafeBang('!ShowMeter', 'MeterDropdownOverlay')
    SafeBang('!ShowMeter', 'MeterDropdownBG')
    SafeBang('!UpdateMeterGroup', 'DropdownGroup')
    SafeBang('!Redraw')
end

function SelectDropdownItem(slot)
    local idx = dropdownScroll + (tonumber(slot) or 1) - 1
    if idx >= 1 and idx <= #fileList then
        currentIndex = idx
        CloseDropdown()
        UpdateRainmeter()
    end
end

function ScrollDropdown(delta)
    if not dropdownOpen or #fileList <= MAX_DROPDOWN_ITEMS then return end
    local maxScroll = #fileList - MAX_DROPDOWN_ITEMS + 1
    local newScroll = dropdownScroll + (tonumber(delta) or 0)
    if newScroll < 1 then newScroll = 1 end
    if newScroll > maxScroll then newScroll = maxScroll end
    if newScroll ~= dropdownScroll then
        dropdownScroll = newScroll
        RenderDropdown()
    end
end

function SafeBang(bangName, ...)
    local params = {...}
    local cmd = bangName
    for _, p in ipairs(params) do
        local s = tostring(p):gsub('"', '""')
        cmd = cmd .. ' "' .. s .. '"'
    end
    SKIN:Bang(cmd)
end

function Next()
    if #fileList == 0 then return end
    CloseDropdown()
    currentIndex = currentIndex + 1
    if currentIndex > #fileList then currentIndex = 1 end
    UpdateRainmeter()
end

function Previous()
    if #fileList == 0 then return end
    CloseDropdown()
    currentIndex = currentIndex - 1
    if currentIndex < 1 then currentIndex = #fileList end
    UpdateRainmeter()
end

function OpenInNotepad()
    if currentFilePath ~= "" then
        LogToFile("Opening in notepad: " .. currentFilePath)
        SKIN:Bang('["' .. currentFilePath .. '"]')
    end
end

-- ==========================================
-- RESIZING / SCALING
-- ==========================================
local isDragging = false
local dragStartScale = 1.0

function StartResize()
    CloseDropdown()
    isDragging = true
    dragStartScale = tonumber(SKIN:GetVariable('Scale', '1.0')) or 1.0
    LogToFile(string.format("Notes: StartResize at scale=%.2f", dragStartScale))
end

function EndResize(releaseX, releaseY)
    if not isDragging then return end
    isDragging = false

    local rx = tonumber(releaseX) or 0
    local ry = tonumber(releaseY) or 0

    local baseW = tonumber(SKIN:GetVariable('BaseWidth', '600')) or 600
    local baseH = tonumber(SKIN:GetVariable('BaseHeight', '500')) or 500

    local scaleByX = rx / baseW
    local scaleByY = ry / baseH

    local newScale
    if math.abs(rx) < 20 and math.abs(ry) < 20 then
        -- tiny drag = accidental, ignore
        return
    elseif math.abs(rx) > math.abs(ry) then
        newScale = scaleByX
    else
        newScale = scaleByY
    end

    if newScale < 0.30 then newScale = 0.30 end
    if newScale > 3.00 then newScale = 3.00 end
    newScale = math.floor(newScale * 100 + 0.5) / 100

    LogToFile(string.format("Notes: EndResize release=(%d,%d) newScale=%.2f", rx, ry, newScale))

    SKIN:Bang('!WriteKeyValue', 'Variables', 'Scale', string.format('%.2f', newScale))
    SKIN:Bang('!SetVariable', 'Scale', string.format('%.2f', newScale))
    SKIN:Bang('!Refresh')
end

function ResetScale()
    isDragging = false
    LogToFile("Notes: ResetScale")
    SKIN:Bang('!WriteKeyValue', 'Variables', 'Scale', '1.00')
    SKIN:Bang('!SetVariable', 'Scale', '1.00')
    SKIN:Bang('!Refresh')
end

function ScaleStep(delta)
    local scale = tonumber(SKIN:GetVariable('Scale', '1.00')) or 1.00
    scale = scale + (tonumber(delta) or 0)
    if scale < 0.30 then scale = 0.30 end
    if scale > 3.00 then scale = 3.00 end
    scale = math.floor(scale * 100 + 0.5) / 100
    LogToFile(string.format("Notes: ScaleStep -> %.2f", scale))
    SKIN:Bang('!WriteKeyValue', 'Variables', 'Scale', string.format('%.2f', scale))
    SKIN:Bang('!SetVariable', 'Scale', string.format('%.2f', scale))
    SKIN:Bang('!Refresh')
end

function SetScale(value)
    local scale = tonumber(value) or 1.00
    if scale < 0.30 then scale = 0.30 end
    if scale > 3.00 then scale = 3.00 end
    scale = math.floor(scale * 100 + 0.5) / 100
    LogToFile(string.format("Notes: SetScale -> %.2f", scale))
    SKIN:Bang('!WriteKeyValue', 'Variables', 'Scale', string.format('%.2f', scale))
    SKIN:Bang('!SetVariable', 'Scale', string.format('%.2f', scale))
    SKIN:Bang('!Refresh')
end
