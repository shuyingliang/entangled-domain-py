(module pycesk3
  racket/base
  (require "utils_cesk3.rkt")
  (provide (all-defined-out))
  (require racket/pretty)
  (require racket/match)
  (require racket/list)
  (require racket/set)
  (require racket/local)
  (require racket/bool)
  (require racket/function)
  
  ;; Abstract interpretation based analyzer for ANF Python code
  ;; support Python dynamic class system, collections and comprehensions
  
  
  ;; apply :: kont-addr -> D -> Store -> OStore -> Measure -> time -> [state]
  (define (apply kont-addr d store ostore  measure time)
    (DEBUG " d's value to apply is: " d)
    (local ([define konts (store-lookup store kont-addr)])
      ;(displayln "kont-length") (displayln (set-count konts))
      ;(for/list ([kont (in-set konts)])
      (define kont (get-elem-from-singleton-set konts))
        (cond
          [(letK? kont) 
           (match-define (struct letK (v e benv kaddr)) kont)
           (define binding ((alloc-bind time) v))
           (define benv*  (benv-extend benv v binding))
           (define store* (store-update store binding d))
           (define measure* (measure-update measure binding))
           (list  (make-state e benv* store* ostore measure*  kaddr time))]
          [(forK? kont)
           (match-define (struct forK (v-k val remaining-seq exp be last-kaddr)) kont)
           (cond 
             [(empty? remaining-seq) 
              (define binding ((alloc-bind time) v-k))
              (define benv*  (benv-extend be v-k binding))
              (define store* (store-update store binding val))
              (define measure* (measure-update measure binding))
              (list (make-state exp benv* store* ostore measure* last-kaddr time))]
             [else
              (define binding ((alloc-bind time) v-k))
              (define benv*  (benv-extend be v-k binding))
              (define store* (store-update store binding val))
              (define measure* (measure-update measure binding))
              (define next-fork-addr ((alloc-kont time) (new-kont-exp kont-addr)))
              (define new-fork (make-forK v-k (car remaining-seq) 
                                       (rest remaining-seq) exp be last-kaddr))
              (define store** (store-update store* next-fork-addr (set new-fork)))
              (define measure** (measure-update measure* next-fork-addr))
              (list (make-state exp benv* store** ostore measure**  next-fork-addr time))])]
          ['$halt empty]
          [else (DEBUG "WARNING: not applying values to either or continuation?!")])))
  
  ;; travel-mro :: [VAR] -> VAR -> String -> OLOC -> OLOC -> benv -> store -> ostore -> D
  ;; this part it is harder to do in the compile time
  (define (travel-mro var-clses var-fld str-type loc-inst loc-super benv store ostore)
    (cond 
      [(empty? var-clses)  (error "referencing unexisted field")]
      [else
       (define cls-cls ((atom-eval benv store) (car var-clses)))
       (define key-set ((atom-eval benv store) var-fld))
       (for/fold ([res-set (set)])
         ([cls (in-set cls-cls)])
         (match cls
           [(struct Cls (cl oloc))
            (local ([define val (obj-lookup key-set (ostore-lookup ostore oloc))])
              (cond
                [(set-empty? val) (travel-mro (rest var-clses) var-fld str-type loc-inst loc-super benv store ostore)]
                [else
                 (cond
                   [(equal? str-type "class") (set-union res-set val)]
                   [(equal? str-type "inst") (set-union res-set (transform-methods-in-inst-fld-reference val loc-inst))]
                   [(equal? str-type "super") (set-union res-set (transform-methods-in-inst-fld-reference val loc-super))]
                   [else (DEBUG "travel mro's tr-type not in class, inst, nor super?") val])]))]
           [else 
            (DEBUG "in travel-mro, and the reference to the cls in the store is not Cls struct!") 
            (error "in travel-mro, and the reference to the cls in the store is not Cls struct!")]))]))
  
  
   ; ********************************* helpers for the ordinary lambda matching **********************
  ;; just avoid code dupilicates which appear in both ordinary lambda class lambda case in function app
  ;; ordinary-lambda-bind :: exp -> store -> ostore -> measure -> kont-addr ->time -> state
  (define (ordinary-lambda-bind clo args env store ostore measure kont-addr time)
    ;(DEBUG "lambda" (closure-lambda clo))
    ;(DEBUG "benv*"  (closure-benv clo))
     (match clo
       [(struct closure (lam benv*))
        (match lam
          [`(lambda (,formals ...) ,exp)
           (DEBUG " app matched normal lambda " (closure-lambda clo))
           (define params (map (atom-eval env store) args))
           (define bindings (map (alloc-bind time) formals))
           (define benv**  (benv-extend* benv* formals bindings))
           (define store* (store-update* store bindings params))
           (define measure* (measure-update* measure bindings))
           (make-state exp benv** store* ostore  measure* kont-addr time)])]))
 
 
  ;******************************* transition rules *******************************************
  ;; next :: state -> [state]
  (define (next st)
    (match-define (struct state (exp benv store ostore measure kont-addr time)) st)
    ;(displayln (gensym "news"))
    (match exp
      ;; if there is an error, the analyzer should also stop?
      [`(error ,ae) (DEBUG " in error ") empty]
      
      ;; condition
      [`(if ,ae ,tce ,fce) 
       (DEBUG " in if " exp)
       (foldr (λ (condition state-lst)
                (local ([define t-st (make-state tce benv store ostore measure  kont-addr time)]
                        [define f-st (make-state fce benv store ostore measure kont-addr time)])
                  (cond
                    [condition (append state-lst (list t-st))]
                    [(false? condition) (append state-lst  (list f-st))]
                    [else (DEBUG "Something wrong may happened: the condition test is neither true nor false!" condition) (append state-lst (list t-st f-st))])))
              (list)
              (set->list ((atom-eval benv store) ae)))] 
      
      [`(set! ,var ,ae)
       (DEBUG " in set! " exp)
       (local ([define new-val ((atom-eval benv store) ae)])
         ;(define store* (store-update store (benv-lookup benv var) new-val)) ;--> before measure compoenent added
         (define store* (proper-update var new-val benv store measure))
         (apply kont-addr (set)  store* ostore  measure time))]
      
      ;; let expression
      [`(let ((,v ,ce)) ,e)
       (DEBUG " in let ")
       (define time* (tick (get-current-time exp) time))
       (define new-kont-addr ((alloc-kont time) exp))
       (define new-kont (make-letK v e benv kont-addr))
       (define new-store (store-update store new-kont-addr (set new-kont)))
       (define measure* (measure-update measure  new-kont-addr))
       (list (make-state ce benv new-store ostore measure*  new-kont-addr time*))]
      
      ;; call/ec
      [`(call/ec ,f)
       (DEBUG " in call/ec " exp)
       (define procs ((atom-eval benv store) f))
       (define time* (tick (get-current-time exp) time))
       (for/list ([proc (in-set procs)])
         (match proc
           [(struct closure (lam benv*))
            (match lam
              [`(lambda (,v) ,exp)
               (define kaddr ((alloc-bind time*) v))
               (define benv** (benv-extend benv* v kaddr))
               (define store* (store-update store kaddr (set (make-kontP kont-addr))))
               (define measure* (measure-update measure kaddr))
               (make-state exp benv** store* ostore measure* kont-addr time*)])]))]
      
      ;; set-field!
      [`(set-field! ,ae-b ,ae-f ,ae-v)
       (DEBUG " in set-field! " exp)
       (define val-set ((atom-eval benv store) ae-v))
       (define field-set ((atom-eval benv store) ae-f))
       (define locs ((atom-eval benv store) ae-b))
       (define ostore* 
         (foldr (λ (loc os)
                  (ostore-update ostore loc (obj-update field-set val-set (ostore-lookup ostore loc))))
                ostore
                (pull-locs locs)))
       (apply kont-addr (set) store ostore* measure  time)]
      
      ;; in dict-set! for class deifinition
      [`((anf dict-set!) gbl-dict ,v-cls ,ae)
       (DEBUG " in " exp)
       (when (equal? v-cls 'tuple) (DEBUG "Yes, we are setting the tuple dict"))
       (define oloc ((atom-eval benv store) ae))
       ;; the following cond is for testing purpose
       (match (get-elem-from-singleton-set oloc)
         [(struct OLoc (e t)) (DEBUG "Yes, it is a oloc in the gbl-set! " oloc)]
         [else (DEBUG "oops, not an location!") (error "sorry, no need to continue since class allocation failed!")])
       ;; in my scheme, every time the oloc returns, it is a singelton set! so another test:
       (local ([define num-oloc (set-count oloc)])
         (cond
           [(= 1 num-oloc) (DEBUG "Yes, it is the only location allocated ")]
           [(< 1 num-oloc) (DEBUG "multiple olocs mapped from the same classname!")]
           [(> 1 num-oloc) (DEBUG "ridiculous result! nothing returned from oloc") (error "nothing returned at the oloc!")]))
       (define store* (store-update-cls store (benv-lookup benv v-cls) (get-elem-from-singleton-set oloc))) ; NOTE: This line may not be 
       ; it makes sense to apply the empty set for any *-set! expression, since there is no need to use the let bound var at the end!
       (apply kont-addr (set) store* ostore measure time)]
      
      ;; in dict-ref gbl-dict
      [`((anf dict-ref) gbl-dict ,v-cls) 
       (DEBUG " should elminate this one! in dict-ref gbl-dict?" exp)
       (define res-set ((atom-eval benv store) v-cls))
       (DEBUG "the class values: " res-set)
       (apply kont-addr res-set store ostore measure  time)]
      
      ;; in biop
      [`((anf ,biop) ,ae1 ,ae2)
       (DEBUG " in biop " exp)
       (define ae1-set ((atom-eval benv store)  ae1))
       (define ae2-set ((atom-eval benv store) ae2))
       (cond
         [(container-biops? biop) 
          (DEBUG " in container biop " biop)
          (define items-locs (obj-lookup* (set "__containerdict__") ae1-set ostore))
          (define d-containerdict-vals (obj-lookup* ae2-set items-locs ostore)) (DEBUG " the val set from __items__ " d-containerdict-vals)
          (define d-elem-vals (obj-lookup* ae2-set ae1-set ostore)) (DEBUG " the val set from what referring " d-elem-vals)
          (define res-set (set-union d-containerdict-vals d-elem-vals))
          (apply kont-addr res-set store ostore measure time)]
         [(or (arith-ops? biop) (comp-biops? biop))
          (define res (map-set2 best-effort-arith-value ae1-set ae2-set biop))
          (apply kont-addr res store ostore  measure time)]
         ;; for container
         [(equal? biop 'for-container)
          (DEBUG "biop for-container " exp)
          ;(cond 
            ;; todo: for container will iterate dictionary, but now it is pylist pyset tuple
            ;[(or (py-list? base store ostore) (pyset? base store ostore) (tuple? base store ostore))
             ;; it is the proc to be applied to every elements in the containers.
             (define proc (get-elem-from-singleton-set ae2-set))
             ;(displayln ((atom-eval benv store) 'cnt12))
             ;(pretty-write proc)
             (define flattened-container-vals (flatten-container-vals ae1-set ostore))
             (DEBUG " flatten-container-vals is " flattened-container-vals)
             (match proc
               [(struct closure (lamb be))
                (match lamb
                    [`(lambda (,v) ,e) 
                     (define new-fork-addr ((alloc-kont time) exp)) ;this exp as part of the forK address)
                    ; (define new-kont-addr ((alloc-kont time) exp))
                    ; (define new-kont (make-letK v e benv kont-addr))
                    ; (define new-store (store-update store new-kont-addr (set new-kont)))
                    ; (list (make-state ce benv new-store ostore new-kont-addr time*)
                            ;(define-struct forK (vk vv rest-seq e benv addr) #:transparent)
                    (cond
                       [(empty? flattened-container-vals) (flatten (apply kont-addr (set) store ostore measure time))]
                       [else
                        (define new-kont-fork (make-forK v (car flattened-container-vals) (rest flattened-container-vals) e be kont-addr))
                        (define store* (store-update store new-fork-addr (set new-kont-fork)))
                        ;(define measure* (measure-update  new-fork-addr))
                        (flatten (apply new-fork-addr (set) store* ostore measure time))])])])])]
                
;             ;; we abstractly apply the for-container proc to every container-vals
;             (define st-lst
;             (for/list ([val (in-list flattened-container-vals)])
;               (match proc 
;                 [(struct closure (lamb be))
;                  ;(displayln "for container proc env, you will find the same everytime) ") (pretty-write be) (displayln ((atom-eval benv store) 'num))
;                  (match lamb
;                    [`(lambda (,v) ,e) 
;                     (define binding ((alloc-bind time) v))
;                     (define benv* (benv-extend be v binding))
;                     (define store* (store-update store binding val))
;                     ;(displayln val)
;                     (define st (make-state e benv* store* ostore kont-addr time))
;                     ;(DEBUG "state in the for container" st)
;                     st]
;                    [else (DEBUG "error in loop proc in for-container" proc) (error "error in loop proc in for-container")])]
;                 [else (error "error in biop container, the loop proc is not closure?!")])))
;             (DEBUG "the st-lst generated is " (length st-lst))
;             st-lst])]
             
      ;; in dict
      [`(dict (,v-k ,ae-v) ...)
       (DEBUG " in dict " exp)
       ;; guess this is the program point where we tick time to construct a new address!?
       (define time* (tick (get-current-time time) time))
       (define oloc (make-OLoc exp time*))
       (define d-ks  (map (atom-eval benv store) v-k))
      
      ; (define d-vs  (map (atom-eval benv store) ae-v))
       (define d-vs (new-vals v-k ae-v benv store))
       (define obj-map (ostore-lookup ostore oloc))
       ;; the following is for testing purpose
;       (when (empty? (hash->list (first obj-map))) 
;         (DEBUG " the bottom value for obj-map, probably the first time allocation? " obj-map))
       (define obj-map* (obj-update* d-ks d-vs obj-map))
       (define ostore* (ostore-update ostore oloc obj-map*))
       (apply kont-addr (set oloc) store ostore* measure time*)]
      
      ;; get-field
      [`(get-field ,ae-b ,ae-f)
       (DEBUG " in get-field " exp)
       (define d-f ((atom-eval benv store) ae-f))
       (define d-b ((atom-eval benv store) ae-b))
       (DEBUG "d-f: " d-f)
       (DEBUG "d-b: " d-b)
       (flatten
        (for/list ([val (in-set d-b)])
          ;; yeah, this is ugly, but for the __class__ case, whose evaluation is just a  class symbol
          (when (symbol? val) (set! val (get-elem-from-singleton-set ((atom-eval benv store) val))))
          (match val
            ;; class get-field
            [(struct Cls (cl oloc)) 
             (DEBUG "get-field's base is a class " val)
             ;(DEBUG "ostore" ostore)
             (local ([define mro-lst (get-elem-from-singleton-set (obj-lookup (set "__mro__") (ostore-lookup ostore oloc)))]
                     [define res (travel-mro mro-lst ae-f "class" #f #f benv store ostore)])
               (apply kont-addr res store ostore  measure time))]
            ;; instance get-field
            [(struct OLoc (e t))
             (DEBUG "get-field's based is an normal location, which is an instance location " (OLoc-exp val))
             ;(DEBUG "the ostore is: " ostore)
             (local ([define inst-om (ostore-lookup ostore val)]
                     [define tmp-res (obj-lookup d-f inst-om)])
               ;(DEBUG  inst-om)
               ;(DEBUG tmp-res)
               (cond
                 [(set-empty? tmp-res)
                  (DEBUG " instance field result not found for " ae-b)
                  (DEBUG "will search up the instance's class mro-lst....")
                  ;(DEBUG "the inst-om is: " inst-om)
                  ;(DEBUG "obj-lookup: "(obj-lookup (set "__class__") inst-om))
                  ; go through the __class__
                  ; note: the __class__ as well the __mro__ is singleton set
                  (define cls (get-elem-from-singleton-set (obj-lookup (set "__class__") inst-om)))
                  (DEBUG "cls" cls)
                  (define cls-cls (get-elem-from-singleton-set ((atom-eval benv store) cls)))
                  (DEBUG "cls-cls" cls-cls)
                  (match cls-cls
                    [(struct Cls (cl oloc)) 
                     (define mro-lst (get-elem-from-singleton-set (obj-lookup (set "__mro__") (ostore-lookup ostore oloc))))
                     (DEBUG "mro-lst get is: " mro-lst)
                     (DEBUG "ae-f passed is: " ae-f)
                     (define res  (travel-mro mro-lst ae-f "inst" val #f benv store ostore))
                     (define states (apply kont-addr res store ostore measure time))
                     ;(DEBUG "list of states?" (list? states)) ;(pretty-write states) 
                     states]
                    ;(apply kont-addr res store ostore time)]
                    [else  (DEBUG "instance get-field not found instance and neither reference to the instance's class field succeeds " cls)
                           (error "referencing the __class__ failed")])]
                 [else
                  (apply kont-addr (transform-methods-in-inst-fld-reference tmp-res val) store ostore measure time)]))])))]
      
      ;; unop
      [`((anf ,unop) ,ae)
       (DEBUG " in unary operation: " exp)
       (define base-set ((atom-eval benv store) ae))
       (apply kont-addr (map-set-uniop compute-each base-set unop store ostore) store ostore measure  time)]
      
      ;; triop
      [`((anf ,triop) ,ae-b ,ae-f ,ae-v) 
       (DEBUG " in triop " exp)
       (define field-set ((atom-eval benv store) ae-f))
       (define val-set ((atom-eval benv store) ae-v))
       (define locs ((atom-eval benv store) ae-b))
       (DEBUG " the triop base set: " locs)
       (cond
         [(or (equal? triop 'dict-set!) (equal? triop 'py-list-set!))
          (define ostore* 
            (foldr (λ (loc os)  ;; for every locations that ae-b points to
                     (local ([define om (ostore-lookup ostore loc)]
                             [define item-locs (obj-lookup (set "__containerdict__") om)])
                       (cond ;; to find the nested dict location
                         [(set-empty? item-locs) (DEBUG " dict-set! no containerdict field found for " ae-b) os]
                         [else
                          (local ([define locs-lst (pull-locs item-locs)]) ;; yeah, we find (possibly) nested locations
                            (cond 
                              [(empty? locs-lst) (DEBUG " dict-set! no containerdict locations for " ae-b) os] ;we don't update values that's not objs
                              [else ;; here we found
                               (foldr (λ (nest-loc oss) ;; we fold the current os 
                                        (ostore-update oss nest-loc (obj-update field-set val-set (ostore-lookup ostore nest-loc))))
                                      os
                                      locs-lst)]))]) 
                       ))
                   ostore
                   (pull-locs locs)))
          (define ostore** (foldr (λ (loc os) (ostore-update os loc (obj-update field-set val-set (ostore-lookup ostore loc))))
                                  ostore*
                                  (pull-locs locs)))
          (apply kont-addr (set) store ostore** measure time)])]
      
      ;; the let binding lambda
      [(or `(lambda (,formals ...) ,body) `(lambda ,formals ,body))
       (DEBUG " in let binding lambda " exp)
       (apply kont-addr ((atom-eval benv store) exp) store ostore measure time)]
      
      ;; special case void
      [(or `(void) 'void)
       (DEBUG " in void" exp)
       (apply kont-addr ((atom-eval benv store) exp) store ostore measure  time)]
      
      ;; special case: (list of class-precedences in the __mro__ field
      [`(list ,e ...)
       (DEBUG " in list of class precedences " exp)
       ; the atom-eval is extended to pack the exp as a singletone set of as it is
       ; for the ease of travel-mro
       (define val-set ((atom-eval benv store) exp)) 
       (apply kont-addr val-set store ostore measure time)]
      
      ;; application
      [`(,f ,args ...)
       (DEBUG " in function app " exp)
       ;(when (equal? (car args) 'cnt12) (displayln ((atom-eval benv store) 'cnt12)))
       (define procs ((atom-eval benv store) f))
       (define time* (tick (get-current-time exp) time))
       (flatten 
        (for/list ([proc (in-set procs)])
          (match proc
            ;; closures with various lambda form
            [(struct closure (lambda-exp benv*))
             (match lambda-exp
               ;; normal lambda
               [`(lambda (,formals ...) ,exp) 
                (DEBUG "in normal lambda")
                (ordinary-lambda-bind proc args benv store ostore measure kont-addr time*)]
               ;; curried lambda
               [`((lambda (,formals ...) ,exp) ,obj-loc)
                (DEBUG " app matched curried lambda " proc)
                (DEBUG "obj-loc: " obj-loc)
                (define params (append (list (set obj-loc)) (map (atom-eval benv store) args)))
                ;(DEBUG "params: " params)
                (define bindings (map (alloc-bind time*) formals))
                ;(DEBUG "bindings" bindings)
                (define benv** (benv-extend* benv* formals bindings))
                (define store* (store-update* store bindings params))
                (define measure* (measure-update* measure bindings))
                ;(DEBUG "ere")
                (make-state exp benv** store* ostore measure* kont-addr time*)]
               ;; object lambda
               [`(lambda () void)
                (DEBUG " app matched in object lambda ")
                (apply kont-addr (set proc) store ostore measure time*)])]
            ;; the process to be applied from call/ec
            [(struct kontP (letk-addr))
             (DEBUG " app matched in continuation " proc)
             (cond
               [(empty? args) (apply letk-addr (set) store ostore measure time*)]
               [else  
                (define val ((atom-eval benv store) (car args)))
                (apply letk-addr val store ostore measure time*)])]
            ;; the Cls structure that enclosed a closure
            [(struct Cls (clo loc))
             (DEBUG "in app: f is evaluted to be cls closure")
             (ordinary-lambda-bind clo  args benv store ostore measure  kont-addr time*)]
            ;; falling through all the cases
            [else
             (DEBUG " no matching for ~a in app " proc)
             (error "no matching in app")])))]
      
      [e (cond
            [(atom? e) (apply kont-addr ((atom-eval benv store) e) store ostore measure  time)]
            [else empty])]))
  
  ;; compute all the reachable states
  ;; reachale :: Set State -> [State] -> Set State
  (define (reachable seen todo)
    (match todo
      [(list) seen]
      [(list-rest (? (curry set-member? seen)) todo) ;(displayln "middle case") 
                                                     (reachable seen todo)]
      [(list-rest st0 todo) ;(displayln "last case") ;(pretty-write st0) 
                            (reachable (set-add seen st0) (append (next st0) todo))]))
  
  ;; gives out initial state
  (define (inject-cesk exp benv0 store0 ostore0 measure0)
    (make-state exp benv0 store0 ostore0 measure0 ((alloc-kont time-zero) `$halt) time-zero))
 
  ;; explore all reachable states
  ;; explore :: initial-state -> Set state
  (define (explore injected-state)
    (define all-reachables-states (reachable empty-set (list injected-state)))
    (display "Number of States = ") (displayln (length (set->list all-reachables-states)))
    (newline)
    all-reachables-states)
                      
 
  

  )


