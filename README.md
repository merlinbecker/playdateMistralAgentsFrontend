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
- **Anzeige**: Aktueller Agent + Anzahl Nachrichten (Out/In)
- **Persistenz**: Agentenliste wird lokal gespeichert und vom Server synchronisiert

### 2. Audio-Aufnahme (B-Button)
- **Drücken**: Startet/Stoppt die Aufnahme
- **Format**: 8-bit Mono, 8000 Hz, max. 5 Minuten
- **Speicherung**: Als `.wav` im `/recordings/` Verzeichnis
- **Feedback**: Beep-Ton bei Start/Stop, Pegel-Visualisierung während Aufnahme

### 3. Nachrichten-Wiedergabe & Lesen (A-Button)
- **Modus**: Wählbar über D-Pad (Out = Eigene Aufnahmen, In = Antworten)
- **Funktion**: Spielt Nachrichten ab oder zeigt Text an
- **Nachrichtentypen**:
  - **Audio (Out)**: Lokale Aufnahmen werden abgespielt
  - **Text (In)**: KI-Antworten werden in einer Sprechblase visualisiert
- **Navigation**: D-Pad ↓ für nächsten Satz

### 4. Synchronisation (Systemmenü → "Sync")
Der Sync-Vorgang läuft in folgenden Schritten:

1. **UPLOAD**: Alle lokalen WAV-Aufnahmen zum Server hochladen. Erfolgreiche Uploads werden lokal gelöscht.
2. **AGENTS**: Aktuelle Agentenliste vom Server abrufen.
3. **AVATARS**: Fehlende Avatare für neue Agenten herunterladen.
4. **ANSWERS**: Neue Text-Antworten (Notifications) vom Server abrufen.

### 5. Reset (Systemmenü)
- Löscht alle lokalen Daten (Aufnahmen, Agenten, Avatare)
- Setzt die App auf den Ursprungszustand zurück

## Bedienung

| Eingabe | Funktion |
|---------|----------|
| **A-Button** | Wiedergabe (Out) oder Lesen (In) / Sync starten (wenn keine Agenten) |
| **B-Button** | Aufnahme starten/stoppen / Wiedergabe stoppen |
| **Kurbel** | Agent wechseln |
| **D-Pad ↑/↓** | Modus wechseln (Out/In) |
| **D-Pad ↓** | Nächster Satz (im Lesemodus) |
| **Systemmenü** | Sync, Reset |

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
- Input-Handler für A/B-Buttons, D-Pad
- Update-Loop für kontinuierliche Aktualisierung

### agents.lua
**Zweck**: Verwaltung von Agenten und deren Daten

- **Agentenliste**: ID, Name, Avatar, Notifications
- **Recordings**: Pro Agent, nach Timestamp
- **Sync-Logik**: Upload -> Agents -> Avatars -> Answers

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

- **Hauptbildschirm**: Avatar, Status, Pegel-Balken, Out/In Counter
- **Text-Display**: Visualisierung des Agenten mit Sprechblase
- **Spinner**: Fortschrittsanzeige während Sync

### Network.lua
**Zweck**: HTTP-Kommunikation

**Endpoints**:
| Methode | Pfad | Beschreibung |
|---------|------|--------------|
| GET | `/health` | Verbindungstest |
| POST | `/messages` | WAV-Upload (Binary) |
| GET | `/messages/answers` | Antworten abrufen |
| GET | `/agents` | Agentenliste |
| GET | `/agents/{id}/avatar` | Agent-Avatar (Binary) |

**Header für Upload**:
```
Authorization: Bearer {API_KEY}
Content-Type: application/octet-stream
X-Agent-ID: {agent_id}
X-Message-Name: {filename}
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

## Backend-API Erwartungen

Das Backend sollte folgende Endpunkte bereitstellen:

### POST /messages
- **Request**: Binary WAV-Daten
- **Header**: `X-Agent-ID`, `X-Message-Name`
- **Response**: 200 OK

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

### GET /agents/{id}/avatar
- **Response**: Binary Data (Custom 1-bit Format)

## Bekannte Einschränkungen

1. **Avatar-Format**: Erwartet ein spezifisches Binärformat (Magic Byte 'A', Version 0x01, 64x64 1-bit), keine Standard-Bildformate.
2. **JSON-Parsing**: Nutzt `playdate.json` (SDK 2.0+)
3. **Netzwerk**: Erfordert WiFi-Verbindung
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
