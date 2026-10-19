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
- **User-Agent de navegador:** `src/fandom-request.rkt` usa un UA de Firefox ESR para evitar
  el bloqueo de Fandom a la cadena `BreezeWiki/*`. Ver sección específica más abajo.
- **Página 404 propia:** `src/page-not-found.rkt` renderiza un 404 con la plantilla del
  sitio en vez del volcado de la petición.
- **Configuración:** `strict_proxy` y `feature_jsonp=false` activados; locale UTF-8 en el
  contenedor (necesario para títulos con acentos).
- **CSS de estructura servido localmente:** `src/application-globals.rkt` enlaza un
  `static/fandom-skin.css` local en vez del `load.php` de Fandom (bloqueado por Cloudflare
  desde IPs residenciales). Ver sección específica más abajo.
- **Namespace de archivo con idioma (`Archivo:`, `File:`, `Datei:`...):** `src/dispatcher-tree.rkt`
  y `src/page-file.rkt` resuelven las páginas de archivo en wikis con prefijo de idioma. La
  detección es universal (por presencia de `imageinfo` en la respuesta de la API, no por lista
  de idiomas), y las páginas que no son archivos (Categoría:, etc.) rebotan a `page-wiki`.
- **Placeholder para imágenes de galería rotas:** `lib/tree-updater.rkt` sustituye los enlaces
  de galería a imágenes inexistentes (que en Fandom llevan a la página de subir archivo, tras
  login) por un placeholder limpio, estilado en `static/bw-custom.css` (CSS propio, versionado).
- **Pies de foto de galeria solapados:** en las galerias `wikia-gallery`, Fandom centra la
  imagen dentro del `.thumb` (altura fija) empujando el `.gallery-image-wrapper` con un `top`
  en linea, pero el `main.css` de BreezeWiki fuerza `.thumb { height:auto !important }` y el
  `.thumb` colapsa sin contar ese `top`, dejando el `.lightbox-caption` solapado bajo la imagen.
  Se neutraliza el `top` del wrapper (`top:0 !important`) en `static/bw-custom.css`.
- **Columnas del main page (LCS/RCS):** el HTML de las portadas de Fandom usa el sistema de
  columnas LCS (clases `main-page-tag-lcs-exploded`, `main-page-tag-rcs`), pero `fandom-skin.css`
  no incluye esas reglas, así que las cajas se apilaban a todo el ancho. `static/fandom-mainpage.css`
  (el módulo `ext.fandom.mainPageTag.css` de Fandom) aporta esas reglas y coloca las columnas.
- **Favicon de fallback:** `src/data.rkt` detecta cuando una wiki no tiene favicon personalizado
  (el `<link rel=icon>` apunta a una ruta interna de Fandom `/skins-ucp/...` en vez de una URL
  absoluta) y cae al favicon propio de BreezeWiki en vez de dejar la ruta cruda (que daba 404).
- **Bloque de categorías al pie del artículo:** Fandom muestra una caja "Categorías" al final
  de cada artículo con enlaces a cada categoría, pero BreezeWiki no la pedía a la API y se perdía.
  `src/page-wiki.rkt` añade `categories` al `prop` de la petición `parse` (en la misma petición
  que ya se hace, sin tráfico extra a Fandom), filtra las categorías ocultas de mantenimiento
  (como hace Fandom), y las enlaza a su página de categoría respetando el prefijo de idioma.
  Estilado en `static/bw-custom.css`.
- **Proxy de medios compatible con Cloudflare:** el CDN `static.wikia.nocookie.net` aplica el
  challenge de Cloudflare y respondía 403 al proxy, que heredaba el User-Agent de Firefox de la
  API. `src/page-proxy.rkt` elige la petición según el host: para `*.wikia.nocookie.net`, un UA
  neutro con las cabeceras `Sec-Fetch-*`; para `fandom.com`, el UA de Firefox de siempre. Además,
  las respuestas CSS que pasan por el proxy (el tema de la wiki) reescriben sus `url()` a
  `/proxy?dest=...`, y `lib/url-utils.rkt` reconoce como de Fandom cualquier subdominio de
  `wikia.nocookie.net` (`static.`, `vignette.`, `images.`), no solo `static.`.
- **`strict_proxy` aplicado al contenido de los artículos:** `update-tree-wiki` sabe proxear
  imágenes, pero ninguna página le pasaba el valor de `strict_proxy` (fallo heredado de
  upstream), así que miniaturas, galerías e infobox se cargaban directamente desde Wikia aunque
  la opción estuviera activada. `page-wiki`, `page-category`, `page-file` y `page-wiki-offline`
  se lo pasan ahora. Con este arreglo y el anterior, el navegador del visitante no contacta
  nunca con Wikia: todo el contenido multimedia sale de la propia instancia.

