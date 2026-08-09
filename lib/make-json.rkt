#lang racket/base
(require racket/list/grouping
         racket/match
         racket/syntax)

(provide make-json)

(module+ test
  (require rackunit json)
  (define sample
  `(: continue
      (: iistart "2022-01-23T03:44:17Z"
         fucontinue "455"
         continue "||")
      query
      (: pages
         (: 198
            (: pageid 198
               ns 6
               title "File:Rainbow Flag1.svg"
               imageinfo
               ((: timestamp "2025-03-10T07:24:50Z"
                   user "DogeMcMeow"))
               fileusage
               ((: pageid 191
                   ns 0
                   title "Gay")
                (: pageid 215
                   ns 0
                   title "LGBTQIA+"))))))))

(define (make-json data)
  (match data
    [(list ': kvs ...)
     (for/fold ([h (hasheq)])
               ([kv (windows 2 2 kvs)])
       (match-define (list raw-k v) kv)
       (define k (format-symbol "~a" raw-k))
       (hash-set h k (make-json v)))]
    [(list x ...)
     (map make-json x)]
    [x
     x]))

(module+ test
  (check-equal? (make-json sample)
                (string->jsexpr #<<END
{
    "continue": {
        "iistart": "2022-01-23T03:44:17Z",
        "fucontinue": "455",
        "continue": "||"
    },
    "query": {
        "pages": {
            "198": {
                "pageid": 198,
                "ns": 6,
                "title": "File:Rainbow Flag1.svg",
                "imageinfo": [
                    {
                        "timestamp": "2025-03-10T07:24:50Z",
                        "user": "DogeMcMeow"
                    }
                ],
                "fileusage": [
                    {
                        "pageid": 191,
                        "ns": 0,
                        "title": "Gay"
                    },
                    {
                        "pageid": 215,
                        "ns": 0,
                        "title": "LGBTQIA+"
                    }
                ]
            }
        }
    }
}
END
                                )))