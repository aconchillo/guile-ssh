;;; tunnel.scm -- SSH tunnels

;; Copyright (C) 2015 Artyom V. Poptsov <poptsov.artyom@gmail.com>
;;
;; This file is a part of Guile-SSH.
;;
;; Guile-SSH is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.
;;
;; Guile-SSH is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Guile-SSH.  If not, see <http://www.gnu.org/licenses/>.


;;; Commentary:


;;; Code:

(define-module (ssh tunnel)
  #:use-module (rnrs io ports)
  #:use-module (srfi srfi-9 gnu)
  #:use-module (ice-9 iconv)
  #:use-module (rnrs bytevectors)
  #:use-module (ssh session)
  #:use-module (ssh channel)
  #:export (make-tunnel
            tunnel?
            tunnel-session
            tunnel-source-host
            tunnel-source-port
            tunnel-remote-host
            tunnel-remote-port
            start-forward
            call-with-ssh-forward))


;;; Tunnel type

(define-immutable-record-type <tunnel>
  (%make-tunnel session timeout source-host local-port
                remote-host remote-port)
  tunnel?
  (session     tunnel-session)
  (timeout     tunnel-timeout)          ; number
  (source-host tunnel-source-host)
  (local-port  tunnel-local-port)
  (remote-host tunnel-remote-host)
  (remote-port tunnel-remote-port))

(set-record-type-printer!
 <tunnel>
 (lambda (tunnel port)
   "Print information about a TUNNEL to a PORT."
   (format port "#<tunnel ~a:~a -> ~a:~a ~a>"
           (tunnel-source-host tunnel)
           (tunnel-local-port  tunnel)
           (tunnel-remote-host tunnel)
           (tunnel-remote-port tunnel)
           (number->string (object-address tunnel) 16))))

(define (make-tunnel-channel tunnel)
  (let ((channel (make-channel (tunnel-session tunnel))))
    (or channel
        (error "Could not make a channel" tunnel))
    channel))


;;; Procedures

(define* (make-tunnel session
                      #:key (source-host "127.0.0.1") local-port
                      remote-host (remote-port local-port)
                      (timeout 1000))
  "Make a new tunnel using SESSION."
  (let ((timeout (if (and timeout (> timeout 0))
                     timeout
                     1)))
    (%make-tunnel session timeout
                  source-host local-port
                  remote-host remote-port)))


(define-syntax cond-io
  (syntax-rules (else <- -> =>)
    ((_ (p1 -> p2 => proc) ...)
     (cond
      ((and (not (or (port-closed? p1) (port-closed? p2)))
            (char-ready? p1))
       (proc p1 p2)) ...))
    ((_ (p1 <- p2 => proc) ...)
     (cond
      ((and (not (or (port-closed? p1) (port-closed? p2)))
            (char-ready? p2))
       (proc p1 p2)) ...))
    ((_ (p1 -> p2 => proc) ... (else exp ...))
     (cond
      ((and (not (or (port-closed? p1) (port-closed? p2)))
            (char-ready? p1))
       (proc p1 p2)) ...
      (else exp ...)))
    ((_ (p1 <- p2 => proc) ... (else exp ...))
     (cond
      ((and (not (or (port-closed? p1) (port-closed? p2)))
            (char-ready? p2))
       (proc p1 p2)) ...
      (else exp ...)))))


(define (transfer port-1 port-2)
  "Transfer data from PORT-1 to PORT-2.  Close both ports if reading from
PORT-1 returns EOF."
  ;; (format #t "transfer: port-1: ~a; port-2: ~a~%" port-1 port-2)
  (let ((data (get-bytevector-some port-1)))
    ;; (format #t "transfer: data: ~a\n" data)
    (if (not (eof-object? data))
        (put-bytevector port-2 data)
        (begin
          (close port-1)
          (close port-2)))))

(define (main-loop tunnel sock idle-proc)

  (define timeout-s  (and (tunnel-timeout tunnel)
                          (quotient  (tunnel-timeout tunnel) 1000000)))
  (define timeout-us (and (tunnel-timeout tunnel)
                          (remainder (tunnel-timeout tunnel) 1000000)))

  (when (connected? (tunnel-session tunnel))
    (let ((channel (make-tunnel-channel tunnel)))
      (case (channel-open-forward channel
                                  #:source-host (tunnel-source-host tunnel)
                                  #:local-port  (tunnel-local-port  tunnel)
                                  #:remote-host (tunnel-remote-host tunnel)
                                  #:remote-port (tunnel-remote-port tunnel))
        ((error again)
         (error "Could not start forwarding")))
      (let* ((client-connection (accept sock))
             (client            (car client-connection)))

        (while (channel-open? channel)
          (cond-io
           (client -> channel => transfer)
           (channel -> client => transfer)
           (else
            ;; (display "ZZzzz...\n")
            (let ((selected (select (list client) '() '()
                                    timeout-s timeout-us)))
              (if (null? (car selected))
                  (idle-proc client channel)))
            (yield))))

        (format #t "~a~%" channel))
      (main-loop tunnel sock idle-proc))))

(define* (start-forward tunnel #:optional (idle-proc (const #f)))
  "Start port forwarding for a TUNNEL."
  (let ((sock (socket PF_INET SOCK_STREAM 0)))
    (setsockopt sock SOL_SOCKET SO_REUSEADDR 1) ; DEBUG
    (bind sock AF_INET (inet-pton AF_INET (tunnel-source-host tunnel))
          (tunnel-local-port tunnel))
    (listen sock 10)
    (main-loop tunnel sock idle-proc)
    (close sock)))

(define (call-with-ssh-forward tunnel proc)
  (let ((sock   (socket PF_INET SOCK_STREAM 0))
        (thread (call-with-new-thread
                 (lambda ()
                   (start-forward tunnel)))))

    (connect sock AF_INET (inet-pton AF_INET (tunnel-source-host tunnel))
             (tunnel-local-port tunnel))

    (proc sock)

    (cancel-thread thread)))

;;; tunnel.scm ends here.
