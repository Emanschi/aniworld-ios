/* AniWorld Cast-Empfänger (Cast Application Framework v3).
   Statische Seite ohne Build-Schritt. Die Cast-Bibliothek lädt der Fernseher selbst von Google. */
(function () {
  "use strict";

  var CONTROL_NS = "urn:x-cast:com.aniworldios.control";
  var SEEK_STEP = 10; // Sekunden
  var NEXT_UP_WINDOW = 15; // so lange (Sekunden) darf der Hinweis "Nächste Folge" höchstens stehen

  var context = cast.framework.CastReceiverContext.getInstance();
  var playerManager = context.getPlayerManager();
  var PlayerState = cast.framework.messages.PlayerState;
  var EventType = cast.framework.events.EventType;

  var el = {
    idle: document.getElementById("idle"),
    info: document.getElementById("info"),
    infoCover: document.getElementById("info-cover"),
    infoState: document.getElementById("info-state"),
    infoTitle: document.getElementById("info-title"),
    infoSubtitle: document.getElementById("info-subtitle"),
    hint: document.getElementById("hint"),
    next: document.getElementById("next"),
    nextSeconds: document.getElementById("next-seconds"),
    nextTitle: document.getElementById("next-title")
  };

  var hintTimer = null;
  var nextTimer = null;
  var idleTimer = null;

  function show(node) { node.classList.remove("hidden"); }
  function hide(node) { node.classList.add("hidden"); }

  // ---------- Hinweise ----------

  function showHint(text, ms) {
    if (!text) return;
    el.hint.textContent = text;
    show(el.hint);
    clearTimeout(hintTimer);
    hintTimer = setTimeout(function () { hide(el.hint); }, ms || 1600);
  }

  function showNextUp(title, seconds) {
    clearTimeout(nextTimer);
    var remaining = Math.max(0, Math.min(Math.round(Number(seconds) || 0), NEXT_UP_WINDOW));
    el.nextTitle.textContent = title || "";
    function render() {
      el.nextSeconds.textContent = remaining > 0 ? "in " + remaining + " s" : "";
    }
    render();
    show(el.next);
    (function tick() {
      if (remaining <= 0) {
        nextTimer = setTimeout(function () { hide(el.next); }, 2500);
        return;
      }
      nextTimer = setTimeout(function () { remaining -= 1; render(); tick(); }, 1000);
    })();
  }

  function hideNextUp() {
    clearTimeout(nextTimer);
    hide(el.next);
  }

  // ---------- Metadaten (aus der LOAD-Nachricht der App) ----------

  function applyMetadata(media) {
    var md = (media && media.metadata) || {};
    el.infoTitle.textContent = md.title || "";
    el.infoSubtitle.textContent = md.subtitle || "";
    var image = md.images && md.images[0] && md.images[0].url;
    el.infoCover.style.backgroundImage = image ? 'url("' + image.replace(/"/g, "%22") + '")' : "none";
  }

  // ---------- Zustand ----------

  function syncScreens() {
    var state = playerManager.getPlayerState();
    clearTimeout(idleTimer);
    if (state === PlayerState.PAUSED) {
      el.infoState.textContent = "Pausiert";
      hide(el.idle);
      show(el.info);
    } else if (state === PlayerState.BUFFERING) {
      el.infoState.textContent = "Lädt …";
      hide(el.idle);
      show(el.info);
    } else if (state === PlayerState.PLAYING) {
      hide(el.idle);
      hide(el.info);
    } else {
      // IDLE: kurz warten, weil zwischen zwei Folgen kurz IDLE gemeldet wird.
      hide(el.info);
      idleTimer = setTimeout(function () {
        if (playerManager.getPlayerState() === PlayerState.IDLE) {
          hideNextUp();
          show(el.idle);
        }
      }, 900);
    }
  }

  playerManager.addEventListener(EventType.PLAYER_STATE_CHANGED, syncScreens);
  playerManager.addEventListener(EventType.MEDIA_INFORMATION_CHANGED, function () {
    applyMetadata(playerManager.getMediaInformation());
  });
  playerManager.addEventListener(EventType.MEDIA_FINISHED, hideNextUp);

  // Neue Folge: Metadaten merken, Hinweis auf die nächste Folge zurücksetzen.
  playerManager.setMessageInterceptor(cast.framework.messages.MessageType.LOAD, function (request) {
    if (request && request.media) applyMetadata(request.media);
    hideNextUp();
    hide(el.idle);
    return request;
  });

  // ---------- Fernbedienung am Fernseher ----------
  // Medientasten der Fernbedienung (HDMI-CEC, Google-TV-Fernbedienung) verarbeitet das Framework
  // selbst. Zusätzlich behandeln wir Tastenereignisse, die manche Fernbedienungen an die Seite senden.

  function togglePause() {
    if (playerManager.getPlayerState() === PlayerState.PLAYING) {
      playerManager.pause();
      showHint("⏸ Pausiert");
    } else {
      playerManager.play();
      showHint("▶ Weiter");
    }
  }

  function seekBy(delta) {
    var duration = playerManager.getDurationSec();
    var target = playerManager.getCurrentTimeSec() + delta;
    if (isFinite(duration) && duration > 0) target = Math.min(target, Math.max(duration - 1, 0));
    playerManager.seek(Math.max(target, 0));
    showHint((delta > 0 ? "+" : "−") + Math.abs(delta) + " s");
  }

  document.addEventListener("keydown", function (event) {
    var handled = true;
    switch (event.key) {
      case "Enter":
      case " ":
      case "MediaPlayPause":
        togglePause();
        break;
      case "MediaPlay":
        playerManager.play();
        showHint("▶ Weiter");
        break;
      case "MediaPause":
        playerManager.pause();
        showHint("⏸ Pausiert");
        break;
      case "ArrowLeft":
      case "MediaRewind":
        seekBy(-SEEK_STEP);
        break;
      case "ArrowRight":
      case "MediaFastForward":
        seekBy(SEEK_STEP);
        break;
      default:
        handled = false;
    }
    if (handled) event.preventDefault();
  });

  // ---------- Nachrichten der App ----------
  // {"type":"skip","to":sekunden,"label":"Intro übersprungen"}
  // {"type":"nextUp","title":"S01E02 · Titel","seconds":8}
  // {"type":"toast","text":"..."}

  context.addCustomMessageListener(CONTROL_NS, function (event) {
    var data = event.data;
    if (typeof data === "string") {
      try { data = JSON.parse(data); } catch (e) { return; }
    }
    if (!data || typeof data !== "object") return;
    switch (data.type) {
      case "skip":
        showHint(data.label || "Übersprungen", 2200);
        break;
      case "nextUp":
        showNextUp(data.title, data.seconds);
        break;
      case "toast":
        showHint(String(data.text || ""), 2600);
        break;
    }
  });

  // ---------- Start ----------

  var options = new cast.framework.CastReceiverOptions();
  // Meldet den eigenen Namespace in RECEIVER_STATUS; daran erkennt die App diesen Empfänger.
  options.customNamespaces = {};
  options.customNamespaces[CONTROL_NS] = cast.framework.system.MessageType.JSON;
  // Leerlauf: Empfänger bleibt eine Stunde offen (Standard sind 10 Minuten).
  options.maxInactivity = 3600;
  // supportedCommands bleibt Standard: Play, Pause, Seek und Stop (auch per Fernbedienung) funktionieren.

  context.start(options);
  syncScreens();
})();
