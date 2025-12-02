-- main.lua
import "CoreLibs/graphics"
import "CoreLibs/timer"
import "CoreLibs/object"
json = playdate.json or json  -- Playdate SDK JSON
import "storage"
import "agents"
import "audio"
import "ui"
-- import "Network"
import "FakeNetwork"  -- Für Entwicklung und Tests
-- Initialisierung
Storage.init()
Agents.init()
Audio.init()
Network.init()  -- Optional: Server-URL und API-Key hier setzen

-- Sync-Zustand
local syncInProgress = false
local syncStep = 0
local pendingUploads = {}
local pendingUploadIndex = 0

-- Forward declarations für lokale Funktionen (Lua erfordert dies für gegenseitige Rekursion)
local uploadNextRecording
local fetchNotifications
local syncAgents
local fetchAgentDetails
local finishSync

-- ====== SYNC FUNKTIONEN ======

-- Beendet den Sync-Vorgang
finishSync = function()
    syncInProgress = false
    syncStep = 0
    UI.hideSpinner()
    print("Sync abgeschlossen!")
end

-- Holt Details für neue Agenten (Avatar etc.)
fetchAgentDetails = function(agentIds, index)
    if index > #agentIds then
        finishSync()
        return
    end
    
    local agentId = agentIds[index]
    UI.updateSpinnerText("Lade Agent " .. index .. "/" .. #agentIds .. "...")
    
    Network.fetchAgentDetails(agentId, function(success, details, err)
        if success and details then
            -- Avatar dekodieren und speichern (falls vorhanden)
            if details.avatar then
                -- TODO: Base64 zu Bild dekodieren
                -- local avatarPath = Storage.saveAgentAvatar(agentId, decodedImage)
                -- Agents.updateAgent(agentId, { avatarPath = avatarPath })
                print("Avatar erhalten für Agent: " .. agentId)
            end
            
            Agents.updateAgent(agentId, { name = details.name })
        else
            print("Agent-Details fehlgeschlagen: " .. (err or "unbekannt"))
        end
        
        -- Nächster Agent
        fetchAgentDetails(agentIds, index + 1)
    end)
end

-- Synchronisiert die Agentenliste
syncAgents = function()
    syncStep = 3
    UI.updateSpinnerText("Synchronisiere Agenten...")
    
    Network.fetchAgentList(function(success, serverAgents, err)
        if success and serverAgents then
            -- Prüfe auf neue Agenten
            local newAgentIds = {}
            for _, serverAgent in ipairs(serverAgents) do
                local existing = Agents.getAgentById(serverAgent.id)
                if not existing then
                    table.insert(newAgentIds, serverAgent.id)
                end
            end
            
            -- Agentenliste aktualisieren
            Agents.setAgents(serverAgents)
            
            -- Details für neue Agenten abrufen
            if #newAgentIds > 0 then
                fetchAgentDetails(newAgentIds, 1)
            else
                finishSync()
            end
        else
            print("Agenten-Abruf fehlgeschlagen: " .. (err or "unbekannt"))
            finishSync()
        end
    end)
end

-- Holt Notifications vom Backend
fetchNotifications = function()
    syncStep = 2
    UI.updateSpinnerText("Lade Nachrichten...")
    
    local agentIds = Agents.getAgentIds()
    
    Network.fetchNotifications(agentIds, function(success, answers, err)
        if success and answers then
            -- Notifications zu Agenten hinzufügen
            for _, answer in ipairs(answers) do
                local agentId = answer.antwort_von
                Agents.addNotification(agentId, {
                    text = answer.antwort,
                    replyTo = answer.antwort_auf,
                    timestamp = playdate.getSecondsSinceEpoch()
                })
            end
            print("Notifications erhalten: " .. #answers)
        else
            print("Notifications-Abruf fehlgeschlagen: " .. (err or "unbekannt"))
        end
        
        -- Weiter zu Agenten-Sync
        syncAgents()
    end)
end

-- Lädt die nächste Aufnahme hoch
uploadNextRecording = function()
    pendingUploadIndex = pendingUploadIndex + 1
    
    if pendingUploadIndex > #pendingUploads then
        -- Alle Uploads fertig, weiter zu Notifications
        fetchNotifications()
        return
    end
    
    local recording = pendingUploads[pendingUploadIndex]
    UI.updateSpinnerText("Uploading... (" .. pendingUploadIndex .. "/" .. #pendingUploads .. ")")
    
    Network.uploadRecording(recording.name, recording.agentId, function(success, messageId, err)
        if success then
            -- Erfolgreich: Lokal löschen
            Storage.deleteRecording(recording.name)
            Agents.removeRecording(recording.agentIndex, recording.name)
            print("Upload erfolgreich: " .. recording.name)
        else
            print("Upload fehlgeschlagen: " .. (err or "unbekannt"))
            -- Trotzdem weitermachen mit nächster Aufnahme
        end
        
        -- Nächste Aufnahme
        uploadNextRecording()
    end)
end

-- Startet den kompletten Sync-Vorgang
local function startSync()
    if syncInProgress then
        print("Sync bereits aktiv")
        return
    end
    
    -- Prüfe ob Aufnahme/Wiedergabe läuft
    if Audio.isRecording() then
        Audio.stopRecording()
    end
    if Audio.isPlaying() then
        Audio.stopPlayback()
    end
    
    syncInProgress = true
    syncStep = 1
    
    -- Starte mit Upload
    pendingUploads = Agents.getAllPendingRecordings()
    pendingUploadIndex = 0
    
    if #pendingUploads > 0 then
        UI.showSpinner("Uploading... (0/" .. #pendingUploads .. ")")
        uploadNextRecording()
    else
        -- Keine Uploads, direkt zu Notifications
        UI.showSpinner("Synchronisiere...")
        fetchNotifications()
    end
end

-- System-Menü einrichten
local menu = playdate.getSystemMenu()

menu:addMenuItem("Sync", function()
    startSync()
end)

menu:addMenuItem("Aufnahmen löschen", function()
    -- Stoppe laufende Wiedergabe/Aufnahme
    if Audio.isRecording() then
        Audio.stopRecording()
    end
    if Audio.isPlaying() then
        Audio.stopPlayback()
    end
    
    -- Lösche alle Aufnahmen
    Agents.deleteAllRecordings()
    print("Alle Aufnahmen wurden gelöscht.")
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
    
    Audio.toggleRecording()
end

function playdate.BButtonDown()
    -- Spinner blockiert Input
    if UI.isSpinnerActive() then return end
    
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
    -- Module aktualisieren
    Agents.update()
    Audio.update()
    
    -- UI zeichnen
    UI.draw()
    
    -- Timer aktualisieren (falls genutzt)
    playdate.timer.updateTimers()
end
