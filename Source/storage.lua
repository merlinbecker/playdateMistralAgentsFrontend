-- Source/storage.lua
-- Persistente Speicherung von Aufnahmen auf Disk.
-- Audio-Dateien werden als .wav gespeichert (fuer Backend-Kompatibilitaet), Metadaten im JSON.

Storage = {}

local RECORDINGS_DIR = "recordings"
local METADATA_FILE = "recordings_meta"
local AGENTS_FILE = "agents_data"
local AVATARS_DIR = "avatars"

-- Hilfsfunktion: Verzeichnis erstellen falls noetig
local function ensureDir(path)
    if not playdate.file.isdir(path) then
        playdate.file.mkdir(path)
    end
end

-- Initialisierung
function Storage.init()
    ensureDir(RECORDINGS_DIR)
    ensureDir(AVATARS_DIR)
end

-- Speichert eine einzelne Aufnahme (Sample + Metadaten)
-- recording: { name, length, agentID, data (sample) }
function Storage.saveRecording(recording)
    if not recording or not recording.data then
        print("Fehler: Keine Daten zum Speichern.")
        return false
    end
    
    ensureDir(RECORDINGS_DIR)
    
    -- Dateiname fuer das Audio-Sample (.wav fuer Backend-Kompatibilitaet)
    local audioFilename = RECORDINGS_DIR .. "/" .. recording.name .. ".wav"
    
    -- Sample als WAV speichern
    local sample = recording.data
    if sample and sample.save then
        sample:save(audioFilename)
        print("Audio gespeichert (WAV): " .. audioFilename)
    else
        print("Fehler: Sample konnte nicht gespeichert werden.")
        return false
    end
    
    -- Metadaten laden, erweitern und speichern
    local meta = Storage.loadAllMetadata() or {}
    
    -- Neue Aufnahme zu Metadaten hinzufuegen (ohne data-Referenz)
    local metaEntry = {
        name = recording.name,
        length = recording.length,
        agentID = recording.agentID,
        agentIndex = recording.agentIndex,
        audioFile = audioFilename
    }
    
    table.insert(meta, metaEntry)
    
    -- Metadaten speichern
    playdate.datastore.write(meta, METADATA_FILE)
    print("Metadaten gespeichert.")
    
    return true
end

-- Laedt alle Metadaten aus dem JSON
function Storage.loadAllMetadata()
    local meta = playdate.datastore.read(METADATA_FILE)
    return meta or {}
end

-- Laedt alle Aufnahmen fuer einen bestimmten Agenten
-- agentIndex: Numerischer Index des Agenten (1-basiert)
-- Gibt eine Tabelle mit { name, length, agentID, data (sample) } zurueck
function Storage.loadRecordingsForAgent(agentIndex)
    local meta = Storage.loadAllMetadata()
    local result = {}
    
    -- agentIndex zu String für Vergleich (wird als String gespeichert)
    local agentIndexStr = tostring(agentIndex)
    
    for _, entry in ipairs(meta) do
        -- Vergleiche sowohl mit agentID (String) als auch agentIndex
        if tostring(entry.agentID) == agentIndexStr or entry.agentIndex == agentIndex then
            -- Sample laden
            local sample = nil
            if entry.audioFile and playdate.file.exists(entry.audioFile) then
                sample = playdate.sound.sample.new(entry.audioFile)
            end
            
            local recording = {
                name = entry.name,
                length = entry.length,
                agentID = entry.agentID,
                data = sample
            }
            table.insert(result, recording)
        end
    end
    
    return result
end

-- Zählt Aufnahmen für einen Agenten (ohne Samples zu laden)
function Storage.getRecordingCountForAgent(agentIndex)
    local meta = Storage.loadAllMetadata()
    local count = 0
    local agentIndexStr = tostring(agentIndex)
    
    for _, entry in ipairs(meta) do
        if tostring(entry.agentID) == agentIndexStr or entry.agentIndex == agentIndex then
            count = count + 1
        end
    end
    
    return count
end

-- Löscht ALLE Aufnahmen (Audio-Dateien + Metadaten)
function Storage.deleteAllRecordings()
    print("Lösche alle Aufnahmen...")
    
    -- Lösche alle Dateien im Recordings-Ordner
    local files = playdate.file.listFiles(RECORDINGS_DIR) or {}
    for _, file in ipairs(files) do
        if file ~= "." and file ~= ".." then
            local fullPath = RECORDINGS_DIR .. "/" .. file
            local success = playdate.file.delete(fullPath)
            if success then
                print("Gelöscht: " .. fullPath)
            else
                print("Konnte nicht löschen: " .. fullPath)
            end
        end
    end
    
    -- Metadaten-Datei löschen
    playdate.datastore.delete(METADATA_FILE)
    
    -- Verzeichnis löschen (falls leer)
    playdate.file.delete(RECORDINGS_DIR)
    
    print("Alle Aufnahmen gelöscht.")
    return true
end

-- Gibt Gesamtzahl aller Aufnahmen zurück
function Storage.getTotalRecordingCount()
    local meta = Storage.loadAllMetadata()
    return #meta
end

-- ====== EINZELNE AUFNAHME LÖSCHEN ======

