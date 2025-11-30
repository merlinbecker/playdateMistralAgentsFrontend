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
local agents = {
    { id = "1", name = "Notizagent", avatarPath = nil, notifications = {} },
    { id = "2", name = "Aktienagent", avatarPath = nil, notifications = {} },
    { id = "3", name = "Suchagent", avatarPath = nil, notifications = {} }
}

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

-- Löscht alle Aufnahmen (RAM + Disk)
function Agents.deleteAllRecordings()
    -- Lösche von Disk
    Storage.deleteAllRecordings()
    
    -- Lösche aus RAM
    for i, _ in ipairs(agents) do
        recordings[i] = {}
    end
    
    print("Alle Aufnahmen gelöscht (RAM + Disk)")
end

function Agents.update()
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
    elseif crankAccumulator < -CRANK_THRESHOLD then
        currentAgentIndex = currentAgentIndex - 1
        if currentAgentIndex < 1 then
            currentAgentIndex = #agents
        end
        crankAccumulator = 0
        print("Agent gewechselt: " .. agents[currentAgentIndex].name)
    end
end

function Agents.getCurrentAgentName()
    return agents[currentAgentIndex].name
end

function Agents.getCurrentAgentID()
    return agents[currentAgentIndex].id
end

function Agents.getCurrentAgentIndex()
    return currentAgentIndex
end

function Agents.getCurrentAgent()
    return agents[currentAgentIndex]
end

function Agents.getRecordingsForCurrentAgent()
    return recordings[currentAgentIndex] or {}
end

function Agents.addRecording(agentIndex, name, length, data)
    if not recordings[agentIndex] then
        recordings[agentIndex] = {}
    end
    
    local newRecording = {
        name = name, -- unixtimestamp
        length = length,
        agentID = agents[agentIndex].id,
        agentIndex = agentIndex,
        data = data -- Sample-Objekt
    }
    
    -- Im RAM speichern
    table.insert(recordings[agentIndex], newRecording)
    
    -- Auf Disk speichern
    Storage.saveRecording(newRecording)
    
    print("Aufnahme gespeichert für Agent " .. agentIndex)
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
