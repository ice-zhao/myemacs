;; -*- lexical-binding: t; -*-
(setq lexical-binding t)
(setq inhibit-startup-message t)
(setq gc-cons-threshold 5000000000)	;;5G
(setq native-comp-async-report-warnings-errors nil)

(require 'package)
(setq package-enable-at-startup nil)
(setq package--init-file-ensured t)
(setq package-archives '(("org"   . "http://orgmode.org/elpa/")
                         ("melpa" . "https://melpa.org/packages/")
                         ("gnu"   . "http://elpa.gnu.org/packages/")))


