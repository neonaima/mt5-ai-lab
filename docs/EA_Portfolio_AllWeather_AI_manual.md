# 1. Cos’è questo EA

Questo Expert Advisor (EA) è un **gestore di portafoglio**, non un sistema di trading intraday. In pratica si comporta come un “pilota automatico” che costruisce e mantiene un portafoglio di strumenti diversi, invece di cercare di comprare e vendere velocemente durante la giornata.

La logica seguita è ispirata al concetto **“All Weather”**: un portafoglio pensato per reggere condizioni di mercato diverse (crescita, crisi, inflazione, deflazione). L’EA applica questa logica a strumenti **ETF in forma di CFD**.

Funziona su **MetaTrader 5 (MT5)** e può essere usato sia su **conto demo** sia su **conto reale**.

# 2. Quali strumenti gestisce

L’EA gestisce questi strumenti (ETF in versione CFD):

- TLT
- VTI
- IEI
- GLD
- USO

Ogni strumento ha un **peso in percentuale**: significa quanto capitale dovrebbe essere allocato a quello strumento rispetto al totale investibile. 

**Importante:** l’EA lavora con **CFD**, non con gli ETF fisici. Quindi non stai comprando l’ETF vero, ma un contratto che ne replica il prezzo.

# 3. Il concetto chiave: capitale investibile e buffer

L’EA **non investe il 100% del capitale**. Tiene un **buffer di sicurezza** (per esempio il 30%).

Perché? Perché lasciare liquidità disponibile aiuta a:

- gestire oscillazioni di mercato senza dover vendere in fretta
- evitare margini troppo tirati
- mantenere stabilità del portafoglio

**Esempio semplice**

- Capitale totale: 10.000 €
- Buffer: 30%
- Capitale investibile: 70% = 7.000 €

In questo caso, l’EA costruisce il portafoglio **solo sui 7.000 €**, mentre i 3.000 € restano liberi.

# 4. Come l’EA costruisce il portafoglio (BOOTSTRAP)

**Bootstrap** significa “costruzione graduale”. L’EA non entra per forza in tutti gli strumenti in un solo momento. Può aprire posizioni in più passaggi.

Cosa significa in pratica:

- se uno strumento è già “troppo pesante”, l’EA lo riduce prima
- solo dopo compra ciò che manca
- se alcuni strumenti non entrano subito, è normale

Questo approccio evita di forzare il portafoglio e permette di arrivare alla composizione corretta in modo ordinato.

# 5. Quando il portafoglio è “completo”

L’EA distingue tra:

- **portfolio incomplete**: mancano ancora posizioni per arrivare ai pesi desiderati
- **portfolio complete**: tutti gli strumenti principali sono presenti e i pesi sono vicini al target

Il controllo viene fatto **solo sulle posizioni aperte da questo EA**, riconoscibili tramite il **magic number** (un codice interno che identifica le sue operazioni).

Quando il portafoglio è completo, l’EA passa a una gestione più “di manutenzione”, con interventi solo quando serve davvero.

# 6. Come funziona il rebalance

Il **rebalance** non è continuo e non è ossessivo. L’EA non corregge ogni minimo scostamento.

Concetti chiave:

- **Turnover massimo**: c’è un limite a quanta “movimentazione” è permessa in un periodo
- **Piccoli scostamenti** non vengono corretti, per evitare troppe operazioni inutili

Questo rende la gestione più stabile e riduce costi e stress sul conto.

# 7. Perché a volte l’EA NON fa nulla

A volte l’EA sembra “fermo”. In realtà sta rispettando regole di prudenza. I motivi principali sono:

- **Spread troppo alto**: se il costo di ingresso è eccessivo, l’EA aspetta
  - Esempio: se comprare costerebbe 50 € solo di spread, è meglio rimandare
- **Lotto minimo non raggiunto**: la quantità necessaria è troppo piccola per aprire un ordine valido
  - Esempio: servirebbe 0,02 lotti ma il minimo è 0,10, quindi l’EA salta
- **Delta troppo piccolo (anti-churn)**: la differenza tra peso attuale e target è minima
  - Esempio: mancherebbe solo lo 0,3% di peso: non vale la pena intervenire
- **Turnover massimo superato**: ha già fatto abbastanza movimenti in quel periodo
  - Esempio: ha già spostato il massimo consentito, quindi aspetta il prossimo ciclo

# 8. Cosa NON fa questo EA

Questo EA non fa:

- **Market timing** (non prova a “indovinare” il momento migliore)
- **Trading direzionale** (non scommette su “sale” o “scende”)
- **Ottimizzazione dei pesi** (i pesi sono fissi e predefiniti)
- **AI decisionale** (per ora usa solo regole, non intelligenza artificiale)

# 9. Log e trasparenza

Ogni decisione dell’EA viene registrata nei log. Sono messaggi utili per capire cosa sta facendo.

Esempi di messaggi e significato:

- **“Phase select”**: sta scegliendo la fase operativa (costruzione o manutenzione)
- **“Target calc”**: sta calcolando i pesi ideali
- **“Skip reason”**: sta spiegando perché salta un’operazione
- **“Trade REDUCE / BUY”**: sta riducendo o comprando uno strumento

# 10. Demo vs conto reale

La logica è la stessa in demo e reale, ma nel reale può muoversi più lentamente.

Perché?

- lo spread può essere più alto
- la liquidità può essere diversa
- il broker può applicare condizioni più rigide

**Avvertenze pratiche:**

- prima di usare il reale, testare bene in demo
- non aspettarsi movimenti immediati
- considerare sempre costi e margini

# 11. Stato attuale del progetto

L’EA oggi è:

- **stabile**
- **prudente**
- progettato per essere **esteso con AI in futuro**

L’idea è che l’AI, in futuro, possa **proporre modifiche periodiche** (per esempio aggiornare pesi o suggerire aggiustamenti), ma **non farà trading diretto**.
