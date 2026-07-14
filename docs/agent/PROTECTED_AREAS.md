# Áreas protegidas

## Backend y datos

- `supabase/`, migraciones, RPCs, esquema, fixtures y datos: pueden alterar contratos o información persistida.
- Edge Functions y demás backend, incluido `netlify/functions/`: pueden cambiar integraciones y superficies públicas.
- Auth y RLS: controlan identidad, acceso y aislamiento de datos.

Requieren aprobación explícita, revisión del contrato y validación proporcional.

## Tracking y contratos públicos

- `/t/:token` y tracking público.
- `/driver/:token` y miniapp del operador/chofer.
- Traccar, GPS y servicios de tracking.

No cambiar rutas, payloads, tokens, permisos ni comportamiento sin aprobación específica.

## Entornos y secretos

- `.env*`, credenciales, tokens y datos sensibles: no leer, copiar ni documentar valores.
- Producción, staging, configuración de deploy y servicios externos: no modificar, ejecutar ni desplegar sin autorización.
- Seed, verify, cleanup y fixtures: pueden escribir o borrar datos.

## Producto y dependencias

- Roles, permisos y visibilidad económica: pueden exponer información sensible.
- `package.json`, lockfiles y dependencias: cambian la superficie técnica y requieren justificación/aprobación.
- Contratos de servicios y tipos compartidos: pueden romper frontend, backend o consumidores externos.

## Worktree compartido

Los cambios existentes pertenecen a otros trabajos hasta demostrar lo contrario. No revertir, sobrescribir, formatear ni incluir cambios ajenos. Antes y después de trabajar, comparar `git status --short`, `git diff --name-only` y el diff limitado al alcance autorizado.

## Regla de parada

Detenerse y pedir aprobación si la solución requiere entrar en un área protegida, ampliar alcance, tocar datos/entornos, instalar dependencias o resolver un conflicto con cambios ajenos.
