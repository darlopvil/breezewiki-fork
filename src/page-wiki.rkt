#lang racket/base
(require racket/dict
         racket/string
         ; html libs
         "../lib/html-parsing/main.rkt"
         html-writing
         ; web server libs
         net/url
         web-server/http
         web-server/dispatchers/dispatch
         ; my libs
         "application-globals.rkt"
         "endpoints.rkt"
         "../lib/tree-updater.rkt"
         "../lib/url-utils.rkt"
         "../lib/xexpr-utils.rkt")
(require (for-syntax racket/base syntax/parse))

(provide
 page-wiki)

(define-endpoint
  wiki-endpoint
  [variables
   (define all-path (url-path (request-uri req)))
   (define wikiname (path/param-path (car all-path)))
   (define after-wiki (cdr all-path))
   ; optional language segment: /{wikiname}/{lang}/wiki/... for Fandom non-English wikis
   (define maybe-lang
     (let ([seg (and (pair? after-wiki) (path/param-path (car after-wiki)))])
       (if (and (string? seg) (not (equal? seg "wiki"))) seg "")))
   (define lang-path (if (equal? maybe-lang "") "" (string-append "/" maybe-lang)))
   ; segments after the optional lang, i.e. ("wiki" "Title" ...)
   (define wiki-segments
     (if (equal? maybe-lang "") after-wiki (cdr after-wiki)))
   ; content segments = everything after the "wiki" marker: ("Title" ...)
   (define segments (map path/param-path (if (pair? wiki-segments) (cdr wiki-segments) '())))
   (define title (url-segments->guess-title segments))
   (define path (string-join segments "/"))
   (define source-url (format "https://~a.fandom.com~a/wiki/~a" wikiname lang-path path))
   (define _set-lang (current-fandom-lang lang-path))]
  [endpoints
   (wikipage (("action" . "parse")
              ("page" . ,path)
              ("prop" . "text|headhtml|langlinks")
              ("formatversion" . "2")
              ("format" . "json")))
   (siteinfo (("action" . "query")
              ("meta" . "siteinfo")
              ("siprop" . "general|rightsinfo")
              ("format" . "json")
              ("formatversion" . "2")))]
  [render
   (define page-html (preprocess-html-wiki (jp "/parse/text" wikipage "")))
   (define page (html->xexp page-html))
   (define head-data ((head-data-getter wikiname) wikipage))
   (define body
     (generate-wiki-page
      (update-tree-wiki page wikiname)
      #:req req
      #:source-url source-url
      #:wikiname wikiname
      #:title (jp "/parse/title" wikipage "")
      #:head-data head-data
      #:siteinfo siteinfo))
   (define redirect-query-parameter (dict-ref (url-query (request-uri req)) 'redirect "yes"))
   (define redirect-msg ((query-selector (attribute-selector 'class "redirectMsg") body)))
   (define redirect-msg-a (if redirect-msg
                              ((query-selector (λ (t a c) (eq? t 'a)) redirect-msg))
                              #f))
   (define html (xexp->html-bytes body))
   (define headers
     (build-headers
      always-headers
      ; redirect-query-parameter: only the string "no" is significant:
      ; https://github.com/Wikia/app/blob/fe60579a53f16816d65dad1644363160a63206a6/includes/Wiki.php#L367
      (when (and redirect-msg-a
                 (not (equal? redirect-query-parameter "no")))
        (let* ([dest (get-attribute 'href (bits->attributes redirect-msg-a))]
               [value (bytes-append #"0;url=" (string->bytes/utf-8 dest))])
          (header #"Refresh" value)))))
   (response/full
    200
    #"OK"
    (current-seconds)
    #"text/html; charset=utf-8"
    headers
    (list html))])

(define-standard-handler (page-wiki-standard req)
  #'wiki-endpoint
  (when (equal? "missingtitle" (jp "/error/code" wikipage #f))
    (next-dispatcher)))

(define-jsonp-handler (page-wiki-jsonp req)
  #'wiki-endpoint)

(define-post-data-handler (page-wiki-with-data req)
  #'wiki-endpoint)

(define page-wiki (make-switch-handler #:standard page-wiki-standard
                                       #:jsonp page-wiki-jsonp
                                       #:post page-wiki-with-data))

#;(define (page-wiki-with-data req)
  (response-handler
   (let/cc return
     (define post-data/bytes (request-post-data/raw req))
     (when (not post-data/bytes)
       (k (response/jsexpr
           #:code 400
           #:headers always-headers
           '#hasheq((error .
                           #hasheq((code . "breezewiki")
                                   (info . "POST requests only, please.")))))))

     (define origin-header
       (or (headers-assq* #"origin" (request-headers/raw req))
           (headers-assq* #"referer" (request-headers/raw req))))
     (when (or (not origin-header) (not (string-prefix? (bytes->string/latin-1 (header-value origin-header)) (config-get 'canonical_origin))))
       (k (response/jsexpr
           #:code 400
           #:headers always-headers
           '#hasheq((error .
                           #hasheq((code . "breezewiki")
                                   (info . "Origin/Referer header failed validation - cross-origin requests are not allowed here")))))))

     (define post-data/string (bytes->string/utf-8 post-data/bytes))
     (define post-data (string->jsexpr post-data/string))
     (define wikiname (jp "/wikiname" post-data))
     (define path (jp "/path" post-data))
     (take-json-rewrite-and-return-page
      #:req req
      #:wikiname wikiname
      #:source-url (format "https://~a.fandom.com/wiki/~a" wikiname path)
      #:data (jp "/data" post-data)
      #:siteinfo (data->siteinfo (jp "/siteinfo" post-data))))))

#;(define (page-wiki req)
  (define wikiname (path/param-path (first (url-path (request-uri req)))))
  (define segments (map path/param-path (cdr (url-path (request-uri req)))))
  (define user-cookies (user-cookies-getter req))
  (define path (string-join (cdr segments) "/"))
  (define source-url (format "https://~a.fandom.com/wiki/~a" wikiname path))

  (define-values (dest-res siteinfo)
    (thread-values
     (λ ()
       (fandom-get-api
        wikiname
        `(("action" . "parse")
          ("page" . ,path)
          ("prop" . "text|headhtml|langlinks")
          ("formatversion" . "2")
          ("format" . "json"))
        #:headers `#hasheq((cookie . ,(format "theme=~a" (user-cookies^-theme user-cookies))))))
     (λ ()
       (siteinfo-fetch wikiname))))

  (cond
    [(eq? 200 (easy:response-status-code dest-res))
     (let ([data (easy:response-json dest-res)])
       (if (equal? "missingtitle" (jp "/error/code" data #f))
           (next-dispatcher)
           (take-json-rewrite-and-return-page data)))]
    [(eq? 404 (easy:response-status-code dest-res))
     (next-dispatcher)]
    [(memq (easy:response-status-code dest-res) '(403 406))
     (response-handler
      (define body
        (generate-wiki-page
         `(div
           (p "Sorry! Fandom isn't allowing BreezeWiki to show pages right now.")
           (p "We'll automatically try again in 30 seconds, so please stay on this page and be patient.")
           (p (small "In a hurry? " (a (@ (href ,source-url)) "Click here to read the page on Fandom."))))
         #:req req
         #:source-url source-url
         #:wikiname wikiname
         #:title (url-segments->guess-title segments)
         #:siteinfo siteinfo))
      (response/output
       #:code 503
       #:headers (build-headers
                  always-headers
                  (header #"Retry-After" #"30")
                  (header #"Cache-Control" #"max-age=30, public")
                  (header #"Refresh" #"35"))
       (λ (out)
         (write-html body out))))]
    [else
     (response-handler
      (error 'page-wiki "Tried to load page ~a/~a~nSadly, the page didn't load because Fandom returned status code ~a with response:~n~a"
             wikiname
             path
             (easy:response-status-code dest-res)
             (easy:response-body dest-res)))]))

