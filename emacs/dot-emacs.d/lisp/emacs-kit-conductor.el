;;; emacs-kit-conductor.el --- Orchestrate parallel Claude Code agents  -*- lexical-binding: t; byte-compile-warnings: (not free-vars unresolved); -*-
;;
;; Author: Kyle Bolton
;; Package-Requires: ((emacs "30.1"))
;; Keywords: tools, convenience
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; Conductor-like workflow for Emacs: create isolated git worktree
;; workspaces, launch Claude Code agents in them via EAT, and
;; send diff feedback from magit to running agents.

;;; Code:

(defvar eat-terminal)
(declare-function eat-term-send-string "eat")
(declare-function eat-make "eat")
(declare-function magit-current-section "magit-section")
(declare-function magit-file-at-point "magit-git")
(declare-function magit-run-git "magit-process")
(declare-function persp-switch "perspective")

(use-package emacs-kit-conductor
  :ensure nil
  :no-require t
  :init

  (defun emacs-kit/conductor-new-workspace (branch task)
    "Create an isolated workspace: perspective + git worktree + Claude agent.
BRANCH is the new branch name.  TASK is the initial prompt for Claude."
    (interactive "sBranch name: \nsTask description: ")
    (let* ((repo-root (or (vc-root-dir)
                          (user-error "Not in a git repository")))
           (repo-name (file-name-nondirectory (directory-file-name repo-root)))
           (worktree-dir (expand-file-name
                          (format "~/.worktrees/%s/%s" repo-name branch))))
      ;; Create worktree via git directly to avoid magit side effects
      (let ((default-directory repo-root))
        (unless (zerop (call-process "git" nil nil nil
                                     "worktree" "add" "-b" branch worktree-dir "main"))
          (user-error "Failed to create worktree at %s" worktree-dir)))
      ;; Switch to new perspective, then set up buffers inside it
      (persp-switch branch)
      (find-file worktree-dir)
      (emacs-kit/claude-chat)
      (when (and task (not (string-empty-p task)))
        (run-at-time 2 nil
                     (lambda (dir input)
                       (let ((buf (format "*claude:%s*"
                                         (file-name-nondirectory
                                          (directory-file-name dir)))))
                         (when-let* ((b (get-buffer buf)))
                           (with-current-buffer b
                             (eat-term-send-string eat-terminal "\e[200~")
                             (eat-term-send-string eat-terminal input)
                             (eat-term-send-string eat-terminal "\e[201~")
                             (eat-term-send-string eat-terminal "\r")))))
                     worktree-dir task))))

  (defun emacs-kit/conductor-comment-on-diff ()
    "From a magit diff, send the hunk at point with feedback to Claude."
    (interactive)
    (unless (derived-mode-p 'magit-diff-mode 'magit-status-mode)
      (user-error "Not in a magit diff buffer"))
    (let* ((section (magit-current-section))
           (hunk-text (when section
                        (buffer-substring-no-properties
                         (oref section start) (oref section end))))
           (file (magit-file-at-point))
           (feedback (read-string "Feedback: "))
           (message (format "In %s, regarding this change:\n\n```diff\n%s\n```\n\n%s"
                            (or file "unknown file") hunk-text feedback))
           (claude-buf (format "*claude:%s*"
                               (file-name-nondirectory
                                (directory-file-name (or (vc-root-dir) default-directory))))))
      (if-let* ((buf (get-buffer claude-buf))
                ((get-buffer-process buf)))
          (progn
            (with-current-buffer buf
              (eat-term-send-string eat-terminal "\e[200~")
              (eat-term-send-string eat-terminal message)
              (eat-term-send-string eat-terminal "\e[201~")
              (eat-term-send-string eat-terminal "\r"))
            (pop-to-buffer buf))
        (user-error "No running Claude session found in %s" claude-buf))))

  (global-set-key (kbd "C-c w") #'emacs-kit/conductor-new-workspace)

  (with-eval-after-load 'magit-diff
    (define-key magit-diff-mode-map (kbd "C-c C-r") #'emacs-kit/conductor-comment-on-diff))
  (with-eval-after-load 'magit
    (define-key magit-status-mode-map (kbd "C-c C-r") #'emacs-kit/conductor-comment-on-diff)))

(provide 'emacs-kit-conductor)
;;; emacs-kit-conductor.el ends here
