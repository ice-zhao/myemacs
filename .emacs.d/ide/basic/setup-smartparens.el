;; -*- lexical-binding: t; -*-


(with-eval-after-load 'smartparens
  (sp-with-modes 'makefile-mode
    (sp-local-pair "ifeq" "endif" :actions '(navigate))
    (sp-local-pair "ifneq" "endif" :actions '(navigate))
    (sp-local-pair "ifdef" "endif" :actions '(navigate))
    (sp-local-pair "ifndef" "endif" :actions '(navigate))))

(provide 'setup-smartparens)
