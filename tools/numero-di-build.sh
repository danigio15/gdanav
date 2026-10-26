#!/bin/sh
# Il numero di build dell'app: i minuti passati dal 1° gennaio 1970, in UTC.
#
# Un numero solo per tutte le corse — «Le prove» e «GdANav nei negozi» — che
# **cresce sempre**: il Play Store rifiuta un versionCode già visto e
# TestFlight un numero non più alto per la stessa versione, e il numero della
# corsa (`github.run_number`) riparte da 1 in ogni workflow nuovo. I minuti
# dall'epoca valgono anche fra workflow diversi, e stanno sotto il tetto del
# Play Store (2.100.000.000) per i prossimi quattromila anni.
#
# Lo stesso numero entra nell'app come GDANAV_COSTRUZIONE: il relay dice in
# GET /v1/versioni la build più vecchia ancora buona (VERSIONE_MINIMA_APP), e
# le build sotto chiedono di aggiornarsi.
echo $(( $(date -u +%s) / 60 ))
