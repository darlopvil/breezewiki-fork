#lang racket/base
(require racket/dict
         racket/string
         (prefix-in easy: net/http-easy)
         net/url
         web-server/http
         html-writing
         "application-globals.rkt"
         "config.rkt"
         "endpoints.rkt"
         "fandom-request.rkt"
         "../lib/url-utils.rkt"
         "../lib/xexpr-utils.rkt")

(provide
 page-search-fandom)

(define-endpoint
  search-endpoint
  [variables
   (define wikiname (path/param-path (car (url-path (request-uri req)))))
   (define params (url-query (request-uri req)))
   (define query (dict-ref params 'q #f))
   (define title "Search")
   (define path (format "Special:Search?~a" (params->query `(("query" . ,query)
                                                             ("search" . "internal")))))
   (define source-url (format "https://~a.fandom.com/wiki/~a" wikiname path))]
  [endpoints
   (search
    (("action" . "query")
     ("list" . "search")
     ("srsearch" . ,query)
     ("formatversion" . "2")
     ("format" . "json")))
   (siteinfo
    (("action" . "query")
     ("meta" . "siteinfo")
     ("siprop" . "general|rightsinfo")
     ("format" . "json")
     ("formatversion" . "2")))]
  [render
   (define search-results (jp "/query/search" search))
   (define body
     (generate-wiki-page
      #:req req
      #:source-url source-url
      #:wikiname wikiname
      #:title query
      #:siteinfo siteinfo
      `(div (@ (class "mw-parser-output"))
            ;; header before the search results showing how many we found
            (p ,(format "~a results found for " (length search-results))
               (strong ,query))
            ;; *u*nordered *l*ist of matching search results
            (ul ,@(for/list ([result search-results])
                    (let* ([title (jp "/title" result)]
                           [page-path (page-title->path title)]
                           [timestamp (jp "/timestamp" result)]
                           [wordcount (jp "/wordcount" result)]
                           [size (jp "/size" result)])
                      ;; and make this x-expression...
                      `(li (@ (class "my-result"))
                           (a (@ (class "my-result__link") (href ,(format "/~a/wiki/~a" wikiname page-path))) ; using unquote to insert the result page URL
                              ,title) ; using unquote to insert the result page title
                           (div (@ (class "my-result__info")) ; constructing the line under the search result
                                "last edited "
                                (time (@ (datetime ,timestamp)) ,(list-ref (string-split timestamp "T") 0))
                                ,(format ", ~a words, ~a kb"
                                         wordcount
                                         (exact->inexact (/ (round (/ size 100)) 10)))))))))))
   (when (config-true? 'debug)
     (xexp->html body))
   (response/output
    #:code 200
    #:headers (build-headers always-headers)
    (λ (out)
      (write-html body out)))])


(define-standard-handler (page-search-standard req)
  #'search-endpoint)

(define-jsonp-handler (page-search-jsonp req)
  #'search-endpoint)

(define-post-data-handler (page-search-with-data req)
  #'search-endpoint
  (define params (url-query (request-uri req)))
  (define query (dict-ref params 'q #f))
  (define title "Search"))

(define page-search-fandom
  (make-switch-handler #:standard page-search-standard
                       #:jsonp page-search-jsonp
                       #:post page-search-with-data))
