#lang racket/base
(require racket/class
         racket/dict
         racket/draw
         pict
         file/convertible
         racket/format
         racket/list
         racket/math
         racket/match
         web-server/http
         (only-in web-server/dispatchers/dispatch next-dispatcher)
         net/url
         (only-in net/cookies/server cookie->set-cookie-header cookie-header->alist)
         html-writing
         "application-globals.rkt"
         "data.rkt"
         "config.rkt"
         "static-data.rkt"
         "../lib/url-utils.rkt"
         "../lib/xexpr-utils.rkt")

(provide
 page-captcha
 page-captcha-image
 page-captcha-verify)

(define (get-ip req)
  (define header
    (if (config-true? 'captcha::ip_header)
        (headers-assq* (string->bytes/utf-8 (config-get 'captcha::ip_header)) (request-headers/raw req))
        #f))
  (if header
      (~a (header-value header))
      (request-client-ip req)))

(define (get-rng req)
  (parameterize ([current-pseudo-random-generator (make-pseudo-random-generator)])
    (define ip-segments (regexp-match* "[0-9]+" (get-ip req)))
    (define seed
      (modulo
       (for/sum ([i (in-naturals)]
                 [s ip-segments])
         (* (add1 i) (add1 (string->number s))))
       (expt 2 32)))
    (random-seed seed)
    (current-pseudo-random-generator)))

(define (get-key-solution req)
  (parameterize ([current-pseudo-random-generator (get-rng req)])
    (random 1 (add1 9))))

(define diameter 35)
(define font (make-object font% 12 'system))
(define msg "I'm not a robot!")
(define checkbox (filled-ellipse diameter diameter #:color "Red"))
(define assembly
  (frame
   (inset
    (hc-append
     8
     checkbox
     (text msg font))
    8)))
(define-values (inner-x inner-y) (cc-find assembly checkbox))
(define-values (lt-x lt-y) (lt-find assembly checkbox))
(define-values (rb-x rb-y) (rb-find assembly checkbox))

(define (get-coordinate-solution req w h)
  (parameterize ([current-pseudo-random-generator (get-rng req)])
    (values (random (exact-truncate lt-x) (exact-truncate (- w rb-x)))
            (random (exact-truncate lt-y) (exact-truncate (- h rb-y))))))

(define (page-captcha req)
  (define cookie-header (headers-assq* #"cookie" (request-headers/raw req)))
  (define cookies-alist (if cookie-header (cookie-header->alist (header-value cookie-header) bytes->string/utf-8) null))
  (for ([pair cookies-alist])
    (match pair
      [(cons "captcha" method)
       (when (config-true? 'captcha::log)
         (printf "captcha skip - via ~a [~a] - ~v~n" method (get-ip req) (url->string (request-uri req))))
       (next-dispatcher)]
      [_ (void)]))
  
  (response-handler
   (define body
     `(*TOP*
       (*DECL* DOCTYPE html)
       (html
        (head
         (meta (@ (name "viewport") (content "width=device-width, initial-scale=1")))
         (title "Checking you're not a bot...")
         (link (@ (rel "stylesheet") (type "text/css") (href ,(get-static-url "internal.css"))))
         (link (@ (rel "stylesheet") (type "text/css") (href ,(get-static-url "main.css"))))
         (link (@ (rel "icon") (href ,(head-data^-icon-url head-data-default))))
         (script (@ (defer) (src ,(get-static-url "captcha.js")))))
        (body (@ (class "skin-fandomdesktop theme-fandomdesktop-light internal"))
              (div (@ (class "main-container"))
                   (div (@ (class "fandom-community-header__background tileBoth header")))
                   (div (@ (class "page"))
                        (main (@ (class "page__main"))
                              (div (@ (class "custom-top"))
                                   (h1 (@ (class "page-title"))
                                       "Checking you're not a bot..."))
                              (div (@ (id "content") #;(class "page-content"))
                                   (div (@ (id "mw-content-text"))
                                        (p "To confirm, please click directly in the circle, or hold down the " ,(~a (get-key-solution req)) " key on your keyboard.")
                                        (noscript (p "JavaScript is required for the captcha. Sorry!"))
                                        (div (@ (id "captcha-area")))))
                              ,(application-footer #f))))))))
   (when (config-true? 'debug)
     (xexp->html body))
   (response/output
    #:code 200
    #:headers always-headers
    (λ (out)
      (write-html body out)))))

(define (page-captcha-image req)
  (response-handler
   (define w (string->number (path/param-path (third (url-path (request-uri req))))))
   (define h (string->number (path/param-path (fourth (url-path (request-uri req))))))
   (define-values (at-x at-y) (get-coordinate-solution req w h))
   (when (config-true? 'captcha::log)
     (printf "captcha show - size ~a x ~a - solution ~a x ~a [~a]~n" w h at-x at-y (get-ip req)))
   #;(printf "target: ~a x ~a~ncanvas: ~a x ~a~npict size: ~a-~a ~a-~a~n" at-x at-y x y lt-x rb-x lt-y rb-y)
   (define dc (make-object bitmap-dc% #f))
   (send dc set-font font)
   (define bm (make-object bitmap% w h #f #f))
   (send dc set-bitmap bm)
   (draw-pict
    assembly
    dc
    (- at-x inner-x)
    (- at-y inner-y))
   (define image (convert bm 'png-bytes))
   (response/output
    #:mime-type #"image/png"
    #:headers (list (header #"Cache-Control" #"no-cache"))
    (λ (out) (display image out)))))

(define (page-captcha-verify req)
  (response-handler
   (match-define (list w h x y) (for/list ([segment (drop (url-path (request-uri req)) 2)])
                                  (string->number (path/param-path segment))))
   #;(printf "solution: ~a x ~a~ncoordinate: ~a x ~a~ndist^2: ~a~n" solution-x solution-y x y dist)
   (define headers
     (build-headers
      always-headers
      (cond
        [(and (= y 0) (= x (get-key-solution req)))
         (when (config-true? 'captcha::log)
           (printf "captcha pass - key ~a [~a]~n" x (get-ip req)))

         (header #"Set-Cookie" (cookie->set-cookie-header (make-cookie "captcha" "key" #:path "/" #:max-age (* 60 60 24 365 10) #:http-only? #t #:secure? #t)))]
        [(= y 0)
         (when (config-true? 'captcha::log)
           (printf "captcha fail - key ~a instead of ~a [~a]~n" x (get-key-solution req) (get-ip req)))]
        [else (void)])
      (when (> y 0)
        (let-values ([(solution-x solution-y) (get-coordinate-solution req w h)])
          (let ([dist (+ (expt (- x solution-x) 2) (expt (- y solution-y) 2))])
            (cond
              [(dist . < . (expt (/ diameter 2) 2))
               (when (config-true? 'captcha::log)
                 (printf "captcha pass - coordinate, dist^2 ~a [~a]~n" dist (get-ip req)))
               (header #"Set-Cookie" (cookie->set-cookie-header (make-cookie "captcha" "coordinate" #:path "/" #:max-age (* 60 60 24 365 10))))]
              [else
               (when (config-true? 'captcha::log)
                 (printf "captcha fail - coordinate, dist^2 ~a - attempt ~a x ~a - solution ~a x ~a [~a]~n" dist x y solution-x solution-y (get-ip req)))]))))))
   (match (dict-ref (url-query (request-uri req)) 'from #f)
     [(? string? dest)
      (response/output
       #:code 302
       #:mime-type #"text/plain"
       #:headers (cons (header #"Location" (string->bytes/utf-8 dest)) headers)
       (λ (out)
         (displayln "Checking your answer..." out)))]
     [#f (next-dispatcher)])))
