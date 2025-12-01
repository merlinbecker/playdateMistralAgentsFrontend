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

-- Cache für geladene Bilder
local imageCache = {}

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
    
    -- Check if there are agents
    if not Agents.hasAgents() then
        UI.drawNoAgentsModal()
        return
    end
    
    -- Aktueller Agent
    local agent = Agents.getCurrentAgent()
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
        
        -- Pegel nur wenn Aufnahme läuft
        if Audio.isRecording() then
            local micLevel = Audio.getMicLevel()
            local maxBarWidth = 200
            local barHeight = 10
            local currentBarWidth = math.floor(micLevel * maxBarWidth)
            local barX = (screenWidth - maxBarWidth) / 2
            local barY = avatarY + 50
            
            gfx.drawRect(barX, barY, maxBarWidth, barHeight)
            if currentBarWidth > 0 then
                gfx.fillRect(barX, barY, currentBarWidth, barHeight)
            end
        end
    end

    -- Hinweise für Buttons
    gfx.drawText("A: Aufnahme", 10, 210)
    -- gfx.drawText("B: Wiedergabe", 280, 210) -- Wiedergabe vielleicht nicht mehr relevant im neuen Konzept?
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
