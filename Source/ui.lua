-- Source/ui.lua
-- Verwaltet die grafische Darstellung.

UI = {}
local gfx = playdate.graphics

-- Spinner-Zustand
local spinnerActive = false
local spinnerText = ""
local spinnerFrame = 0
local spinnerFrames = { "|", "/", "-", "\\" }

-- Text-Anzeige-Zustand (fuer Notifications)
local textDisplayActive = false
local textDisplayContent = {}
local textDisplayCurrentSentence = 1
local textDisplayCallback = nil
local textCrankAccumulator = 0
local TEXT_CRANK_THRESHOLD = 45 -- Empfindlichkeit fuer Text-Scrollen

-- Selection State
local selectedMode = "Out" -- "Out" or "In"

-- Cache fuer geladene Bilder
local imageCache = {}

function UI.handleCrank(change)
    if textDisplayActive then
        textCrankAccumulator = textCrankAccumulator + change
        if textCrankAccumulator > TEXT_CRANK_THRESHOLD then
            UI.nextSentence()
            textCrankAccumulator = 0
        elseif textCrankAccumulator < -TEXT_CRANK_THRESHOLD then
            UI.prevSentence()
            textCrankAccumulator = 0
        end
    end
end

function UI.toggleSelection()
    if selectedMode == "Out" then
        selectedMode = "In"
    else
        selectedMode = "Out"
    end
end

function UI.getSelectedMode()
    return selectedMode
end

function UI.draw()
    gfx.clear(gfx.kColorWhite)
    
    local screenWidth = 400
    local screenHeight = 240
    
    -- Spinner hat hoechste Prioritaet
    if spinnerActive then
        UI.drawSpinner()
        return
    end
    
    -- Text-Anzeige fuer Notifications
    if textDisplayActive then
        UI.drawTextDisplay()
        return
    end
    
    -- Check if there are agents
    if not Agents.hasAgents() then
        UI.drawNoAgentsModal()
        return
    end
    
    -- Aktueller Agent
    local agent = Agents.getCurrentAgent()
    if not agent then return end -- Safety check
    
    local agentName = agent.name
    local avatarPath = agent.avatarPath
    
    -- Avatar zeichnen
    local avatarY = 40
    if avatarPath then
        local img = imageCache[avatarPath]
        
        if img == nil then
            -- Versuche Bild zu laden
            if playdate.file.exists(avatarPath) then
                local fileSize = playdate.file.getSize(avatarPath)
                print("Lade Avatar: " .. avatarPath .. " (" .. fileSize .. " bytes)")
                
                local imgOrNil, err = gfx.image.new(avatarPath)
                if imgOrNil then
                    img = imgOrNil
                    imageCache[avatarPath] = img
                    print("Avatar erfolgreich geladen.")
                else
                    print("Fehler beim Laden von " .. avatarPath .. ": " .. (err or "unbekannt"))
                    imageCache[avatarPath] = "failed"
                end
            else
                -- Datei noch nicht da (oder Pfad falsch)
                -- print("Avatar-Datei fehlt: " .. avatarPath)
            end
        end
        
        if img and img ~= "failed" then
            local imgWidth, imgHeight = img:getSize()
            local x = (screenWidth - imgWidth) / 2
            img:draw(x, avatarY)
            
            -- Counts anzeigen (rechts vom Avatar)
            local agentIndex = Agents.getCurrentAgentIndex()
            local outCount = Agents.getOutgoingCount(agentIndex)
            local inCount = Agents.getIncomingCount(agentIndex)
            
            local countX = x + imgWidth + 20
            local countY = avatarY + 10
            
            gfx.drawText("Out: " .. outCount, countX, countY)
            gfx.drawText("In: " .. inCount, countX, countY + 25)
            
            -- Pfeil zeichnen
            local arrowY = (selectedMode == "Out") and countY or (countY + 25)
            gfx.drawText(">", countX - 15, arrowY)
            
            avatarY = avatarY + imgHeight + 10
        else
            -- Platzhalter
            gfx.drawRect((screenWidth - 100) / 2, avatarY, 100, 100)
            gfx.drawText("Kein Bild", (screenWidth - 70) / 2, avatarY + 40)
            avatarY = avatarY + 110
        end
    else
        -- Platzhalter
        gfx.drawRect((screenWidth - 100) / 2, avatarY, 100, 100)
        gfx.drawText("Kein Bild", (screenWidth - 70) / 2, avatarY + 40)
        avatarY = avatarY + 110
    end
    
    -- Name zeichnen
    local nameWidth, nameHeight = gfx.getTextSize(agentName)
    gfx.drawText(agentName, (screenWidth - nameWidth) / 2, avatarY)
    
    -- Status / Aufnahme
    local statusText = Audio.getStatusText()
    if statusText ~= "" then
        local textWidth, _ = gfx.getTextSize(statusText)
        gfx.drawText(statusText, (screenWidth - textWidth) / 2, avatarY + 30)
        
        -- Pegel nur wenn Aufnahme laeuft
        if Audio.isRecording() then
            local micLevel = Audio.getMicLevel()
            local maxBarWidth = 200
            local barHeight = 10
            
            -- Pegel verstaerken fuer bessere Sichtbarkeit (x5), aber cappen bei 1.0
            local displayLevel = math.min(1.0, micLevel * 5.0)
            local currentBarWidth = math.floor(displayLevel * maxBarWidth)
            
            local barX = (screenWidth - maxBarWidth) / 2
            local barY = avatarY + 50
            
            gfx.drawRect(barX, barY, maxBarWidth, barHeight)
            if currentBarWidth > 0 then
                gfx.fillRect(barX, barY, currentBarWidth, barHeight)
            end
        end
    end

    -- Hinweise fuer Buttons
    if selectedMode == "Out" then
        gfx.drawText("A: Wiedergabe", 10, 210)
    else
        gfx.drawText("A: Lesen", 10, 210)
    end
    gfx.drawText("B: Aufnahme", 280, 210)
