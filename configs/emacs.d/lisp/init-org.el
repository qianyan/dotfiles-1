;;; init-org.el --- Set up Org Mode
;;; Commentary:

;; Basic Org Mode configuration, assuming presence of Evil & Evil Leader.

;; Helper functions

(defun air-org-bulk-copy-headlines (&optional strip-tags)
  "Copy the headline text of the marked headlines in an agenda view.

This function is designed to be called interactively from an agenda
view with marked items.

If STRIP-TAGS is not nil, remove tags and trailing spaces from
the headlines."
  (interactive "P")
  (unless org-agenda-bulk-marked-entries (user-error "No entries are marked"))
  (let ((entries "")
        entry)
    (dolist (entry-marker (reverse org-agenda-bulk-marked-entries))
      (with-current-buffer (marker-buffer entry-marker)
        (save-excursion
          (goto-char (marker-position entry-marker))
          (when (re-search-forward org-heading-regexp (line-end-position) t)
            (setq entry (match-string-no-properties 2))
            (if strip-tags
                (setq entry (replace-regexp-in-string
                             (rx (0+ " ")
                                 (0+ (any alpha ":"))
                                 line-end)
                             "" entry)))
            (setq entries (concat entries entry "\n"))))))
    (if (length entries)
        (kill-new entries)))
  (message "Acted on %s entries%s"
           (length org-agenda-bulk-marked-entries)
           (if org-agenda-persistent-marks
               " (kept marked)" ""))
  (unless org-agenda-persistent-marks
    (org-agenda-bulk-unmark-all)))

(defun air-org-agenda-next-header ()
  "Jump to the next header in an agenda series."
  (interactive)
  (air--org-agenda-goto-header))

(defun air-org-agenda-previous-header ()
  "Jump to the previous header in an agenda series."
  (interactive)
  (air--org-agenda-goto-header t))

