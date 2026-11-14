# AniWorld Cast-Empfänger

Eigener Chromecast-/Google-TV-Empfänger (Cast Application Framework v3) im AniWorld-Design:
dunkler Hintergrund, Violett/Pink, Startbildschirm mit App-Icon, Info-Karte mit Cover, Serie und
Folge bei Pause, kurze Hinweise („⏸ Pausiert“, „+10 s“, „Intro übersprungen“) und ein Hinweis auf
die nächste Folge. Es ist eine reine statische Seite ohne Build-Schritt.

Ohne diesen Empfänger funktioniert das Streamen weiterhin, dann mit dem Standard-Player von Google.

## Dateien

- `index.html`, `style.css`, `app.js`, `icon.png` – die komplette Seite (alle Pfade relativ)
- Die Cast-Bibliothek lädt der Fernseher beim Start selbst von Google (`gstatic.com`); sie ist nicht Teil
  dieses Repos.

## Veröffentlichen

1. **Hosten (HTTPS Pflicht).** Den Inhalt von `receiver/` auf einen statischen HTTPS-Host legen, zum
   Beispiel:
   - ein kleines separates öffentliches GitHub-Repo mit GitHub Pages (Dateien in den Wurzelordner,
     Pages für den Branch `main` aktivieren, URL z. B. `https://DEINNAME.github.io/aniworld-receiver/`), oder
   - Cloudflare Pages, Netlify oder ein beliebiger anderer Webspace mit HTTPS.
2. **Entwickler-Konto.** In der [Google Cast SDK Developer Console](https://cast.google.com/publish)
   anmelden und die einmalige Registrierungsgebühr (5 US-Dollar) bezahlen.
3. **Anwendung anlegen.** „Add new application“ → **Custom Receiver** → Name z. B. „AniWorld“ und als
   Receiver-Application-URL die HTTPS-Adresse aus Schritt 1 (mit `/` am Ende, z. B.
   `https://DEINNAME.github.io/aniworld-receiver/`). Speichern. Die **Application ID** (8 Zeichen,
   z. B. `A1B2C3D4`) wird angezeigt.
4. **Testgerät registrieren.** Unveröffentlichte Apps laufen nur auf registrierten Geräten: In der
   Console „Add new device“ und die Seriennummer des Chromecasts bzw. Google-TV-Geräts eintragen
   (steht auf der Verpackung oder unter Geräte-Einstellungen → Info). Nach der Registrierung das Gerät
   einmal neu starten; es dauert bis zu 15 Minuten, bis es aktiv ist. Alternativ die App
   veröffentlichen („Publish“), dann läuft sie auf allen Geräten.
5. **In der App eintragen.** AniWorld → Einstellungen → „Fernseher (Chromecast)“ → „Eigene
   Empfänger-App-ID“ → Application ID einfügen. Beim nächsten Streamen startet der Fernseher den
   AniWorld-Empfänger.

Nach Änderungen an der Seite die Dateien neu hochladen. Der Fernseher cached sie manchmal; im Zweifel
das Gerät neu starten. Zum Debuggen kann man Chrome unter `chrome://inspect` mit dem Gerät verbinden
(Gerät dafür in der Console als Test-Gerät registrieren).

## Fallback

Ist die App-ID unbekannt, das Gerät nicht registriert oder der Empfänger nicht erreichbar, meldet der
Fernseher einen Startfehler. Die App startet dann automatisch den Standard-Player (`CC1AD845`) und
zeigt einen kurzen Hinweis.

## Fernbedienung am Fernseher

- Medientasten (Play/Pause, Stopp, Vor/Zurück-Spulen) der Google-TV-Fernbedienung und per HDMI-CEC
  verarbeitet das Framework selbst; die Befehle sind nicht eingeschränkt.
- Zusätzlich reagiert die Seite auf Tastenereignisse: **OK/Enter** und **Play/Pause** = Pause bzw.
  Weiter, **←/→** und **Zurückspulen/Vorspulen** = −10 s / +10 s, jeweils mit kurzem Hinweis.

## Nachrichten der App

Namespace `urn:x-cast:com.aniworldios.control` (JSON). Die App sendet sie nur, wenn der Empfänger den
Namespace in `RECEIVER_STATUS` meldet, also nur an diesen Empfänger:

| Nachricht | Wirkung |
|---|---|
| `{"type":"skip","to":123,"label":"Intro übersprungen"}` | zeigt den Hinweis auf dem Fernseher (das Springen macht die App per SEEK) |
| `{"type":"nextUp","title":"S01E02 · Titel","seconds":8}` | Karte „Nächste Folge in 8 s“ |
| `{"type":"toast","text":"…"}` | beliebiger kurzer Hinweis |

Titel, Folge und Cover kommen aus den Metadaten der LOAD-Nachricht (`metadata.title`, `subtitle`,
`images[0].url`).

## Farben

Wie in der App (`Theme.swift`): Hintergrund `#0B0A13`, Karten `#1A1726`, Violett `#9E5CFF`,
Pink `#F5509E`. Das Icon `icon.png` ist das verkleinerte App-Icon.
