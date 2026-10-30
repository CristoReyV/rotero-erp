# Entradas revisadas de reconciliación

Estos archivos son metadatos SQL sanitizados, no datos de negocio ni credenciales.

- `OBSERVED_FUNCTIONS.json`: las 169 funciones adicionales/distintas observadas en B.
- `CANONICAL_ENTRIES.json`: las 42 entradas canónicas distintas/ausentes necesarias.
- `CANONICAL_PUBLIC_NAMES.json`: nombres para resolver defaults sin ambigüedad.
- `STATE_FENCE.sql`: consulta reproducible del estado de entrada. No escribe.

El generador offline `scripts/codex/generate-cierre02-reconciliation.py` usa estos
contratos y las decisiones en `docs/delivery/reconciliation`. Sólo reemplaza el
bloque marcado de la migración 46 y verifica el hash de su resto original.
No conecta a Supabase. Ejecutarlo dos veces debe dejar los mismos bytes.

Después se reproduce el generador de adopción con el inventario local del replay
canónico de 49 migraciones y su orden de columnas:

```text
python scripts/codex/generate-cierre02-reconciliation.py
python scripts/codex/generate-delivery-adoption.py --catalog <CANONICAL49_CATALOG_JSON> --column-order <CANONICAL49_COLUMNS_JSON> --manifest docs/delivery/SCOPE_ADOPTION_MANIFEST.json
```

Los dos orígenes se ensayan independientemente. Nunca se edita una migración ya
aplicada para obtener equivalencia. Un estado distinto del revisado exige nueva
comparación, decisión y prueba; no basta añadir un hash permitido.

Las pruebas transaccionales están en `supabase/tests/cierre02_reconciliation.sql`
y las suites M06/M07/M08/delivery. La restauración local exige Auth sintético válido
para nuevos fixtures con FK, y catálogo pg_cron en una base postgres sin servicios
Auth/REST sobre los usuarios restaurados. Los jobs permanecen inactivos.
