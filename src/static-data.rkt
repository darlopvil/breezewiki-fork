#lang typed/racket/base
(require racket/path
         racket/runtime-path
         racket/string
         typed/json)

(provide
 get-static-url
 importmap
 link-header)

(define-runtime-path path-static "../static")

(define static-data
  (for/hash : (Immutable-HashTable Path Nonnegative-Integer)
            ([f (directory-list path-static)]
             #:when (not (regexp-match? #rx"^.#|^#|~$" (path->string f))))
    (define built (simple-form-path (build-path path-static f)))
    (values built (file-or-directory-modify-seconds built))))

(: get-static-url (Path-String -> String))
(define (get-static-url path-or-filename)
  (define the-path (simple-form-path (if (path? path-or-filename)
                                         path-or-filename
                                         (build-path path-static path-or-filename))))
  (format "/static/~a?t=~a" (file-name-from-path the-path) (hash-ref static-data the-path)))

(: importmap String)
(define importmap
  (jsexpr->string
   `#hasheq((imports . ,(for/hasheq : (Immutable-HashTable Symbol String)
                                    ([(k v) (in-hash static-data)]
                                     #:when (equal? (path-get-extension k) #".js"))
                          (values (string->symbol (path->string (path-replace-extension (assert (file-name-from-path k) path?) #"")))
                                  (get-static-url k)))))))

; https://developer.mozilla.org/en-US/docs/Web/HTML/Link_types/preload
(: link-header String)
(define link-header
  (let* ([with-t '(("main.css" "as=style")
                   ("preact.js" "as=script"))]
         [without-t '(("source-sans-pro-v21-vietnamese_latin-ext_latin_greek-ext_greek_cyrillic-ext_cyrillic-regular.woff2" "as=font" "crossorigin" "type=font/woff2"))]
         [with-t-full (map (λ ([path : (Listof String)]) (cons (get-static-url (car path)) (cdr path))) with-t)]
         [without-t-full (map (λ ([path : (Listof String)]) (cons (format "/static/~a" (car path)) (cdr path))) without-t)]
         [all (append with-t-full without-t-full)]
         [header-parts
          (for/list : (Listof String) ([full-path all])
            (define attributes (map (λ ([s : String]) (format "; ~a" s)) (cdr full-path)))
            (format "<~a>; rel=preload~a" (car full-path) (string-join attributes "")))])
    (string-join header-parts ", ")))