## Limitaciones conocidas

- **`<createbox>` no se renderiza.** La extensión InputBox de MediaWiki que genera el botón
  "crear tema" en los foros aparece como texto crudo. No es un fallo del fork: la propia API
  de Fandom entrega la etiqueta sin expandir (se ve igual de rota en Fandom original), y además
  `<createbox>` sirve para *crear* páginas, algo incompatible con un frontend de solo lectura.
- **Imágenes con dominios legacy muertos.** Algunas páginas antiguas enlazan imágenes en
  dominios de Wikia ya desaparecidos (p. ej. `images.wikia.com`, que devuelve 404). Estas
  imágenes salen rotas también en Fandom original; el fork refleja fielmente la fuente y no
  intenta "arreglar" contenido roto en origen.

## CSS del skin de Fandom (`static/fandom-skin.css`)

Este fichero NO se incluye en el repositorio (es CSS propiedad de Fandom, no cubierto por
la licencia de este fork). El servidor lo sirve localmente porque Fandom bloquea el
`load.php` desde IPs residenciales (Cloudflare).

Para generarlo, abre esta URL **en un navegador** (para pasar el challenge de Cloudflare)
y guarda el resultado como `static/fandom-skin.css`:
`https://<wiki>.fandom.com/load.php?lang=es&modules=site.styles%7Cskin.fandomdesktop.styles%7Cext.fandom.PortableInfoboxFandomDesktop.css%7Cext.fandom.GlobalComponents.CommunityHeaderBackground.css%7Cext.fandom.photoGallery.gallery.css&only=styles&skin=fandomdesktop`
Después, elimina los `@import` internos (apuntan a recursos tras Cloudflare):

```bash
sed -i '/@import/d' static/fandom-skin.css
```

Por último, reescribe sus `url()` hacia el CDN de Wikia para que pasen por el proxy. Si no se
hace, el navegador del visitante pide esas imágenes directamente a Wikia, saltándose
`strict_proxy`:

```bash
python3 - << 'EOF'
import re, urllib.parse
p = "static/fandom-skin.css"
c = open(p, encoding="utf-8").read()
rx = re.compile(r"url\(\s*['\"]?(https://[a-z0-9-]+\.wikia\.nocookie\.net/[^)'\"]*)['\"]?\s*\)")
c, n = rx.subn(lambda m: "url(/proxy?dest=" + urllib.parse.quote(m.group(1), safe="") + ")", c)
open(p, "w", encoding="utf-8").write(c)
print(n, "url() reescritas")
EOF
```

El fichero se monta en el contenedor vía bind-mount (ver `docker-compose.yml`) y se enlaza
desde `src/application-globals.rkt`. En cambio, `static/bw-custom.css` (estilos propios del
fork, como el placeholder de imagen no disponible) SÍ se versiona.

`static/fandom-mainpage.css` también SÍ se versiona (a diferencia del skin grande): es pequeño,
autocontenido y sin `@import`. Contiene solo las reglas de columnas del main page (LCS/RCS) y se
genera con:
`https://<wiki>.fandom.com/load.php?lang=en&modules=ext.fandom.mainPageTag.css&only=styles&skin=fandomdesktop`

## User-Agent

`src/fandom-request.rkt` fija un User-Agent de Firefox porque Fandom devuelve 403 a cualquier
UA que contenga "BreezeWiki". Se usa deliberadamente una versión **ESR** (Extended Support
Release), que se publica ~una vez al año, de modo que el string envejece despacio y no hay que
tocarlo cada pocas semanas. Fandom no valida la versión concreta del navegador (solo bloquea
UAs identificables como bots), así que el riesgo de caducidad es bajo; si algún día reaparecen
errores 403, subir el número a un ESR más reciente es lo primero a probar.

El proxy de medios (`src/page-proxy.rkt`) necesita lo contrario para el CDN de imágenes
(`*.wikia.nocookie.net`): ahí Cloudflare da 403 al UA de Firefox cuando no llega acompañado del
resto de cabeceras de un navegador real, y deja pasar un UA neutro con las cabeceras
`Sec-Fetch-*`. Por eso el proxy usa su propio UA solo para esos hosts y mantiene el de Firefox
para `fandom.com`.

## Licencia

AGPLv3, igual que el proyecto original ([cadence/breezewiki](https://gitdab.com/cadence/breezewiki)).
Ver [`LICENSE`](./LICENSE). Al ser AGPL, si ejecutas una versión modificada como servicio
accesible por red, debes ofrecer su código fuente a los usuarios; este repositorio cumple
esa obligación. Fork no oficial, sin afiliación con cadence ni con Fandom.