-- Loescht eine einzelne Aufnahme (Audio + Metadaten)
function Storage.deleteRecording(recordingName)
    local meta = Storage.loadAllMetadata()
    local newMeta = {}
    local deletedFromMeta = false
    
    for _, entry in ipairs(meta) do
        if entry.name == recordingName then
            deletedFromMeta = true
        else
            table.insert(newMeta, entry)
        end
    end
    
    -- Aktualisierte Metadaten speichern
    if deletedFromMeta then
        playdate.datastore.write(newMeta, METADATA_FILE)
        print("Metadaten geloescht fuer: " .. recordingName)
    end
    
    -- Versuche IMMER die Datei zu loeschen, auch wenn nicht in Metadaten
    local audioFile = RECORDINGS_DIR .. "/" .. recordingName .. ".wav"
    local fileDeleted = false
    if playdate.file.exists(audioFile) then
        playdate.file.delete(audioFile)
        print("Audio-Datei geloescht: " .. audioFile)
        fileDeleted = true
    else
        print("Audio-Datei nicht gefunden (bereits geloescht?): " .. audioFile)
    end
    
    return deletedFromMeta or fileDeleted
end

-- ====== BINARY READ FÜR UPLOAD ======

-- Liest eine WAV-Datei als Binary-Daten (für HTTP-Upload)
function Storage.readRecordingBinary(recordingName)
    local audioFile = RECORDINGS_DIR .. "/" .. recordingName .. ".wav"
    
    if not playdate.file.exists(audioFile) then
        print("Datei nicht gefunden: " .. audioFile)
        return nil
    end
    
    local file, err = playdate.file.open(audioFile, playdate.file.kFileRead)
    if not file then
        print("Fehler beim Öffnen: " .. (err or "unbekannt"))
        return nil
    end
    
    local size = playdate.file.getSize(audioFile)
    local data, readErr = file:read(size)
    file:close()
    
    if not data then
        print("Fehler beim Lesen: " .. (readErr or "unbekannt"))
        return nil
    end
    
    return data
end

-- Gibt den Dateipfad einer Aufnahme zurück
function Storage.getRecordingFilePath(recordingName)
    return RECORDINGS_DIR .. "/" .. recordingName .. ".wav"
end

-- ====== AGENTEN PERSISTENZ ======

-- Speichert die Agentenliste (mit Notifications, ohne Sample-Daten)
function Storage.saveAgents(agents)
    -- Kopiere Agenten ohne data-Referenzen
    local saveData = {}
    for _, agent in ipairs(agents) do
        table.insert(saveData, {
            id = agent.id,
            name = agent.name,
            avatarPath = agent.avatarPath,
            notifications = agent.notifications or {}
        })
    end
    
    playdate.datastore.write(saveData, AGENTS_FILE)
    print("Agenten gespeichert: " .. #saveData)
    return true
end

-- Lädt die Agentenliste von Disk
function Storage.loadAgents()
    local agents = playdate.datastore.read(AGENTS_FILE)
    if agents then
        print("Agenten geladen: " .. #agents)
        -- Stelle sicher, dass jeder Agent notifications hat
        for _, agent in ipairs(agents) do
            agent.notifications = agent.notifications or {}
        end
    end
    return agents
end

-- ====== RESET ======

function Storage.resetAll()
    -- Lösche Aufnahmen
    local files = playdate.file.listFiles(RECORDINGS_DIR) or {}
    for _, file in ipairs(files) do
        if file ~= "." and file ~= ".." then
            playdate.file.delete(RECORDINGS_DIR .. "/" .. file)
        end
    end
    
    -- Verifiziere Löschung der Aufnahmen
    local remainingRecordings = playdate.file.listFiles(RECORDINGS_DIR) or {}
    local recCount = 0
    for _, file in ipairs(remainingRecordings) do
        if file ~= "." and file ~= ".." then
            recCount = recCount + 1
            print("WARNUNG: Aufnahme nicht gelöscht: " .. file)
            -- Versuche erneut zu löschen
            playdate.file.delete(RECORDINGS_DIR .. "/" .. file)
        end
    end
    if recCount == 0 then
        print("Verifizierung: Alle Aufnahmen erfolgreich gelöscht.")
    end
    
    -- Lösche Avatare
    files = playdate.file.listFiles(AVATARS_DIR) or {}
    for _, file in ipairs(files) do
        if file ~= "." and file ~= ".." then
            playdate.file.delete(AVATARS_DIR .. "/" .. file)
        end
    end
    
    -- Verifiziere Löschung der Avatare
    local remainingAvatars = playdate.file.listFiles(AVATARS_DIR) or {}
    local avCount = 0
    for _, file in ipairs(remainingAvatars) do
        if file ~= "." and file ~= ".." then
            avCount = avCount + 1
            print("WARNUNG: Avatar nicht gelöscht: " .. file)
             -- Versuche erneut zu löschen
             playdate.file.delete(AVATARS_DIR .. "/" .. file)
        end
    end
    if avCount == 0 then
        print("Verifizierung: Alle Avatare erfolgreich gelöscht.")
    end
    
    -- Lösche Datastore Dateien
    playdate.datastore.delete(METADATA_FILE)
    playdate.datastore.delete(AGENTS_FILE)
    
    print("Alle Daten gelöscht.")
end

-- ====== AVATAR SPEICHERUNG ======

-- Speichert ein Avatar-Bild (Base64 vom Server dekodiert zu Bild)
function Storage.saveAgentAvatar(agentId, imageData)
    ensureDir(AVATARS_DIR)
    
    local filename = AVATARS_DIR .. "/avatar_" .. agentId
    
    -- imageData ist ein playdate.graphics.image Objekt
    if imageData and imageData.getSize then
        playdate.datastore.writeImage(imageData, filename)
        print("Avatar gespeichert: " .. filename)
        return filename
    end
    
    return nil
end

-- Lädt ein Avatar-Bild
function Storage.loadAgentAvatar(agentId)
    local filename = AVATARS_DIR .. "/avatar_" .. agentId
    local image = playdate.datastore.readImage(filename)
    return image
end
