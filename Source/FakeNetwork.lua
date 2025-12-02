-- Source/FakeNetwork.lua
-- Mock-Implementierung von Network.lua für Tests ohne Backend.
-- Implementiert die gleiche Schnittstelle wie Network.lua.
-- Nutzt playdate.timer für simulierte Netzwerkverzögerungen.

Network = {}

-- Konfiguration (wird beim Init gesetzt, aber nicht wirklich verwendet)
local config = {
    server = "fake-backend.local",
    port = 443,
    useSSL = true,
    apiKey = "FAKE_API_KEY"
}

-- Simulierte Daten
local fakeData = {
    -- Simulierte Notifications (werden beim ersten Abruf geliefert)
    pendingNotifications = {
        {
            antwort_auf = "1732980000",
            antwort_von = "1",
            antwort = "Das ist eine simulierte Antwort vom Notizagenten. Sie hat mehrere Sätze! Damit können wir das Satz-Splitting testen? Ja, das können wir."
        },
        {
            antwort_auf = "1732980100",
            antwort_von = "2",
            antwort = "Der Aktienagent meldet: DAX +1.2%, NASDAQ -0.5%. Empfehlung: Halten."
        }
    },
    
    -- Simulierte Agentenliste
    agents = {
        { id = "1", name = "Notizagent" },
        { id = "2", name = "Aktienagent" },
        { id = "3", name = "Suchagent" }
    },
    
    -- Simulierte Agent-Details
    agentDetails = {
        ["1"] = { id = "1", name = "Notizagent", avatar = nil },
        ["2"] = { id = "2", name = "Aktienagent", avatar = nil },
        ["3"] = { id = "3", name = "Suchagent", avatar = nil }
    }
}

-- ====== INITIALISIERUNG ======

function Network.init(serverUrl, apiKey)
    if serverUrl then
        config.server = serverUrl:gsub("^https?://", ""):gsub("/$", "")
    end
    
    if apiKey then
        config.apiKey = apiKey
    end
    
    print("[FakeNetwork] Initialisiert (Mock-Modus): " .. config.server)
end

-- ====== HEALTH CHECK ======

function Network.checkHealth(callback)
    print("[FakeNetwork] Health Check...")
    playdate.timer.performAfterDelay(200, function()
        print("[FakeNetwork] Health OK")
        callback(true, nil)
    end)
end

-- ====== NACHRICHTEN UPLOAD ======

function Network.uploadRecording(recordingName, agentId, callback)
    print("[FakeNetwork] Uploading: " .. recordingName .. " für Agent " .. tostring(agentId))
    
    -- Prüfe ob Datei existiert (realistischer Mock)
    local binaryData = Storage.readRecordingBinary(recordingName)
    
    if not binaryData then
        print("[FakeNetwork] Fehler: Datei nicht gefunden")
        callback(false, nil, "Datei nicht gefunden")
        return
    end
    
    -- Simuliere Upload-Verzögerung (länger für größere Dateien)
    local delay = math.min(2000, 500 + #binaryData / 100)
    
    playdate.timer.performAfterDelay(delay, function()
        local messageId = "msg_" .. recordingName
        print("[FakeNetwork] Upload erfolgreich: " .. messageId)
        callback(true, messageId, nil)
    end)
end

-- ====== NOTIFICATIONS ABRUFEN ======

function Network.fetchNotifications(agentIds, callback)
    print("[FakeNetwork] Fetching notifications...")
    
    playdate.timer.performAfterDelay(500, function()
        -- Liefere die ausstehenden Notifications und leere sie dann
        local answers = fakeData.pendingNotifications
        fakeData.pendingNotifications = {} -- Nach Abruf leer
        
        print("[FakeNetwork] Notifications: " .. #answers .. " Antworten")
        callback(true, answers, nil)
    end)
end

-- ====== AGENTEN ABRUFEN ======

function Network.fetchAgentList(callback)
    print("[FakeNetwork] Fetching agent list...")
    
    playdate.timer.performAfterDelay(400, function()
        print("[FakeNetwork] Agents: " .. #fakeData.agents)
        callback(true, fakeData.agents, nil)
    end)
end

function Network.fetchAgentDetails(agentId, callback)
    print("[FakeNetwork] Fetching details for agent: " .. tostring(agentId))
    
    playdate.timer.performAfterDelay(300, function()
        local details = fakeData.agentDetails[tostring(agentId)]
        
        if details then
            print("[FakeNetwork] Details gefunden für: " .. details.name)
            callback(true, details, nil)
        else
            print("[FakeNetwork] Agent nicht gefunden: " .. tostring(agentId))
            callback(false, nil, "Agent nicht gefunden")
        end
    end)
end

-- ====== HILFSFUNKTIONEN ======

function Network.getStatus()
    -- Simuliere immer verbunden
    return "connected"
end

function Network.isConnected()
    return true
end

function Network.setEnabled(enabled, callback)
    print("[FakeNetwork] setEnabled: " .. tostring(enabled))
    if callback then
        playdate.timer.performAfterDelay(100, function()
            callback(true, nil)
        end)
    end
end

-- ====== TEST-HELFER (nur für FakeNetwork) ======

-- Fügt eine neue Notification zum nächsten Abruf hinzu
function Network.addFakeNotification(agentId, text, replyTo)
    table.insert(fakeData.pendingNotifications, {
        antwort_auf = replyTo or tostring(playdate.getSecondsSinceEpoch()),
        antwort_von = tostring(agentId),
        antwort = text
    })
    print("[FakeNetwork] Fake-Notification hinzugefügt für Agent " .. tostring(agentId))
end

-- Fügt einen neuen Agenten hinzu
function Network.addFakeAgent(id, name)
    table.insert(fakeData.agents, { id = tostring(id), name = name })
    fakeData.agentDetails[tostring(id)] = { id = tostring(id), name = name, avatar = nil }
    print("[FakeNetwork] Fake-Agent hinzugefügt: " .. name)
end

-- Setzt alle Fake-Daten zurück
function Network.resetFakeData()
    fakeData.pendingNotifications = {
        {
            antwort_auf = "1732980000",
            antwort_von = "1",
            antwort = "Das ist eine simulierte Antwort vom Notizagenten. Sie hat mehrere Sätze! Damit können wir das Satz-Splitting testen? Ja, das können wir."
        },
        {
            antwort_auf = "1732980100",
            antwort_von = "2",
            antwort = "Der Aktienagent meldet: DAX +1.2%, NASDAQ -0.5%. Empfehlung: Halten."
        }
    }
    print("[FakeNetwork] Fake-Daten zurückgesetzt")
end