end

-- ====== SPINNER ======

function UI.showSpinner(text)
    spinnerActive = true
    spinnerText = text or "Laden..."
    spinnerFrame = 0
    print("Spinner: " .. spinnerText)
end

function UI.hideSpinner()
    spinnerActive = false
    spinnerText = ""
    print("Spinner versteckt")
end

function UI.isSpinnerActive()
    return spinnerActive
end

function UI.updateSpinnerText(text)
    spinnerText = text or spinnerText
end

function UI.drawSpinner()
    local screenWidth = 400
    local screenHeight = 240
    
    -- Hintergrund leicht abdunkeln (Dither-Muster)
    gfx.setColor(gfx.kColorBlack)
    gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer4x4)
    gfx.fillRect(0, 0, screenWidth, screenHeight)
    
    -- Zentrales weisses Feld
    local boxWidth = 200
    local boxHeight = 80
    local boxX = (screenWidth - boxWidth) / 2
    local boxY = (screenHeight - boxHeight) / 2
    
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRoundRect(boxX, boxY, boxWidth, boxHeight, 8)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRoundRect(boxX, boxY, boxWidth, boxHeight, 8)
    
    -- Spinner-Animation
    spinnerFrame = (spinnerFrame + 1) % (#spinnerFrames * 4)
    local frameIndex = math.floor(spinnerFrame / 4) + 1
    local spinnerChar = spinnerFrames[frameIndex]
    
    -- Spinner-Zeichen gross zeichnen
    local spinnerDisplay = spinnerChar
    local spinnerWidth, _ = gfx.getTextSize(spinnerDisplay)
    gfx.drawText(spinnerDisplay, (screenWidth - spinnerWidth) / 2, boxY + 15)
    
    -- Status-Text
    local textWidth, _ = gfx.getTextSize(spinnerText)
    gfx.drawText(spinnerText, (screenWidth - textWidth) / 2, boxY + 45)
end

-- ====== TEXT-ANZEIGE FUER NOTIFICATIONS ======

-- Zeigt Text satzweise an
-- content: { sentences = {"Satz 1", "Satz 2"}, ... }
-- callback: function() - wird aufgerufen wenn alle Saetze gelesen
function UI.showTextDisplay(content, callback)
    textDisplayActive = true
    textDisplayContent = content
    textDisplayCurrentSentence = 1
    textDisplayCallback = callback
    print("Text-Anzeige gestartet: " .. #(content.sentences or {}) .. " Saetze")
end

function UI.hideTextDisplay()
    textDisplayActive = false
    textDisplayContent = {}
    textDisplayCurrentSentence = 1
    textDisplayCallback = nil
end

function UI.isTextDisplayActive()
    return textDisplayActive
end

-- Vorheriger Satz
function UI.prevSentence()
    if not textDisplayActive then return false end
    
    if textDisplayCurrentSentence > 1 then
        textDisplayCurrentSentence = textDisplayCurrentSentence - 1
        return true
    end
    return false
end

-- Naechster Satz (D-Pad Down)
function UI.nextSentence()
    if not textDisplayActive then return false end
    
    local sentences = textDisplayContent.sentences or {}
    
    if textDisplayCurrentSentence < #sentences then
        textDisplayCurrentSentence = textDisplayCurrentSentence + 1
        return true
    else
        -- Letzter Satz erreicht - Nichts tun (Warten auf B)
        return false
    end
end

function UI.drawTextDisplay()
    local screenWidth = 400
    local screenHeight = 240
    
    -- Hintergrund
    gfx.clear(gfx.kColorWhite)
    
    -- Agent Avatar holen
    local agent = Agents.getCurrentAgent()
    local avatarPath = agent and agent.avatarPath
    local avatarImg = nil
    
    if avatarPath then
        avatarImg = imageCache[avatarPath]
        -- Falls nicht im Cache, versuchen zu laden
        if avatarImg == nil and playdate.file.exists(avatarPath) then
             local imgOrNil, err = gfx.image.new(avatarPath)
             if imgOrNil then
                 avatarImg = imgOrNil
                 imageCache[avatarPath] = avatarImg
             else
                 imageCache[avatarPath] = "failed"
             end
        end
    end
    
    -- Avatar Position (Links unten)
    local avatarX = 10
    local avatarY = screenHeight - 64 - 10 -- 64px hoehe + 10px padding
    
    if avatarImg and avatarImg ~= "failed" then
        avatarImg:draw(avatarX, avatarY)
    else
        -- Fallback Box
        gfx.drawRect(avatarX, avatarY, 64, 64)
        gfx.drawText("Agent", avatarX + 5, avatarY + 25)
    end
    
    -- Sprechblase
    local bubbleX = 85
    local bubbleY = 20
    local bubbleW = screenWidth - bubbleX - 10
    local bubbleH = screenHeight - 40 
    
    -- Sprechblasen-Rahmen
    local radius = 10
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRoundRect(bubbleX, bubbleY, bubbleW, bubbleH, radius)
    
    -- Verbindungslinie zum Avatar
    gfx.drawLine(avatarX + 64, avatarY + 20, bubbleX, bubbleY + bubbleH - 40)

    local sentences = textDisplayContent.sentences or {}
    local currentSentence = sentences[textDisplayCurrentSentence] or ""
    
    -- Header (Fortschritt)
    local headerText = "(" .. textDisplayCurrentSentence .. "/" .. #sentences .. ")"
    gfx.drawText(headerText, bubbleX + 10, bubbleY + 10)
    
    -- Text Inhalt
    local textMargin = 15
    local textX = bubbleX + textMargin
    local textY = bubbleY + 35
    local maxTextWidth = bubbleW - (textMargin * 2)
    
    local wrappedText = UI.wrapText(currentSentence, maxTextWidth)
    
    for _, line in ipairs(wrappedText) do
        gfx.drawText(line, textX, textY)
        textY = textY + 20
    end
    
    -- Hinweis fuer Weiter
    local hintText = "weiter" 
    if textDisplayCurrentSentence >= #sentences then
        hintText = "Fertig"
    end
    
    local hintW, hintH = gfx.getTextSize(hintText)
    gfx.drawText(hintText, bubbleX + bubbleW - hintW - 10, bubbleY + bubbleH - hintH - 10)
end

-- Hilfsfunktion: Text umbrechen
function UI.wrapText(text, maxWidth)
    local lines = {}
    local currentLine = ""
    
    for word in text:gmatch("%S+") do
        local testLine = currentLine .. (currentLine ~= "" and " " or "") .. word
        local width, _ = gfx.getTextSize(testLine)
        
        if width <= maxWidth then
            currentLine = testLine
        else
            if currentLine ~= "" then
                table.insert(lines, currentLine)
            end
            currentLine = word
        end
    end
    
    if currentLine ~= "" then
        table.insert(lines, currentLine)
    end
    
    return lines
end

function UI.drawNoAgentsModal()
    local screenWidth = 400
    local screenHeight = 240
    
    -- Modal Background
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(50, 70, 300, 100)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(50, 70, 300, 100)
    
    -- Text
    local text1 = "Keine Agenten vorhanden."
    local text2 = "A zum Synchronisieren."
    
    local w1, h1 = gfx.getTextSize(text1)
    local w2, h2 = gfx.getTextSize(text2)
    
    gfx.drawText(text1, (screenWidth - w1) / 2, 90)
    gfx.drawText(text2, (screenWidth - w2) / 2, 120)
end
