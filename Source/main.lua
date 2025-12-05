-- main.lua
import "CoreLibs/graphics"
import "CoreLibs/timer"
import "CoreLibs/object"
json = playdate.json or json  -- Playdate SDK JSON
import "storage"
import "agents"
import "audio"
import "ui"
import "Network"

-- Initialisierung
Storage.init()
Agents.init()
Audio.init()
Network.init()

-- Sync-Zustand
local syncInProgress = false
local shouldStartSync = false

local function startSync()
    if syncInProgress then return end
    syncInProgress = true
    UI.showSpinner("Synchronisiere...")
    
    Agents.sync(function(success)
        syncInProgress = false
        UI.hideSpinner()
        if success then
            print("Sync erfolgreich")
        else
            print("Sync fehlgeschlagen")
        end
    end)
end

-- System-Menü einrichten
local menu = playdate.getSystemMenu()

menu:addMenuItem("Sync", function()
    shouldStartSync = true
end)

menu:addMenuItem("Reset", function()
    -- Stoppe laufende Wiedergabe/Aufnahme
    if Audio.isRecording() then
        Audio.stopRecording()
    end
    if Audio.isPlaying() then
        Audio.stopPlayback()
    end
    
    -- Alles zurücksetzen
    Agents.reset()
    print("Reset durchgefuehrt.")
end)

-- Nachrichten-Zustand für Text-Anzeige
local messageList = {}
local messageIndex = 0

-- Spielt nächste Audio-Nachricht oder zeigt nächsten Text an
local function playNextMessage()
    messageIndex = messageIndex + 1
    
    if messageIndex > #messageList then
        messageList = {}
        messageIndex = 0
        print("Alle Nachrichten durchlaufen.")
        return
    end
    
    local msg = messageList[messageIndex]
    
    if msg.type == "audio" then
        -- Audio abspielen
        Audio.playSample(msg.data, function()
            playNextMessage()
        end)
    elseif msg.type == "text" then
        -- Text-Nachricht anzeigen
        UI.showTextDisplay({
            sentences = msg.sentences or { msg.text }
        }, function()
            -- Callback wenn Text fertig gelesen
            playNextMessage()
        end)
    else
        playNextMessage()
    end
end

-- Input Handler
function playdate.AButtonDown()
    -- Spinner/Text-Anzeige blockiert Input
    if UI.isSpinnerActive() then return end
    if UI.isTextDisplayActive() then return end
    
    -- Wenn keine Agenten da sind, startet A den Sync
    if not Agents.hasAgents() then
        shouldStartSync = true
        return
    end
    
    local mode = UI.getSelectedMode()
    if mode == "Out" then
        -- Play recordings
        local recordings = Agents.getRecordingsForCurrentAgent()
        if #recordings == 0 then
            print("Keine Aufnahmen.")
            return
        end
        
        messageList = {}
        for _, rec in ipairs(recordings) do
            table.insert(messageList, {
                type = "audio",
                data = rec.data,
                name = rec.name
            })
        end
        messageIndex = 0
        playNextMessage()
    else
        -- Show notifications
        local agentId = Agents.getCurrentAgentID()
        local notifications = Agents.getNotifications(agentId)
        if #notifications == 0 then
            print("Keine Nachrichten.")
            return
        end
        
        messageList = {}
        for _, notif in ipairs(notifications) do
            table.insert(messageList, {
                type = "text",
                text = notif.text,
                sentences = notif.sentences
            })
        end
        messageIndex = 0
        playNextMessage()
    end
end

function playdate.BButtonDown()
    -- Spinner blockiert Input
    if UI.isSpinnerActive() then return end
    
    -- Wenn keine Agenten da sind, macht B nichts
    if not Agents.hasAgents() then return end
    
    -- Text-Anzeige: B beendet vorzeitig
    if UI.isTextDisplayActive() then
        UI.hideTextDisplay()
        messageList = {}
        messageIndex = 0
        return
    end
    
    -- Stoppe laufende Wiedergabe
    if Audio.isPlaying() then
        Audio.stopPlayback()
        messageList = {}
        messageIndex = 0
        return
    end
    
    -- Toggle Recording (Aufnahme auf B)
    Audio.toggleRecording()
end

-- D-Pad Down: Naechster Satz in Text-Anzeige oder Toggle Selection
function playdate.downButtonDown()
    if UI.isTextDisplayActive() then
        UI.nextSentence()
    else
        UI.toggleSelection()
    end
end

-- D-Pad Up: Toggle Selection
function playdate.upButtonDown()
    if UI.isTextDisplayActive() then
        UI.prevSentence()
    else
        UI.toggleSelection()
    end
end

-- D-Pad Left: Vorheriger Agent
function playdate.leftButtonDown()
    if UI.isTextDisplayActive() then return end
    if UI.isSpinnerActive() then return end
    if Audio.isRecording() then return end
    Agents.prevAgent()
end

-- D-Pad Right: Naechster Agent
function playdate.rightButtonDown()
    if UI.isTextDisplayActive() then return end
    if UI.isSpinnerActive() then return end
    if Audio.isRecording() then return end
    Agents.nextAgent()
end

-- Update Loop
function playdate.update()
    if shouldStartSync then
        shouldStartSync = false
        startSync()
    end

    -- Crank Input verarbeiten
    local crankChange = playdate.getCrankChange()
    
    if UI.isTextDisplayActive() then
        UI.handleCrank(crankChange)
    else
        Agents.handleCrank(crankChange)
    end

    -- Module aktualisieren
    Audio.update()
    
    -- UI zeichnen
    UI.draw()
    
    -- Timer aktualisieren (falls genutzt)
    playdate.timer.updateTimers()
end
