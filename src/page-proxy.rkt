#lang racket/base
(require racket/dict
         racket/match
         racket/port
         ; libs
         (prefix-in easy: net/http-easy)
         ; web server libs
         net/url
         web-server/http
         (only-in web-server/dispatchers/dispatch next-dispatcher)
         "application-globals.rkt"
         "../lib/url-utils.rkt"
         "../lib/xexpr-utils.rkt")

(provide
 page-proxy)

; Respuestas CSS (p. ej. el tema de la wiki via ThemeApi): sus url() apuntan al CDN de
; Wikia y el navegador las pediria directamente. Se reescriben para que pasen por el proxy.
(define (css-response? r)
  (let ([ct (easy:response-headers-ref r 'content-type)])
    (and ct (regexp-match? #rx#"^text/css" ct))))

(define (rewrite-css-urls css)
  (regexp-replace* #rx"url\\(['\"]?(https://[^)'\"]*)['\"]?\\)" css
                   (λ (whole url) (string-append "url(" (u-proxy-url url) ")"))))

(define (page-proxy req)
  (match (dict-ref (url-query (request-uri req)) 'dest #f)
    [(? string? dest)
     (if (is-fandom-url? dest)
         (response-handler ; catches and reports errors
          ; Cada host de Wikia/Fandom exige una peticion distinta (verificado):
          ;  - *.nocookie.net (CDN de imagenes, tras Cloudflare challenge): con el UA de
          ;    Firefox global (fandom-request.rkt) Cloudflare espera el perfil completo de
          ;    un Firefox real y da 403. Pasa con UA NEUTRO + cabeceras Sec-Fetch-*.
          ;  - fandom.com (CSS del tema via ThemeApi, etc.): al reves, rechaza UAs que no
          ;    son de navegador (403) y necesita el UA de Firefox global, sin tocar.
          (let ([dest-r (if (regexp-match? #rx"^https://[^/]*\\.nocookie\\.net/" dest)
                            (parameterize ([easy:current-user-agent "BreezeWiki-fork image proxy"])
                              (easy:get dest #:stream? #t
                                        #:headers (hasheq 'Sec-Fetch-Dest "image"
                                                          'Sec-Fetch-Mode "no-cors"
                                                          'Sec-Fetch-Site "cross-site")))
                            (easy:get dest #:stream? #t))])
            (with-handlers ([exn:fail? (λ (e) ; cleans up and re-throws
                                         (easy:response-close! dest-r)
                                         (raise e))])
              (response/output
               #:code (easy:response-status-code dest-r)
               #:mime-type (easy:response-headers-ref dest-r 'content-type)
               #:headers (build-headers always-headers)
               (λ (out)
                 (if (css-response? dest-r)
                     (write-string (rewrite-css-urls (port->string (easy:response-output dest-r))) out)
                     (copy-port (easy:response-output dest-r) out))
                 (easy:response-close! dest-r))))))
         (next-dispatcher))]
    [#f (next-dispatcher)]))
