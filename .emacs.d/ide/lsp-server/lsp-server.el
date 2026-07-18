;; -*- lexical-binding: t; -*-
;;skip ALL lsp-mode warning
(add-to-list 'warning-suppress-log-types '(lsp-mode))
(add-to-list 'warning-suppress-types '(lsp-mode))

;;disable semgrep client of lsp server. pip install --user semgrep
(setq lsp-disabled-clients '(semgrep-ls))

;;set the path of clangd binary
(setq lsp-clangd-binary-path (format emacs-home ".cache/lsp/clangd/clangd_16.0.2/bin/clangd"))
