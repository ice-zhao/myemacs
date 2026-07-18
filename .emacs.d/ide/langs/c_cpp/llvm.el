;; -*- lexical-binding: t; -*-
;llvm assembly and tablegen syntax highlighting
(setq load-path
	    (cons (expand-file-name (format emacs-home "ide/langs/c_cpp/llvm")) load-path))
(require 'llvm-mode)
(require 'tablegen-mode)
(require 'llvm-mir-mode)
