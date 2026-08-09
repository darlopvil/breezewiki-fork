# BreezeWiki (fork con soporte de idiomas)

Fork de [BreezeWiki](https://gitdab.com/cadence/breezewiki) de cadence, un frontend
alternativo, ligero y respetuoso con la privacidad para Fandom/Wikia.

Este fork añade **soporte para las wikis de idioma no-inglés de Fandom** (las que usan
el patrón `wiki.fandom.com/es/wiki/...`), que el BreezeWiki original no maneja.

## Cambios respecto al upstream

- **Soporte de idioma (`/es/`, `/de/`, etc.):** enrutado, llamada a la API y navegación
  interna preservando el prefijo de idioma. Ficheros: `lib/url-utils.rkt`,
  `src/dispatcher-tree.rkt`, `src/page-wiki.rkt`, `src/fandom-request.rkt`,
  `lib/tree-updater.rkt`.
- **Herencia de parámetros entre hilos:** `lib/thread-utils.rkt` propaga la
  parameterización al hilo hijo (necesario para que el idioma llegue al fetch).
- **User-Agent de navegador:** `src/fandom-request.rkt` usa un UA de Firefox para evitar
  el bloqueo de Fandom a la cadena `BreezeWiki/*`.
- **Página 404 propia:** `src/page-not-found.rkt` renderiza un 404 con la plantilla del
  sitio en vez del volcado de la petición.
- **Configuración:** `strict_proxy` y `feature_jsonp=false` activados; locale UTF-8 en el
  contenedor (necesario para títulos con acentos).

## Limitaciones conocidas

- El CSS de estructura del skin de Fandom (`load.php`) está tras Cloudflare y no se puede
  proxear desde el servidor; algunas tablas/galerías pueden verse sin estilo completo.
- Las plantillas dinámicas de Fandom (ej. `<createbox>`) no se renderizan (limitación
  heredada del upstream).
- El User-Agent de Firefox está fijado y envejecerá; revisar si reaparecen errores 403.

## Licencia

AGPLv3, igual que el proyecto original ([cadence/breezewiki](https://gitdab.com/cadence/breezewiki)).
Ver [`LICENSE`](./LICENSE). Al ser AGPL, si ejecutas una versión modificada como servicio
accesible por red, debes ofrecer su código fuente a los usuarios; este repositorio cumple
esa obligación. Fork no oficial, sin afiliación con cadence ni con Fandom.