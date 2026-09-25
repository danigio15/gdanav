// L'informativa sulla privacy di gdanav, per il Play Store:
// https://gdanav.gdahome.org/privacy

export const PRIVACY = `<!doctype html>
<html lang="it">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>gdanav · Privacy</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 720px; margin: 0 auto; padding: 24px 16px; line-height: 1.55; color: #1b2130; background: #fff; }
  h1 { font-size: 1.6rem; } h2 { font-size: 1.15rem; margin-top: 1.6em; }
  @media (prefers-color-scheme: dark) { body { color: #e8eaf0; background: #1b2130; } a { color: #7cc4ff; } }
</style>
</head>
<body>
<h1>gdanav · Informativa sulla privacy</h1>
<p>gdanav è un navigatore per auto elettriche. Non ha account, pubblicità né statistiche d'uso: non raccoglie dati per profilarti e non li vende.</p>

<h2>Posizione</h2>
<p>La posizione del telefono serve a calcolare il percorso, guidarti e mostrarti colonnine, traffico e segnalazioni vicine. Resta sul telefono; ai servizi qui sotto arrivano solo i punti necessari a ogni richiesta, senza nessun identificativo tuo:</p>
<ul>
  <li><b>Percorsi</b>: partenza, tappe e arrivo al server Valhalla di FOSSGIS (OpenStreetMap Germania).</li>
  <li><b>Ricerca dei luoghi</b>: il testo cercato e la zona a Photon (Komoot).</li>
  <li><b>Traffico e colonnine libere/occupate</b>: la zona della mappa e le colonnine delle soste a TomTom.</li>
  <li><b>Meteo</b> (Premium): alcuni punti del percorso e la zona in cui sei, arrotondati a circa un chilometro, a MET Norway (api.met.no) per le previsioni.</li>
  <li><b>Colonnine fuori dall'archivio dell'app</b>: la zona del percorso al relay di gdanav, che le chiede a OpenStreetMap.</li>
</ul>

<h2>Dati dell'auto e Home Assistant</h2>
<p>Se colleghi gdanav alla tua Home Assistant, batteria, stato di carica e viaggio passano dal relay di gdanav cifrati da un capo all'altro (AES-256-GCM, con una chiave che conoscono solo il telefono e la tua Home Assistant). Il relay non può leggerli e non li conserva: li inoltra e basta. Per sapere chi può entrare nel canale della tua auto tiene solo l'impronta di un gettone ricavato dalla chiave. Il codice di abbinamento scritto a mano resta sul relay, cifrato, al massimo dieci minuti e si cancella alla prima lettura.</p>
<p>I dati letti dall'auto (Android Auto, dongle OBD) restano sul telefono.</p>

<h2>Segnalazioni</h2>
<p>Quando segnali polizia, incidenti, lavori o altro, al relay arrivano solo il tipo e il punto della segnalazione, senza nessun identificativo tuo. Gli altri la vedono per un tempo che dipende dal tipo: da 45 minuti per il traffico a un giorno per i lavori e una settimana per un autovelox, meno se chi passa dice che non c'è più. Per limitare gli abusi il relay tiene, solo in memoria e per dieci minuti, un'impronta non reversibile dell'indirizzo di rete.</p>

<h2>Foto</h2>
<p>La foto della tua auto, se la scegli, resta sul telefono. Le foto dei modelli si scaricano da Wikimedia Commons.</p>

<h2>Abbonamento Premium</h2>
<p>L'abbonamento si compra e si gestisce con Google Play: pagamento e dati della carta li tratta Google, secondo la sua informativa. gdanav riceve da Google Play solo se l'abbonamento è attivo, e lo ricorda sul telefono.</p>
<h2>Cancellazione</h2>
<p>Tutto quello che gdanav salva è sul telefono: disinstallando l'app si cancella. Scollegando Home Assistant la chiave di abbinamento sparisce.</p>

<h2>Contatti</h2>
<p>Per domande: <a href="https://github.com/danigio15/gdanav/issues">github.com/danigio15/gdanav/issues</a>.</p>
<p><small>Ultimo aggiornamento: settembre 2026.</small></p>
</body>
</html>
`;
