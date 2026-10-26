/* Le prove del caricamento di GdANav sul Play Console.
 *
 * Qui non si prova «funziona»: quello lo dice Google, e lo dice una volta sola
 * quando si carica davvero. Si prova quello che **si puo'** provare da qui, ed
 * e' quasi tutto quello che conta:
 *
 *  - che un credenziale incollato nel modo sbagliato dica **come** e' sbagliato,
 *    invece di far cadere la corsa su un `JSON.parse`;
 *  - che il biglietto firmato sia un JWT vero, verificabile con la chiave
 *    pubblica, e che chieda il permesso giusto: se quello e' storto, Google
 *    risponde «invalid_grant» e da quella parola non si capisce niente;
 *  - che le novita' troppo lunghe fermino tutto **prima** di caricare settanta
 *    megabyte — compreso il caso vero: quelle che stanno in questa repository;
 *  - che «production» non parta per sbaglio;
 *  - e che una modifica aperta non resti mai aperta, nemmeno quando qualcosa
 *    va male a meta' strada. E' la cosa che si dimentica sempre, e che la volta
 *    dopo fa trovare il negozio in uno stato che nessuno sa spiegare.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, createVerify } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  CARTELLA_DELLE_NOVITA,
  COME_SI_CHIAMA,
  QUANTO_SI_PUO_SCRIVERE,
  ilBiglietto,
  ilCredenziale,
  lePiste,
  lePisteDette,
  leNovita,
  porta,
  quantoPesa,
} from "./porta-nel-negozio.mjs";

const RADICE = dirname(dirname(fileURLToPath(import.meta.url)));

/* Una chiave finta, fatta qui: la firma si verifica per davvero, e non serve
 * nessun segreto di nessuno. */
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const CHIAVE = privateKey.export({ type: "pkcs8", format: "pem" });

function credenzialeFinto() {
  return {
    type: "service_account",
    client_email: "negozio@gdanav.iam.gserviceaccount.com",
    private_key: CHIAVE,
    token_uri: "https://oauth2.googleapis.com/token",
  };
}

const daUrl = (testo) => Buffer.from(testo.replace(/-/g, "+").replace(/_/g, "/"), "base64");

