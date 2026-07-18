;; -*- lexical-binding: t; -*-
(require 'indent-tools)
(global-set-key (kbd "C-c >") 'indent-tools-hydra/body)

(add-hook 'python-mode-hook
	(lambda () (define-key python-mode-map (kbd "C-c >") 'indent-tools-hydra/body))
)
