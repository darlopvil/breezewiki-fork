#lang racket/base
(require racket/list
         racket/string
         ; html libs
         "../lib/html-parsing/main.rkt"
         html-writing
         ; web server libs
         net/url
         web-server/http
         (only-in web-server/dispatchers/dispatch next-dispatcher)
         "application-globals.rkt"
         "endpoints.rkt"
         "../lib/tree-updater.rkt"
         "../lib/url-utils.rkt"
         "../lib/xexpr-utils.rkt"
         "../lib/make-json.rkt")

(provide page-file)

(module+ test
  (require rackunit
           "test-utils.rkt"
           "../lib/make-json.rkt")
  (define test-wikipage
    (make-json
     '(: parse
         (: title "File:Sailor Cinnamoroll.jpg"
            pageid 4448
            revid 13121
            text
            (: * "<div class=\"mw-content-ltr mw-parser-output\" lang=\"en\" dir=\"ltr\">\n<!-- \nNewPP limit report\nCached time: 20251122101032\nCache expiry: 1209600\nReduced expiry: false\nComplications: []\nCPU time usage: 0.001 seconds\nReal time usage: 0.001 seconds\nPreprocessor visited node count: 0/1000000\nPost\u2010expand include size: 0/2097152 bytes\nTemplate argument size: 0/2097152 bytes\nHighest expansion depth: 0/100\nExpensive parser function count: 0/100\nUnstrip recursion depth: 0/20\nUnstrip post\u2010expand size: 0/5000000 bytes\n-->\n<!--\nTransclusion expansion time report (%,ms,calls,template)\n100.00%    0.000      1 -total\n-->\n\n<!-- Saved in parser cache with key 1.43.1_prod_squishmallowsquad:pcache:idhash:4448-0!sseVary=RegularPage!FandomDesktop!LegacyGalleries and timestamp 20251122101032 and revision id 13121. Rendering was triggered because: api-parse\n -->\n</div>")
            langlinks ()
            categories ()
            links ()
            templates ()
            images ()
            externallinks ()
            sections ()
            parsewarnings ()
            displaytitle "<span class=\"mw-page-title-namespace\">File</span><span class=\"mw-page-title-separator\">:</span><span class=\"mw-page-title-main\">Sailor Cinnamoroll.jpg</span>"
            iwlinks ()
            properties ()))))
  (define test-imageinfo-outer
    (make-json
     `(: continue
         (: iistart "2022-01-23T03:44:17Z"
            fucontinue "455"
            continue "||")
         query
         (: pages
            ((: pageid 198
                ns 6
                title "File:Rainbow Flag1.svg"
                imageinfo
                ((: timestamp "2025-03-10T07:24:50Z"
                    user "DogeMcMeow"
                    url "https://static.wikia.nocookie.net/lgbtqia-sandbox/images/f/f8/Rainbow_Flag1.svg/revision/latest?cb=20250310072450"
                    descriptionurl "https://lgbtqia.fandom.com/wiki/File:Rainbow_Flag1.svg"
                    descriptionshorturl "https://lgbtqia.fandom.com/index.php?curid=198"
                    mime "image/svg+xml"
                    mediatype "DRAWING"))
                fileusage
                ((: pageid 191
                    ns 0
                    title "Gay")
                 (: pageid 215
                    ns 0
                    title "LGBTQIA+")))))))))

;; https://gerrit.wikimedia.org/r/plugins/gitiles/mediawiki/core/+/refs/heads/REL1_44/includes/libs/mime/defines.php
;; (define possible-mediatypes '("UNKNOWN" "BITMAP" "DRAWING" "AUDIO" "VIDEO" "MULTIMEDIA" "OFFICE" "TEXT" "EXECUTABLE" "ARCHIVE" "3D"))

(define (get-media-html url imageinfo-inner)
  (define maybe-proxied-url (if (config-true? 'strict_proxy) (u-proxy-url url) url))
  (define mediatype (jp "/mediatype" imageinfo-inner #f))
  (case mediatype
    [("BITMAP" "DRAWING")
     (match imageinfo-inner
       [(hash* ['width width] ['height height])
        `(img (@ (src ,maybe-proxied-url) (width ,(~a width)) (height ,(~a height))))]
       [else
        `(img (@ (src ,maybe-proxied-url)))])]
    [("AUDIO") `(audio (@ (src ,maybe-proxied-url) (controls)))]
    [("VIDEO") `(video (@ (src ,maybe-proxied-url) (controls)))]
    [else ""]))

(define (generate-results-page #:req req
                               #:source-url source-url
                               #:wikiname wikiname
                               #:title title
                               #:wikipage wikipage
                               #:imageinfo imageinfo-outer
                               #:siteinfo [siteinfo #f])
  (define imageinfo-inner (jp "/query/pages/0" imageinfo-outer))
  (define fileusage-continues? (jp "/continue/fucontinue" imageinfo-outer #f))
  (define fileusage-titles (for/list ([page (jp "/fileusage" imageinfo-inner)]) (jp "/title" page)))
  (define image-url (jp "/imageinfo/0/url" imageinfo-inner))
  (define username (jp "/imageinfo/0/user" imageinfo-inner))
  (define maybe-proxied-image-url
    (if (config-true? 'strict_proxy) (u-proxy-url image-url) image-url))
  (generate-wiki-page
   #:req req
   #:source-url source-url
   #:wikiname wikiname
   #:title title
   #:siteinfo siteinfo
   `(div ,(get-media-html maybe-proxied-image-url (jp "/imageinfo/0" imageinfo-inner))
         (p (a (@ (href ,maybe-proxied-image-url)) "Download original file"))
         ,(if (pair? (jp "/parse/sections" wikipage))
              (update-tree-wiki (html->xexp (preprocess-html-wiki (jp "/parse/text" wikipage ""))) wikiname)
              ; file license info wasn't displayed in the description (example: /lgbtqia/wiki/File:Rainbow_Flag1.svg)
              `(p "This file may be copyrighted. Consider licensing and fair use law before reusing it."))
         (p "Uploaded by "
            (a (@ (href ,(format "/~a/wiki/User:~a" wikiname username))) ,username)
            ".")
         ,(if (pair? fileusage-titles)
              `(p "This file is used in "
                  ,@(add-between
                     (for/list ([title fileusage-titles]
                                [i (in-naturals)])
                       (define page-path (regexp-replace* #rx" " title "_"))
                       `(a (@ (href ,(format "/~a/wiki/~a" wikiname page-path)))
                           ,title))
                     ", ")
                  ,(if fileusage-continues? "…" "."))
              `""))))

(define-endpoint
  file-endpoint
  [variables
   (define all-segments (map path/param-path (url-path (request-uri req))))
   (define wikiname (first all-segments))
   ; detectar prefijo de idioma: si el 2º segmento no es "wiki", es un código de idioma
   (define maybe-lang (and (>= (length all-segments) 2) (cadr all-segments)))
   (define lang-path
     (if (and maybe-lang (not (equal? maybe-lang "wiki")))
         (format "/~a" maybe-lang)
         ""))
   (current-fandom-lang lang-path)
   ; segmentos tras el marcador "wiki" (el título con su namespace)
   (define after-wiki
     (let loop ([segs (cdr all-segments)])
       (cond [(null? segs) '()]
             [(equal? (car segs) "wiki") (cdr segs)]
             [else (loop (cdr segs))])))
   (define prefixed-file (string-join after-wiki "/"))
   (define segments after-wiki)
   (define title (url-segments->guess-title segments))
   (define path (string-join segments "/"))
   (define source-url (format "https://~a.fandom.com~a/wiki/~a" wikiname lang-path prefixed-file))]
  [endpoints
   (wikipage
    (("action" . "parse")
     ("page" . ,prefixed-file)
     ("prop" . "text|headhtml|langlinks|sections")
     ("formatversion" . "2")
     ("format" . "json")))
   (siteinfo
    (("action" . "query")
     ("meta" . "siteinfo")
     ("siprop" . "general|rightsinfo")
     ("format" . "json")
     ("formatversion" . "2")))
   (imageinfo
    (("action" . "query")
     ("titles" . ,prefixed-file)
     ("prop" . "imageinfo|fileusage")
     ("iiprop" . "timestamp|user|canonicaltitle|url|size|mime|mediatype")
     ("iilocalonly" . "true")
     ("format" . "json")
     ("formatversion" . "2")))]
  [render
   (response-handler
    (define title (jp "/parse/title" wikipage prefixed-file))
    (define body
      (generate-results-page #:req req
                             #:source-url source-url
                             #:wikiname wikiname
                             #:title title
                             #:wikipage wikipage
                             #:imageinfo imageinfo
                             #:siteinfo siteinfo))
    (when (config-true? 'debug)
      ; used for its side effects
      ; convert to string with error checking, error will be raised if xexp is invalid
      (xexp->html body))
    (response/output #:code 200
                     #:headers (build-headers always-headers)
                     (λ (out) (write-html body out))))])

(define-standard-handler (page-file-standard req)
  #'file-endpoint
  (when (equal? "missingtitle" (jp "/error/code" wikipage #f))
    (next-dispatcher))
  ; si no hay imageinfo, no es un archivo (ej. Categoría: en otro idioma que
  ; entró por la ruta genérica de namespace) -> dejar que lo maneje page-wiki
  (when (not (jp "/query/pages/0/imageinfo" imageinfo #f))
    (next-dispatcher)))
(define-jsonp-handler (page-file-jsonp req)
  #'file-endpoint)

(define-post-data-handler (page-file-with-data req)
  #'file-endpoint
  (define prefixed-file path))

(define page-file (make-switch-handler #:standard page-file-standard
                                       #:jsonp page-file-jsonp
                                       #:post page-file-with-data))

#;(define (page-file req)
  (response-handler
   (define wikiname (path/param-path (first (url-path (request-uri req)))))
   (define prefixed-title (path/param-path (caddr (url-path (request-uri req)))))
   (define source-url (format "https://~a.fandom.com/wiki/~a" wikiname prefixed-title))

   (define-values (media-detail siteinfo)
     (thread-values
      (λ ()
        (define dest-res
          (fandom-get
           wikiname
           (format "/wikia.php?~a"
                   (params->query `(("format" . "json") ("controller" . "Lightbox")
                                                        ("method" . "getMediaDetail")
                                                        ("fileTitle" . ,prefixed-title))))))
        (easy:response-json dest-res))
      (λ ()
        (siteinfo-fetch wikiname))))
   (if (not (jp "/exists" media-detail #f))
       (next-dispatcher)
       (response-handler
        (define file-title (jp "/fileTitle" media-detail ""))
        (define title
          (if (non-empty-string? file-title) (format "File:~a" file-title) prefixed-title))
        (define image-content-type
          (if (non-empty-string? (jp "/videoEmbedCode" media-detail ""))
              #f
              (url-content-type (jp "/imageUrl" media-detail))))
        (define body
          (generate-results-page #:req req
                                 #:source-url source-url
                                 #:wikiname wikiname
                                 #:title title
                                 #:media-detail media-detail
                                 #:image-content-type image-content-type
                                 #:siteinfo siteinfo))
        (when (config-true? 'debug)
          ; used for its side effects
          ; convert to string with error checking, error will be raised if xexp is invalid
          (xexp->html body))
        (response/output #:code 200
                         #:headers (build-headers always-headers)
                         (λ (out) (write-html body out)))))))
(module+ test
  (parameterize ([(config-parameter 'strict_proxy) "true"])
    (check-equal? (get-media-html "https://static.wikia.nocookie.net/a" (make-json '(: mediatype "BITMAP")))
                  `(img (@ (src "/proxy?dest=https%3A%2F%2Fstatic.wikia.nocookie.net%2Fa"))))
    (check-equal? (get-media-html "https://static.wikia.nocookie.net/b" (make-json '(: mediatype "AUDIO")))
                  `(audio (@ (src "/proxy?dest=https%3A%2F%2Fstatic.wikia.nocookie.net%2Fb")
                             (controls)))))
  (parameterize ([(config-parameter 'strict_proxy) "false"])
    (check-equal? (get-media-html "https://static.wikia.nocookie.net/c" (make-json '(: mediatype "AUDIO")))
                  `(audio (@ (src "https://static.wikia.nocookie.net/c")
                             (controls))))
    (check-equal? (get-media-html "https://static.wikia.nocookie.net/d" (make-json '(: mediatype "VIDEO")))
                  `(video (@ (src "https://static.wikia.nocookie.net/d")
                             (controls)))))
  (check-equal? (get-media-html "https://example.com" "who knows") "")
  (check-equal? (get-media-html "https://example.com" #f) ""))
(module+ test
  (parameterize ([(config-parameter 'strict_proxy) "true"])
    (check-not-false
     ((query-selector
       (attribute-selector 'src "/proxy?dest=https%3A%2F%2Fstatic.wikia.nocookie.net%2Flgbtqia-sandbox%2Fimages%2Ff%2Ff8%2FRainbow_Flag1.svg%2Frevision%2Flatest%3Fcb%3D20250310072450")
       (generate-results-page #:req test-req
                              #:source-url ""
                              #:wikiname "test"
                              #:title "File:Example file"
                              #:wikipage test-wikipage
                              #:imageinfo test-imageinfo-outer))))))
