;;;; tools.lisp — helpers loaded into every per-worktree swank image at
;;;; bootstrap. The point is to give Claude (via eval_swank) cheap
;;;; primitives for the moves a human gets from slime keybindings:
;;;;
;;;;   eval-form-at  ~  C-x C-e / C-M-x   (eval form at point, see value)
;;;;   reload-form   ~  C-c C-c           (re-eval one defun by name)
;;;;
;;;; Both read from the file using the live image's reader, so reader
;;;; macros, #|...|#, #\(, #+feature etc. all work — no second
;;;; source-of-truth for "what's a form."
;;;;
;;;; Lives in its own package (`claude-tools`) so it can't collide with
;;;; symbols project code might intern in cl-user. Call sites are
;;;; (claude-tools:eval-form-at ...) / (claude-tools:reload-form ...) —
;;;; spell out the package, no nickname, since `clt` is opaque enough
;;;; that the savings aren't worth it.

(defpackage #:claude-tools
  (:use #:cl)
  (:export #:eval-form-at
           #:reload-form))

(in-package #:claude-tools)

(defun eval-form-at (file line &optional (col 0))
  "Read the form starting at FILE:LINE:COL and eval it. Returns the value.

   LINE is 1-based (matches editor + ripgrep conventions). COL is
   0-based and counts characters into the line *after* line skipping.
   With COL omitted, reads from the start of LINE — leading whitespace
   is fine, since the reader skips it before consuming the form.

   The form is read with the current *package* and *readtable*; if the
   file lives in a different package, bind *package* yourself before
   calling, e.g. (let ((*package* (find-package :elp)))
                   (clt:eval-form-at ...))."
  (with-open-file (s file)
    (loop repeat (1- line) do (read-line s))
    (loop repeat col do (read-char s))
    (eval (read s))))

(defun reload-form (file name)
  "Find the top-level form in FILE whose head is NAME (a symbol — typically
   the name of a defun/defmacro/defparameter/defvar) and re-eval it.
   Returns the value of the eval, or NIL if no matching form was found.

   When the file contains multiple forms with the same head (e.g. a
   debug-redefinition below the original), the last one wins — matching
   what (load FILE) would have done."
  (with-open-file (s file)
    (let ((match nil))
      (loop for form = (read s nil :eof)
            until (eq form :eof)
            when (and (consp form)
                      (consp (cdr form))
                      (eq (cadr form) name))
              do (setf match form))
      (when match (eval match)))))
