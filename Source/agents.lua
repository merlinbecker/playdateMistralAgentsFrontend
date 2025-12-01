-- Source/agents.lua
-- Verwaltet die Agenten, deren Auswahl und die zugehörigen Aufnahmen.

Agents = {}

-- Konfiguration
local MAX_NOTIFICATIONS = 5 -- Maximale Anzahl Notifications pro Agent
local currentAgentIndex = 1
local crankAccumulator = 0
local CRANK_THRESHOLD = 360 -- Eine volle Umdrehung

-- Dynamische Agentenliste (wird vom Server geladen)
-- Format: { { id = "server-id", name = "Name", avatarPath = "path/to/image", notifications = {} }, ... }
local agents = {}

-- Datenstruktur für Aufnahmen (im RAM gehalten nach Laden)
-- Format: { [agentIndex] = { { name = "timestamp", length = 123, data = sample }, ... } }
local recordings = {}

function Agents.init()
    -- Lade gespeicherte Agenten von Disk (falls vorhanden)
    local savedAgents = Storage.loadAgents()
    if savedAgents and #savedAgents > 0 then
        agents = savedAgents
    end
    
    -- Initialisiere leere Aufnahmelisten für jeden Agenten
    for i, _ in ipairs(agents) do
        recordings[i] = {}
    end
    
    -- Lade gespeicherte Aufnahmen von Disk
    Agents.loadAllFromStorage()
end

