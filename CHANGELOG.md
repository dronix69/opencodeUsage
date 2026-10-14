# Changelog

Todos los cambios relevantes de este plugin se documentan aquí.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y el versionado [Semantic Versioning](https://semver.org/lang/es/).

## 1.1.0 - 2026-10-14

### Añadido

- Panel emergente rediseñado: tarjetas de resumen (tokens 7D, coste 7D, modelos),
  línea de reparto porcentual (hoy / 7D / 30D), desglose por proveedor con barra
  de progreso y gráfico de uso de los últimos 7 días.
- Límites reales de **OpenCode Go** (rolling 5 h, semanal y mensual) consultados a
  `https://opencode.ai/zen/go/v1/usage` con la clave de `auth.json`, con
  porcentaje consumido, barra y cuenta atrás de reinicio.
- Conteo de tokens de caché (lectura y escritura) en los totales y en las tarjetas.
- Ventana de 7 días móvil (rolling) en lugar de semana natural.
- Traducciones al español (`translations/es.json`).
- `README.md`, `README.en.md`, `CHANGELOG.md`, `LICENSE` (MIT) y `screenshot.png`.

### Cambiado

- Las ventanas de hoy / 7D / 30D se calculan por el timestamp de cada mensaje del
  asistente en `opencode.db`, no por la fecha de creación de la sesión.
- El indicador de la barra muestra los tokens de 7 días en lugar del coste de hoy.
- `plugin.json`: `author` → Daniel Ferrada, `dependencies` incluye `curl`.

## 1.0.0 - 2026-10-14

### Añadido

- Versión inicial: widget de barra y daemon que leen `opencode.db` (solo lectura)
  y muestran coste y tokens de hoy, la semana y el mes.
- Ajustes: intervalo de refresco, mostrar tokens, mostrar sesiones y alerta de
  coste diario.
