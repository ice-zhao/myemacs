;; -*- lexical-binding: t; -*-
(setq package-selected-packages '(lsp-mode yasnippet lsp-treemacs helm-lsp
    projectile hydra flycheck company avy which-key helm-xref dap-mode helm-swoop))

(when (cl-find-if-not #'package-installed-p package-selected-packages)
  (package-refresh-contents)
  (mapc #'package-install package-selected-packages))

(use-package lsp-mode
  :init
  ;; set prefix for lsp-command-keymap (few alternatives - "C-l", "C-c l")
  (setq lsp-keymap-prefix "C-c l")
  :hook (;; replace XXX-mode with concrete major-mode(e. g. python-mode)
         (XXX-mode . lsp)
         (python-mode . lsp-deferred)
         ;; if you want which-key integration
         (lsp-mode . lsp-enable-which-key-integration))
  :commands lsp)

(helm-mode)
(require 'helm-xref)
(define-key global-map [remap find-file] #'helm-find-files)
(define-key global-map [remap execute-extended-command] #'helm-M-x)
(define-key global-map [remap switch-to-buffer] #'helm-mini)

(which-key-mode)
(add-hook 'c-mode-hook 'lsp)
(add-hook 'c++-mode-hook 'lsp)

(setq read-process-output-max (* 1024 3072)
      treemacs-space-between-root-nodes nil
      company-idle-delay 0.0
	  lsp-file-watch-threshold 5000		;;file watch warning threshold
	  lsp-use-plists t	;;Use plists for deserialization.
      company-minimum-prefix-length 1
      lsp-idle-delay 0.0)  ;; clangd is fast

(with-eval-after-load 'lsp-mode
  (add-hook 'lsp-mode-hook #'lsp-enable-which-key-integration)
  (require 'dap-cpptools)
  (yas-global-mode))

;disable cursor hover (keep mouse hover)
(setq lsp-ui-doc-show-with-cursor nil)

;disable mouse hover (keep cursor hover)
(setq lsp-ui-doc-show-with-mouse nil)

;Flycheck
(setq lsp-diagnostics-provider :none)


;Increase the amount of data which Emacs reads from the LSP process in [800k,3M] range.
;(setq read-process-output-max (* 1024 3072)) ;; 3MB
;(setq lsp-idle-delay 0.500) ;;how often lsp-mode will refresh the highlights, lenses, links, etc while you type
(setq lsp-log-io nil) ;logging is switched off

;(setq lsp-enable-symbol-highlighting nil) ;disable symbol highlight
(setq lsp-enable-indentation nil); disable indentation region

;;exclude folders from file watcher
(with-eval-after-load 'lsp-mode
  ;;(add-to-list 'lsp-file-watch-ignored-directories "[/\\\\]\\.my-folder\\'")
  (add-to-list 'lsp-file-watch-ignored-directories "[/\\\\]Documentation\\'")
  ;; or
  (add-to-list 'lsp-file-watch-ignored-files "[/\\\\]\\..*\\'")
  (add-to-list 'lsp-file-watch-ignored-files "[/\\\\]*\\.o\\'"))

;;enable paramters name hint
;;(setq lsp-inlay-hint-enable t)

;;reference https://emacs-lsp.github.io/lsp-mode/tutorials/how-to-turn-off/
;;lsp-ui-doc - on hover dialogs. * disable
(setq lsp-ui-doc-enable nil)
;;disable cursor hover (keep mouse hover)
(setq lsp-ui-doc-show-with-cursor nil)
;;Lenses
(setq lsp-lens-enable nil)
;;Sideline code actions * disable whole sideline
(setq lsp-ui-sideline-enable nil)
;;hide code actions
(setq lsp-ui-sideline-show-code-actions nil)
;;Modeline code actions
(setq lsp-modeline-code-actions-enable nil)
;;Flycheck
(setq lsp-diagnostics-provider :none)
;;Eldoc
;;(setq lsp-eldoc-enable-hover nil)
;;Modeline diagnostics statistics
(setq lsp-modeline-diagnostics-enable nil)
;;Signature help documentation(keep the signatures)
(setq lsp-signature-render-documentation nil)

(global-set-key (kbd "C-c l g b") 'xref-go-back)