-- Lädt alle gespeicherten Aufnahmen von Disk in den RAM
function Agents.loadAllFromStorage()
    for i, _ in ipairs(agents) do
        recordings[i] = Storage.loadRecordingsForAgent(i)
        print("Agent " .. i .. ": " .. #recordings[i] .. " Aufnahmen geladen")
    end
end

-- Lösche alle Aufnahmen (RAM + Disk)
function Agents.deleteAllRecordings()
    -- Lösche von Disk
    Storage.deleteAllRecordings()
    
    -- Lösche aus RAM
    for i, _ in ipairs(agents) do
        recordings[i] = {}
    end
    
    print("Alle Aufnahmen geloescht (RAM + Disk)")
end

-- Komplett-Reset
function Agents.reset()
    Storage.resetAll()
    
    -- Reset to defaults
    agents = {}
    currentAgentIndex = 1
    
    -- Reset recordings
    recordings = {}
    
    print("Agents reset complete.")
end

function Agents.update()
    if #agents == 0 then return end

    -- Crank-Logik zum Wechseln der Agenten
    local change = playdate.getCrankChange()
    crankAccumulator = crankAccumulator + change

    if crankAccumulator > CRANK_THRESHOLD then
        currentAgentIndex = currentAgentIndex + 1
        if currentAgentIndex > #agents then
            currentAgentIndex = 1
        end
        crankAccumulator = 0
        print("Agent gewechselt: " .. agents[currentAgentIndex].name)
        if Audio and Audio.playSwitchSound then Audio.playSwitchSound() end
    elseif crankAccumulator < -CRANK_THRESHOLD then
        currentAgentIndex = currentAgentIndex - 1
        if currentAgentIndex < 1 then
            currentAgentIndex = #agents
        end
        crankAccumulator = 0
        print("Agent gewechselt: " .. agents[currentAgentIndex].name)
        if Audio and Audio.playSwitchSound then Audio.playSwitchSound() end
    end
end

function Agents.hasAgents()
    return #agents > 0
end

function Agents.getCurrentAgentName()
    if #agents == 0 then return "" end
    return agents[currentAgentIndex].name
end

function Agents.getCurrentAgentID()
    if #agents == 0 then return nil end
    return agents[currentAgentIndex].id
end

function Agents.getCurrentAgentIndex()
    return currentAgentIndex
end

function Agents.getCurrentAgent()
    if #agents == 0 then return nil end
    return agents[currentAgentIndex]
end

function Agents.getRecordingsForCurrentAgent()
    return recordings[currentAgentIndex] or {}
end

function Agents.addRecording(agentIndex, timestamp, length, data)
    if not recordings[agentIndex] then
        recordings[agentIndex] = {}
    end
    
    local agentId = agents[agentIndex].id
    -- Filename format: agentId_timestamp
    local filename = agentId .. "_" .. timestamp
    
    local newRecording = {
        name = filename, 
        length = length,
        agentID = agentId,
        agentIndex = agentIndex,
        data = data -- Sample-Objekt
    }
    
    -- Im RAM speichern
    table.insert(recordings[agentIndex], newRecording)
    
    -- Auf Disk speichern
    Storage.saveRecording(newRecording)
    
    print("Aufnahme hinzugefügt: " .. filename)
end

-- ====== SYNC ======

function Agents.sync(callback)
    print("Starte Sync...")
    
    -- 1. Upload Pending Messages
    local files = playdate.file.listFiles("recordings") or {}
    local pendingFiles = {}
    for _, file in ipairs(files) do
        if file:sub(-4) == ".wav" then
            table.insert(pendingFiles, "recordings/" .. file)
        end
    end
    
    local function uploadNext(index)
        if index > #pendingFiles then
            -- Alle hochgeladen, weiter zu Schritt 2
            Agents.fetchAgents(callback)
            return
        end
        
        local filePath = pendingFiles[index]
        local filename = filePath:match("([^/]+)%.wav$")
        -- Parse agentId from filename (assuming agentId_timestamp format)
        -- Format: agentId_timestamp
        -- Wir suchen nach dem letzten Underscore als Trenner, falls die ID Underscores enthält
        local lastUnderscore = filename:match("^.*()_")
        local agentId = nil
        if lastUnderscore then
            agentId = filename:sub(1, lastUnderscore - 1)
        end
        
        if agentId then
            print("Lade hoch: " .. filename .. " für Agent " .. agentId)
            Network.uploadMessage(filePath, agentId, filename .. ".wav", function(success, err)
                if success then
                    print("Upload erfolgreich: " .. filename)
                    playdate.file.delete(filePath)
                else
                    print("Upload Fehler: " .. (err or "unknown"))
                end
                uploadNext(index + 1)
            end)
        else
            print("Konnte AgentID nicht parsen: " .. filename)
            uploadNext(index + 1)
        end
    end
    
    uploadNext(1)
end

function Agents.fetchAgents(callback)
    print("Lade Agentenliste...")
    Network.getAgents(function(success, remoteAgents, err)
        if success and remoteAgents then
            local newAgentList = {}
            local oldAgentsMap = {}
            for _, a in ipairs(agents) do oldAgentsMap[a.id] = a end
            
            local pendingAvatars = {}
            
            for _, remoteAgent in ipairs(remoteAgents) do
                local localAgent = oldAgentsMap[remoteAgent.id]
                if localAgent then
                    -- Update name if changed
                    localAgent.name = remoteAgent.name
                    table.insert(newAgentList, localAgent)
                else
                    -- New agent
                    local newAgent = {
                        id = remoteAgent.id,
                        name = remoteAgent.name,
                        avatarPath = nil, 
                        notifications = {}
                    }
                    table.insert(newAgentList, newAgent)
                    table.insert(pendingAvatars, newAgent)
                end
            end
            
            agents = newAgentList
            -- Reset current index if out of bounds
            if currentAgentIndex > #agents then
                currentAgentIndex = 1
            end
            
            Storage.saveAgents(agents)
            print("Agentenliste aktualisiert. " .. #agents .. " Agenten.")
            
            -- Fetch avatars for new agents
            local function fetchNextAvatar(index)
                if index > #pendingAvatars then
                    if callback then callback(true) end
                    return
                end
                
                local agent = pendingAvatars[index]
                print("Lade Avatar für: " .. agent.name)
                Network.getAvatar(agent.id, function(success, data)
                    if success and data then
                        -- Format-Erkennung
                        local ext = nil
                        if data:sub(1, 4) == "\137PNG" then
                            ext = ".png"
                            print("Warnung: Server sendet PNG. Playdate kann PNGs zur Laufzeit nicht laden (nur GIF oder PDI).")
                        elseif data:sub(1, 3) == "GIF" then
                            ext = ".gif"
                        end
                        
                        if ext then
                            local path = "avatars/" .. agent.id .. ext
                            -- Ensure directory exists
                            if not playdate.file.isdir("avatars") then
                                playdate.file.mkdir("avatars")
                            end

                            local file = playdate.file.open(path, playdate.file.kFileWrite)
                            if file then
                                file:write(data)
                                file:close()
                                
                                agent.avatarPath = path
                                Storage.saveAgents(agents)
                                print("Avatar gespeichert: " .. path)
                            end
                        else
                            print("Unbekanntes Bildformat für Agent " .. agent.name)
                        end
                    else
                        print("Fehler beim Avatar laden für " .. agent.name)
                    end
                    fetchNextAvatar(index + 1)
                end)
            end
            
            fetchNextAvatar(1)
            
        else
            print("Fehler beim Laden der Agenten: " .. (err or "unknown"))
            if callback then callback(false) end
        end
    end)
end

-- Entfernt eine Aufnahme aus RAM (nach erfolgreichem Upload)
function Agents.removeRecording(agentIndex, recordingName)
    if not recordings[agentIndex] then return false end
    
    for i, rec in ipairs(recordings[agentIndex]) do
        if rec.name == recordingName then
            table.remove(recordings[agentIndex], i)
            return true
        end
    end
    return false
end

-- Gibt alle Aufnahmen für alle Agenten zurück (für Sync)
function Agents.getAllPendingRecordings()
    local all = {}
    for agentIndex, recs in pairs(recordings) do
        for _, rec in ipairs(recs) do
            table.insert(all, {
                agentIndex = agentIndex,
                agentId = agents[agentIndex].id,
                name = rec.name,
                length = rec.length
            })
        end
    end
    return all
end

function Agents.getRecordingCount(agentIndex)
    if recordings[agentIndex] and #recordings[agentIndex] > 0 then
        return #recordings[agentIndex]
    end
    -- Fallback: Zähle von Disk
    return Storage.getRecordingCountForAgent(agentIndex)
end

function Agents.getAgentCount()
    return #agents
end

-- ====== AGENTEN-VERWALTUNG ======

-- Gibt alle Agenten zurück
function Agents.getAll()
    return agents
end

-- Gibt einen Agenten nach Server-ID zurück
function Agents.getAgentById(id)
    for i, agent in ipairs(agents) do
        if agent.id == id then
            return agent, i
        end
    end
    return nil, nil
end

-- Setzt die komplette Agentenliste (nach Sync)
function Agents.setAgents(newAgents)
    -- Behalte lokale Daten (notifications, avatarPath) für bekannte Agenten
    for _, newAgent in ipairs(newAgents) do
        local existing, idx = Agents.getAgentById(newAgent.id)
        if existing then
            -- Übernehme nur Name (Avatar/Notifications bleiben)
            existing.name = newAgent.name
        else
            -- Neuer Agent
            newAgent.notifications = newAgent.notifications or {}
            newAgent.avatarPath = nil
            table.insert(agents, newAgent)
            recordings[#agents] = {}
        end
    end
    
    -- Speichere auf Disk
    Storage.saveAgents(agents)
end

-- Aktualisiert einen einzelnen Agenten (nach Detail-Abruf)
function Agents.updateAgent(id, updates)
    local agent, idx = Agents.getAgentById(id)
    if agent then
        for k, v in pairs(updates) do
            agent[k] = v
        end
        Storage.saveAgents(agents)
        return true
    end
    return false
end

-- Gibt die IDs aller Agenten zurück
function Agents.getAgentIds()
    local ids = {}
    for _, agent in ipairs(agents) do
        table.insert(ids, agent.id)
    end
    return ids
end

-- ====== NOTIFICATIONS ======

-- Fügt eine Notification zu einem Agenten hinzu (max. 5, älteste raus)
function Agents.addNotification(agentId, notification)
    local agent, idx = Agents.getAgentById(agentId)
    if not agent then
        print("Agent nicht gefunden: " .. tostring(agentId))
        return false
    end
    
    if not agent.notifications then
        agent.notifications = {}
    end
    
    -- Notification-Struktur: { text, sentences, timestamp, replyTo }
    local newNotification = {
        text = notification.text or notification.antwort,
        sentences = Agents.splitIntoSentences(notification.text or notification.antwort),
        timestamp = notification.timestamp or playdate.getSecondsSinceEpoch(),
        replyTo = notification.replyTo or notification.antwort_auf,
        type = "text"
    }
    
    -- Am Ende hinzufügen
    table.insert(agent.notifications, newNotification)
    
    -- Max. 5 behalten (älteste entfernen)
    while #agent.notifications > MAX_NOTIFICATIONS do
        table.remove(agent.notifications, 1)
    end
    
    -- Speichern
    Storage.saveAgents(agents)
    
    print("Notification hinzugefügt für Agent " .. agentId)
    return true
end

-- Gibt alle Notifications für einen Agenten zurück
function Agents.getNotifications(agentId)
    local agent = Agents.getAgentById(agentId)
    if agent then
        return agent.notifications or {}
    end
    return {}
end

-- Gibt alle Nachrichten (Audio + Text) für den aktuellen Agenten zurück
function Agents.getAllMessagesForCurrentAgent()
    local messages = {}
    local agentIndex = currentAgentIndex
    local agent = agents[agentIndex]
    
    -- Audio-Aufnahmen hinzufügen
    if recordings[agentIndex] then
        for _, rec in ipairs(recordings[agentIndex]) do
            table.insert(messages, {
                type = "audio",
                name = rec.name,
                length = rec.length,
                data = rec.data,
                timestamp = tonumber(rec.name) or 0
            })
        end
    end
    
    -- Text-Notifications hinzufügen
    if agent.notifications then
        for _, notif in ipairs(agent.notifications) do
            table.insert(messages, {
                type = "text",
                text = notif.text,
                sentences = notif.sentences,
                timestamp = notif.timestamp or 0,
                replyTo = notif.replyTo
            })
        end
    end
    
    -- Nach Timestamp sortieren
    table.sort(messages, function(a, b)
        return (a.timestamp or 0) < (b.timestamp or 0)
    end)
    
    return messages
end

-- Hilfsfunktion: Text in Sätze aufteilen
function Agents.splitIntoSentences(text)
    if not text then return {} end
    
    local sentences = {}
    -- Splitten an . ! ? gefolgt von Leerzeichen oder Ende
    for sentence in text:gmatch("[^%.!?]+[%.!?]*") do
        sentence = sentence:match("^%s*(.-)%s*$") -- Trim
        if sentence and #sentence > 0 then
            table.insert(sentences, sentence)
        end
    end
    
    -- Falls keine Sätze gefunden, ganzen Text als einen Satz
    if #sentences == 0 and #text > 0 then
        table.insert(sentences, text)
    end
    
    return sentences
end

-- Gibt die Gesamtzahl der Nachrichten (Audio + Text) zurück
function Agents.getTotalMessageCount(agentIndex)
    local count = 0
    
    -- Audio zählen
    if recordings[agentIndex] then
        count = count + #recordings[agentIndex]
    end
    
    -- Text-Notifications zählen
    if agents[agentIndex] and agents[agentIndex].notifications then
        count = count + #agents[agentIndex].notifications
    end
    
    return count
end
