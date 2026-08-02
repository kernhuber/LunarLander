In diesem Verzeichnis findest Du ein XCode-Projekt in Swift und Metal, welches ein kleines Videospiel („LunarLander“) darstellt. Ziel des Spiels ist es, ein Raumschiff mit begrenztem Treibstoff-Vorrat auf fremden Planeten auf einer Plattform zu landen. Allerdings ändern sich Windverhältnisse pro Level, es fliegen Objekte herum, die man einsammeln kann, oder denen man ausweichen muss. Man hat pro Level zudem eine Shield-Waffe, mit der man gefährliche Objekte innerhalb eines bestimmten Radius zerstören kann.  # Deine Aufgabe Erstelle eine sehr detaillierte Beschreibung des Spiels in dem Folder. Eine KI wie Claude Code oder Codex soll damit in der Lage sein, einen Klon des Spiels zu bauen. Die Beschreibung soll hierarchisch sein: sie beginnt mit dem Sinn des Spiels und den Bedienelementen auf einem Computer und auf einem Touch-Device. Sowie dem Attraction-Screen. Danach geht sie in technische Details.  
# Abstrakt
Die Beschreibung soll keine Details in Swift enthalten. Sie soll einerseits so abstrakt sein, dass die KI das Spiel in einer anderen Programmiersprache etwa für Windows oder Android implementieren könnte

# Details
Die Details soll aber Architekturentscheidungen enthalten: so gibt es eine zentrale Stelle, an der Konfigurationsvariablen gespeichert werden. Die Beschreibung soll auch alle relevanten Formeln enthalten, die im Spiel zum Tragen kommen, um Objekte zu bewegen.  Die Beschreibung darf externe Elemente wie Grafik- oder Sound-Dateien explizit erwähnen. Eine KI, die das Spiel anhand dieser Beschreibung nachbaut, soll die Dateien auch verwenden.  # Grafik
Die Beschreibung soll so detailliert sein, dass auch der verwendete Vektor-Zeichensatz zum Einsatz kommt. Ausserdem sollen die Metal-Details so genau beschrieben werden, dass eine KI sie etwa für DirectX, OpenGL oder andere Frameworks nachbauen kann.

# Referenzen
Auch wenn die Beschreibung selbst keine Swift-Code enthalten soll, darf sie
- daraus zitieren
- auf die Swift-Dateien verweisen
- auf andere projekt-Dateien verweisen
 Gehe davon aus, dass die KI, die die Beschreibung liest und umsetzt, Zugriff auf die Dateien hat. Eine lapidare Anweisung wie „konvertiere die Datei xyz in die Programmiersprache ABC“ ist aber nicht zulässig.

# Erstellung der Beschreibung
Die Beschreibung soll in einer .md-Datei gespeichert werden. Bei der Erstellung darfst du auf alle Dateien und Artefakte, insbesondere die .claude-Dateien zugreifen.

# Ergebnis
Das Resultat dieser Aufgabe ist [`GAME_SPEC.md`](GAME_SPEC.md). Auf dieser Grundlage hat im weiteren Verlauf des Trainings eine andere KI eine in JavaScript geschriebene, im Browser lauffähige Portierung erstellt (noch in Arbeit): <https://turbonerd.org/lunarlander/>.
