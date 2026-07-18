;; -*- lexical-binding: t; -*-
;; Add Kbuild to the list of files for Makefile mode
(add-to-list 'auto-mode-alist '("Kbuild" . makefile-gmake-mode))
(add-to-list 'auto-mode-alist '("Kbuild\\..*" . makefile-gmake-mode))
;; Associate Makefile.* suffix files with makefile-mode
(add-to-list 'auto-mode-alist '("Makefile\\..*" . makefile-gmake-mode))

(add-to-list 'auto-mode-alist '("\\.lds?\\'" . ld-script-mode))
(add-to-list 'auto-mode-alist '("\\.ldscript\\'" . ld-script-mode))
