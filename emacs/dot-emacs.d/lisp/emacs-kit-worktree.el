;;; emacs-kit-worktree.el --- Git worktree management via VC  -*- lexical-binding: t; -*-
;;
;; Author: Kyle
;; URL: https://github.com/kb/emacs-kit
;; Package-Requires: ((emacs "30.1"))
;; Keywords: vc, tools, convenience
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; Interactive git worktree management commands that integrate with
;; Emacs VC mode.  Provides create, list, remove, and switch
;; operations bound under the `C-x v W' prefix.

;;; Code:

(use-package emacs-kit-worktree
  :ensure nil
  :no-require t
  :defer t
  :init
  (require 'vc-git)
  (require 'cl-lib)

  (defun emacs-kit/worktree--root ()
    "Return the git root directory or signal an error."
    (expand-file-name
     (or (vc-git-root default-directory)
         (user-error "Not in a git repository"))))

  (defun emacs-kit/worktree--list-paths ()
    "Return list of all worktree paths from porcelain output."
    (let ((output (shell-command-to-string
                   (format "git -C %s worktree list --porcelain"
                           (shell-quote-argument (emacs-kit/worktree--root))))))
      (cl-loop for line in (split-string output "\n" t)
               when (string-prefix-p "worktree " line)
               collect (substring line 9))))

  (defun emacs-kit/worktree--main-path ()
    "Return the main worktree path (first entry in porcelain output)."
    (car (emacs-kit/worktree--list-paths)))

  (defun emacs-kit/worktree-list ()
    "List all git worktrees for the current repo."
    (interactive)
    (let* ((root (emacs-kit/worktree--root))
           (output (shell-command-to-string
                    (format "git -C %s worktree list"
                            (shell-quote-argument root)))))
      (with-output-to-temp-buffer "*Worktrees*"
        (princ (string-trim output)))))

  (defun emacs-kit/worktree-create (path branch)
    "Create a new git worktree at PATH for BRANCH.
If BRANCH doesn't exist, create it."
    (interactive
     (let* ((root (or (vc-git-root default-directory)
                      (user-error "Not in a git repository")))
            (branches (split-string
                       (shell-command-to-string
                        (format "git -C %s branch --format='%%(refname:short)'"
                                (shell-quote-argument root)))
                       "\n" t))
            (branch (completing-read "Branch (existing or new): " branches))
            (repo-name (file-name-nondirectory
                        (directory-file-name root)))
            (default-path (expand-file-name
                           (concat "~/.worktrees/" repo-name "/" branch)))
            (path (read-directory-name "Worktree path: " default-path default-path)))
       (list path branch)))
    (let* ((root (expand-file-name (vc-git-root default-directory)))
           (expanded-path (expand-file-name path))
           (exists (member branch
                           (split-string
                            (shell-command-to-string
                             (format "git -C %s branch --format='%%(refname:short)'"
                                     (shell-quote-argument root)))
                            "\n" t)))
           (_ (make-directory (file-name-directory expanded-path) t))
           (cmd (if exists
                    (format "git -C %s worktree add %s %s"
                            (shell-quote-argument root)
                            (shell-quote-argument expanded-path)
                            (shell-quote-argument branch))
                  (format "git -C %s worktree add -b %s %s"
                          (shell-quote-argument root)
                          (shell-quote-argument branch)
                          (shell-quote-argument expanded-path)))))
      (if (= 0 (shell-command cmd))
          (progn
            (message "Worktree created: %s [%s]" expanded-path branch)
            (when (y-or-n-p "Open worktree in dired? ")
              (dired expanded-path)))
        (user-error "Failed to create worktree"))))

  (defun emacs-kit/worktree-remove ()
    "Remove a git worktree, selected interactively."
    (interactive)
    (let* ((root (emacs-kit/worktree--root))
           (all-paths (emacs-kit/worktree--list-paths))
           (main (emacs-kit/worktree--main-path))
           (current (expand-file-name (directory-file-name root)))
           (worktrees (cl-remove-if
                       (lambda (p)
                         (let ((norm (expand-file-name (directory-file-name p))))
                           (or (string= norm current)
                               (string= norm (expand-file-name
                                              (directory-file-name main))))))
                       all-paths)))
      (if (null worktrees)
          (user-error "No secondary worktrees to remove")
        (let ((choice (completing-read "Remove worktree: " worktrees nil t)))
          (when (y-or-n-p (format "Remove worktree %s? " choice))
            (with-temp-buffer
              (let ((exit-code (call-process "git" nil t nil
                                             "-C" (expand-file-name root)
                                             "worktree" "remove" choice)))
                (if (= 0 exit-code)
                    (message "Removed worktree: %s" choice)
                  (user-error "Failed to remove worktree: %s"
                              (string-trim (buffer-string)))))))))))

  (defun emacs-kit/worktree-switch ()
    "Switch to another worktree via dired."
    (interactive)
    (let* ((paths (emacs-kit/worktree--list-paths))
           (choice (completing-read "Switch to worktree: " paths nil t)))
      (dired choice)))

  (define-prefix-command 'emacs-kit/worktree-map)
  (keymap-set vc-prefix-map "W" 'emacs-kit/worktree-map)
  (keymap-set emacs-kit/worktree-map "c" #'emacs-kit/worktree-create)
  (keymap-set emacs-kit/worktree-map "l" #'emacs-kit/worktree-list)
  (keymap-set emacs-kit/worktree-map "r" #'emacs-kit/worktree-remove)
  (keymap-set emacs-kit/worktree-map "s" #'emacs-kit/worktree-switch))

(provide 'emacs-kit-worktree)
;;; emacs-kit-worktree.el ends here