(defun air--org-agenda-goto-header (&optional backwards)
  "Find the next agenda series header forwards or BACKWARDS."
  (let ((pos (save-excursion
               (goto-char (if backwards
                              (line-beginning-position)
                            (line-end-position)))
               (let* ((find-func (if backwards
                                     'previous-single-property-change
                                   'next-single-property-change))
                      (end-func (if backwards
                                    'max
                                  'min))
                      (all-pos-raw (list (funcall find-func (point) 'org-agenda-structural-header)
                                         (funcall find-func (point) 'org-agenda-date-header)))
                      (all-pos (cl-remove-if-not 'numberp all-pos-raw))
                      (prop-pos (if all-pos (apply end-func all-pos) nil)))
                 prop-pos))))
    (if pos (goto-char pos))
    (if backwards (goto-char (line-beginning-position)))))

(defun air--org-display-tag (tag &optional focus)
  "Display entries tagged with TAG in a fit window.

Do not make the new window current unless FOCUS is set."
  (org-tags-view nil tag)
  (fit-window-to-buffer)
  (unless focus
    (other-window 1)))

(defun air-org-display-directs (&optional focus)
  "Display entries tagged with `direct'.

Do not make the new window current unless FOCUS is set."
  (interactive "P")
  (air--org-display-tag "direct" focus))

(defun air-org-display-managers (&optional focus)
  "Display entries tagged with `manager'.

Do not make the new window current unless FOCUS is set."
  (interactive "P")
  (air--org-display-tag "manager" focus))

(defun air-org-skip-if-not-closed-today (&optional subtree)
  "Skip entries that were not closed today.

Skip the current entry unless SUBTREE is not nil, in which case skip
the entire subtree."
  (let ((end (if subtree (subtree-end (save-excursion (org-end-of-subtree t)))
               (save-excursion (progn (outline-next-heading) (1- (point))))))
        (today-prefix (format-time-string "%Y-%m-%d")))
    (if (save-excursion
          (and (re-search-forward org-closed-time-regexp end t)
               (string= (substring (match-string-no-properties 1) 0 10) today-prefix)))
        nil
      end)))

(defun air-org-skip-if-habit (&optional subtree)
  "Skip an agenda entry if it has a STYLE property equal to \"habit\".

Skip the current entry unless SUBTREE is not nil, in which case skip
the entire subtree."
  (let ((end (if subtree (subtree-end (save-excursion (org-end-of-subtree t)))
                (save-excursion (progn (outline-next-heading) (1- (point)))))))
    (if (string= (org-entry-get nil "STYLE") "habit")
        end
      nil)))

(defun air-org-skip-if-priority (priority &optional subtree)
  "Skip an agenda item if it has a priority of PRIORITY.

PRIORITY may be one of the characters ?A, ?B, or ?C.

Skips the current entry unless SUBTREE is not nil."
  (let ((end (if subtree (subtree-end (save-excursion (org-end-of-subtree t)))
                (save-excursion (progn (outline-next-heading) (1- (point))))))
        (pri-value (* 1000 (- org-lowest-priority priority)))
        (pri-current (org-get-priority (thing-at-point 'line t))))
    (if (= pri-value pri-current)
        end
      nil)))

(defun air--org-global-custom-ids ()
  "Find custom ID fields in all org agenda files."
  (let ((files (org-agenda-files))
        file
        air-all-org-custom-ids)
    (while (setq file (pop files))
      (with-current-buffer (org-get-agenda-file-buffer file)
        (save-excursion
          (save-restriction
            (widen)
            (goto-char (point-min))
            (while (re-search-forward "^[ \t]*:CUSTOM_ID:[ \t]+\\(\\S-+\\)[ \t]*$"
                                      nil t)
              (add-to-list 'air-all-org-custom-ids
                           `(,(match-string-no-properties 1)
                             ,(concat file ":" (number-to-string (line-number-at-pos))))))))))
    air-all-org-custom-ids))

(defun air-org-goto-custom-id ()
  "Go to the location of CUSTOM-ID, or prompt interactively."
  (interactive)
  (let* ((all-custom-ids (air--org-global-custom-ids))
         (custom-id (completing-read
                     "Custom ID: "
                     all-custom-ids)))
    (when custom-id
      (let* ((val (cadr (assoc custom-id all-custom-ids)))
             (id-parts (split-string val ":"))
             (file (car id-parts))
             (line (string-to-int (cadr id-parts))))
        (pop-to-buffer (org-get-agenda-file-buffer file))
        (goto-char (point-min))
        (forward-line line)
        (org-reveal)
        (org-up-element)))))

(defun air-org-insert-custom-id-link ()
  "Insert an Org link to a custom ID selected interactively."
  (interactive)
  (let* ((all-custom-ids (air--org-global-custom-ids))
         (custom-id (completing-read
                     "Custom ID: "
                     all-custom-ids)))
    (when custom-id
      (let* ((val (cadr (assoc custom-id all-custom-ids)))
             (id-parts (split-string val ":"))
             (file (car id-parts))
             (line (string-to-int (cadr id-parts))))
        (org-insert-link nil (concat file "::#" custom-id) custom-id)))))

(defun air-org-nmom-capture-template ()
  "Return a Nine Minutes on Monday weekly agenda template suitable for capture."
  (let* ((deadline-timestamp (format-time-string "<%Y-%m-%d %a>"
                                                 (air-calendar-next-day-of-week 5)))
         (deadline (format "DEADLINE: %s\n\n" deadline-timestamp)))
    (concat (format "* Week %02d\n\n" (org-days-to-iso-week (org-today)))
            (concat "** ☛ TODO Care: \n" deadline
                    "** ☛ TODO Mastery: \n" deadline
                    "** ☛ TODO Recognition: \n" deadline
                    "** ☛ TODO Purpose: \n" deadline))))

(defun air-org-set-category-property (value)
  "Set the category property of the current item to VALUE."
  (interactive (list (org-read-property-value "CATEGORY")))
  (org-set-property "CATEGORY" value))

(defun air-org-insert-heading (&optional subheading)
  "Insert a heading or a subheading.

If the optional SUBHEADING is t, insert a subheading.  Inserting
headings always respects content."
  (interactive "P")
  (if subheading
      (org-insert-subheading t)
    (org-insert-heading t)))

(defun air-org-insert-scheduled-heading (&optional subheading)
  "Insert a new org heading scheduled for today.

Insert the new heading at the end of the current subtree if
FORCE-HEADING is non-nil."
  (interactive "P")
  (if subheading
      (org-insert-subheading t)
    (org-insert-todo-heading t t))
  (org-schedule nil (format-time-string "%Y-%m-%d")))

(defun air-org-task-capture (&optional vanilla)
  "Capture a task with my default template.

If VANILLA is non-nil, run the standard `org-capture'."
  (interactive "P")
  (if vanilla
      (org-capture)
    (org-capture nil "a")))

(defun air-org-agenda-capture (&optional vanilla)
  "Capture a task in agenda mode, using the date at point.

If VANILLA is non-nil, run the standard `org-capture'."
  (interactive "P")
  (if vanilla
      (org-capture)
    (let ((org-overriding-default-time (org-get-cursor-date)))
      (org-capture nil "a"))))

(defun air-org-agenda-toggle-date (current-line)
  "Toggle `SCHEDULED' and `DEADLINE' tag in the capture buffer."
  (interactive "P")
  (save-excursion
    (let ((search-limit (if current-line
                            (line-end-position)
                          (point-max))))

      (if current-line (beginning-of-line)
        (beginning-of-buffer))
      (if (search-forward "DEADLINE:" search-limit t)
          (replace-match "SCHEDULED:")
        (and (search-forward "SCHEDULED:" search-limit t)
             (replace-match "DEADLINE:"))))))

(defun air-pop-to-org-todo (split)
  "Visit my main TODO list, in the current window or a SPLIT."
  (interactive "P")
  (air--pop-to-file "~/Dropbox/org/todo.org" split))

(defun air-pop-to-org-notes (split)
  "Visit my main notes file, in the current window or a SPLIT."
  (interactive "P")
  (air--pop-to-file "~/Dropbox/org/notes.org" split))

(defun air-pop-to-org-vault (split)
  "Visit my encrypted vault file, in the current window or a SPLIT."
  (interactive "P")
  (air--pop-to-file "~/Dropbox/org/vault.gpg" split))

(defun air-pop-to-org-agenda (split)
  "Visit the org agenda, in the current window or a SPLIT."
  (interactive "P")
  (org-agenda nil "d")
  (when (not split)
    (delete-other-windows)))

(defun air--org-insert-list-leader-or-self (char)
  "If on column 0, insert space-padded CHAR; otherwise insert CHAR.

This has the effect of automatically creating a properly indented list
leader; like hyphen, asterisk, or plus sign; without having to use
list-specific key maps."
  (if (= (current-column) 0)
      (insert (concat " " char " "))
    (insert char)))

(defun air--org-swap-tags (tags)
  "Replace any tags on the current headline with TAGS.

The assumption is that TAGS will be a string conforming to Org Mode's
tag format specifications, or nil to remove all tags."
  (let ((old-tags (org-get-tags-string))
        (tags (if tags
                  (concat " " tags)
                "")))
    (save-excursion
      (beginning-of-line)
      (re-search-forward
       (concat "[ \t]*" (regexp-quote old-tags) "[ \t]*$")
       (line-end-position) t)
      (replace-match tags)
      (org-set-tags t))))

(defun air-org-goto-first-child ()
  "Goto the first child, even if it is invisible.

Return t when a child was found.  Otherwise don't move point and
return nil."
  (interactive)
  (let ((pos (point))
        (re (concat "^" outline-regexp))
        level)
    (when (condition-case nil (org-back-to-heading t) (error nil))
      (setq level (outline-level))
      (forward-char 1)
      (if (and (re-search-forward re nil t) (> (outline-level) level))
          (progn (goto-char (match-beginning 0)) t)
        (goto-char pos) nil))))


(defun air-org-set-tags (tag)
  "Add TAG if it is not in the list of tags, remove it otherwise.

TAG is chosen interactively from the global tags completion table."
  (interactive
   (list (let ((org-last-tags-completion-table
                (if (derived-mode-p 'org-mode)
                    (org-uniquify
                     (delq nil (append (org-get-buffer-tags)
                                       (org-global-tags-completion-table))))
                  (org-global-tags-completion-table))))
           (completing-read
            "Tag: " 'org-tags-completion-function nil nil nil
            'org-tags-history))))
  (let* ((cur-list (org-get-tags))
         (new-tags (mapconcat 'identity
                              (if (member tag cur-list)
                                  (delete tag cur-list)
                                (append cur-list (list tag)))
                              ":"))
         (new (if (> (length new-tags) 1) (concat " :" new-tags ":")
                nil)))
    (air--org-swap-tags new)))


;;; Code:
(use-package org
  :ensure t
  :defer t
  :commands (org-capture)
  :bind (("C-c c" .   air-org-task-capture)
         ("C-c l" .   org-store-link)
         ("C-c t n" . air-pop-to-org-notes)
         ("C-c t t" . air-pop-to-org-todo)
         ("C-c t v" . air-pop-to-org-vault)
         ("C-c t a" . air-pop-to-org-agenda)
         ("C-c t A" . org-agenda)
         ("C-c f k" . org-search-view)
         ("C-c f t" . org-tags-view)
         ("C-c f i" . air-org-goto-custom-id))
  :config
  (setq org-hide-emphasis-markers t)
  (setq org-modules
        '(org-bbdb org-bibtex org-docview org-habit org-info org-w3m))
  (setq org-todo-keywords
        '((sequence "☛ TODO" "○ IN-PROGRESS" "⚑ WAITING" "|" "✓ DONE" "✗ CANCELED")))
  (setq org-blank-before-new-entry '((heading . t)
                                     (plain-list-item . t)))
  (setq org-capture-templates
        '(("a" "My TODO task format." entry
           (file "todo.org")
           "* ☛ TODO %?")

          ("n" "A (work-related) note." entry
           (file+headline "notes.org" "Work")
           "* %?\n%u\n\n"
           :jump-to-captured t)

          ("w" "Nine Minutes on Monday weekly agenda." entry
           (id "9A6DDE04-90B8-49ED-90B9-A55A0D1E7B28")
           (function air-org-nmom-capture-template))))
  (setq org-default-notes-file "~/Dropbox/org/todo.org")
  (setq org-directory "~/Dropbox/org")
  (setq org-enforce-todo-dependencies t)

  ;; Logging of state changes
  (setq org-log-done (quote time))
  (setq org-log-redeadline (quote time))
  (setq org-log-reschedule (quote time))
  (setq org-log-into-drawer t)

  (setq org-insert-heading-respect-content t)
  (setq org-ellipsis " …")
  (setq org-startup-with-inline-images t)
  (setq org-export-initial-scope 'subtree)
  (setq org-use-tag-inheritance nil) ;; Use the list form, which happens to be blank

  ;; Agenda configuration
  (setq org-agenda-text-search-extra-files '(agenda-archives))
  (setq org-agenda-files '("~/Dropbox/org/"))
  (setq org-agenda-skip-scheduled-if-done t)
  (setq org-agenda-custom-commands
        '(("d" "Daily agenda and all TODOs"
           ((tags "PRIORITY=\"A\""
                  ((org-agenda-skip-function '(org-agenda-skip-entry-if 'todo 'done))
                   (org-agenda-overriding-header "High-priority unfinished tasks:")))
            (agenda "" ((org-agenda-ndays 1)))
            (alltodo ""
                     ((org-agenda-skip-function '(or (air-org-skip-if-habit)
                                                     (air-org-skip-if-priority ?A)
                                                     (org-agenda-skip-if nil '(scheduled deadline))))
                      (org-agenda-overriding-header "ALL normal priority tasks:")))

            (todo "✓ DONE"
                     ((org-agenda-skip-function 'air-org-skip-if-not-closed-today)
                      (org-agenda-overriding-header "Closed today:"))
                     )
            )
           ((org-agenda-compact-blocks t)))))

  (set-face-attribute 'org-upcoming-deadline nil :foreground "gold1")

  (evil-leader/set-key-for-mode 'org-mode
    "$"  'org-archive-subtree
    "a"  'org-agenda
    "c"  'air-org-set-category-property
    "d"  'org-deadline
    "ns" 'org-narrow-to-subtree
    "p"  'org-set-property
    "s"  'org-schedule
    "t"  'air-org-set-tags)

  (add-hook 'org-agenda-mode-hook
            (lambda ()
              (setq org-habit-graph-column 50)
              (define-key org-agenda-mode-map "H"          'beginning-of-buffer)
              (define-key org-agenda-mode-map "j"          'org-agenda-next-item)
              (define-key org-agenda-mode-map "k"          'org-agenda-previous-item)
              (define-key org-agenda-mode-map "J"          'air-org-agenda-next-header)
              (define-key org-agenda-mode-map "K"          'air-org-agenda-previous-header)
              (define-key org-agenda-mode-map "n"          'org-agenda-next-date-line)
              (define-key org-agenda-mode-map "p"          'org-agenda-previous-date-line)
              (define-key org-agenda-mode-map "c"          'air-org-agenda-capture)
              (define-key org-agenda-mode-map "R"          'org-revert-all-org-buffers)
              (define-key org-agenda-mode-map "y"          'air-org-bulk-copy-headlines)
              (define-key org-agenda-mode-map "/"          'counsel-grep-or-swiper)
              (define-key org-agenda-mode-map (kbd "RET")  'org-agenda-switch-to)

              (define-prefix-command 'air-org-run-shortcuts)
              (define-key air-org-run-shortcuts "f" (tiny-menu-run-item "org-files"))
              (define-key air-org-run-shortcuts "t" (tiny-menu-run-item "org-things"))
              (define-key air-org-run-shortcuts "c" (tiny-menu-run-item "org-captures"))
              (define-key air-org-run-shortcuts "l" (tiny-menu-run-item "org-links"))
              (define-key org-agenda-mode-map (kbd "\\") air-org-run-shortcuts)))

  (add-hook 'org-capture-mode-hook
            (lambda ()
              (evil-define-key '(normal insert) org-capture-mode-map (kbd "C-d") 'air-org-agenda-toggle-date)
              (evil-define-key 'normal org-capture-mode-map "+" 'org-priority-up)
              (evil-define-key 'normal org-capture-mode-map "-" 'org-priority-down)
              (evil-define-key '(normal insert) org-capture-mode-map (kbd "C-=" ) 'org-priority-up)
              (evil-define-key '(normal insert) org-capture-mode-map (kbd "C--" ) 'org-priority-down)
              ;; TODO this seems like a hack
              (evil-insert-state)))

  (add-hook 'org-mode-hook
            (lambda ()
              ;; Special plain list leader inserts
              (dolist (char '("+" "-"))
                (define-key org-mode-map (kbd char)
                  `(lambda ()
                    (interactive)
                    (air--org-insert-list-leader-or-self ,char))))

              ;; Normal maps
              (define-key org-mode-map (kbd "C-c d")   (lambda ()
                                                         (interactive) (air-org-agenda-toggle-date t)))
              (define-key org-mode-map (kbd "C-c ,")   'org-time-stamp-inactive)
              (define-key org-mode-map (kbd "C-|")     'air-org-insert-scheduled-heading)
              (define-key org-mode-map (kbd "C-\\")    'air-org-insert-heading)
              (define-key org-mode-map (kbd "s-r")     'org-revert-all-org-buffers)
              (define-key org-mode-map (kbd "C-c C-l") (tiny-menu-run-item "org-links"))

              (define-key org-mode-map (kbd "C-<")                'org-shiftmetaleft)
              (define-key org-mode-map (kbd "C->")                'org-shiftmetaright)

              ;; These are set as evil keys because they conflict with
              ;; existing commands I don't use, or are superseded by
              ;; some evil function that org-mode-map is shadowed by.
              (evil-define-key 'normal org-mode-map (kbd "TAB")   'org-cycle)

              (evil-define-key 'normal org-mode-map (kbd "C-,")   'org-metaleft)
              (evil-define-key 'normal org-mode-map (kbd "C-.")   'org-metaright)

              (evil-define-key 'insert org-mode-map (kbd "C-,")   'org-metaleft)
              (evil-define-key 'insert org-mode-map (kbd "C-.")   'org-metaright)

              (evil-define-key 'normal org-mode-map (kbd "C-S-l") 'org-shiftright)
              (evil-define-key 'normal org-mode-map (kbd "C-S-h") 'org-shiftleft)

              (evil-define-key 'insert org-mode-map (kbd "C-S-l") 'org-shiftright)
              (evil-define-key 'insert org-mode-map (kbd "C-S-h") 'org-shiftleft)

              ;; Navigation
              (define-key org-mode-map (kbd "M-h") 'org-up-element)
              (define-key org-mode-map (kbd "M-j") 'org-forward-heading-same-level)
              (define-key org-mode-map (kbd "M-k") 'org-backward-heading-same-level)
              (define-key org-mode-map (kbd "M-l") 'air-org-goto-first-child)

              ;; Use fill column, but not in agenda
              (setq fill-column 100)
              (when (not (eq major-mode 'org-agenda-mode))
                (visual-line-mode)
                (visual-fill-column-mode))
              (flyspell-mode)
              (org-indent-mode))))

(use-package org-bullets
  :ensure t
  :config
  (add-hook 'org-mode-hook (lambda () (org-bullets-mode 1)))
  (setq org-bullets-bullet-list '("•")))

(provide 'init-org)
;;; init-org.el ends here
