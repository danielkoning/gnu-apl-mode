;;; -*- lexical-binding: t -*-

(defun gnu-apl--make-trace-buffer-name (varname)
  (format "*gnu-apl trace %s*" varname))

;;;
;;;  gnu-apl-trace-symbols is a list of traced symbols, each element
;;;  has the following structure:
;;;
;;;    ("symbol_name" <buffer>)
;;;

(defun gnu-apl-trace-mode-kill-buffer ()
  (interactive)
  (unless (and (boundp 'gnu-apl-trace-buffer)
               gnu-apl-trace-buffer)
    (error "Not a variable trace buffer"))
  (kill-buffer (current-buffer)))

(defvar gnu-apl-trace-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") 'gnu-apl-trace-mode-kill-buffer)
    map))

(define-derived-mode gnu-apl-trace-mode fundamental-mode "GNU APL Variable"
  "Major mode for live display of variable content"
  (use-local-map gnu-apl-trace-mode-map)
  (read-only-mode 1))

(defun gnu-apl--find-traced-symbol (varname)
  (cl-find varname gnu-apl-trace-symbols :key #'car :test #'string=))

(defun gnu-apl--cleanup-trace-symbol (buffer)
  (with-current-buffer buffer
    (when (boundp 'gnu-apl-trace-symbols)
      (dolist (sym gnu-apl-trace-symbols)
        (when (buffer-live-p (cadr sym))
          (with-current-buffer (cadr sym)
            (when (boundp 'gnu-apl-trace-variable)
              (setq gnu-apl-trace-variable nil))))))))

(defun gnu-apl--trace-buffer-closed ()
  (let ((varname gnu-apl-trace-variable))
    (when varname
      (let ((session (gnu-apl--get-interactive-session-with-nocheck)))
        (when session
          (with-current-buffer session
            (let ((traced (gnu-apl--find-traced-symbol varname)))
              (when traced
                (setq gnu-apl-trace-symbols (cl-remove (car traced) gnu-apl-trace-symbols :key #'car :test #'string=))
                (let ((result (gnu-apl--send-network-command-and-read (format "trace:%s:off" (car traced)))))
                  (unless (and result (string= (car result) "disabled"))
                    (error "Symbol was not traced")))))))))))

(defun gnu-apl--trace-symbol-updated (content)
  (let ((varname (car content)))
    (let ((traced (gnu-apl--find-traced-symbol varname)))
      (when traced
        (with-current-buffer (cadr traced)
          (let ((inhibit-read-only t))
            (widen)
            (let ((pos (line-number-at-pos (point))))
              (delete-region (point-min) (point-max))
              (dolist (row (cdr content))
                (insert row "\n"))
              (goto-char (point-min))
              (forward-line (1- pos)))))))))

(defun gnu-apl--trace-symbol-erased (varname)
  (let ((traced (gnu-apl--find-traced-symbol varname)))
    (when traced
      (with-current-buffer (cadr traced)
        (setq gnu-apl-trace-variable nil))
      (setq gnu-apl-trace-symbols (cl-remove (car traced) gnu-apl-trace-symbols :key #'car :test #'string=))
      (kill-buffer (cadr traced))))
  (message "Symbol erased: %S" varname))

(defun gnu-apl-trace (varname)
  (interactive (list (gnu-apl--choose-variable "Variable" :variable (gnu-apl--symbol-at-point))))
  (with-current-buffer (gnu-apl--get-interactive-session)
    (let ((traced (gnu-apl--find-traced-symbol varname)))
      (let ((b (if traced
                   (cadr traced)
                 (let ((result (gnu-apl--send-network-command-and-read (format "trace:%s:on" varname))))
                   (cond ((null result)
                          (error "No result"))
                         ((string= (car result) "undefined")
                          (user-error "No such variable"))
                         ((string= (car result) "enabled")
                          (let ((buffer (generate-new-buffer (gnu-apl--make-trace-buffer-name varname))))
                            (with-current-buffer buffer
                              (gnu-apl-trace-mode)
                              (let ((inhibit-read-only t))
                                (set (make-local-variable 'gnu-apl-trace-variable) varname)
                                (set (make-local-variable 'gnu-apl-trace-buffer) t)
                                (add-hook 'kill-buffer-hook 'gnu-apl--trace-buffer-closed nil t)
                                (dolist (row (cdr result))
                                  (insert row "\n"))
                                (goto-char (point-min))))
                            (push (list varname buffer) gnu-apl-trace-symbols)
                            buffer))
                         (t
                          (error "Unexpected response from trace command")))))))
        (switch-to-buffer-other-window b)))))
