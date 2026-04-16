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

(declare-function vterm-send-string "vterm")
(declare-function vterm-send-return "vterm")
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
      (require 'magit)
      (let ((default-directory worktree-dir))
        (magit-status-setup-buffer worktree-dir))
      (emacs-kit/claude-chat t)
      (when (and task (not (string-empty-p task)))
        (run-at-time 2 nil
                     (lambda (dir input)
                       (let ((buf (format "*claude:%s*"
                                         (file-name-nondirectory
                                          (directory-file-name dir)))))
                         (when-let* ((b (get-buffer buf)))
                           (with-current-buffer b
                             (vterm-send-string input)
                             (vterm-send-return)))))
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
              (vterm-send-string message)
              (vterm-send-return))
            (pop-to-buffer buf))
        (user-error "No running Claude session found in %s" claude-buf))))

  (defun emacs-kit/conductor--current-worktree-dir ()
    "Return the worktree directory for the current perspective, or nil."
    (let ((persp (persp-current-name)))
      (cdr (assoc persp (emacs-kit/conductor--worktree-dirs)))))

  (defun emacs-kit/conductor--find-worktree-in (dir)
    "Find the first git worktree directory under DIR."
    (catch 'found
      (dolist (entry (directory-files dir t "\\`[^.]"))
        (when (file-directory-p entry)
          (if (file-exists-p (expand-file-name ".git" entry))
              (throw 'found entry)
            ;; Check one level deeper for slash-branched worktrees
            (dolist (sub (directory-files entry t "\\`[^.]"))
              (when (and (file-directory-p sub)
                         (file-exists-p (expand-file-name ".git" sub)))
                (throw 'found sub))))))))

  (defun emacs-kit/conductor--worktree-dirs ()
    "Return alist of (BRANCH . DIR) for all worktrees under ~/.worktrees.
Uses `git worktree list' to find worktrees, filtering to those in ~/.worktrees."
    (let ((base (expand-file-name "~/.worktrees/"))
          results)
      (when (file-directory-p base)
        (dolist (repo-dir (directory-files base t "\\`[^.]"))
          (when (file-directory-p repo-dir)
            ;; Find any worktree to run git from
            (when-let* ((sample-wt (emacs-kit/conductor--find-worktree-in repo-dir)))
              (with-temp-buffer
                (let ((default-directory sample-wt))
                  (when (zerop (call-process "git" nil t nil
                                             "worktree" "list" "--porcelain"))
                    (goto-char (point-min))
                    (let (wt-path wt-branch)
                      (while (not (eobp))
                        (let ((line (buffer-substring-no-properties
                                     (line-beginning-position) (line-end-position))))
                          (cond
                           ((string-prefix-p "worktree " line)
                            (setq wt-path (substring line 9)))
                           ((string-prefix-p "branch refs/heads/" line)
                            (setq wt-branch (substring line 18)))
                           ((string-empty-p line)
                            (when (and wt-path wt-branch
                                       (string-prefix-p base wt-path))
                              (push (cons wt-branch wt-path) results))
                            (setq wt-path nil wt-branch nil))))
                        (forward-line 1))
                      ;; Handle last entry if no trailing blank line
                      (when (and wt-path wt-branch
                                 (string-prefix-p base wt-path))
                        (push (cons wt-branch wt-path) results))))))))))
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
      (require 'magit)
      (let ((default-directory worktree-dir))
        (magit-status-setup-buffer worktree-dir))
      (emacs-kit/claude-chat t)))

  (defun emacs-kit/conductor-resume-all ()
    "Resume all existing worktrees as conductor workspaces."
    (interactive)
    (require 'magit)
    (let ((worktrees (emacs-kit/conductor--worktree-dirs)))
      (unless worktrees
        (user-error "No worktrees found in ~/.worktrees"))
      (dolist (wt worktrees)
        (let ((branch (car wt))
              (dir (cdr wt)))
          (persp-switch branch)
          (let ((default-directory dir))
            (magit-status-setup-buffer dir))
          (emacs-kit/claude-chat t)))
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
        (persp-switch "main")
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

  ;; --- Agent State ---

  (defvar emacs-kit/conductor--events-file
    (expand-file-name "~/.claude/agent-control-events.jsonl"))

  (defun emacs-kit/conductor--agent-states ()
    "Read latest agent state per cwd from the events JSONL file.
Returns a hash table mapping cwd to the latest state string."
    (let ((states (make-hash-table :test 'equal)))
      (when (file-readable-p emacs-kit/conductor--events-file)
        (with-temp-buffer
          ;; Read last 200 lines — enough to cover recent state for all sessions
          (let ((coding-system-for-read 'utf-8))
            (call-process "tail" nil t nil "-n" "200"
                          emacs-kit/conductor--events-file))
          (goto-char (point-min))
          (while (not (eobp))
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position) (line-end-position))))
              (unless (string-empty-p line)
                (condition-case nil
                    (let* ((event (json-parse-string line :object-type 'alist))
                           (cwd (alist-get 'cwd event))
                           (transition (alist-get 'state_transition event))
                           (new-state (alist-get 'new_state transition)))
                      (when (and cwd new-state)
                        (puthash cwd new-state states)))
                  (error nil))))
            (forward-line 1))))
      states))

  ;; --- Dashboard ---

  (defvar emacs-kit/conductor-dashboard-mode-map
    (let ((map (make-sparse-keymap)))
      (define-key map (kbd "r") #'emacs-kit/conductor-dashboard)
      (define-key map (kbd "RET") #'emacs-kit/conductor-dashboard-open)
      (define-key map (kbd "R") #'emacs-kit/conductor-dashboard-resume)
      (define-key map (kbd "D") #'emacs-kit/conductor-dashboard-delete)
      map))

  (defvar emacs-kit/conductor--refresh-timer nil)
  (defvar emacs-kit/conductor--prev-states (make-hash-table :test 'equal))
  (defvar emacs-kit/conductor--newly-idle nil)

  (define-derived-mode emacs-kit/conductor-dashboard-mode tabulated-list-mode
    "Conductor"
    "Major mode for the Conductor workspace dashboard."
    (setq tabulated-list-format [(" " 2 nil)
                                 ("Workspace" 30 t)
                                 ("Repo" 20 t)
                                 ("Claude" 10 t)
                                 ("Perspective" 12 t)
                                 ("Path" 0 t)])
    (setq tabulated-list-sort-key '("Workspace"))
    (tabulated-list-init-header)
    (add-hook 'kill-buffer-hook #'emacs-kit/conductor--stop-refresh nil t))

  (defun emacs-kit/conductor--workspace-entries ()
    "Build tabulated-list entries for all conductor workspaces."
    (let ((worktrees (emacs-kit/conductor--worktree-dirs))
          (active-persps (persp-names))
          (agent-states (emacs-kit/conductor--agent-states))
          entries)
      (dolist (wt worktrees)
        (let* ((branch (car wt))
               (dir (cdr wt))
               (repo (file-name-nondirectory
                      (directory-file-name (file-name-directory dir))))
               (claude-buf (format "*claude:%s*" branch))
               (has-process (and (get-buffer claude-buf)
                                 (get-buffer-process (get-buffer claude-buf))))
               (agent-state (gethash dir agent-states))
               (status (cond
                        ((equal agent-state "running") "working")
                        ((equal agent-state "waiting_for_input") "idle")
                        ((equal agent-state "ended") "ended")
                        (has-process "active")
                        (t "off")))
               (persp-status (if (member branch active-persps) "active" ""))
               (indicator (cond
                           ((member branch emacs-kit/conductor--newly-idle)
                            (propertize "\u25cf" 'face '(:foreground "#a6e3a1")))
                           ((equal status "working")
                            (propertize "\u25cf" 'face '(:foreground "#f9e2af")))
                           (t ""))))
          (push (list branch
                      (vector indicator branch repo status persp-status
                              (abbreviate-file-name dir)))
                entries)))
      (nreverse entries)))

  (defun emacs-kit/conductor--detect-transitions (entries)
    "Update newly-idle list based on state transitions in ENTRIES."
    (dolist (entry entries)
      (let* ((branch (car entry))
             (status (aref (cadr entry) 2))
             (prev (gethash branch emacs-kit/conductor--prev-states)))
        (when (and (equal status "idle") (equal prev "working"))
          (cl-pushnew branch emacs-kit/conductor--newly-idle :test #'equal))
        (puthash branch status emacs-kit/conductor--prev-states))))

  (defun emacs-kit/conductor--clear-at-point ()
    "Clear the newly-idle indicator for the workspace at point."
    (when-let* ((branch (tabulated-list-get-id)))
      (setq emacs-kit/conductor--newly-idle
            (delete branch emacs-kit/conductor--newly-idle))))

  (defun emacs-kit/conductor--refresh-if-visible ()
    "Refresh the dashboard if it's visible in a window."
    (when-let* ((buf (get-buffer "*Conductor*"))
                ((get-buffer-window buf t)))
      (with-current-buffer buf
        (let ((pos (point)))
          (setq tabulated-list-entries (emacs-kit/conductor--workspace-entries))
          (emacs-kit/conductor--detect-transitions tabulated-list-entries)
          (tabulated-list-print t)
          (goto-char (min pos (point-max)))))))

  (defun emacs-kit/conductor--stop-refresh ()
    "Stop the dashboard auto-refresh timer."
    (when emacs-kit/conductor--refresh-timer
      (cancel-timer emacs-kit/conductor--refresh-timer)
      (setq emacs-kit/conductor--refresh-timer nil)))

  (defun emacs-kit/conductor-dashboard ()
    "Open the Conductor workspace dashboard."
    (interactive)
    (let ((buf (get-buffer-create "*Conductor*")))
      (with-current-buffer buf
        (emacs-kit/conductor-dashboard-mode)
        (setq tabulated-list-entries (emacs-kit/conductor--workspace-entries))
        (tabulated-list-print t))
      (pop-to-buffer buf)
      ;; Start auto-refresh every 5 seconds
      (emacs-kit/conductor--stop-refresh)
      (setq emacs-kit/conductor--refresh-timer
            (run-with-timer 5 5 #'emacs-kit/conductor--refresh-if-visible))))

  (defun emacs-kit/conductor-dashboard--branch ()
    "Get the branch name at point in the dashboard."
    (or (tabulated-list-get-id)
        (user-error "No workspace at point")))

  (defun emacs-kit/conductor-dashboard-open ()
    "Switch to the perspective for the workspace at point."
    (interactive)
    (emacs-kit/conductor--clear-at-point)
    (let ((branch (emacs-kit/conductor-dashboard--branch)))
      (if (member branch (persp-names))
          (persp-switch branch)
        (emacs-kit/conductor-resume-workspace branch))))

  (defun emacs-kit/conductor-dashboard-resume ()
    "Resume the workspace at point."
    (interactive)
    (emacs-kit/conductor--clear-at-point)
    (emacs-kit/conductor-resume-workspace
     (emacs-kit/conductor-dashboard--branch)))

  (defun emacs-kit/conductor-dashboard-delete ()
    "Delete the workspace at point."
    (interactive)
    (let ((branch (emacs-kit/conductor-dashboard--branch)))
      (emacs-kit/conductor-delete-workspace branch)
      (emacs-kit/conductor-dashboard)))

  (defun emacs-kit/conductor-shell ()
    "Open a vterm shell in the current workspace's worktree directory."
    (interactive)
    (require 'vterm)
    (let* ((dir (or (vc-root-dir) default-directory))
           (name (file-name-nondirectory (directory-file-name dir)))
           (vterm-buffer-name (format "*shell:%s*" name))
           (existing (get-buffer vterm-buffer-name)))
      (if (and existing (get-buffer-process existing))
          (pop-to-buffer existing)
        (when (and existing (not (get-buffer-process existing)))
          (kill-buffer existing))
        (let ((default-directory dir))
          (vterm vterm-buffer-name)))))

  ;; --- Workspace-aware wrappers ---

  (defun emacs-kit/conductor-workspace-claude ()
    "Open Claude chat in the current workspace's directory."
    (interactive)
    (let ((default-directory (or (emacs-kit/conductor--current-worktree-dir)
                                 default-directory)))
      (emacs-kit/claude-chat t)))

  (defun emacs-kit/conductor-workspace-shell ()
    "Open a shell in the current workspace's directory."
    (interactive)
    (let ((default-directory (or (emacs-kit/conductor--current-worktree-dir)
                                 default-directory)))
      (emacs-kit/conductor-shell)))

  (defun emacs-kit/conductor-workspace-magit ()
    "Open magit in the current workspace's directory."
    (interactive)
    (require 'magit)
    (let* ((dir (or (emacs-kit/conductor--current-worktree-dir)
                    default-directory)))
      (magit-status-setup-buffer dir)))

  ;; --- Transient Menu ---

  (require 'transient)

  (transient-define-prefix emacs-kit/conductor ()
    "Conductor workspace orchestration."
    ["Workspaces"
     ("w" "New workspace" emacs-kit/conductor-new-workspace)
     ("W" "Resume workspace" emacs-kit/conductor-resume-workspace)
     ("a" "Resume all" emacs-kit/conductor-resume-all)
     ("d" "Dashboard" emacs-kit/conductor-dashboard)
     ("Q" "Delete workspace" emacs-kit/conductor-delete-workspace)]
    ["Current workspace"
     ("c" "Claude chat" emacs-kit/conductor-workspace-claude)
     ("t" "Shell" emacs-kit/conductor-workspace-shell)
     ("g" "Magit" emacs-kit/conductor-workspace-magit)
     ("r" "Comment on diff" emacs-kit/conductor-comment-on-diff)])

  (global-set-key (kbd "C-c c") #'emacs-kit/conductor)

  (with-eval-after-load 'magit-diff
    (define-key magit-diff-mode-map (kbd "C-c C-r") #'emacs-kit/conductor-comment-on-diff))
  (with-eval-after-load 'magit
    (define-key magit-status-mode-map (kbd "C-c C-r") #'emacs-kit/conductor-comment-on-diff)))

(provide 'emacs-kit-conductor)
;;; emacs-kit-conductor.el ends here
