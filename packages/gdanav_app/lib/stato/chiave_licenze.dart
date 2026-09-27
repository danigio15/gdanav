/// La chiave pubblica Ed25519 del quadro (32 byte, base64url senza `=`), con
/// cui si verificano i gettoni delle licenze: vedi `docs/LICENZE.md` di
/// gdahome.
///
/// **Di serie è vuota**: nessun gettone vale e Premium arriva solo dal
/// negozio (Play Store, App Store), come prima dei codici regalo. La scrive
/// `node strumenti/chiave-licenze.mjs --gdanav ../gdanav` prima del rilascio.
/// La coppia di prova del contratto non va mai qui.
const chiavePubblicaLicenze = '';
