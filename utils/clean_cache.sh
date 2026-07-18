#!/bin/bash
base_dir="/home/ice/installed/emacs"
cache_dir="${base_dir}/.cache"

rm -rf ${cache_dir}/*
rm -rf ${base_dir}/.emacs.d/recentf
rm -rf ${base_dir}/.emacs.d/projectile.cache
rm -rf ${base_dir}/.emacs.d/projectile-bookmarks.eld
rm -rf ${base_dir}/.emacs.d/.dap-breakpoints
rm -rf ${base_dir}/.emacs.d/.lsp-session-v1
rm -rf ${base_dir}/.emacs.d/auto-save-list/
rm -rf ${base_dir}/.emacs.d/semanticdb/*
rm -rf ${base_dir}/.emacs.d/snippets/*
rm -rf ${base_dir}/.emacs.d/tramp
rm -rf ${base_dir}/.emacs.d/projectile-frecency.eld
rm -rf ${base_dir}/.python_history
rm -rf ${base_dir}/.emacs.d/eln-cache/*
rm -rf ${base_dir}/.emacs.d/eshell/*
