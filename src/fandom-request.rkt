#lang typed/racket/base
(require racket/format
         racket/string
         "config.rkt"
         "../lib/url-utils.rkt")
(define-type Headers (HashTable Symbol (U Bytes String)))
(require/typed net/http-easy
  [#:opaque Timeout-Config timeout-config?]
  [#:opaque Response response?]
  [#:opaque Session session?]
  [response-status-code (Response -> Natural)]
  [current-session (Parameter Session)]
  [current-user-agent (Parameter (U Bytes String))]
  [make-timeout-config ([#:lease Positive-Real] [#:connect Positive-Real] -> Timeout-Config)]
  [get ((U Bytes String)
        [#:close? Boolean]
        [#:headers Headers]
        [#:timeouts Timeout-Config]
        [#:max-attempts Exact-Positive-Integer]
        [#:max-redirects Exact-Nonnegative-Integer]
        [#:user-agent (U Bytes String)]
        -> Response)])

(provide
 fandom-get
 fandom-get-api
 timeouts)

(current-user-agent
 "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0")

(define timeouts (make-timeout-config #:lease 5 #:connect 5))

(: last-failure Flonum)
(define last-failure 0.0)
(: stored-failure (Option Response))
(define stored-failure #f)
(define failure-persist-time 30000)

(: no-headers Headers)
(define no-headers '#hasheq())

(: fandom-get (String String [#:headers (Option Headers)] -> Response))
(define (fandom-get wikiname path #:headers [headers #f])
  (or
   (and ((current-inexact-milliseconds) . < . (+ last-failure failure-persist-time)) stored-failure)
   (let ()
     (define dest-url (format "https://~a.fandom.com~a~a" wikiname (current-fandom-lang) path))
     (define host (format "~a.fandom.com" wikiname))
     (log-outgoing wikiname path)
     (define res
       (get dest-url
            #:timeouts timeouts
            #:headers (hash-set (or headers no-headers) 'Host host)))
     (when (memq (response-status-code res) '(403 406))
       (set! last-failure (current-inexact-milliseconds))
       (set! stored-failure res))
     res)))

(: fandom-get-api (String (Listof (Pair String String)) [#:headers (Option Headers)] -> Response))
(define (fandom-get-api wikiname params #:headers [headers #f])
  (fandom-get wikiname
              (string-append "/api.php?" (params->query params))
              #:headers headers))

(: log-outgoing (String String -> Void))
(define (log-outgoing wikiname path)
  (when (config-true? 'log_outgoing)
    (printf "out: ~a ~a~n" wikiname path)))
