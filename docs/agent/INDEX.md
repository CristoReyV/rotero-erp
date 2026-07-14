# Índice para agentes

## Orden de lectura

1. `AGENTS.md`: reglas globales y límites.
2. `PROJECT_CONTEXT.md`: modelo de negocio y arquitectura verificada.
3. `PROJECT_PROGRESS.md`: estado breve de la implementación.
4. `NEXT_STEPS.md`: trabajo pendiente sin autorización implícita.
5. `DECISIONS.md`: decisiones aprobadas.
6. `PROTECTED_AREAS.md`: áreas que exigen aprobación explícita.

No cargar todos los documentos por defecto. Leer solo lo necesario y verificar en código cualquier hecho de implementación.

## Clasificación de fuentes

- **Verificado:** confirmado en código, configuración o validación actual.
- **Aprobado:** decisión humana vigente.
- **Pendiente de validar:** existe evidencia parcial, pero falta reconciliación, runtime o revisión visual.
- **Propuesta:** opción no autorizada para ejecutar.
- **Legacy:** antecedente útil que puede estar desactualizado o contradecir el estado vigente.

La solicitud humana actual y el código vigente prevalecen sobre notas históricas. `.agents/*`, goals, planes y changelogs son referencias de solo lectura hasta ser verificados o aprobados de nuevo.

## Higiene de contexto

No copiar secretos, `.env`, credenciales, identificadores privados ni datos sensibles. Usar rutas relativas y mantener separados contexto, progreso, decisiones y propuestas.
