;;; core-lib.el

(require 'cl-lib)
(eval-when-compile
  (require 'subr-x))

;; I don't use use-package for these to save on the `fboundp' lookups it does
;; for its :commands property.
(mapc (lambda (sym) (autoload sym "async"))
      '(async-start async-start-process async-byte-recompile-directory))

(mapc (lambda (sym) (autoload sym "persistent-soft"))
      '(persistent-soft-exists-p persistent-soft-fetch persistent-soft-flush persistent-soft-store))

(mapc (lambda (sym) (autoload sym "s"))
      '(s-trim s-trim-left s-trim-right s-chomp s-collapse-whitespace s-word-wrap
        s-center s-pad-left s-pad-right s-truncate s-left s-right s-chop-suffix
        s-chop-suffixes s-chop-prefix s-chop-prefixes s-shared-start s-shared-end
        s-repeat s-concat s-prepend s-append s-lines s-match s-match-strings-all
        s-matched-positions-all s-slice-at s-split s-split-up-to s-join s-equals?
        s-less? s-matches? s-blank? s-present? s-ends-with? s-starts-with? s-contains?
        s-lowercase? s-uppercase? s-mixedcase? s-capitalized? s-numeric? s-replace
        s-replace-all s-downcase s-upcase s-capitalize s-titleize s-with s-index-of
        s-reverse s-presence s-format s-lex-format s-count-matches s-wrap s-split-words
        s-lower-camel-case s-upper-camel-case s-snake-case s-dashed-words
        s-capitalized-words s-titleized-words s-word-initials))


;;
;; Library
;;

(defmacro @λ (&rest body)
  "A shortcut for inline interactive lambdas."
  (declare (doc-string 1))
  `(lambda () (interactive) ,@body))

(defmacro @after (feature &rest forms)
  "A smart wrapper around `with-eval-after-load'. Supresses warnings during
compilation."
  (declare (indent defun) (debug t))
  `(,(if (or (not (boundp 'byte-compile-current-file))
             (not byte-compile-current-file)
             (if (symbolp feature)
                 (require feature nil :no-error)
               (load feature :no-message :no-error)))
         'progn
       'with-no-warnings)
    (with-eval-after-load ',feature ,@forms)))

(defmacro @quiet (&rest forms)
  "Run FORMS without making any noise."
  `(progn
     (fset 'doom--old-write-region-fn (symbol-function 'write-region))
     (cl-letf ((standard-output (lambda (&rest _)))
               ((symbol-function 'load-file) (lambda (file) (load file nil t)))
               ((symbol-function 'message) (lambda (&rest _)))
               ((symbol-function 'write-region)
                (lambda (start end filename &optional append visit lockname mustbenew)
                  (unless visit (setq visit 'no-message))
                  (doom--old-write-region-fn
                   start end filename append visit lockname mustbenew)))
               (inhibit-message t)
               (save-silently t))
       ,@forms)))

(defmacro @add-hook (hook &rest func-or-forms)
  "A convenience macro for `add-hook'.

HOOK can be one hook or a list of hooks. If the hook(s) are not quoted, -hook is
appended to them automatically. If they are quoted, they are used verbatim.

FUNC-OR-FORMS can be a quoted symbol, a list of quoted symbols, or forms. Forms
will be wrapped in a lambda. A list of symbols will expand into a series of
add-hook calls.

Examples:
    (@add-hook 'some-mode-hook 'enable-something)
    (@add-hook some-mode '(enable-something and-another))
    (@add-hook '(one-mode-hook second-mode-hook) 'enable-something)
    (@add-hook (one-mode second-mode) 'enable-something)
    (@add-hook (one-mode second-mode) (setq v 5) (setq a 2))"
  (declare (indent defun) (debug t))
  (unless func-or-forms
    (error "@add-hook: FUNC-OR-FORMS is empty"))
  (let* ((val (car func-or-forms))
         (quoted-p (eq (car-safe hook) 'quote))
         (hook (if quoted-p (cadr hook) hook))
         (funcs (if (eq (car-safe val) 'quote)
                    (if (cdr-safe (cadr val))
                        (cadr val)
                      (list (cadr val)))
                  (list func-or-forms)))
         forms)
    ;; Maybe use `cl-loop'?
    (dolist (fn funcs)
      (setq fn (if (symbolp fn) `(quote ,fn) `(lambda (&rest _) ,@func-or-forms)))
      (dolist (h (if (listp hook) hook (list hook)))
        (push `(add-hook ',(if quoted-p h (intern (format "%s-hook" h))) ,fn)
              forms)))
    `(progn ,@(reverse forms))))

(defmacro @associate (mode &rest plist)
  "Associate a major or minor mode to certain patterns and project files."
  (declare (indent 1))
  (unless noninteractive
    (let* ((minor (plist-get plist :minor))
           (in    (plist-get plist :in))
           (match (plist-get plist :match))
           (files (plist-get plist :files))
           (pred  (plist-get plist :when)))
      (cond ((or files in pred)
             (when (and files
                        (not (or (listp files)
                                 (stringp files))))
               (user-error "@associate :files expects a string or list of strings"))
             (let ((hook-name (intern (format "doom--init-mode-%s" mode))))
               (macroexp-progn
                (list `(defun ,hook-name ()
                         (when (and ,(if match `(if buffer-file-name (string-match-p ,match buffer-file-name)) t)
                                    (or ,(not files)
                                        (and (boundp ',mode)
                                             (not ,mode)
                                             (doom-project-has-files ,@(if (listp files) files (list files)))))
                                    (or (not ,pred)
                                        (funcall ,pred buffer-file-name)))
                           (,mode 1)))
                      (if (and in (listp in))
                          (macroexp-progn
                           (mapcar (lambda (h) `(add-hook ',h ',hook-name))
                                   (mapcar (lambda (m) (intern (format "%s-hook" m))) in)))
                        `(add-hook 'find-file-hook ',hook-name))))))
            (match
             `(add-to-list ',(if minor 'doom-auto-minor-mode-alist 'auto-mode-alist)
                           (cons ,match ',mode)))
            (t (user-error "@associate invalid rules for mode [%s] (in %s) (match %s) (files %s)"
                           mode in match files))))))

(provide 'core-lib)
;;; core-lib.el ends here
