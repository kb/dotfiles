;;; emacs-kit-ai.el --- AI assistant integration (Ollama, Gemini, Claude)  -*- lexical-binding: t; -*-
;;
;; Author: Rahul Martim Juliato
;; URL: https://github.com/LionyxML/emacs-kit
;; Package-Requires: ((emacs "30.1"))
;; Keywords: tools, convenience
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; Provides interactive functions to launch AI chat sessions
;; (Ollama, Gemini, Claude).  Claude uses `vterm' buffers for
;; robust TUI rendering.  Ollama and Gemini use `eat'.
;; Supports sending selected regions as context.

;;; Code:

(defvar vterm-shell)
(defvar vterm-buffer-name)

(use-package emacs-kit-ai
  :ensure nil
  :no-require t
  :defer t
  :after eat
  :init
  (defun emacs-kit/ollama-run-model ()
    "Run `ollama list`, let the user choose a model.
And open it in `eat'.
If a region is selected, use it as a query.
If a prompt is provided, it's prepended."
    (interactive)
    (let* ((output (shell-command-to-string "ollama list"))
           (models (mapcar (lambda (line) (car (split-string line)))
                           (cdr (split-string output "\n" t))))
           (selected (completing-read "Select Ollama model: " models nil t))
           (region-text (when (use-region-p)
                          (buffer-substring-no-properties (region-beginning)
                                                          (region-end))))
           (prompt (read-string "Ollama Prompt (optional): " nil nil nil)))
      (when (and selected (not (string-empty-p selected)))
        (let* ((body (string-join (delq nil (list prompt region-text)) "\n"))
               (escaped-body (replace-regexp-in-string "\"" "\\\\\"" body))
               (command (format "printf \"%s\" | ollama run %s" escaped-body selected))
               (buf (eat-make (generate-new-buffer-name "ollama") "/bin/sh" nil)))
          (pop-to-buffer buf)
          (run-at-time 0.5 nil
                       (lambda (b cmd)
                         (when (buffer-live-p b)
                           (with-current-buffer b
                             (eat-term-send-string eat-terminal cmd)
                             (eat-term-send-string eat-terminal "\n"))))
                       buf command)))))


  (defun emacs-kit/gemini-chat ()
    "Start a new interactive `gemini` session in an `eat' buffer."
    (interactive)
    (let* ((default-directory (or (vc-root-dir)
                                  (and emacs-kit-ai-scratch-path
                                       (file-directory-p emacs-kit-ai-scratch-path)
                                       emacs-kit-ai-scratch-path)
                                  default-directory))
           (buffer-name (generate-new-buffer-name
                         (format "gemini-chat:%s"
                                 (file-name-nondirectory (directory-file-name default-directory))))))
      (let ((buf (eat-make buffer-name "gemini" nil)))
        (pop-to-buffer buf)
        (with-current-buffer buf
          (setq-local column-number-mode nil)))))

  (defun emacs-kit/claude-chat (&optional dangerously-skip-permissions)
    "Start or reuse an interactive `claude' session in a `vterm' buffer.
  If a region is active, prompt for a query and send the region text
  along with the query to Claude. If a claude buffer for the current
  project already exists with a live process, reuse it. Otherwise,
  start a new session.
  When DANGEROUSLY-SKIP-PERMISSIONS is non-nil, pass that flag to claude."
    (interactive)
    (require 'vterm)
    (let* ((source-file (buffer-file-name))
           (project-root (vc-root-dir))
           (default-directory (or project-root
                                  (and emacs-kit-ai-scratch-path
                                       (file-directory-p emacs-kit-ai-scratch-path)
                                       emacs-kit-ai-scratch-path)
                                  default-directory))
           (file-ref (when source-file
                       (if project-root
                           (file-relative-name source-file project-root)
                         source-file)))
           (file-prefix (when file-ref
                          (format "On file @%s " file-ref)))
           (region-text (when (use-region-p)
                          (buffer-substring-no-properties (region-beginning) (region-end))))
           (query (when region-text
                    (read-string "Prompt about this region: " file-prefix)))
           (initial-input (cond
                           (region-text
                            (format "%s\n\n```\n%s\n```" query region-text))
                           (file-prefix
                            file-prefix)))
           (base-name (format "claude:%s"
                              (file-name-nondirectory (directory-file-name default-directory))))
           (vterm-buffer-name (format "*%s*" base-name))
           (existing-buffer (get-buffer vterm-buffer-name)))
      (if (and existing-buffer
               (buffer-live-p existing-buffer)
               (get-buffer-process existing-buffer))
          ;; Reuse existing buffer — just switch and send input
          (progn
            (pop-to-buffer existing-buffer)
            (when initial-input
              (with-current-buffer existing-buffer
                (vterm-send-string initial-input)
                (vterm-send-return))))
        ;; Kill stale buffer if process is dead
        (when (and existing-buffer (not (get-buffer-process existing-buffer)))
          (kill-buffer existing-buffer))
        ;; Create new session
        (let* ((vterm-shell (concat "claude"
                                    (when dangerously-skip-permissions
                                      " --dangerously-skip-permissions")))
               (vterm-buffer-name vterm-buffer-name)
               (buf (vterm vterm-buffer-name)))
          (pop-to-buffer buf)
          (with-current-buffer buf
            (setq-local column-number-mode nil)
            (when initial-input
              (run-at-time 1 nil
                           (lambda (b input)
                             (when (buffer-live-p b)
                               (with-current-buffer b
                                 (vterm-send-string input)
                                 (vterm-send-return))))
                           buf initial-input)))))))

  (global-set-key (kbd "C-c C-0") #'emacs-kit/claude-chat))

(provide 'emacs-kit-ai)
;;; emacs-kit-ai.el ends here
