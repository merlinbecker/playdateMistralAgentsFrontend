-- Source/agents.lua
-- Verwaltet die Agenten, deren Auswahl und die zugehoerigen Aufnahmen.

Agents = {}

-- Konfiguration
local MAX_NOTIFICATIONS = 5 -- Maximale Anzahl Notifications pro Agent
local currentAgentIndex = 1
local crankAccumulator = 0
local CRANK_THRESHOLD = 360 -- Eine volle Umdrehung

-- Dynamische Agentenliste (wird vom Server geladen)
-- Format: { { id = "server-id", name = "Name", avatarPath = "path/to/image", notifications = {} }, ... }
local agents = {}

-- Datenstruktur fuer Aufnahmen (im RAM gehalten nach Laden)
-- Format: { [agentIndex] = { { name = "timestamp", length = 123, data = sample }, ... } }
local recordings = {}

-- Helper: Parse Binary Avatar (64x64, 1-bit)
local function loadAvatarFromBinary(data)
    local gfx = playdate.graphics
    
    -- Minimalpruefungen
    if #data < 516 then return nil, "data too short" end

    local magic = string.byte(data, 1)
    local version = string.byte(data, 2)
    local width = string.byte(data, 3)
    local height = string.byte(data, 4)

    if magic ~= string.byte("A") then return nil, "invalid magic" end
    if version ~= 0x01 then return nil, "unsupported version" end
    if width ~= 64 or height ~= 64 then return nil, "unsupported size" end

    local pixelData = data:sub(5) -- ab Byte 5 (1-basiert), 512 Bytes

    local img = gfx.image.new(width, height, gfx.kColorWhite)
    gfx.pushContext(img)

    local byteCount = #pixelData
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local bitIndex = y * width + x                -- 0..4095
            local byteIndex = math.floor(bitIndex / 8) + 1
            if byteIndex <= byteCount then
                local bitInByte = 7 - (bitIndex % 8)      -- MSB zuerst
                local byte = string.byte(pixelData, byteIndex)
                -- Native Bit-Operatoren statt bit32 (Lua 5.4 / Playdate SDK)
                local isBlack = ((byte & (1 << bitInByte)) ~= 0)
                if isBlack then
                    gfx.drawPixel(x, y)
                end
            end
        end
    end

    gfx.popContext()
    return img
end

function Agents.init()
    -- Lade gespeicherte Agenten von Disk (falls vorhanden)
    local savedAgents = Storage.loadAgents()
    if savedAgents and #savedAgents > 0 then
        agents = savedAgents
    end
    
    -- Initialisiere leere Aufnahmelisten fuer jeden Agenten
    for i, _ in ipairs(agents) do
        recordings[i] = {}
    end
    
    -- Lade gespeicherte Aufnahmen von Disk
    Agents.loadAllFromStorage()
end

