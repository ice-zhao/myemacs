;; -*- lexical-binding: t; -*-
(setq emacs-home "/home/ice/installed/emacs/.emacs.d/%s")

(load-file (format emacs-home "init.el"))
(load-file (format emacs-home "ide/basic.el"))
(load-file (format emacs-home "ide/ide.el"))

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(ansi-color-names-vector
   ["black" "red" "green" "yellow" "royal blue" "magenta" "cyan" "white"])
 '(custom-enabled-themes '(tsdh-dark))
 '(custom-safe-themes
   '("0e91d917a613f30bf66da182e919e213ffaba16e9147b84da92204a7635231a5"
	 default))
 '(ecb-options-version "2.50")
 '(grep-find-ignored-files
   '(".#*" "*.o" "*~" "*.bin" "*.lbin" "*.so" "*.a" "*.ln" "*.blg"
	 "*.bbl" "*.elc" "*.lof" "*.glo" "*.idx" "*.lot" "*.fmt" "*.tfm"
	 "*.class" "*.fas" "*.lib" "*.mem" "*.x86f" "*.sparcf" "*.dfsl"
	 "*.pfsl" "*.d64fsl" "*.p64fsl" "*.lx64fsl" "*.lx32fsl"
	 "*.dx64fsl" "*.dx32fsl" "*.fx64fsl" "*.fx32fsl" "*.sx64fsl"
	 "*.sx32fsl" "*.wx64fsl" "*.wx32fsl" "*.fasl" "*.ufsl" "*.fsl"
	 "*.dxl" "*.lo" "*.la" "*.gmo" "*.mo" "*.toc" "*.aux" "*.cp"
	 "*.fn" "*.ky" "*.pg" "*.tp" "*.vr" "*.cps" "*.fns" "*.kys"
	 "*.MIT" "*.map" "*.deb" "*.html" "*.zip" "*.cps" "*.fns" "*.kys"
	 "*.pgs" "*.tps" "*.vrs" "*.pyc" "*.pyo" "GTAGS" "GRTAGS" "GPATH"
	 "tags" "cscope.*" "BROWSE" ".emacs.desktop" "ctags"
	 ".tmp_System.map" ".tmp_vmlinux*" "vmlinux" "ctags" "ID"
	 "bookmark" "*.out" "*.elf" "*.opp" "DCS" "DPS" "*.so*" "*.img"
	 "*.rst" "*test*" "*.asm" "*.md" "*Test*"))
 '(package-selected-packages nil))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:family "JetBrains Mono" :foundry "unknown" :slant normal :weight normal :height 150 :width normal))))
 '(comint-highlight-prompt ((t nil)))
 '(ebrowse-root-class ((t (:foreground "deep sky blue" :weight bold))))
 '(font-lock-comment-face ((t (:foreground "gray"))))
 '(font-lock-function-name-face ((t (:foreground "yellow green"))))
 '(font-lock-type-face ((t (:foreground "light salmon"))))
 '(helm-ff-directory ((t (:extend t :foreground "deep sky blue"))))
 '(helm-grep-file ((t (:foreground "sky blue" :underline t))))
 '(helm-selection ((t (:background "dark slate gray" :distant-foreground "dim gray"))))
 '(helm-source-header ((t (:background "#22083397778B" :foreground "white" :weight bold :height 0.9 :family "Sans Serif"))))
 '(highlight-current-line-face ((t (:background "dim gray"))))
 '(term-color-blue ((t (:background "royal blue" :foreground "royal blue")))))

(load-file (format emacs-home "ide/frame_set.el"))
