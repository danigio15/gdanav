# Valhalla

Il calcolo dei percorsi, sul piano **Always Free** di Oracle Cloud. Costo: 0 €.

> Questa cartella non è ancora stata provata su una macchina vera: l'ambiente
> dove è nata non ha Docker. Il client dell'app invece è provato contro
> Valhalla 3.9 (`packages/gdanav_core/test/valhalla_test.dart`).

## Una volta sola

1. **La macchina.** Oracle Cloud → Compute → Create instance: immagine
   *Ubuntu 24.04*, forma **VM.Standard.A1.Flex** con **4 OCPU e 24 GB**,
   disco da **100 GB**. Tieni la chiave SSH.
2. **Le porte.** Nella *Security List* della rete aggiungi le regole di
   ingresso TCP 80 e 443 da `0.0.0.0/0`. Poi sulla macchina:

       sudo iptables -I INPUT 6 -p tcp -m multiport --dports 80,443 -j ACCEPT
       sudo netfilter-persistent save

3. **Docker.**

       curl -fsSL https://get.docker.com | sudo sh
       sudo usermod -aG docker $USER   # poi esci e rientra

4. **gdanav.**

       git clone https://github.com/danigio15/gdanav && cd gdanav/valhalla
       cp .env.esempio .env && nano .env   # IP e chiave
       docker compose up -d
       docker compose logs -f valhalla     # la prima volta: 1–3 ore

   La prima costruzione scarica l'Italia (~2 GB) e le quote del terreno, e
   prepara le tile. Dopo riparte in pochi secondi.

5. **Prova.**

       curl -H "X-Gdanav-Chiave: $GDANAV_CHIAVE" https://$GDANAV_HOST/status

## Nell'app

L'indirizzo `https://<ip-con-trattini>.sslip.io/` e la chiave vanno in
`ClienteValhalla(indirizzo, chiave: …)`. La chiave sta nell'app, quindi non
è un segreto vero: serve a tenere fuori chi passa per caso, non chi smonta
l'APK. Se un giorno servisse di più, si mette il relay di Cloudflare davanti.

## Aggiornare la mappa

Una volta al mese basta:

    docker compose down
    rm -rf dati/valhalla_tiles* dati/*.pbf
    docker compose up -d

## Se Oracle spegne la macchina

Oracle può recuperare le macchine gratuite inattive. Questa cartella gira
uguale su qualunque server con Docker (Hetzner CAX21, ~8 €/mese, ARM come
Oracle): si copia, si scrive `.env`, `docker compose up -d`.