-- Laedt alle gespeicherten Aufnahmen von Disk in den RAM
function Agents.loadAllFromStorage()
    for i, agent in ipairs(agents) do
        recordings[i] = Storage.loadRecordingsForAgent(agent.id)
        print("Agent " .. agent.name .. " (" .. agent.id .. "): " .. #recordings[i] .. " Aufnahmen geladen")
    end
end

-- Loesche alle Aufnahmen (RAM + Disk)
function Agents.deleteAllRecordings()
    -- Loesche von Disk
    Storage.deleteAllRecordings()
    
    -- Loesche aus RAM
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

function Agents.nextAgent()
    if #agents == 0 then return end
    currentAgentIndex = currentAgentIndex + 1
    if currentAgentIndex > #agents then
        currentAgentIndex = 1
    end
    print("Agent gewechselt: " .. agents[currentAgentIndex].name)
    if Audio and Audio.playSwitchSound then Audio.playSwitchSound() end
end

function Agents.prevAgent()
    if #agents == 0 then return end
    currentAgentIndex = currentAgentIndex - 1
    if currentAgentIndex < 1 then
        currentAgentIndex = #agents
    end
    print("Agent gewechselt: " .. agents[currentAgentIndex].name)
    if Audio and Audio.playSwitchSound then Audio.playSwitchSound() end
end

function Agents.handleCrank(change)
    if #agents == 0 then return end

    -- Crank-Logik zum Wechseln der Agenten
    crankAccumulator = crankAccumulator + change

    if crankAccumulator > CRANK_THRESHOLD then
        Agents.nextAgent()
        crankAccumulator = 0
    elseif crankAccumulator < -CRANK_THRESHOLD then
        Agents.prevAgent()
        crankAccumulator = 0
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
    
    print("Aufnahme hinzugefuegt: " .. filename)
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
    
    local totalUploads = #pendingFiles
    if UI and UI.updateSpinnerText then
        UI.updateSpinnerText(string.format("Upload: 0/%d", totalUploads))
    end

    local function uploadNext(index)
        if index > #pendingFiles then
            -- Alle hochgeladen, weiter zu Schritt 2
            if UI and UI.updateSpinnerText then
                UI.updateSpinnerText("Hole Agenten...")
            end
            Agents.fetchAgents(callback)
            return
        end
        
        if UI and UI.updateSpinnerText then
            UI.updateSpinnerText(string.format("Upload: %d/%d", index, totalUploads))
        end

        local filePath = pendingFiles[index]
        local filename = filePath:match("([^/]+)%.wav$")
        -- Parse agentId from filename (assuming agentId_timestamp format)
        -- Format: agentId_timestamp
        -- Wir suchen nach dem letzten Underscore als Trenner, falls die ID Underscores enthält
        local lastUnderscore = filename:match("^.*()_")
        local agentId = nil
        local timestamp = nil
        
        if lastUnderscore then
            agentId = filename:sub(1, lastUnderscore - 1)
            timestamp = filename:sub(lastUnderscore + 1)
        end
        
        if agentId and timestamp then
            -- Spec requires X-Message-Name: <unix_timestamp>_<agent_id>
            local messageName = timestamp .. "_" .. agentId
            
            print("Lade hoch: " .. filename .. " als " .. messageName)
            Network.uploadMessage(filePath, agentId, messageName, function(success, err)
                if success then
                    print("Upload erfolgreich: " .. filename)
                    
                    -- Loesche Datei und Metadaten via Storage
                    Storage.deleteRecording(filename)
                    
                    -- Remove from memory (aktualisiert Out-Counter)
                    local agent, idx = Agents.getAgentById(agentId)
                    if idx then
                        Agents.removeRecording(idx, filename)
                    end
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
                local agentToUse = nil

                if localAgent then
                    -- Update name if changed
                    localAgent.name = remoteAgent.name
                    agentToUse = localAgent
                else
                    -- New agent
                    agentToUse = {
                        id = remoteAgent.id,
                        name = remoteAgent.name,
                        avatarPath = nil, 
                        notifications = {}
                    }
                end
                
                -- Pruefen ob Avatar existiert (fuer neue UND bestehende Agenten)
                local expectedPath = "avatars/" .. remoteAgent.id .. ".pdi"
                
                -- Fall 1: Pfad ist gesetzt und Datei existiert -> Alles gut
                if agentToUse.avatarPath and playdate.file.exists(agentToUse.avatarPath) then
                    -- Avatar vorhanden
                -- Fall 2: Datei existiert an erwarteter Stelle (aber Pfad war evtl. nil)
                elseif playdate.file.exists(expectedPath) then
                    print("Avatar bereits vorhanden: " .. expectedPath)
                    agentToUse.avatarPath = expectedPath
                -- Fall 3: Kein Avatar -> Downloaden
                else
                    table.insert(pendingAvatars, agentToUse)
                end
                
                table.insert(newAgentList, agentToUse)
            end
            
            agents = newAgentList
            -- Reset current index if out of bounds
            if currentAgentIndex > #agents then
                currentAgentIndex = 1
            end
            
            Storage.saveAgents(agents)
            print("Agentenliste aktualisiert. " .. #agents .. " Agenten.")
            
            local totalAvatars = #pendingAvatars
            if UI and UI.updateSpinnerText and totalAvatars > 0 then
                UI.updateSpinnerText(string.format("Lade Avatare: 0/%d", totalAvatars))
            end

            -- Fetch avatars for new agents
            local function fetchNextAvatar(index)
                if index > #pendingAvatars then
                    -- Weiter zu Antworten abrufen
                    Agents.fetchAnswers(callback)
                    return
                end
                
                if UI and UI.updateSpinnerText then
                    UI.updateSpinnerText(string.format("Lade Avatare: %d/%d", index, totalAvatars))
                end

                local agent = pendingAvatars[index]
                print("Lade Avatar fuer: " .. agent.name)
                Network.getAvatar(agent.id, function(success, data)
                    if success and data then
                        -- Versuche als Binaer-Avatar zu laden
                        local img, err = loadAvatarFromBinary(data)
                        
                        if img then
                            -- Ensure directory exists
                            if not playdate.file.isdir("avatars") then
                                playdate.file.mkdir("avatars")
                            end
                            
                            local path = "avatars/" .. agent.id .. ".pdi"
                            
                            -- Nutze playdate.datastore.writeImage mit expliziter Endung
                            local success, err = playdate.datastore.writeImage(img, path)
                            
                            -- Explizite Pruefung ob Datei erstellt wurde
                            if playdate.file.exists(path) then
                                agent.avatarPath = path
                                Storage.saveAgents(agents)
                                print("Avatar gespeichert: " .. path)
                            else
                                print("Fehler beim Speichern des Avatars: " .. path .. " konnte nicht erstellt werden. Err: " .. tostring(err))
                            end
                        else
                             print("Fehler beim Parsen des Avatars fuer " .. agent.name .. ": " .. (err or "unknown"))
                        end
                    else
                        print("Fehler beim Avatar laden fuer " .. agent.name)
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

function Agents.fetchAnswers(callback)
    if UI and UI.updateSpinnerText then
        UI.updateSpinnerText("Lade Antworten...")
    end
    
    print("Lade Antworten...")
    -- Agent IDs sind optional, da der Server alle fuer den User holt
    Network.fetchNotifications(nil, function(success, answers, err)
        if success and answers then
            print("Antworten erhalten: " .. #answers)
            local count = 0
            for _, answer in ipairs(answers) do
                -- answer: { antwort_auf, antwort_von, antwort }
                local agentId = answer.antwort_von
                if agentId then
                    if Agents.addNotification(agentId, answer) then
                        count = count + 1
                    end
                end
            end
            print(count .. " Antworten verarbeitet.")
            if callback then callback(true) end
        else
            print("Fehler beim Laden der Antworten: " .. (err or "unknown"))
            -- Wir betrachten den Sync trotzdem als erfolgreich, auch wenn Antworten fehlen
            if callback then callback(true) end
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

-- Gibt alle Aufnahmen fuer alle Agenten zurueck (fuer Sync)
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
    -- Fallback: Zaehle von Disk
    if agents[agentIndex] then
        return Storage.getRecordingCountForAgent(agents[agentIndex].id)
    end
    return 0
end

function Agents.getOutgoingCount(agentIndex)
    return Agents.getRecordingCount(agentIndex)
end

function Agents.getIncomingCount(agentIndex)
    if agents[agentIndex] and agents[agentIndex].notifications then
        return #agents[agentIndex].notifications
    end
    return 0
end

function Agents.getAgentCount()
    return #agents
end

-- ====== AGENTEN-VERWALTUNG ======

-- Gibt alle Agenten zurueck
function Agents.getAll()
    return agents
end

-- Gibt einen Agenten nach Server-ID zurueck
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
    -- Behalte lokale Daten (notifications, avatarPath) fuer bekannte Agenten
    for _, newAgent in ipairs(newAgents) do
        local existing, idx = Agents.getAgentById(newAgent.id)
        if existing then
            -- Uebernehme nur Name (Avatar/Notifications bleiben)
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

-- Gibt die IDs aller Agenten zurueck
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
    
    print("Notification hinzugefuegt fuer Agent " .. agentId)
    return true
end

-- Gibt alle Notifications fuer einen Agenten zurueck
function Agents.getNotifications(agentId)
    local agent = Agents.getAgentById(agentId)
    if agent then
        return agent.notifications or {}
    end
    return {}
end

-- Gibt alle Nachrichten (Audio + Text) fuer den aktuellen Agenten zurueck
function Agents.getAllMessagesForCurrentAgent()
    local messages = {}
    local agentIndex = currentAgentIndex
    local agent = agents[agentIndex]
    
    -- Audio-Aufnahmen hinzufuegen
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
    
    -- Text-Notifications hinzufuegen
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

-- Hilfsfunktion: Text in Saetze aufteilen
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
    
    -- Falls keine Saetze gefunden, ganzen Text als einen Satz
    if #sentences == 0 and #text > 0 then
        table.insert(sentences, text)
    end
    
    return sentences
end

-- Gibt die Gesamtzahl der Nachrichten (Audio + Text) zurueck
function Agents.getTotalMessageCount(agentIndex)
    local count = 0
    
    -- Audio zaehlen
    if recordings[agentIndex] then
        count = count + #recordings[agentIndex]
    end
    
    -- Text-Notifications zaehlen
    if agents[agentIndex] and agents[agentIndex].notifications then
        count = count + #agents[agentIndex].notifications
    end
    
    return count
end
