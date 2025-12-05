# Binary Avatar Format (64×64, 1‑bit)

Dieses Dokument beschreibt das Binärformat für Avatare und das HTTP‑Protokoll zwischen Backend und Playdate‑Client.

Ziel:
- möglichst kleine Payload
- einfache, eindeutige Interpretation
- kein JSON‑Overhead zur Laufzeit
- Debugging über Hilfstools (z. B. Hex‑Dump → Bildkonverter) möglich

---

## 1. Bild‑Eigenschaften

- Auflösung: **64 × 64 Pixel**
- Farbtiefe: **1 Bit pro Pixel** (Schwarz/Weiß)
- Gesamtzahl Pixel: 4096
- Bits pro Pixel: 1
- Gesamtgröße der Pixeldaten: 4096 / 8 = **512 Bytes**

---

## 2. Binäres Datenformat (Variante A, mit Header)

Das Format ist self‑describing und beginnt mit einem kleinen Header.

**Gesamtaufbau**

```text
Offset  Größe  Beschreibung
0       1      Magic Byte 'A' (0x41)  // steht für "Avatar"
1       1      Version (aktuell: 0x01)
2       1      Width  (z. B. 64)
3       1      Height (z. B. 64)
4       N      Pixeldaten (1 Bit pro Pixel, row‑major)
```

**Pixeldaten‑Layout**

- Reihenfolge: Zeilenweise von oben nach unten, innerhalb einer Zeile von links nach rechts (row‑major).
- 8 Pixel werden zu einem Byte gepackt.
- **Bit‑Reihenfolge im Byte**:
  - **MSB (Bit 7)** = Pixel mit kleinstem x in dieser 8er‑Gruppe
  - **LSB (Bit 0)** = Pixel mit größtem x in dieser 8er‑Gruppe

Beispiel für eine Zeile (y):

- Pixel von x = 0..63.
- Byte 0 (für diese Zeile):
  - Bit 7 → Pixel (x=0, y)
  - Bit 6 → Pixel (x=1, y)
  - …
  - Bit 0 → Pixel (x=7, y)
- Byte 1:
  - Bit 7 → Pixel (x=8, y)
  - …
  - Bit 0 → Pixel (x=15, y)
- usw.

**Bit‑Bedeutung (Farbwert)**

- Bit = 0 → Hintergrund (weiß)
- Bit = 1 → Vordergrund (schwarz)

Dies entspricht `kColorBlack` / `kColorWhite` auf dem Playdate.

**Erwartete Werte für 64×64**

- Magic: `0x41` (`'A'`)
- Version: `0x01`
- Width: `0x40` (64)
- Height: `0x40` (64)
- Pixeldaten: 512 Bytes

Gesamtpaketgröße: **4 + 512 = 516 Bytes**

---

## 3. HTTP‑API Konvention

### 3.1. Abruf eines Avatars

**Request (Beispiel)**

```http
GET /agents/<agentId>/avatar HTTP/1.1
Host: example.com
Accept: application/octet-stream
```

**Response**

- Status: `200 OK`
- Header:
  - `Content-Type: application/octet-stream`
  - `Content-Length: 516`
- Body: Binärdaten gemäß obigem Format.

**Fehlerfälle**

- Kein Avatar vorhanden:
  - `404 Not Found`
  - Optional JSON‐Fehlerobjekt oder leerer Body.
- Serverfehler:
  - `5xx` mit passendem Fehlerobjekt (JSON).

---

## 4. Server‑Implementierung (Richtlinien)

Die serverseitige Implementierung muss:

1. Den Quellavatar (z. B. PNG, GIF, etc.) intern in ein 64×64‑1‑Bit‑Raster umwandeln.
2. ggf. Scaling/Cropping so definieren, dass es deterministisch ist (z. B. center‑crop, dann scale).
3. Pro Pixel den Schwellwert bestimmen:
   - Helligkeit > Threshold → Weiß (Bit 0)
   - Helligkeit ≤ Threshold → Schwarz (Bit 1)
   - Typischer Threshold: 0.5 (oder 128/255) auf Luminanz.
4. Die Pixeldaten in oben definierter Reihenfolge packen:
   - Schleife über `y = 0..height-1`
   - Schleife über `x = 0..width-1`
   - Pixel in Bits eines Byte aggregieren (Bit 7 → erstes Pixel, Bit 0 → achtes Pixel).
5. Header voranstellen.

Pseudocode (Server‑Seite):

```text
writeByte('A')         // Magic
writeByte(0x01)        // Version
writeByte(64)          // Width
writeByte(64)          // Height

for y in 0..63:
    for group in 0..7:          // 8 Gruppen à 8 Pixel (8*8 = 64)
        byte = 0
        for i in 0..7:          // 8 Pixel zu einem Byte
            x = group*8 + i
            pixel = getPixel(x, y)         // 0 = white, 1 = black
            bitPos = 7 - i                // MSB = erstes Pixel
            if pixel == 1:
                byte |= (1 << bitPos)
        writeByte(byte)
```

---

## 5. Client‑Implementierung (Playdate)

Der Playdate‑Client:

1. Holt die Binärdaten über das `Network`‑Modul per HTTP GET (`/agents/<agentId>/avatar`).
2. Prüft den Header:
   - Magic == `'A'`
   - Version == 0x01 (oder kompatibel)
   - Width == 64, Height == 64 (oder zumindest unterstützt)
3. Liest 512 Bytes Pixeldaten in ein Lua‑String/Bytearray.
4. Erzeugt ein neues `playdate.graphics.image` und zeichnet Pixel basierend auf den Bits.
5. Speichert das fertige Bild mit `playdate.datastore.writeImage`.

Beispiel‑Dekodierlogik in Lua (nur zur Referenz, nicht Teil des Protokolls):

```lua
local gfx = playdate.graphics

local function loadAvatarFromBinary(data)
    -- Minimalprüfungen
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
                local isBlack = (bit32.band(byte, bit32.lshift(1, bitInByte)) ~= 0)
                if isBlack then
                    gfx.drawPixel(x, y)
                end
            end
        end
    end

    gfx.popContext()
    return img
end

-- Beispiel: Bild laden und speichern
-- local avatarImage, err = loadAvatarFromBinary(binaryData)
-- if avatarImage then
--     playdate.datastore.writeImage(avatarImage, "avatar_64x64")
-- end
```

---

## 6. Debugging / Tools

Für Debugging und Entwicklung können separate Hilfstools (nicht Teil dieser Spezifikation) genutzt werden:

- Converter, der:
  - PNG/GIF → Binary‑Format exportiert
  - Binary‑Format → PNG rendert
- Hex‑Viewer, der 516‑Byte‑Files inspiziert.

Dadurch ist das Runtime‑Protokoll effizient, aber die Entwicklung weiterhin gut debugbar.
