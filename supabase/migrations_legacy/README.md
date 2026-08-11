# Migraciones legacy (solo referencia)

Este directorio preserva, sin modificar, la línea de migraciones auditada en DB.0A el 3 de agosto de 2026.

La historia archivada no es reproducible desde una base vacía: contiene versiones cortas y duplicadas, depende de objetos fundacionales ausentes y su orden activo fallaba antes de crear el esquema requerido. Se conserva únicamente para investigación histórica y trazabilidad.

- No se ejecuta mediante el flujo activo de Supabase.
- No debe usarse con `supabase db push` ni copiarse de vuelta selectivamente.
- No se deben editar estos archivos para corregir el baseline nuevo.
- El SQL original, incluidos archivos vacíos, nombres y timestamps, se preserva deliberadamente.

La línea activa y las reglas de recuperación se documentan en `docs/DB_BASELINE.md`.
