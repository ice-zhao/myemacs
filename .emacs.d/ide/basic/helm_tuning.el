;; -*- lexical-binding: t; -*-
;helm features
(add-hook 'eshell-mode-hook
          #'(lambda ()
              (define-key eshell-mode-map (kbd "C-c C-l")  'helm-eshell-history)))  ;for eshell history
(define-key minibuffer-local-map (kbd "C-c C-l") 'helm-minibuffer-history)  ; for helm-mini buffer history.

