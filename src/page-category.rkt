#lang racket/base
(require racket/string
         (prefix-in easy: net/http-easy)
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
         "../lib/xexpr-utils.rkt")

(provide
 page-category)

(module+ test
  (require rackunit
           "test-utils.rkt")
  (define category-json-data
    '#hasheq((batchcomplete . #t) (continue . #hasheq((cmcontinue . "page|4150504c45|41473") (continue . "-||"))) (query . #hasheq((categorymembers . (#hasheq((ns . 0) (pageid . 25049) (title . "Item (entity)")) #hasheq((ns . 0) (pageid . 128911) (title . "3D")) #hasheq((ns . 0) (pageid . 124018) (title . "A Very Fine Item")) #hasheq((ns . 0) (pageid . 142208) (title . "Amethyst Shard")) #hasheq((ns . 0) (pageid . 121612) (title . "Ankle Monitor")))))))))

(define (generate-results-page
         #:req req
         #:source-url source-url
         #:wikiname wikiname
         #:title title
         #:members-data members-data
         #:page page
         #:head-data [head-data #f]
         #:siteinfo [siteinfo #f])
  (define members (jp "/query/categorymembers" members-data))
  (generate-wiki-page
   #:req req
   #:source-url source-url
   #:wikiname wikiname
   #:title title
   #:head-data head-data
   #:siteinfo siteinfo
   `(div
     ,(update-tree-wiki page wikiname)
     (hr)
     (h2 ,(format "All Pages in ~a" title))
     (div (@ (class "mw-parser-output"))
          (ul (@ (class "my-category-list"))
              ,@(map
                 (λ (result)
                   (define title (jp "/title" result))
                   (define page-path (page-title->path title))
                   `(li
                     (a (@ (href ,(format "/~a/wiki/~a" wikiname page-path)))
                        ,title)))
                 members))))))


(define-endpoint
  category-endpoint
  [variables
    (define wikiname (path/param-path (car (url-path (request-uri req)))))
    (define prefixed-category (string-join (map path/param-path (cddr (url-path (request-uri req)))) "/"))
    (define segments (map path/param-path (cdr (url-path (request-uri req)))))
    (define title (url-segments->guess-title segments))
    (define path (string-join (cdr segments) "/"))
    (define origin (format "https://~a.fandom.com" wikiname))
    (define source-url (format "~a/wiki/~a" origin prefixed-category))]
  [endpoints
   (membersdata
    (("action" . "query")
      ("list" . "categorymembers")
      ("cmtitle" . ,prefixed-category)
      ("cmlimit" . "max")
      ("formatversion" . "2")
      ("format" . "json")))
   (pagedata
    (("action" . "parse")
      ("page" . ,prefixed-category)
      ("prop" . "text|headhtml|langlinks")
      ("formatversion" . "2")
      ("format" . "json")))
   (siteinfo
    (("action" . "query")
      ("meta" . "siteinfo")
      ("siprop" . "general|rightsinfo")
      ("format" . "json")
      ("formatversion" . "2")))]
  [render
   (define page-html (preprocess-html-wiki (jp "/parse/text" pagedata "")))
   (define page (html->xexp page-html))
   (define head-data ((head-data-getter wikiname) pagedata))
   (define body (generate-results-page
                 #:req req
                 #:source-url source-url
                 #:wikiname wikiname
                 #:title (preprocess-html-wiki (jp "/parse/title" pagedata prefixed-category))
                 #:members-data membersdata
                 #:page page
                 #:head-data head-data
                 #:siteinfo siteinfo))

   (when (config-true? 'debug)
     ; used for its side effects
     ; convert to string with error checking, error will be raised if xexp is invalid
     (xexp->html body))
   (response/output
    #:code 200
    #:headers (build-headers always-headers)
    (λ (out)
      (write-html body out)))])

(define-standard-handler (page-category-standard req)
  #'category-endpoint)

(define-jsonp-handler (page-category-jsonp req)
  #'category-endpoint)

(define-post-data-handler (page-category-with-data req)
  #'category-endpoint
  (define prefixed-category path))

(define page-category (make-switch-handler #:standard page-category-standard
                                           #:jsonp page-category-jsonp
                                           #:post page-category-with-data))

(module+ test
  (check-not-false ((query-selector (attribute-selector 'href "/test/wiki/Ankle_Monitor")
                                    (generate-results-page
                                     #:req test-req
                                     #:source-url ""
                                     #:wikiname "test"
                                     #:title "Category:Items"
                                     #:members-data category-json-data
                                     #:page '(div "page text"))))))
