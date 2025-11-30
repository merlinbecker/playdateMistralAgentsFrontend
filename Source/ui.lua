-- Source/ui.lua
-- Verwaltet die grafische Darstellung.

UI = {}
local gfx = playdate.graphics

-- Spinner-Zustand
local spinnerActive = false
local spinnerText = ""
local spinnerFrame = 0
local spinnerFrames = { "|", "/", "-", "\\" }

-- Text-Anzeige-Zustand (für Notifications)
local textDisplayActive = false
local textDisplayContent = {}
local textDisplayCurrentSentence = 1
local textDisplayCallback = nil

function UI.draw()
    gfx.clear(gfx.kColorWhite)
    
    local screenWidth = 400
    local screenHeight = 240
    
    -- Spinner hat höchste Priorität
    if spinnerActive then
        UI.drawSpinner()
        return
    end
    
    -- Text-Anzeige für Notifications
    if textDisplayActive then
        UI.drawTextDisplay()
        return
    end
    
    -- 1. Aufnahmeindikator / Status
    local statusText = Audio.getStatusText()
    local textWidth, textHeight = gfx.getTextSize(statusText)
    gfx.drawText(statusText, (screenWidth - textWidth) / 2, 40)
    
    -- 2. Pegel-Visualisierung
    -- Ein einfaches Rechteck, das breiter wird
    local micLevel = Audio.getMicLevel() -- 0.0 bis 1.0
    local maxBarWidth = 300
    local barHeight = 20
    local currentBarWidth = math.floor(micLevel * maxBarWidth)
    
    local barX = (screenWidth - maxBarWidth) / 2
    local barY = 80
    
    -- Rahmen zeichnen
    gfx.drawRect(barX, barY, maxBarWidth, barHeight)
    -- Füllung zeichnen
    if currentBarWidth > 0 then
        gfx.fillRect(barX, barY, currentBarWidth, barHeight)
    end
    
    -- 3. Agentenanzeige
    local agentName = Agents.getCurrentAgentName()
    local agentIndex = Agents.getCurrentAgentIndex()
    local totalMessages = Agents.getTotalMessageCount(agentIndex)
    local agentDisplay = agentName .. " (" .. totalMessages .. ")"
    
    local agentTextWidth, _ = gfx.getTextSize(agentDisplay)
    gfx.drawText(agentDisplay, (screenWidth - agentTextWidth) / 2, 150)
    
    -- Hinweise für Buttons
    gfx.drawText("A: Aufnahme", 10, 210)
    gfx.drawText("B: Wiedergabe", 280, 210)
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
    
    -- Zentrales weißes Feld
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
    
    -- Spinner-Zeichen groß zeichnen
    local spinnerDisplay = spinnerChar
    local spinnerWidth, _ = gfx.getTextSize(spinnerDisplay)
    gfx.drawText(spinnerDisplay, (screenWidth - spinnerWidth) / 2, boxY + 15)
    
    -- Status-Text
    local textWidth, _ = gfx.getTextSize(spinnerText)
    gfx.drawText(spinnerText, (screenWidth - textWidth) / 2, boxY + 45)
end

-- ====== TEXT-ANZEIGE FÜR NOTIFICATIONS ======

-- Zeigt Text satzweise an
-- content: { sentences = {"Satz 1", "Satz 2"}, ... }
-- callback: function() - wird aufgerufen wenn alle Sätze gelesen
function UI.showTextDisplay(content, callback)
    textDisplayActive = true
    textDisplayContent = content
    textDisplayCurrentSentence = 1
    textDisplayCallback = callback
    print("Text-Anzeige gestartet: " .. #(content.sentences or {}) .. " Sätze")
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

-- Nächster Satz (D-Pad Down)
function UI.nextSentence()
    if not textDisplayActive then return false end
    
    local sentences = textDisplayContent.sentences or {}
    
    if textDisplayCurrentSentence < #sentences then
        textDisplayCurrentSentence = textDisplayCurrentSentence + 1
        return true
    else
        -- Letzter Satz erreicht - Callback aufrufen
        UI.hideTextDisplay()
        if textDisplayCallback then
            textDisplayCallback()
        end
        return false
    end
end

function UI.drawTextDisplay()
    local screenWidth = 400
    local screenHeight = 240
    
    -- Hintergrund
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(0, 0, screenWidth, screenHeight)
    
    local sentences = textDisplayContent.sentences or {}
    local currentSentence = sentences[textDisplayCurrentSentence] or ""
    
    -- Rahmen oben
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 0, screenWidth, 30)
    gfx.setColor(gfx.kColorWhite)
    
    local headerText = "Nachricht (" .. textDisplayCurrentSentence .. "/" .. #sentences .. ")"
    local headerWidth, _ = gfx.getTextSize(headerText)
    gfx.drawText(headerText, (screenWidth - headerWidth) / 2, 8)
    
    -- Text-Bereich
    gfx.setColor(gfx.kColorBlack)
    
    -- Text umbrechen wenn nötig
    local margin = 20
    local maxWidth = screenWidth - (margin * 2)
    local wrappedText = UI.wrapText(currentSentence, maxWidth)
    
    local yPos = 60
    for _, line in ipairs(wrappedText) do
        gfx.drawText(line, margin, yPos)
        yPos = yPos + 20
    end
    
    -- Hinweis unten
    gfx.fillRect(0, screenHeight - 30, screenWidth, 30)
    gfx.setColor(gfx.kColorWhite)
    
    local hintText = "↓ Weiter"
    if textDisplayCurrentSentence >= #sentences then
        hintText = "↓ Fertig"
    end
    local hintWidth, _ = gfx.getTextSize(hintText)
    gfx.drawText(hintText, (screenWidth - hintWidth) / 2, screenHeight - 22)
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
