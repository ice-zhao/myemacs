;; -*- lexical-binding: t; -*-
(add-hook 'python-mode-hook 'lsp-deferred)

(setq lsp-clients-python-command "/usr/local/bin/pylsp")
(setq lsp-prefer-flymake nil)
(setq python-indent-offset 4)

;; fold and unfold function and class
;; C-c @ C-h fold; C-c @ C-s unfold
(add-hook 'python-mode-hook 'hs-minor-mode)

(add-hook 'python-mode-hook
  (lambda ()
    (define-key python-mode-map "\C-cne" 'python-nav-end-of-block)))
