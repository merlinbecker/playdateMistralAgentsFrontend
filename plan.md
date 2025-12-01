ok, nun baue folgendes ein bzw. ueberarbeite das gesamt konzept diesbezueglich: 


- wenn der sync button gedrueckt wird, dann wird jede audio nachricht schritt fuer schritt auf den server geladen. die wav wird nach einer erfolgreichen antwort dann geloescht
die api route hierfuer ist
POST /messages
mit den headern
"x-agent-id": id des agenten
"x-message-name" : name der wav datei
"content-type" : application/octet-stream
und dem header
Authorization : Bearer <Api Key= merlinBESTE4Ev3r>


- nach dem upload aller pending nachrichten wird die liste der agenten angefordert

die api route dafuer ist
GET /agents
mit dem api key als bearer
antwort ist beispielhaft

[
    {
        "id": "ag_019adb6ede6571358db4a9090c2a99bb",
        "name": "Notizagent"
    },
    {
        "id": "ag_019adb60a4c473a2968be7f0d9ba7979",
        "name": "Bildagent"
    },
    {
        "id": "ag_019adb283faa703882c1d8d93de193dc",
        "name": "Aktienagent"
    }
]


- diese agenten werden gespeichert im game state, bzw. abgeglichen mit dem aktuellen gamestate. ist ein agent aus dem gamestate nicht mehr dabei, wird er entfernt

- wenn es einen agenten gibt, der noch nicht im gamestate ist, wird dessen avatar angefordert 
der endpunkt ist
/agents/<agentid>/avatar
es ist ein binaeres bild, welches du abspeicherst unter der agenten id


die ui wird geaendert.
es erscheint immer das jeweilige bild des agenten und darunter dann sein namen. mit dem crank wechselt der name und das bild
zusaetzlich soll noch ein ton beim wechsel abgespielt werden.
es erscheint der name des agenten unter dem bild, wenn eine aufnahme getaetigt wird, wird diese aber mit der agentenid an den server gesendet


nun erstelle einen plan wie du diese sachen umsetzen kannst. dann fuehre ihn aus.
Achte darauf, dass du nicht objektorientiert programmierst und so schlank und funktional wie moeglich.






achja du solltest dann den menueintrag "aufnahmen loeschen"  umbenennen in "reset" und dort sollte dann auch alles geloescht werden, alle grafiken und aufnahmen und was gespeichert wurde.