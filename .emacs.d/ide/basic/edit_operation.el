;; -*- lexical-binding: t; -*-
;backup file at temporary dir.
(setq make-backup-files nil)
(setq backup-directory-alist
      `((".*" . ,temporary-file-directory)))
(setq auto-save-file-name-transforms
      `((".*" ,temporary-file-directory t)))



;screen display and scroll screen
(setq redisplay-dont-pause t
  scroll-margin 3
  scroll-step 1
  scroll-conservatively 10000
  scroll-preserve-screen-position 1)


;disable auto-save
(auto-save-mode nil)

;loading huge file warning
(setq large-file-warning-threshold nil) ;never to request


(set-face-attribute 'default nil :height 130)

;cscope
(require 'xcscope)
;this will enable cscope key bindings
(cscope-setup)

;set c mode tab width to 4
(setq-default c-basic-offset 4
              tab-width 4
              indent-tabs-mode t)


(add-to-list 'auto-mode-alist '("\\.bbclass\\'" . python-mode))
;(electric-indent-mode -1)

;; Set CTRL-v to scroll down 15 lines
(global-set-key (kbd "C-v") (lambda () (interactive) (scroll-up 15)))

;; Set ALT-v to scroll up 15 lines
(global-set-key (kbd "M-v") (lambda () (interactive) (scroll-down 15)))
