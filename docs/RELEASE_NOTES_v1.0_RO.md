# Note de lansare v1.0

## Rezumat
Versiunea 1.0 oferă un flux determinist, bazat pe dovezi, cu un singur folder de rulare fixat pentru fiecare URL și un pachet de livrare sigur pentru client.

## Contract de livrare (Output canonic)
Fiecare rulare reușită produce un singur folder de rulare care conține:

- `deliverables/Decision_Brief_{LANG}.pdf`
- `deliverables/Evidence_Appendix_{LANG}.pdf`
- `deliverables/verdict.json`
- `final/master.pdf`
- `final/MASTER_BUNDLE.pdf`
- `final/client_safe_bundle.zip`
- `final/checksums.sha256`

Toate butoanele de livrare deschid doar fișierele din acest folder.

## Rezultate
Există două rezultate explicite:

1. **SUCCESS**
   - Audit complet.
   - Pachetul include PDF‑urile uneltelor și toate livrabilele.

2. **NOT AUDITABLE**
   - Verificarea de dovezi a eșuat (identitate, domeniu placeholder sau dovadă insuficientă).
   - Se livrează totuși un pachet minim, sigur, cu o decizie clară „ne‑auditabil”.

## Pachet client‑safe
- Allowlist strict (fără fișiere în plus).
- Sume de control generate și verificate pentru toate artefactele livrate.

## Porți de dovezi (fail‑closed)
Rularea se oprește dacă apare oricare dintre:
- Hostul final nu corespunde hostului cerut (cu excepția www/non‑www).
- Domeniu placeholder detectat.
- Dovezi prea mici pentru un rezultat credibil.

## Suport de limbă
- Livrabile în EN și RO.
- Diacriticele românești sunt suportate în PDF‑urile client.

## Note pentru operatori
- O rulare este considerată completă doar când există artefactele finale în `final/`.
- NOT AUDITABLE este un rezultat livrabil, nu o eroare ascunsă.
