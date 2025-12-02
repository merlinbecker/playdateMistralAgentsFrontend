# Playdate Mistral Agents Frontend

Eine Playdate-App zur Interaktion mit KI-Agenten über Sprachnachrichten. Die App ermöglicht das Aufnehmen von Audio-Nachrichten, deren Upload zu einem Backend-Server und den Empfang von Text-Antworten der KI-Agenten.

## Übersicht

```
┌─────────────────────────────────────────────────────────────────┐
│                         PLAYDATE                                │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │   agents.lua │    │   audio.lua  │    │   ui.lua     │       │
│  │  Agenten &   │    │  Aufnahme &  │    │  Grafische   │       │
│  │ Nachrichten  │    │  Wiedergabe  │    │  Darstellung │       │
│  └──────────────┘    └──────────────┘    └──────────────┘       │
│         │                   │                    │              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │ storage.lua  │    │  Network.lua │    │   main.lua   │       │
│  │  Persistenz  │    │    HTTP      │    │   Steuerung  │       │
│  └──────────────┘    └──────────────┘    └──────────────┘       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ HTTPS
                 ┌────────────────────────┐
                 │    Backend Server      │
                 │   (Mistral Agents)     │
                 └────────────────────────┘
```

## Features

### 1. Agenten-Auswahl (Kurbel)
- **Funktion**: Mit der Kurbel zwischen verschiedenen KI-Agenten wechseln
- **Anzeige**: Aktueller Agent + Anzahl ausstehender Nachrichten
- **Persistenz**: Agentenliste wird lokal gespeichert und vom Server synchronisiert

### 2. Audio-Aufnahme (A-Button)
- **Drücken**: Startet/Stoppt die Aufnahme
- **Format**: 8-bit Mono, 8000 Hz, max. 5 Minuten
- **Speicherung**: Als `.wav` im `/recordings/` Verzeichnis
- **Feedback**: Beep-Ton bei Start/Stop, Pegel-Visualisierung während Aufnahme

### 3. Nachrichten-Wiedergabe (B-Button)
- **Funktion**: Spielt alle Nachrichten des aktuellen Agenten ab
- **Reihenfolge**: Chronologisch nach Timestamp sortiert
- **Nachrichtentypen**:
  - **Audio**: Lokale Aufnahmen werden abgespielt
  - **Text**: KI-Antworten werden satzweise angezeigt
- **Navigation**: D-Pad ↓ für nächsten Satz, B zum Überspringen

### 4. Synchronisation (Systemmenü → "Sync")
Der Sync-Vorgang läuft in folgenden Schritten:

```
1. UPLOAD       → Alle lokalen WAV-Aufnahmen zum Server hochladen
                  (Binary + Header: X-Agent-ID, X-Message-Name)
                  
2. DELETE       → Erfolgreich hochgeladene Aufnahmen lokal löschen

3. NOTIFICATIONS → Text-Antworten der Agenten abrufen
                   (Max. 5 pro Agent, älteste werden entfernt)
                   
4. AGENTS       → Agentenliste vom Server synchronisieren
                  (Neue Agenten werden hinzugefügt, Details geladen)
```

### 5. Aufnahmen löschen (Systemmenü)
- Löscht alle lokalen Aufnahmen (RAM + Disk)
- Stoppt laufende Aufnahme/Wiedergabe automatisch

## Bedienung

| Eingabe | Funktion |
|---------|----------|
| **A-Button** | Aufnahme starten/stoppen |
| **B-Button** | Alle Nachrichten abspielen |
| **Kurbel** | Agent wechseln (360° = nächster Agent) |
| **D-Pad ↓** | Nächster Satz (bei Text-Anzeige) |
| **Systemmenü** | Sync, Aufnahmen löschen |

## Dateistruktur

```
Source/
├── main.lua        # Hauptsteuerung, Input-Handler, Sync-Workflow
├── agents.lua      # Agenten-Verwaltung, Notifications, Recordings
├── audio.lua       # Mikrofon-Aufnahme, Sample-Wiedergabe
├── storage.lua     # Persistenz (WAV-Dateien, JSON-Metadaten)
├── ui.lua          # Grafische Darstellung, Spinner, Text-Display
├── Network.lua     # HTTP-Kommunikation mit Backend
└── FakeNetwork.lua # Mock für Tests ohne Netzwerk (optional)

Data/
├── recordings/     # WAV-Audiodateien
├── avatars/        # Agent-Avatare (optional)
├── recordings_meta.json  # Aufnahme-Metadaten
└── agents_data.json      # Agentenliste mit Notifications
```

