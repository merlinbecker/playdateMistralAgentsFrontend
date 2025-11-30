-- Source/audio.lua
-- Verwaltet Audio-Aufnahme, Wiedergabe und Pegelmessung.

Audio = {}

local snd = playdate.sound

-- Konstanten
local SAMPLE_RATE = 8000
local MAX_RECORD_TIME = 5 * 60 -- 5 Minuten
local BUFFER_SIZE = MAX_RECORD_TIME * SAMPLE_RATE -- 8-bit mono = 1 byte per sample

-- Zustand
local isRecording = false
local isPlaying = false
local recordingStartTime = 0.0
local playbackStartTime = 0.0
local currentPlaybackIndex = 0
local currentPlaybackList = {}
local currentSample = nil -- Das aktuelle Sample-Objekt für Aufnahme/Wiedergabe
local micLevel = 0.0

-- Synth für den "Beep"
local beepSynth = snd.synth.new(snd.kWaveSine)

function Audio.init()
    -- Initialisierung
    -- Starte Mic-Monitoring für Pegelanzeige
    if snd.micinput then
        snd.micinput.startListening()
    end
end

local function playBeep()
    if beepSynth then
        beepSynth:playNote("C5", 0.5, 0.1)
    end
end

function Audio.toggleRecording()
    if isPlaying then
        Audio.stopPlayback()
    end

    if isRecording then
        Audio.stopRecording()
    else
        Audio.startRecording()
    end
end

function Audio.startRecording()
    playBeep()
    print("Start Recording...")
    
    -- Erstelle einen neuen Buffer für die Aufnahme (Sekunden, Format)
    currentSample = snd.sample.new(MAX_RECORD_TIME, snd.kFormat8bitMono)
    
    isRecording = true
    recordingStartTime = playdate.getElapsedTime() or 0
    
    if snd.micinput and currentSample then
        snd.micinput.recordToSample(currentSample, function(sample)
            -- Callback wird aufgerufen, wenn der Buffer voll ist oder gestoppt wird
            print("Aufnahme beendet (Callback).")
            -- Falls der Buffer voll lief und wir noch im Recording-Modus sind, stoppen wir ordentlich.
            if isRecording then
                Audio.stopRecording()
            end
        end)
    end
end

function Audio.stopRecording()
    if not isRecording then return end
    
    -- Zuerst Flag setzen, um Rekursion im Callback zu verhindern
    isRecording = false
    
    print("Stop Recording...")
    if snd.micinput then
        snd.micinput.stopRecording()
    end
    playBeep()
    
    -- Speichere die Aufnahme
    local duration = (playdate.getElapsedTime() or 0) - recordingStartTime
    local timestamp = playdate.getSecondsSinceEpoch() or 0
    
    -- Aufnahme speichern (wird automatisch auf Disk gespeichert via Agents)
    if currentSample then
        Agents.addRecording(Agents.getCurrentAgentIndex(), tostring(timestamp), duration, currentSample)
    end
    currentSample = nil
end

-- Stoppt Wiedergabe (öffentlich für Menü-Callback)
function Audio.stopRecordingPublic()
    Audio.stopRecording()
end

function Audio.playAllForAgent()
    if isRecording then
        Audio.stopRecording()
    end
    
    if isPlaying then
        Audio.stopPlayback()
        return -- Toggle-Verhalten: Drücken beendet Wiedergabe
    end

    playBeep()
    currentPlaybackList = Agents.getRecordingsForCurrentAgent()
    
    if #currentPlaybackList == 0 then
        print("Keine Aufnahmen vorhanden.")
        return
    end
    
    currentPlaybackIndex = 1
    Audio.playNextInQueue()
end

function Audio.playNextInQueue()
    if currentPlaybackIndex > #currentPlaybackList then
        isPlaying = false
        currentPlaybackList = {}
        print("Wiedergabe aller Aufnahmen beendet.")
        return
    end

    local recording = currentPlaybackList[currentPlaybackIndex]
    print("Spiele Aufnahme: " .. recording.name)
    
    -- Sample laden (hier haben wir es direkt im Speicher gehalten)
    local sample = recording.data
    if sample then
        local player = snd.sampleplayer.new(sample)
        
        if player then
            -- Callback wenn fertig
            player:setFinishCallback(function()
                currentPlaybackIndex = currentPlaybackIndex + 1
                Audio.playNextInQueue()
            end)
            
            player:play()
            isPlaying = true
            -- Speichere Player referenz, um Zeit abzufragen (wenn nötig)
            Audio.currentPlayer = player
        end
    else
        -- Falls Daten fehlen, überspringen
        currentPlaybackIndex = currentPlaybackIndex + 1
        Audio.playNextInQueue()
    end
end

function Audio.stopPlayback()
    if Audio.currentPlayer then
        Audio.currentPlayer:stop()
    end
    isPlaying = false
    currentPlaybackList = {}
    Audio.currentPlayer = nil
    print("Wiedergabe abgebrochen.")
end

function Audio.update()
    -- Pegel aktualisieren
    if isRecording and snd.micinput then
        micLevel = snd.micinput.getLevel() or 0
    else
        micLevel = 0
    end
end

function Audio.getStatusText()
    if isRecording then
        local elapsed = math.floor((playdate.getElapsedTime() or 0) - recordingStartTime)
        return "Aufnahme läuft: " .. elapsed .. "s"
    elseif isPlaying then
        if currentPlaybackList[currentPlaybackIndex] and Audio.currentPlayer then
            local totalLen = currentPlaybackList[currentPlaybackIndex].length or 0
            local offset = Audio.currentPlayer:getOffset() or 0
            local remaining = math.max(0, math.floor(totalLen - offset))
            return "Wiedergabe: " .. currentPlaybackList[currentPlaybackIndex].name .. " (-" .. remaining .. "s)"
        else
            return "Wiedergabe..."
        end
    else
        return "Keine Aufnahme"
    end
end

function Audio.getMicLevel()
    return micLevel
end

function Audio.isRecording() return isRecording end
function Audio.isPlaying() return isPlaying end
