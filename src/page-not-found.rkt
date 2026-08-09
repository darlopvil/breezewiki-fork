#lang racket/base
(require racket/string
         net/url
         html-writing
         web-server/http
         "application-globals.rkt"
         "config.rkt"
         "../lib/xexpr-utils.rkt")
(provide
 page-not-found)

;; Extract wikiname + optional Fandom URL from a wiki-looking path.
;; Returns (values wikiname fandom-url) where either can be #f.
(define (analyze-path req)
  (define segs (map path/param-path (url-path (request-uri req))))
  (define (real-title? t) (and (not (string=? t "")) (not (string=? t "Main_Page"))))
  (cond
    ;; /{wiki}/{lang}/wiki/{title...}
    [(and (>= (length segs) 4)
          (equal? (caddr segs) "wiki")
          (real-title? (string-join (cdddr segs) "/")))
     (values (car segs)
             (format "https://~a.fandom.com/~a/wiki/~a"
                     (car segs) (cadr segs) (string-join (cdddr segs) "/")))]
    ;; /{wiki}/wiki/{title...}
    [(and (>= (length segs) 3)
          (equal? (cadr segs) "wiki")
          (real-title? (string-join (cddr segs) "/")))
     (values (car segs)
             (format "https://~a.fandom.com/wiki/~a"
                     (car segs) (string-join (cddr segs) "/")))]
    ;; looks like a wiki root but nothing else: /{wiki} or /{wiki}/wiki
    [(and (>= (length segs) 1) (not (string=? (car segs) "")))
     (values (car segs) #f)]
    [else (values #f #f)]))

(define (page-not-found req)
  (define-values (wikiname fandom-url) (analyze-path req))
  (define content
    `(div (@ (class "bw-404") (style "text-align:center; margin:3rem auto; max-width:680px"))
          (h1 "Página no encontrada")
          (p "El recurso que buscas no existe en esta wiki, o aún no ha sido creado.")
          ,(if fandom-url
               `(p "¿Quieres comprobarlo en el origen? "
                   (a (@ (href ,fandom-url) (rel "nofollow noreferrer"))
                      "Ver esta página en Fandom"))
               "")
          (p (a (@ (href "/")) "Volver al inicio"))))
  (response/output
   #:code 404
   #:mime-type #"text/html; charset=utf-8"
   (λ (out)
     (write-html
      (generate-wiki-page
       content
       #:req req
       #:source-url (or fandom-url "https://www.fandom.com")
       #:wikiname (or wikiname "")
       #:title "Página no encontrada")
      out))))