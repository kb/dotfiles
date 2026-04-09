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
      ;; Register with project.el and switch to new perspective
      (project-remember-project (project-current nil worktree-dir))
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

  (defun emacs-kit/conductor--worktree-dirs ()
    "Return alist of (BRANCH . DIR) for all worktrees under ~/.worktrees."
    (let ((base (expand-file-name "~/.worktrees"))
          results)
      (when (file-directory-p base)
        (dolist (repo (directory-files base t "\\`[^.]"))
          (when (file-directory-p repo)
            (dolist (branch (directory-files repo t "\\`[^.]"))
              (when (and (file-directory-p branch)
                         (file-exists-p (expand-file-name ".git" branch)))
                (push (cons (file-name-nondirectory branch) branch)
                      results))))))
      (nreverse results)))

  (defun emacs-kit/conductor-resume-workspace (branch)
    "Resume an existing worktree as a conductor workspace.
Opens a perspective with dired and Claude Code for the selected worktree."
    (interactive
     (let ((worktrees (emacs-kit/conductor--worktree-dirs)))
       (unless worktrees
         (user-error "No worktrees found in ~/.worktrees"))
       (list (completing-read "Resume workspace: "
                              (mapcar #'car worktrees) nil t))))
    (let* ((worktrees (emacs-kit/conductor--worktree-dirs))
           (worktree-dir (cdr (assoc branch worktrees))))
      (unless worktree-dir
        (user-error "Worktree not found: %s" branch))
      (persp-switch branch)
      (find-file worktree-dir)
      (emacs-kit/claude-chat)))

  (defun emacs-kit/conductor-resume-all ()
    "Resume all existing worktrees as conductor workspaces."
    (interactive)
    (let ((worktrees (emacs-kit/conductor--worktree-dirs)))
      (unless worktrees
        (user-error "No worktrees found in ~/.worktrees"))
      (dolist (wt worktrees)
        (let ((branch (car wt))
              (dir (cdr wt)))
          (persp-switch branch)
          (find-file dir)
          (emacs-kit/claude-chat)))
      (message "Resumed %d workspaces" (length worktrees))))

  (defun emacs-kit/conductor-delete-workspace (branch)
    "Delete a conductor workspace: kill perspective, remove worktree, delete branch.
Prompts for confirmation before proceeding."
    (interactive
     (let ((worktrees (emacs-kit/conductor--worktree-dirs)))
       (unless worktrees
         (user-error "No worktrees found in ~/.worktrees"))
       (list (completing-read "Delete workspace: "
                              (mapcar #'car worktrees) nil t))))
    (let* ((worktrees (emacs-kit/conductor--worktree-dirs))
           (worktree-dir (cdr (assoc branch worktrees))))
      (unless worktree-dir
        (user-error "Worktree not found: %s" branch))
      (unless (yes-or-no-p (format "Delete workspace '%s'? (worktree + branch) " branch))
        (user-error "Aborted"))
      ;; Remove from project.el
      (project-forget-project (file-name-as-directory
                               (abbreviate-file-name worktree-dir)))
      ;; Kill the perspective if it exists
      (when (member branch (persp-names))
        (persp-switch branch)
        (persp-kill branch))
      ;; Remove the git worktree
      (let ((repo-root (with-temp-buffer
                         (let ((default-directory worktree-dir))
                           (when (zerop (call-process "git" nil t nil
                                                      "rev-parse" "--path-format=absolute"
                                                      "--git-common-dir"))
                             (file-name-directory
                              (string-trim (buffer-string))))))))
        (when repo-root
          (let ((default-directory repo-root))
            (call-process "git" nil nil nil "worktree" "remove" "--force" worktree-dir)
            (call-process "git" nil nil nil "branch" "-D" branch))))
      (message "Deleted workspace '%s'" branch)))

  (global-set-key (kbd "C-c w") #'emacs-kit/conductor-new-workspace)
  (global-set-key (kbd "C-c W") #'emacs-kit/conductor-resume-workspace)
  (global-set-key (kbd "C-c Q") #'emacs-kit/conductor-delete-workspace)

  (with-eval-after-load 'magit-diff
    (define-key magit-diff-mode-map (kbd "C-c C-r") #'emacs-kit/conductor-comment-on-diff))
  (with-eval-after-load 'magit
    (define-key magit-status-mode-map (kbd "C-c C-r") #'emacs-kit/conductor-comment-on-diff)))

(provide 'emacs-kit-conductor)
;;; emacs-kit-conductor.el ends here