test("il credenziale si accetta in chiaro e in base64, e sbagliato dice come", () => {
  const dentro = JSON.stringify(credenzialeFinto());

  const chiaro = ilCredenziale(dentro);
  assert.equal(chiaro.posta, "negozio@gdanav.iam.gserviceaccount.com");
  assert.equal(chiaro.dove, "https://oauth2.googleapis.com/token");

  /* In base64 esce identico: sono due modi di incollare la stessa cosa, e chi
   * non sa quale usare usa questo perche' di a-capo non ne ha. */
  const impacchettato = ilCredenziale(Buffer.from(dentro, "utf8").toString("base64"));
  assert.deepEqual(impacchettato, chiaro);

  /* E i tre modi di sbagliarlo, ognuno con la sua frase. */
  assert.throws(() => ilCredenziale(""), /manca NEGOZIO_GOOGLE/);
  assert.throws(() => ilCredenziale("questo non e' niente"), /non e' un JSON/);
  assert.throws(
    () => ilCredenziale(JSON.stringify({ project_id: "gdanav" })),
    /mancano «client_email» o «private_key»/,
    "il file del progetto non e' il file della chiave, e succede di scambiarli",
  );
});

test("il biglietto e' un JWT vero, e chiede il permesso giusto", () => {
  const credenziale = ilCredenziale(JSON.stringify(credenzialeFinto()));
  const adesso = Date.parse("2026-09-17T02:00:00Z");
  const biglietto = ilBiglietto(credenziale, { adesso });

  const [testa, dentro, firma] = biglietto.split(".");
  assert.deepEqual(JSON.parse(daUrl(testa).toString("utf8")), { alg: "RS256", typ: "JWT" });

  const detto = JSON.parse(daUrl(dentro).toString("utf8"));
  assert.equal(detto.iss, "negozio@gdanav.iam.gserviceaccount.com");
  assert.equal(detto.scope, "https://www.googleapis.com/auth/androidpublisher");
  assert.equal(detto.aud, "https://oauth2.googleapis.com/token");
  assert.equal(detto.iat, adesso / 1000);
  assert.equal(detto.exp - detto.iat, 3600, "vale un'ora, come vuole Google");

  /* E la firma regge: e' l'unica cosa che qui si puo' verificare davvero, ed e'
   * quella che decide se Google ci parla o no. */
  assert.ok(
    createVerify("RSA-SHA256").update(`${testa}.${dentro}`).verify(publicKey, daUrl(firma)),
    "la firma doveva tornare con la chiave pubblica",
  );
});

test("le novita': il nome del file e' la lingua, e 500 caratteri sono 500", (t) => {
  const cartella = mkdtempSync(join(tmpdir(), "negozio-"));
  t.after(() => rmSync(cartella, { recursive: true, force: true }));

  writeFileSync(join(cartella, "it-IT.txt"), "Adesso fa una cosa nuova.\n");
  writeFileSync(join(cartella, "en-US.txt"), "It now does a new thing.\n");
  /* Un file che non e' una lingua non ci va: questa cartella e' un elenco di
   * lingue, e un `LEGGIMI.txt` diventerebbe una lingua che non esiste. Per
   * questo il foglietto accanto e' un `.md`. */
  writeFileSync(join(cartella, "LEGGIMI.md"), "spiegazioni");

  assert.deepEqual(leNovita(cartella), [
    { language: "en-US", text: "It now does a new thing." },
    { language: "it-IT", text: "Adesso fa una cosa nuova." },
  ]);

  writeFileSync(join(cartella, "it-IT.txt"), "a".repeat(QUANTO_SI_PUO_SCRIVERE + 12));
  assert.throws(
    () => leNovita(cartella),
    /it-IT\.txt e' 512 caratteri.*12 di troppo/,
    "deve dire quale file e di quanto: rifarlo a occhio e' come non dirlo",
  );

  writeFileSync(join(cartella, "it-IT.txt"), "   \n  ");
  assert.throws(() => leNovita(cartella), /it-IT\.txt e' vuoto/);

  assert.throws(() => leNovita(join(cartella, "non-c-e")), /manca la cartella/);
});

test("le novita' di questa repository stanno nella casella", () => {
  /* La prova che vale di piu', ed e' quella che si sarebbe presa in faccia: se
   * un giorno una di quelle frasi cresce di venti caratteri, questo si ferma
   * qui e non dopo aver caricato l'`.aab`. */
  const dette = leNovita(join(RADICE, CARTELLA_DELLE_NOVITA));
  assert.ok(dette.length >= 2, "italiano e inglese, come tutto il resto");
  for (const una of dette) {
    assert.match(
      una.language,
      /^[a-z]{2}-[A-Z]{2}$/,
      `«${una.language}» non e' un codice di lingua`,
    );
    assert.ok(
      una.text.length <= QUANTO_SI_PUO_SCRIVERE,
      `${una.language}: ${una.text.length} caratteri, il negozio ne prende ${QUANTO_SI_PUO_SCRIVERE}`,
    );
  }
});

test("«production» non parte per sbaglio", () => {
  assert.deepEqual(lePisteDette("internal"), ["internal"]);
  assert.deepEqual(lePisteDette(" alpha "), ["alpha"]);
  assert.throws(() => lePisteDette(""), /su quale pista/);
  assert.throws(() => lePisteDette("  ,  ,"), /su quale pista/);
  assert.throws(() => lePisteDette("production"), /aggiungi --davvero/);
  assert.deepEqual(lePisteDette("production", { davvero: true }), ["production"]);
  /* E non basta nasconderla in mezzo a un elenco: il freno guarda tutte. */
  assert.throws(() => lePisteDette("alpha,production"), /aggiungi --davvero/);
  /* Le piste fatte a mano hanno un nome loro, e passano: l'elenco delle solite
   * serve a suggerire, non a vietare. */
  assert.deepEqual(lePisteDette("custom-12345"), ["custom-12345"]);
});

test("piu' piste in una volta: si scrivono con la virgola, e production va in fondo", () => {
  assert.deepEqual(lePisteDette("internal,alpha,beta"), ["internal", "alpha", "beta"]);
  assert.deepEqual(lePisteDette(" internal , alpha "), ["internal", "alpha"]);
  /* Scritta due volte e' una volta: il negozio la stessa pista la vuole una
   * volta sola, e chi ha battuto due volte non voleva due cose. */
  assert.deepEqual(lePisteDette("alpha,alpha"), ["alpha"]);
  /* L'ordine e' quello scritto, con una sola eccezione: `production` in coda.
   * E' l'unica che il negozio puo' negare — un account personale nuovo non ce
   * l'ha finche' non ha finito la prova chiusa — e messa per ultima un suo
   * rifiuto lascia in piedi quello che era gia' andato sulle altre. */
  assert.deepEqual(lePisteDette("production,alpha,internal", { davvero: true }), [
    "alpha",
    "internal",
    "production",
  ]);
});

test("il peso si dice come lo direbbe uno", () => {
  assert.equal(quantoPesa(68_075_192), "65 MB");
  assert.equal(quantoPesa(1_500_000), "1.4 MB");
});

/* ─── Il viaggio, con un negozio finto ─────────────────────────────────────── */

/* Un Play Console finto: tiene in fila le chiamate che gli arrivano — perche'
 * metà di questa prova e' **quali** chiamate partono, e in che ordine — e sa
 * fallire su una di esse, per vedere cosa succede alla modifica aperta. */
function negozioFinto({
  rompiti = "",
  piste = null,
  sullaPista = null,
  rompiLaPista = "",
  revisioneAMano = false,
  soloLaConsegna = false,
} = {}) {
  const fatte = [];
  const prendi = async (dove, opzioni = {}) => {
    const via = String(dove);
    const metodo = String(opzioni.method || "GET");
    fatte.push(`${metodo} ${via.replace("https://androidpublisher.googleapis.com", "")}`);
    const risposta = (stato, cosa) => ({
      ok: stato < 400,
      status: stato,
      async text() {
        return JSON.stringify(cosa);
      },
      async json() {
        return cosa;
      },
    });
    if (via.includes("oauth2.googleapis.com/token")) {
      return risposta(200, { access_token: "un-gettone" });
    }
    if (rompiti && via.includes(rompiti) && metodo !== "DELETE") {
      return risposta(403, { error: { message: "the caller does not have permission" } });
    }
    /* Una pista sola che non va: e' cosi' che il Play Console ha risposto per
     * «beta» nella prova della 1.6.11, mentre internal e alpha andavano. */
    if (rompiLaPista && via.endsWith(`/tracks/${rompiLaPista}`) && metodo === "PATCH") {
      return risposta(500, { error: { message: "Internal error encountered." } });
    }
    if (piste && via.endsWith("/tracks") && metodo === "GET")
      return risposta(200, { tracks: piste });
    /* Cosa c'e' su UNA pista: e' la domanda che si fa dopo aver consegnato,
     * per sapere se il pacchetto e' arrivato davvero. */
    if (/\/tracks\/[^/]+$/.test(via) && metodo === "GET")
      return risposta(200, {
        track: via.split("/").pop(),
        releases: sullaPista ?? [{ status: "completed", versionCodes: ["104322"] }],
      });
    /* Com'e' andata la 1.14.2: il controllo non conosce il parametro della
     * revisione a mano, e il negozio vero risponde cosi'. */
    if (via.includes(":validate?"))
      return risposta(400, {
        error: {
          message:
            "Invalid JSON payload received. Unknown name \"changesNotSentForReview\": Cannot bind query parameter. Field 'changesNotSentForReview' could not be found in request message.",
        },
      });
    /* Com'e' andata la 1.14.0: dopo un rifiuto il negozio non manda piu' da
     * solo in revisione, e lo dice cosi'. */
    if (
      (revisioneAMano && (via.endsWith(":commit") || via.endsWith(":validate"))) ||
      (soloLaConsegna && via.endsWith(":commit"))
    )
      return risposta(400, {
        error: {
          message:
            "Changes cannot be sent for review automatically. Please set the query parameter changesNotSentForReview to true.",
        },
      });
    if (via.includes("/bundles?uploadType=media")) return risposta(200, { versionCode: 104322 });
    if (via.endsWith("/edits") && metodo === "POST") return risposta(200, { id: "modifica-1" });
    return risposta(200, {});
  };
  return { prendi, fatte };
}

function unPacco(t) {
  const cartella = mkdtempSync(join(tmpdir(), "pacco-"));
  t.after(() => rmSync(cartella, { recursive: true, force: true }));
  const dove = join(cartella, "app-release.aab");
  writeFileSync(dove, Buffer.alloc(2048, 7));
  return dove;
}

const NOVITA = [{ language: "it-IT", text: "Una cosa nuova." }];

test("il giro intero: apre, carica, mette sulla pista, chiede, consegna", async (t) => {
  const negozio = negozioFinto();
  const esito = await porta({
    pacco: unPacco(t),
    piste: ["internal"],
    novita: NOVITA,
    segreto: JSON.stringify(credenzialeFinto()),
    prendi: negozio.prendi,
    aspetta: async () => {},
  });

  /* Consegnata E confermata: il `commit` dice che il negozio ha preso la
   * modifica, e da solo non basta — «l'apk dell'ultima release non e' arrivato
   * nello store» e' la domanda che nasce da li'. Dopo la consegna si riguarda
   * la pista, e quello che si vede si scrive. */
  assert.deepEqual(esito, {
    versione: 104322,
    piste: ["internal"],
    pubblicato: true,
    esiti: [{ pista: "internal", confermato: true, stato: "completed" }],
    confermato: true,
  });
  const app = `/androidpublisher/v3/applications/${COME_SI_CHIAMA}`;
  assert.deepEqual(negozio.fatte, [
    "POST https://oauth2.googleapis.com/token",
    `POST ${app}/edits`,
    `POST /upload/androidpublisher/v3/applications/${COME_SI_CHIAMA}/edits/modifica-1/bundles?uploadType=media`,
    `PATCH ${app}/edits/modifica-1/tracks/internal`,
    `POST ${app}/edits/modifica-1:validate`,
    `POST ${app}/edits/modifica-1:commit`,
    /* La riguardata: una modifica nuova, perche' quella consegnata non c'e'
     * piu', e poi buttata. */
    `POST ${app}/edits`,
    `GET ${app}/edits/modifica-1/tracks/internal`,
    `DELETE ${app}/edits/modifica-1`,
  ]);
});

test("una pista che il negozio non prende non si porta via le altre", async (t) => {
  /* Successo davvero, il 26 settembre: chieste internal, alpha e beta, il
   * negozio ha preso le prime due e su beta — mai preparata nella console —
   * ha risposto «500, Internal error encountered». Stando tutte nella stessa
   * modifica quel 500 si e' portato via anche le due che erano andate, e un
   * rilascio vero non avrebbe pubblicato niente per colpa di una pista che
   * non c'entrava. Adesso viaggiano separate, e questa prova e' quel giorno. */
  const negozio = negozioFinto({ rompiLaPista: "beta" });
  const detto = [];
  await assert.rejects(
    () =>
      porta({
        pacco: unPacco(t),
        piste: ["internal", "alpha", "beta"],
        novita: NOVITA,
        segreto: JSON.stringify(credenzialeFinto()),
        prendi: negozio.prendi,
        aspetta: async () => {},
        dillo: (cosa) => detto.push(cosa),
      }),
    /«internal», «alpha».*«beta» il negozio non l'ha presa/s,
    "quello che e' andato si dice, e quello che non e' andato fa diventare rossa la corsa",
  );

  const app = `/androidpublisher/v3/applications/${COME_SI_CHIAMA}`;
  assert.ok(
    negozio.fatte.includes(`PATCH ${app}/edits/modifica-1/tracks/internal`),
    "internal l'ha presa",
  );
  assert.ok(
    negozio.fatte.includes(`PATCH ${app}/edits/modifica-1/tracks/alpha`),
    "e alpha pure, nonostante beta",
  );
  assert.equal(
    negozio.fatte.filter((una) => una.includes(":commit")).length,
    2,
    "due consegne riuscite: internal col caricamento, alpha per conto suo",
  );
  assert.ok(
    detto.some((una) => una.startsWith("ATTENZIONE: la pista «beta» non l'ha presa")),
    "e si dice quale, mentre succede",
  );
});

test("tre piste, un caricamento solo", async (t) => {
  /* Il `versionCode` e' unico per tutta l'app: il negozio un numero gia' visto
   * lo rifiuta, quindi «la stessa versione anche su beta» non si fa caricando
   * tre volte. Si carica una volta e si mette su tre piste dentro la stessa
   * modifica — e la prova guarda proprio questo, che di caricamenti ce ne sia
   * uno. */
  const negozio = negozioFinto();
  const esito = await porta({
    pacco: unPacco(t),
    piste: ["internal", "alpha", "beta"],
    novita: NOVITA,
    segreto: JSON.stringify(credenzialeFinto()),
    prendi: negozio.prendi,
    aspetta: async () => {},
  });

  assert.deepEqual(esito.piste, ["internal", "alpha", "beta"]);
  assert.equal(esito.confermato, true);
  assert.equal(
    negozio.fatte.filter((una) => una.includes("bundles?uploadType=media")).length,
    1,
    "il pacchetto sale una volta sola",
  );
  const app = `/androidpublisher/v3/applications/${COME_SI_CHIAMA}`;
  for (const pista of ["internal", "alpha", "beta"]) {
    assert.ok(negozio.fatte.includes(`PATCH ${app}/edits/modifica-1/tracks/${pista}`));
  }
  assert.equal(
    negozio.fatte.filter((una) => una.includes(":commit")).length,
    3,
    "una modifica per pista: il caricamento con la prima, le altre da sole",
  );
});

test("--prova le chiede tutte insieme, che tanto butta la modifica", async (t) => {
  /* Qui il verso e' l'opposto del rilascio vero, ed e' voluto. Una prova serve
   * a scoprire la pista che il negozio non vuole **prima** di spenderci sopra
   * un'etichetta, e per scoprirla bisogna chiedergliele tutte nello stesso
   * giro. Tanto alla fine c'e' il cestino al posto della consegna. */
  const negozio = negozioFinto();
  const esito = await porta({
    pacco: unPacco(t),
    piste: ["internal", "alpha", "beta"],
    novita: NOVITA,
    segreto: JSON.stringify(credenzialeFinto()),
    prendi: negozio.prendi,
    prova: true,
  });

  assert.equal(esito.pubblicato, false);
  const app = `/androidpublisher/v3/applications/${COME_SI_CHIAMA}`;
  for (const pista of ["internal", "alpha", "beta"]) {
    assert.ok(
      negozio.fatte.includes(`PATCH ${app}/edits/modifica-1/tracks/${pista}`),
      `${pista} va chiesta anche in prova, se no la prova non prova niente`,
    );
  }
  assert.equal(
    negozio.fatte.filter((una) => una === `POST ${app}/edits`).length,
    1,
    "una modifica sola: sono tutte li' dentro",
  );
  assert.ok(!negozio.fatte.some((una) => una.includes(":commit")));
  assert.ok(negozio.fatte.some((una) => una.startsWith("DELETE")));
});

test("«production» viaggia da sola, e dopo le altre", async (t) => {
  /* E' l'unica pista che il negozio puo' negare: un account personale nuovo
   * non ce l'ha finche' non ha finito la prova chiusa coi suoi collaudatori.
   * Se stesse nella stessa modifica delle altre, un suo «403» si porterebbe
   * via anche alpha — che era andata. Quindi va in una modifica sua, per
   * ultima, e senza ricaricare niente: la versione nel negozio c'e' gia'. */
  const negozio = negozioFinto();
  const esito = await porta({
    pacco: unPacco(t),
    piste: ["alpha", "production"],
    novita: NOVITA,
    segreto: JSON.stringify(credenzialeFinto()),
    prendi: negozio.prendi,
    aspetta: async () => {},
  });

  assert.equal(
    negozio.fatte.filter((una) => una.includes("bundles?uploadType=media")).length,
    1,
    "promuovere non e' ricaricare",
  );
  assert.equal(
    negozio.fatte.filter((una) => una.includes(":commit")).length,
    2,
    "due modifiche, due consegne: e' proprio il punto",
  );
  const app = `/androidpublisher/v3/applications/${COME_SI_CHIAMA}`;
  const alpha = negozio.fatte.indexOf(`PATCH ${app}/edits/modifica-1/tracks/alpha`);
  const produzione = negozio.fatte.indexOf(`PATCH ${app}/edits/modifica-1/tracks/production`);
  assert.ok(alpha >= 0 && produzione > alpha, "production tocca per ultima");
  assert.deepEqual(
    esito.esiti.map((uno) => uno.pista),
    ["alpha", "production"],
  );
});

test("consegnata ma non ancora visibile: lo dice, e non dice di aver fallito", async (t) => {
  /* Il pacchetto puo' essere in lavorazione o in revisione: la consegna e'
   * andata davvero, e far diventare rosso il lavoro sarebbe sbagliato quanto
   * il verde di prima, che diceva «pubblicato» senza aver guardato. */
  const negozio = negozioFinto({ sullaPista: [{ status: "completed", versionCodes: ["104321"] }] });
  const detto = [];
  const esito = await porta({
    pacco: unPacco(t),
    piste: ["alpha"],
    novita: NOVITA,
    segreto: JSON.stringify(credenzialeFinto()),
    prendi: negozio.prendi,
    aspetta: async () => {},
    dillo: (cosa) => detto.push(cosa),
  });

  assert.equal(esito.pubblicato, true, "la modifica e' stata consegnata");
  assert.equal(esito.confermato, false);
  const avviso = detto.find((una) => una.startsWith("ATTENZIONE"));
  assert.ok(avviso, "senza conferma lo deve dire, e non a mezza bocca");
  assert.match(avviso, /non mi conferma la 104322 sulla pista «alpha»/);
  assert.match(avviso, /li' vedo la 104321/);
  assert.match(avviso, /in lavorazione o in revisione/);
});

test("--prova fa tutto e poi butta: nel negozio non cambia niente", async (t) => {
  /* E' il modo di provare il credenziale la prima volta senza che nessuno si
   * ritrovi una versione nuova. Il `validate` ci resta — e' li' che si scopre
   * se qualcosa non va — e al posto del `commit` c'e' il cestino. */
  const negozio = negozioFinto();
  const esito = await porta({
    pacco: unPacco(t),
    piste: ["internal"],
    novita: NOVITA,
    segreto: JSON.stringify(credenzialeFinto()),
    prendi: negozio.prendi,
    prova: true,
  });

  assert.equal(esito.pubblicato, false);
  assert.equal(esito.versione, 104322);
  assert.ok(
    negozio.fatte.some((una) => una.includes(":validate")),
    "il controllo di Google si fa anche in prova: e' quello che serve",
  );
  assert.ok(!negozio.fatte.some((una) => una.includes(":commit")));
  assert.ok(negozio.fatte.some((una) => una.startsWith("DELETE")));
});

test("se qualcosa va male la modifica si butta, e si dice cosa ha detto Google", async (t) => {
  const negozio = negozioFinto({ rompiti: "/tracks/" });
  await assert.rejects(
    () =>
      porta({
        pacco: unPacco(t),
        piste: ["internal"],
        novita: NOVITA,
        segreto: JSON.stringify(credenzialeFinto()),
        prendi: negozio.prendi,
      }),
    /403.*does not have permission/,
    "un «403» da solo manderebbe a cercare dalla parte sbagliata",
  );
  assert.ok(
    negozio.fatte.some(
      (una) =>
        una === `DELETE /androidpublisher/v3/applications/${COME_SI_CHIAMA}/edits/modifica-1`,
    ),
    "una modifica aperta e mai consegnata resta li' a scadere, e la volta dopo nessuno sa cosa c'era dentro",
  );
});

test("senza gettone non si carica niente, e si dice dove guardare", async (t) => {
  const prendi = async (dove) => {
    if (String(dove).includes("oauth2")) {
      return {
        ok: false,
        status: 400,
        async json() {
          return { error: "invalid_grant" };
        },
        async text() {
          return "";
        },
      };
    }
    throw new Error("non ci si doveva arrivare");
  };
  await assert.rejects(
    () =>
      porta({
        pacco: unPacco(t),
        piste: ["internal"],
        novita: NOVITA,
        segreto: JSON.stringify(credenzialeFinto()),
        prendi,
      }),
    /va invitato nel Play Console/,
  );
});

test("«--piste» dice i nomi veri, e non lascia la modifica aperta", async (t) => {
  /* Il nome di una pista non si indovina: una prova chiusa aperta a mano nel
   * Play Console si chiama `custom-4697217…`, non «prova chiusa». Questo giro
   * serve solo a leggerli, e quindi **non deve cambiare niente**: apre una
   * modifica perche' il negozio le piste le racconta solo dentro una, e poi la
   * butta. */
  const negozio = negozioFinto({
    piste: [
      { track: "internal", releases: [{ status: "completed", versionCodes: ["104322"] }] },
      {
        track: "custom-4697217",
        releases: [{ status: "inProgress", versionCodes: ["104320", "104321"] }],
      },
    ],
  });

  const piste = await lePiste({
    segreto: JSON.stringify(credenzialeFinto()),
    prendi: negozio.prendi,
  });

  /* Col nome, le versioni e **in che stato stanno**: «completed» e' arrivata a
   * tutti quelli della pista, «inProgress» a una fetta, «draft» non e' uscita.
   * Senza quella parola l'elenco diceva un numero e lasciava la domanda —
   * «l'apk non e' arrivato nello store» si risponde qui. */
  assert.deepEqual(piste, [
    { nome: "internal", versioni: [104322], stati: ["completed"] },
    { nome: "custom-4697217", versioni: [104320, 104321], stati: ["inProgress"] },
  ]);
  assert.ok(
    negozio.fatte.some((una) => una.startsWith("DELETE")),
    "una modifica aperta e mai buttata resta li' a scadere, e sarebbe il colmo per un giro che voleva solo leggere",
  );
  assert.ok(
    !negozio.fatte.some((una) => una.includes(":commit") || una.includes("uploadType=media")),
    "leggere i nomi delle piste non carica niente e non pubblica niente",
  );
});

test("il tasto del workflow e lo strumento si chiamano la stessa cosa", () => {
  /* Le due meta': il bottone su GitHub e la parola che lo strumento capisce.
   * Se una delle due cambia nome, il bottone resta li' e non fa piu' niente —
   * e non se ne accorge nessuno finche' non serve. */
  const workflow = readFileSync(join(RADICE, ".github", "workflows", "negozi.yml"), "utf8");
  assert.match(
    workflow,
    /porta-nel-negozio\.mjs --piste/,
    "il workflow deve chiamare lo strumento con la parola che lo strumento capisce",
  );
  const strumento = readFileSync(join(RADICE, "tools", "porta-nel-negozio.mjs"), "utf8");
  assert.match(strumento, /detto\.includes\("--piste"\)/, "e lo strumento deve ancora capirla");
});

test("le app non si pubblicano su GitHub: vanno solo nei negozi", () => {
  /* La repository e' pubblica: un APK, un AAB o un IPA lasciati fra gli
   * artefatti o in una release li scarica chiunque, Premium compreso. Il
   * workflow che costruisce l'app la porta nel Play Console e su TestFlight,
   * e basta. («Le prove» lascia fra gli artefatti solo le anteprime della
   * mappa, e nelle release solo dati: mai un pacchetto.) */
  for (const nome of ["negozi.yml"]) {
    const workflow = readFileSync(join(RADICE, ".github", "workflows", nome), "utf8");
    assert.doesNotMatch(
      workflow,
      /upload-artifact/,
      `${nome} non deve lasciare pacchetti fra gli artefatti`,
    );
    assert.doesNotMatch(
      workflow,
      /gh release (create|upload|edit)/,
      `${nome} non deve scrivere release`,
    );
  }
});

test("quando il negozio non manda da solo in revisione, si consegna lo stesso e lo si dice", async (t) => {
  const negozio = negozioFinto({ revisioneAMano: true });
  const detto = [];
  const esito = await porta({
    pacco: unPacco(t),
    piste: ["internal"],
    novita: NOVITA,
    segreto: JSON.stringify(credenzialeFinto()),
    prendi: negozio.prendi,
    dillo: (riga) => detto.push(riga),
    aspetta: async () => {},
  });
  assert.equal(esito.pubblicato, true);
  const app = `/androidpublisher/v3/applications/${COME_SI_CHIAMA}`;
  /* Com'e' andata la 1.14.1: il negozio rifiuta gia' il controllo. Il
   * controllo NON si rifa' col parametro (la 1.14.2 si e' fermata li': il
   * controllo non lo conosce), e la consegna nasce gia' cosi'. */
  const chiamate = negozio.fatte.filter((una) => /:(validate|commit)/.test(una));
  assert.deepEqual(chiamate, [
    `POST ${app}/edits/modifica-1:validate`,
    `POST ${app}/edits/modifica-1:commit?changesNotSentForReview=true`,
  ]);
  assert.ok(!negozio.fatte.some((una) => una.includes(":validate?")));
  /* Il primo cestino viene dopo la consegna: quella e' la riguardata. */
  const consegnata = negozio.fatte.indexOf(
    `POST ${app}/edits/modifica-1:commit?changesNotSentForReview=true`,
  );
  assert.ok(negozio.fatte.indexOf(`DELETE ${app}/edits/modifica-1`) > consegnata);
  assert.ok(
    detto.some((riga) => /Invia per revisione/.test(riga)),
    "il registro dice che la revisione va mandata dal Play Console",
  );
});

test("se rifiuta solo la consegna, il controllo resta com'e' e si riconsegna", async (t) => {
  /* Com'e' andata la 1.14.0: controllo buono, consegna rifiutata. */
  const negozio = negozioFinto({ soloLaConsegna: true });
  const esito = await porta({
    pacco: unPacco(t),
    piste: ["internal"],
    novita: NOVITA,
    segreto: JSON.stringify(credenzialeFinto()),
    prendi: negozio.prendi,
    aspetta: async () => {},
  });
  assert.equal(esito.pubblicato, true);
  const app = `/androidpublisher/v3/applications/${COME_SI_CHIAMA}`;
  assert.deepEqual(
    negozio.fatte.filter((una) => /:(validate|commit)/.test(una)),
    [
      `POST ${app}/edits/modifica-1:validate`,
      `POST ${app}/edits/modifica-1:commit`,
      `POST ${app}/edits/modifica-1:commit?changesNotSentForReview=true`,
    ],
  );
});