## Module im Detail

### main.lua
**Zweck**: Zentrale Steuerung der App

- Initialisiert alle Module
- Verwaltet den Sync-Workflow mit Forward-Declarations (Lua-Rekursion)
- Input-Handler für A/B-Buttons, D-Pad
- Update-Loop für kontinuierliche Aktualisierung

**Sync-Ablauf**:
```lua
startSync() 
  → uploadNextRecording() [rekursiv für alle Aufnahmen]
    → fetchNotifications()
      → syncAgents()
        → fetchAgentDetails() [für neue Agenten]
          → finishSync()
```

### agents.lua
**Zweck**: Verwaltung von Agenten und deren Daten

- **Agentenliste**: ID, Name, Avatar, Notifications
- **Recordings**: Pro Agent, nach Timestamp
- **Notifications**: Max. 5 pro Agent (FIFO)
- **Helfer**: Satz-Splitting, Message-Aggregation

### audio.lua
**Zweck**: Audio-Aufnahme und -Wiedergabe

- **Recording**: `playdate.sound.micinput` → Sample → WAV
- **Playback**: Queue-basiert mit Finish-Callbacks
- **Status**: Pegel-Anzeige, Aufnahmezeit, Wiedergabefortschritt

### storage.lua
**Zweck**: Persistente Speicherung

- **WAV-Dateien**: Binary-Format für Backend-Kompatibilität
- **Metadaten**: JSON via `playdate.datastore`
- **Agenten**: Separate JSON-Datei mit Notifications

### ui.lua
**Zweck**: Grafische Darstellung

- **Hauptbildschirm**: Status, Pegel-Balken, Agent-Name
- **Spinner**: Animiertes Lade-Symbol während Sync
- **Text-Display**: Satzweise Anzeige von KI-Antworten

### Network.lua
**Zweck**: HTTP-Kommunikation

**Endpoints**:
| Methode | Pfad | Beschreibung |
|---------|------|--------------|
| GET | `/health` | Verbindungstest |
| POST | `/messages` | WAV-Upload (Binary) |
| GET | `/messages/answers` | Notifications abrufen |
| GET | `/agents` | Agentenliste |
| GET | `/agents/{id}` | Agent-Details (Avatar) |

**Header für Upload**:
```
Authorization: Bearer {API_KEY}
Content-Type: audio/wav
X-Agent-ID: {agent_id}
X-Message-Name: {timestamp}
```

## Konfiguration

In `Network.lua` müssen folgende Werte angepasst werden:

```lua
local config = {
    server = "your-backend.replit.app",  -- Backend-URL
    port = 443,
    useSSL = true,
    apiKey = "YOUR_API_KEY"  -- API-Schlüssel
}
```

Alternativ bei Init:
```lua
Network.init("https://my-server.com", "my-api-key")
```

## Backend-API Erwartungen

Das Backend sollte folgende Endpunkte bereitstellen:

### POST /messages
- **Request**: Binary WAV-Daten
- **Header**: `X-Agent-ID`, `X-Message-Name`
- **Response**: `{ "message_id": "..." }`

### GET /messages/answers
- **Response**: 
```json
[
  {
    "antwort_auf": "1732980000",
    "antwort_von": "agent-1",
    "antwort": "Das ist die Antwort des KI-Agenten."
  }
]
```

### GET /agents
- **Response**:
```json
[
  { "id": "agent-1", "name": "Notizagent" },
  { "id": "agent-2", "name": "Aktienagent" }
]
```

### GET /agents/{id}
- **Response**:
```json
{
  "id": "agent-1",
  "name": "Notizagent",
  "avatar": "base64-encoded-image..."
}
```

## Bekannte Einschränkungen

1. **Avatar-Dekodierung**: Base64 → Bild-Konvertierung ist noch nicht implementiert (TODO in `main.lua`)
2. **JSON-Parsing**: Nutzt `playdate.json` (SDK 2.0+)
3. **Netzwerk**: Erfordert WiFi-Verbindung, max. 4 gleichzeitige Connections
4. **Speicher**: Große Aufnahmen können RAM-Limits erreichen

## Entwicklung

### Voraussetzungen
- Playdate SDK 2.0+ (für JSON und Networking)
- Playdate Device oder Simulator

### Kompilieren
```bash
pdc Source mygame.pdx
```

### Testen ohne Netzwerk
`FakeNetwork.lua` kann anstelle von `Network.lua` importiert werden, um Mock-Responses zu erhalten.

## Lizenz

MIT License

## Autor

Merlin Becker
