;; -*- lexical-binding: t; -*-
;disable tool bar mode
(tool-bar-mode -1)

;disable menu bar mode
(menu-bar-mode -1)

;; show line and column numbers in mode line
(line-number-mode 1)
(column-number-mode 1)

;;set cursor color
(set-cursor-color "white")

;set mode bar's height
(set-face-attribute 'mode-line nil :height 160)

;change scroll-bar to right side
(custom-set-variables '(scroll-bar-mode 'right))


