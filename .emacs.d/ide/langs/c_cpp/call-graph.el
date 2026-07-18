;; -*- lexical-binding: t; -*-
(add-to-list 'load-path (format emacs-home "ide/langs/c_cpp/call-graph"))
(require 'call-graph)
(call-graph) ;; to launch it

(global-set-key (kbd "C-c c g") 'call-graph)
(customize-set-variable 'cg-initial-max-depth 5)

;;Ignore reference which has function name but no `(...)'
(customize-set-variable 'cg-ignore-invalid-reference t)
;;Display function together with its args
(customize-set-variable 'cg-display-func-args t)
;;Avoid truncating Imenu entries
(customize-set-variable 'imenu-max-item-length "Unlimited")
;;Exclude UT/CT directories like /Dummy_SUITE/ /Dummy_Test/
(dolist (filter '("grep -v \"Test/\""
                  "grep -v \"Stub/\""
                  "grep -v \"_SUITE/\""
                  "grep -v \"/test-src/\""
                  "grep -v \"/TestPkg/\""
                  "grep -v \"/unittest/\""
                  "grep -v \"/test_src/\""
                  "grep -v \"/ct/\""))
(add-to-list 'cg-search-filters filter))


;;help doc
;;(define-key map (kbd "e") 'cg-widget-expand-all)
;;(define-key map (kbd "c") 'cg-widget-collapse-all)
;;(define-key map (kbd "p") 'widget-backward)
;;(define-key map (kbd "n") 'widget-forward)
;;(define-key map (kbd "q") 'cg-quit)
;;(define-key map (kbd "+") 'cg-expand)
;;(define-key map (kbd "_") 'cg-collapse)
;;(define-key map (kbd "o") 'cg-goto-file-at-point)
;;(define-key map (kbd "d") 'cg-remove-caller)
;;(define-key map (kbd "l") 'cg-select-caller-location)
;;(define-key map (kbd "r") 'cg-reset-caller-cache)
;;(define-key map (kbd "?") 'cg-help)
;;(define-key map (kbd "<RET>") 'cg-goto-file-at-point)
