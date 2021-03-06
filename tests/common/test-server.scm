(use-modules (ice-9 rdelim)
             (tests common)
             (ssh auth)
             (ssh channel)
             (ssh dist)
             (ssh key)
             (ssh message)
             (ssh popen)
             (ssh server)
             (ssh session)
             (ssh tunnel)
             (ssh log)
             (ssh server))

(define (log message)
  (let ((f (open-file "/tmp/b.txt" "a+")))
    (display message f)
    (newline f)
    (close f)))

(define (main args)
  (log args)
  (let ((test-suite-name (list-ref args 1))
        (test-name       (list-ref args 2)))
    (unless (file-exists? test-suite-name)
      (mkdir test-suite-name))
    (set-log-userdata! test-name)
    (setup-test-suite-logging! (string-append test-suite-name "/" test-name))
    (log "test 1")
    (let* ((port      (string->number (list-ref args 3)))
           (handler   (eval-string (list-ref args 4)))
           (s         (make-server
                       #:bindaddr %addr
                       #:bindport port
                       #:rsakey   %rsakey
                       #:dsakey   %dsakey
                       #:log-verbosity 'functions)))
      (log "test 2")
      (server-listen s)
      (let ((p (open-output-file (string-append test-name ".run"))))
        (close p))
      (log handler)
      (handler s)   (log "test 4"))))

