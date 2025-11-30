-- Source/Network.lua
-- HTTP-Netzwerk-Modul für die Kommunikation mit dem Backend.
-- Nutzt playdate.network.http für echte HTTP-Requests.
-- HINWEIS: json wird in main.lua global verfügbar gemacht (playdate.json)

Network = {}

-- Konfiguration (wird beim Init gesetzt)
local config = {
    server = "your-backend.replit.app",  -- Backend-Server
    port = 443,
    useSSL = true,
    apiKey = "YOUR_API_KEY"  -- Wird aus Config geladen
}

local http = playdate.network.http

-- ====== INITIALISIERUNG ======

function Network.init(serverUrl, apiKey)
    if serverUrl then
        -- Parse URL (entferne https:// falls vorhanden)
        local server = serverUrl:gsub("^https?://", "")
        -- Entferne trailing slash
        server = server:gsub("/$", "")
        config.server = server
    end
    
    if apiKey then
        config.apiKey = apiKey
    end
    
    print("Network initialisiert: " .. config.server)
end

-- Gibt Authorization-Header zurück
local function getAuthHeader()
    return "Authorization: Bearer " .. config.apiKey
end

-- ====== HEALTH CHECK ======

-- Prüft die Verbindung zum Backend
function Network.checkHealth(callback)
    local conn = http.new(config.server, config.port, config.useSSL, "Netzwerkzugriff für Sync")
    
    if not conn then
        callback(false, "Verbindung fehlgeschlagen")
        return
    end
    
    local headers = {
        getAuthHeader(),
        "Content-Type: application/json"
    }
    
    local success, err = conn:get("/health", headers)
    
    if not success then
        callback(false, err or "Request fehlgeschlagen")
        return
    end
    
    conn:setRequestCompleteCallback(function()
        local status = conn:getResponseStatus()
        if status == 200 then
            callback(true, nil)
        else
            callback(false, "Status: " .. tostring(status))
        end
        conn:close()
    end)
end

-- ====== NACHRICHTEN UPLOAD ======

-- Lädt eine einzelne WAV-Datei hoch (Binary + Metadaten im Header)
-- recordingName: Name der Aufnahme (Timestamp)
-- agentId: Server-ID des Agenten
-- callback: function(success, messageId, error)
function Network.uploadRecording(recordingName, agentId, callback)
    -- Binary-Daten laden
    local binaryData = Storage.readRecordingBinary(recordingName)
    
    if not binaryData then
        callback(false, nil, "Datei nicht gefunden")
        return
    end
    
    local conn = http.new(config.server, config.port, config.useSSL, "Upload Sprachnotiz")
    
    if not conn then
        callback(false, nil, "Verbindung fehlgeschlagen")
        return
    end
    
    local headers = {
        getAuthHeader(),
        "Content-Type: audio/wav",
        "X-Agent-ID: " .. tostring(agentId),
        "X-Message-Name: " .. tostring(recordingName)
    }
    
    local success, err = conn:post("/messages", headers, binaryData)
    
    if not success then
        callback(false, nil, err or "Request fehlgeschlagen")
        return
    end
    
    conn:setRequestCompleteCallback(function()
        local status = conn:getResponseStatus()
        
        if status == 200 or status == 201 then
            -- Response lesen und parsen
            local responseData = conn:read(4096)
            local response = nil
            
            if responseData then
                response = json.decode(responseData)
            end
            
            local messageId = response and response.message_id or recordingName
            callback(true, messageId, nil)
        else
            callback(false, nil, "Upload fehlgeschlagen: " .. tostring(status))
        end
        
        conn:close()
    end)
end

-- ====== NOTIFICATIONS ABRUFEN ======

-- Holt alle ausstehenden Antworten vom Backend
-- agentIds: Liste der Agent-IDs
-- callback: function(success, answers, error)
-- answers: { { antwort_auf, antwort_von, antwort }, ... }
function Network.fetchNotifications(agentIds, callback)
    local conn = http.new(config.server, config.port, config.useSSL, "Lade Benachrichtigungen")
    
    if not conn then
        callback(false, nil, "Verbindung fehlgeschlagen")
        return
    end
    
    local headers = {
        getAuthHeader(),
        "Content-Type: application/json"
    }
    
    -- Agent-IDs als Query-Parameter oder im Body
    local path = "/messages/answers"
    
    local success, err = conn:get(path, headers)
    
    if not success then
        callback(false, nil, err or "Request fehlgeschlagen")
        return
    end
    
    conn:setRequestCompleteCallback(function()
        local status = conn:getResponseStatus()
        
        if status == 200 then
            local responseData = conn:read(8192)
            local answers = {}
            
            if responseData then
                answers = json.decode(responseData) or {}
            end
            
            callback(true, answers, nil)
        else
            callback(false, nil, "Abruf fehlgeschlagen: " .. tostring(status))
        end
        
        conn:close()
    end)
end

-- ====== AGENTEN ABRUFEN ======

-- Holt die Liste aller verfügbaren Agenten
-- callback: function(success, agents, error)
-- agents: { { id, name }, ... }
function Network.fetchAgentList(callback)
    local conn = http.new(config.server, config.port, config.useSSL, "Lade Agenten")
    
    if not conn then
        callback(false, nil, "Verbindung fehlgeschlagen")
        return
    end
    
    local headers = {
        getAuthHeader(),
        "Content-Type: application/json"
    }
    
    local success, err = conn:get("/agents", headers)
    
    if not success then
        callback(false, nil, err or "Request fehlgeschlagen")
        return
    end
    
    conn:setRequestCompleteCallback(function()
        local status = conn:getResponseStatus()
        
        if status == 200 then
            local responseData = conn:read(4096)
            local agents = {}
            
            if responseData then
                agents = json.decode(responseData) or {}
            end
            
            callback(true, agents, nil)
        else
            callback(false, nil, "Abruf fehlgeschlagen: " .. tostring(status))
        end
        
        conn:close()
    end)
end

-- Holt Details eines einzelnen Agenten (inkl. Avatar)
-- agentId: Server-ID des Agenten
-- callback: function(success, agentDetails, error)
-- agentDetails: { id, name, avatar (Base64) }
function Network.fetchAgentDetails(agentId, callback)
    local conn = http.new(config.server, config.port, config.useSSL, "Lade Agent-Details")
    
    if not conn then
        callback(false, nil, "Verbindung fehlgeschlagen")
        return
    end
    
    local headers = {
        getAuthHeader(),
        "Content-Type: application/json"
    }
    
    local success, err = conn:get("/agents/" .. tostring(agentId), headers)
    
    if not success then
        callback(false, nil, err or "Request fehlgeschlagen")
        return
    end
    
    conn:setRequestCompleteCallback(function()
        local status = conn:getResponseStatus()
        
        if status == 200 then
            local responseData = conn:read(16384)  -- Größerer Buffer für Avatar
            local details = nil
            
            if responseData then
                details = json.decode(responseData)
            end
            
            callback(true, details, nil)
        else
            callback(false, nil, "Abruf fehlgeschlagen: " .. tostring(status))
        end
        
        conn:close()
    end)
end

-- ====== HILFSFUNKTIONEN ======

-- Prüft Netzwerkstatus
function Network.getStatus()
    return playdate.network.getStatus()
end

-- Gibt true zurück wenn verbunden
function Network.isConnected()
    local status = playdate.network.getStatus()
    return status == playdate.network.kStatusConnected
end

-- Aktiviert/Deaktiviert WLAN
function Network.setEnabled(enabled, callback)
    playdate.network.setEnabled(enabled, function(err)
        if callback then
            callback(err == nil, err)
        end
    end)
end
