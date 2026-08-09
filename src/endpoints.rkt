#lang racket/base
(require racket/format
         racket/match
         racket/string
         ; libs
         (prefix-in easy: net/http-easy)
         json
         ; html libs
         html-writing
         ; web server libs
         web-server/http
         web-server/dispatchers/dispatch
         ; my libs
         "application-globals.rkt"
         "config.rkt"
         "data.rkt"
         "fandom-request.rkt"
         "static-data.rkt"
         "../lib/archive-file-mappings.rkt"
         "../lib/thread-utils.rkt"
         "../lib/url-utils.rkt"
         "../lib/xexpr-utils.rkt")
(require (for-syntax racket/base syntax/parse))

(provide
 define-endpoint
 define-standard-handler
 define-post-data-handler
 define-jsonp-handler
 make-switch-handler
 (all-from-out racket/format
               racket/match
               json
               net/http-easy
               web-server/dispatchers/dispatch
               "../lib/thread-utils.rkt"
               "../lib/archive-file-mappings.rkt"
               "config.rkt"
               "data.rkt"
               "fandom-request.rkt"
               "static-data.rkt"))


(define-for-syntax (fix-scopes here orig stx)
  (define remover (make-syntax-delta-introducer here #f))
  (define introducer (make-syntax-delta-introducer orig #f))
  (introducer (remover stx 'remove)))


(define-syntax (define-endpoint stx)
  (syntax-parse stx
    [(_ name
        (~and (~seq all ...)
              (~seq
               ((~datum variables) variable ...)
               ((~datum endpoints) endpoint ...)
               ((~datum render) render ...))))
     #'(define-syntax name #'(all ...))]))


(define ((make-switch-handler #:standard standard #:jsonp jsonp #:post post) req)
  (cond
    [(equal? (request-method req) #"POST")
     (post req)]
    [(config-true? 'feature_jsonp::enabled)
     (jsonp req)]
    [else
     (standard req)]))


(define-syntax (define-standard-handler stx)
  (syntax-parse stx
    [(_ (~and name-args (name:id arg:id ...)) endpoint-ref:expr fn-body ...)
     #:with endpoint-syntax (syntax-local-value (cadr (syntax->list #'endpoint-ref)))
     (syntax-parse #'endpoint-syntax
       #:context 'endpoint-data
       [(((~datum variables) variable ...)
         ((~datum endpoints) (endpoint-id:id (endpoint-param:expr ...)) ...)
         ((~datum render) render ...))
        #:with endpoint-getters (for/list ([id (syntax-e #'(endpoint-id ...))]
                                           [params (syntax-e #'((endpoint-param ...) ...))])
                                  (with-syntax ([params (append (syntax-e params) #;'(("callback" . "proxy.wikipage")))])
                                    (if (eq? (syntax-e id) 'siteinfo)
                                        #'(λ ()
                                            (siteinfo-fetch wikiname))
                                        #'(λ ()
                                            (fandom-get-api
                                             wikiname
                                             `params
                                             #:headers `#hasheq((cookie . ,(format "theme=~a" (user-cookies^-theme user-cookies)))))))))
        #:with endpoint-intermediates->values (for/list ([id (syntax-e #'(endpoint-id ...))])
                                                (with-syntax ([id id])
                                                  (if (eq? (syntax-e #'id) 'siteinfo)
                                                      #'id
                                                      #'(easy:response-json id))))

        (fix-scopes
         #'here stx
         #'(define name-args
             (response-handler
              (let/cc k
                variable ...
                (define user-cookies (user-cookies-getter req))
                (define-values (endpoint-id ...)
                  (let-values ([(endpoint-id ...) (thread-values (~@ . endpoint-getters))])
                    (for ([response (list endpoint-id ...)]
                          #:when (easy:response? response))
                      (match (easy:response-status-code response)
                        [404
                         (next-dispatcher)]
                        [(or 403 406)
                         (define body
                           (generate-wiki-page
                            `(div
                              (p "Sorry! Fandom isn't allowing BreezeWiki to show pages right now.")
                              (p "We'll automatically try again in 30 seconds, so please stay on this page and be patient.")
                              (p (small "In a hurry? " (a (@ (href ,source-url)) "Click here to read the page on Fandom."))))
                            #:req req
                            #:source-url source-url
                            #:wikiname wikiname
                            #:title title
                            #:siteinfo siteinfo))
                         (k (response/output
                             #:code 503
                             #:headers (build-headers
                                        always-headers
                                        (header #"Retry-After" #"30")
                                        (header #"Cache-Control" #"max-age=30, public")
                                        (header #"Refresh" #"35"))
                             (λ (out)
                               (write-html body out))))]
                        [(not 200)
                         (k (error 'page-wiki "Tried to load page ~a/~a~nSadly, the page didn't load because Fandom returned status code ~a with response:~n~a"
                                   wikiname
                                   path
                                   (easy:response-status-code response)
                                   (easy:response-body response)))]
                        [_ (void)]))
                    (values (~@ . endpoint-intermediates->values))))
                fn-body ...
                render ...))))])]))


(define-syntax (define-post-data-handler stx)
  (syntax-parse stx
    [(_ (~and name-args (name:id arg:id ...)) endpoint-ref:expr fn-body ...)
     #:with endpoint-syntax (syntax-local-value (cadr (syntax->list #'endpoint-ref)))
     (syntax-parse #'endpoint-syntax
       #:context 'endpoint-data
       [(((~datum variables) variable ...)
         ((~datum endpoints) (endpoint-id:id (endpoint-param:expr ...)) ...)
         ((~datum render) render ...))
        #:with endpoint-getters (for/list ([id (syntax-e #'(endpoint-id ...))]
                                           [params (syntax-e #'((endpoint-param ...) ...))])
                                  (with-syntax ([id id])
                                    (if (eq? (syntax-e #'id) 'siteinfo)
                                        #'(data->siteinfo (hash-ref post-data 'id))
                                        #'(hash-ref post-data 'id))))

        (fix-scopes
         #'here stx
         #'(define name-args
             (response-handler
              (let/cc k
                (define (k-validation-error message)
                  (k (response/jsexpr
                      #:code 400
                      #:headers always-headers
                      `#hasheq((error .
                                      #hasheq((code . "breezewiki")
                                              (info . ,message)))))))
                (define post-data/bytes (request-post-data/raw req))
                (when (not post-data/bytes)
                  (k-validation-error "POST requests only, please."))

                (define origin-header
                  (or (headers-assq* #"origin" (request-headers/raw req))
                      (headers-assq* #"referer" (request-headers/raw req))))
                (when (or (not origin-header) (not (string-prefix? (bytes->string/latin-1 (header-value origin-header)) (config-get 'canonical_origin))))
                  (k-validation-error "Origin/Referer header failed validation - cross-origin requests are not allowed here"))

                (define post-data/string (bytes->string/utf-8 post-data/bytes))
                (define post-data (string->jsexpr post-data/string))
                (define-values (endpoint-id ...) (values (~@ . endpoint-getters)))
                (define wikiname (hash-ref post-data 'wikiname))
                (define path (hash-ref post-data 'path))
                (define source-url (format "https://~a.fandom.com/wiki/~a" wikiname path))
                fn-body ...
                render ...))))])]))


(define-syntax (define-jsonp-handler stx)
  (syntax-parse stx
    [(_ (~and name-args (name:id arg:id ...)) endpoint-ref:expr fn-body ...)
     #:with endpoint-syntax (syntax-local-value (cadr (syntax->list #'endpoint-ref)))
     (syntax-parse #'endpoint-syntax
       #:context 'endpoint-data
       [(((~datum variables) variable ...)
         ((~datum endpoints) (endpoint-id:id (endpoint-param:expr ...)) ...)
         ((~datum render) render ...))
        #:with endpoint-scripts (for/list ([id (syntax-e #'(endpoint-id ...))]
                                           [params (syntax-e #'((endpoint-param ...) ...))])
                                  (with-syntax ([id id]
                                                [params (append (syntax-e params)
                                                                `(("callback" . ,(format "proxy.~a" (syntax-e id)))))])
                                    #'(script (@ (async)
                                                 (src ,(format "https://~a.fandom.com/api.php?~a"
                                                               wikiname
                                                               (params->query `params)))
                                                 (data-jsonp-var ,(format "~a" 'id))
                                                 (onerror ,(format "proxy.~a({error: {code: 'disconnected', info: 'Fandom connection failed or was blocked by your browser. Check any browser extensions that may block third-party scripts, then reload the page.'}})" 'id))))))

        (fix-scopes
         #'here stx
         #'(define name-args
             (response-handler
              (let/cc k
                variable ...
                fn-body ...

                (define body
                  (generate-wiki-page
                   `(div
                     (noscript "You have to enable JavaScript to load wiki pages. Sorry!")
                     (div (@ (id "loading")))
                     (div (@ (id "progress-bar") (style "margin-bottom: 50vh"))
                          (progress))
                     (script #<<END
var jsonpData = {}
var proxy = new Proxy(jsonpData, {get(obj, prop) { return value => obj[prop] = value }})
END
                             )
                     endpoint-scripts
                     (script (@ (type "module") (src ,(get-static-url "jsonp.js")))))
                   #:req req
                   #:source-url source-url
                   #:wikiname wikiname
                   #:title title
                   #:siteinfo siteinfo-default
                   #:path path
                   #:jsonp #t))
                (when (config-true? 'debug)
                  (xexp->html body))
                (response/output
                 #:code 200
                 #:headers always-headers
                 (λ (out)
                   (write-html body out)))))))])]))
