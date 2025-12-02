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
    print("Reset durchgeführt.")
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
        local sample = msg.data
        if sample then
            local player = playdate.sound.sampleplayer.new(sample)
            if player then
                player:setFinishCallback(function()
                    playNextMessage()
                end)
                player:play()
            else
                playNextMessage()
            end
        else
            playNextMessage()
        end
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
    
    Audio.toggleRecording()
end

function playdate.BButtonDown()
    -- Spinner blockiert Input
    if UI.isSpinnerActive() then return end
    
    -- Wenn keine Agenten da sind, macht B nichts
    if not Agents.hasAgents() then return end
    
    -- Text-Anzeige: B beendet vorzeitig
    if UI.isTextDisplayActive() then
        UI.hideTextDisplay()
        playNextMessage()
        return
    end
    
    -- Stoppe laufende Wiedergabe/Aufnahme
    if Audio.isRecording() then
        Audio.stopRecording()
    end
    if Audio.isPlaying() then
        Audio.stopPlayback()
        return -- Toggle: nochmal drücken beendet
    end
    
    -- Hole alle Nachrichten für aktuellen Agenten
    messageList = Agents.getAllMessagesForCurrentAgent()
    
    if #messageList == 0 then
        print("Keine Nachrichten vorhanden.")
        return
    end
    
    messageIndex = 0
    playNextMessage()
end

-- D-Pad Down: Nächster Satz in Text-Anzeige
function playdate.downButtonDown()
    if UI.isTextDisplayActive() then
        UI.nextSentence()
    end
end

-- D-Pad Up: Vorheriger Satz (optional)
function playdate.upButtonDown()
    -- Könnte später implementiert werden für Zurück-Navigation
end

-- Update Loop
function playdate.update()
    if shouldStartSync then
        shouldStartSync = false
        startSync()
    end

    -- Module aktualisieren
    Agents.update()
    Audio.update()
    
    -- UI zeichnen
    UI.draw()
    
    -- Timer aktualisieren (falls genutzt)
    playdate.timer.updateTimers()
end
