;;; p-mode.el --- Major mode for the P model checker  -*- lexical-binding: t; -*-

;; Copyright (C) 2022  Rudolf Schlatte

;; Author: Rudolf Schlatte <rudi@constantly.at>
;; URL: https://github.com/rudi/p-mode
;; Version: 0.1
;; Package-Requires: ((emacs "28.1") (yasnippet "0.14.0") (transient "0.3"))
;; Keywords: tools, languages

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Major mode for editing files for the P model checker
;; (https://p-org.github.io/P/).

;;; Code:

(require 'yasnippet)
(require 'transient)
(require 'cl-lib)

;;; Customizations
(defgroup p nil
  "Major mode for editing files for the P model checker."
  :group 'languages)

(defcustom p-pc-command "pc"
  "The command to run the P model checker."
  :type 'string
  :risky t)

(defcustom p-override-pascal-file-type nil
  "Toggle to choose whether to associate the `.p' file extension with `p-mode'.
By default, `.p' is associated with files written in the Pascal language."
  :type 'boolean)

(defcustom p-mode-hook (list 'yas-minor-mode-on)
  "Hook run after entering P mode."
  :type 'hook
  :options (list 'yas-minor-mode-on))

;;; Snippets
(defvar p--yas-snippets-dir
  (expand-file-name
   "snippets"
   (file-name-directory
    (cond
     (load-in-progress
      load-file-name)
     ((and (boundp 'byte-compile-current-file)
           byte-compile-current-file)
      byte-compile-current-file)
     (t
      (buffer-file-name)))))
  "Directory containing yasnippet snippets for P.")

;;; Syntax highlighting
(defvar p-mode-syntax-table (copy-syntax-table)
  "Syntax table for `p-mode'.")
(modify-syntax-entry ?/   ". 124" p-mode-syntax-table)
(modify-syntax-entry ?*   ". 23b" p-mode-syntax-table)
(modify-syntax-entry ?\n  ">" p-mode-syntax-table)
(modify-syntax-entry ?\^m ">" p-mode-syntax-table)

(defconst p-keywords
  (regexp-opt
   ;; taken from `While.g4'
   '(
     ;; keywords
     "announce" "as" "assert" "assume" "break" "case" "cold" "continue"
     "default" "defer" "do" "else" "entry" "exit" "foreach" "format" "fun"
     "goto" "halt" "hot" "if" "ignore" "in" "keys" "new" "observes" "on"
     "print" "raise" "receive" "return" "send" "sizeof" "spec" "start"
     "state" "this" "type" "values" "var" "while" "with" "choose"
     ;; module-test-implementation declarations
     "module" "implementation" "test" "refines"
     ;; module constructors
     "compose" "union" "hidee" "hidei" "rename" "safe" "main"
     ;; machine annotations
     "receives" "sends"
     ;; common keywords
     "creates" "to")
   'words)
  "List of P keywords.")

(defconst p-constants
  (regexp-opt
   '("true" "false" "null")
   'words)
  "List of P constants.")

(defconst p-types
  ;; taken from
  ;; https://github.com/p-org/P/blob/master/Src/PCompiler/CompilerCore/Parser/PLexer.g4
  (regexp-opt
   '("any" "bool" "enum" "event" "eventset" "float" "int" "machine" "interface"
     "map" "set" "string" "seq" "data")
   'words)
  "List of P type names.")

;; Naming conventions, as documented in the Sublime mode at
;; https://github.com/p-org/Sublime-P
(defconst p-type-regexp (rx word-start (one-or-more (or word "_")) "Type" word-end))
(defconst p-field-regexp (rx word-start (one-or-more (or word "_")) "V" word-end))
(defconst p-event-regexp (rx word-start "e" (one-or-more (or word "_")) word-end))
(defconst p-machine-regexp (rx word-start (one-or-more (or word "_")) "Machine" word-end))

;; There is no predefined face for events; for maximum compatibility with
;; Emacs themes, start from a predefined face that we don't otherwise use.
(defface p-event-name-face '((default :inherit font-lock-function-name-face))
  "Face for highlighting P event names.")
(defvar p-event-name-face 'p-event-name-face)

(defvar p-font-lock-defaults
  (list
   (cons p-keywords font-lock-keyword-face)
   (cons p-constants font-lock-constant-face)
   (cons p-types font-lock-type-face)

   (cons p-type-regexp font-lock-type-face)
   (cons p-field-regexp font-lock-variable-name-face)
   (cons p-event-regexp p-event-name-face)
   (cons p-machine-regexp font-lock-type-face)
   ())
  "Font lock information for P.")

;;; Support for running various tools
(defvar p--last-tool-run nil
  "Identifies the last tool run on the current model (compiler, checker, ...).
This is used to decide how to parse the `*p-compilation*' buffer
after the tool has finished.")

(defvar p--compiled-model-dlls nil
  "List of DLLs produced by the last successful run of `pc'.")

(defvar p--compiled-model-names nil
  "List of model names produced by the last successful run of `pc'.")

(define-compilation-mode p-compilation-mode "P-compile"
  "A variant of `compilation-mode' used for running P tools."
  (add-hook 'p-compilation-finish-functions
            'p--analyze-tool-output))

(defun p--analyze-tool-output (buffer status)
  "Extract various state information from output of P tools.
Argument BUFFER is the compilation buffer, STATUS is the status;
\"finished\" for successful compilation."
  ;; After `pc', get the name(s) of DLLs containing the compiled models
  ;;   ClientServer -> /Users/rudi/Sync/Source/P/P/Tutorial/1_ClientServer/POutput/netcoreapp3.1/ClientServer.dll
  (cl-case p--last-tool-run
    (:pc
     (setq p--compiled-model-dlls nil
           p--compiled-model-names nil)
     (save-match-data
       (with-current-buffer buffer
         (goto-char (point-min))
         (while (re-search-forward "^\\s-+\\([a-zA-Z0-9_]+\\) -> \\(.+\\.dll\\)$" (point-max) t)
           (let ((model-name (match-string-no-properties 1))
                 (dll-name (match-string-no-properties 2)))
             (when (file-exists-p dll-name)
               (push model-name p--compiled-model-names)
               (push dll-name p--compiled-model-dlls)))
           (goto-char (match-end 0)))))
     (setq p--compiled-model-dlls (nreverse p--compiled-model-dlls)
           p--compiled-model-names (nreverse p--compiled-model-names))
     (unless (member p--current-model-dll p--compiled-model-dlls)
       ;; convenience: set dll to something meaningful, or nil if we didn't
       ;; create any dll
       (setq p--current-model-dll (car p--compiled-model-dlls))))
    (:pmc
     (message "P model checker finished successfully."))))

(defun p--test-cases-from-dll (dll)
  "List all test cases in DLL.
This parses the output of `pmc <dll>'."
  ;; todo use `with-temp-buffer'
  (let ((test-cases nil))
    (with-current-buffer (get-buffer-create "*coyote output*")
      (erase-buffer)
      (call-process "coyote" nil t nil "test" dll)
      (goto-char (point-min))
      (while (re-search-forward "^[a-zA-Z0-9_.]+$" (point-max) t)
        (goto-char (match-end 0))
        (push (match-string-no-properties 0) test-cases)))
    test-cases))

(defun p--run-pc-compiler (&optional _args)
  "Run the compiler."
  (interactive
   (list (transient-args 'p-transient)))
  (transient-set)
  (setq-local compile-command
              (concat p-pc-command " "
                      "-proj:" (expand-file-name p--current-project-file)))
  (setq p--last-tool-run :pc)
  (compilation-start compile-command 'p-compilation-mode))

(defun p--run-pmc (&optional _args)
  "Run the model checker."
  (interactive
   (list (transient-args 'p-transient)))
  (transient-set)
  (setq p--last-tool-run :pmc)
  (setq-local compile-command
              (concat "coyote" " " "test" " "
                      (expand-file-name p--current-model-dll)
                      " " "-m" " " p--current-test-case-from-dll))
  (setq p--last-tool-run :pmc)
  (compilation-start compile-command 'p-compilation-mode)
  ;; prompt user for dll; use content of `p--compiled-model-dlls' for
  ;; suggestions, maybe introduce `p--last-checked-dll' as default

  ;; list test cases in chosen dll via the output of `coyote test foo.dll';
  ;; prompt user for test to run as value of `-m' parameter

  ;; prompt user for number of schedules as value of `-i' parameter
  )

;;; Transient menus
(defvar-local p--current-project-file nil
  "The project file to use for the `-proj:' argument to pc.")

(defvar-local p--current-model-dll nil
  "The model dll to check for pmc.")

(defvar-local p--current-test-case-from-dll nil
  "The test case to use for the `-m' argument to pmc.")

(defvar-local p--number-of-schedules 1
  "The number of schedules to use for the `-i' argument to pmc.")

(transient-define-infix p--project-file (&optional _args)
  :description "Project file"
  :class 'transient-lisp-variable
  :variable 'p--current-project-file
  :key "-p"
  :argument "-proj:"
  :reader (lambda (prompt _initial-input _history)
            (read-file-name
             prompt
             (file-name-directory (or p--current-project-file ""))
             (file-name-nondirectory (or p--current-project-file ""))
             t
             nil)))

(transient-define-infix p--program-dll (&optional _args)
  :description "Compiled dll"
  :class 'transient-lisp-variable
  :variable 'p--current-model-dll
  :key "d"
  :reader (lambda (prompt _initial-input _history)
            ()
            (read-file-name
             prompt
             (file-name-directory (or p--current-model-dll ""))
             (file-name-nondirectory (or p--current-model-dll ""))
             t
             nil)))

(transient-define-infix p--test-case-from-dll (&optional _args)
  :description "Test case"
  :class 'transient-lisp-variable
  :variable 'p--current-test-case-from-dll
  :key "-m"
  :reader (lambda (prompt initial-input history)
            (completing-read prompt
                             (p--test-cases-from-dll p--current-model-dll)
                             nil t initial-input history)))

(defun p--read-integer (prompt initial-input history)
  "Read an integer from the minibuffer, prompting with PROMPT.
INITIAL-INPUT is the default value, HISTORY is the input history."
  (let ((s nil))
    (while (progn
             (setq s (read-from-minibuffer prompt initial-input nil nil history))
             (unless (integerp (setq s (car (ignore-errors (read-from-string s)))))
               (message "Please enter a whole number.")
               (sit-for 1)
               t)))
    s))

(transient-define-infix p--test-case-schedules (&optional _args)
  :description "Number of schedules"
  :class 'transient-lisp-variable
  :variable 'p--number-of-schedules
  :key "-i"
  :reader #'p--read-integer)

(transient-define-prefix p-transient ()
  "Menu of commands for P files."
  ["Compile"
   (p--project-file)
   ("c" "Compile model" p--run-pc-compiler)]
  ["Test"
   (p--program-dll)
   (p--test-case-from-dll)
   (p--test-case-schedules)
   ("t" "Test model" p--run-pmc)])

;;; The major mode itself

;;;###autoload
(define-derived-mode p-mode prog-mode "P"
  "Major mode for editing files for the P model checker."
  :group 'P
  (setq-local comment-use-syntax t
              comment-start "//"
              comment-end ""
              comment-start-skip "//+\\s-*")
  (setq font-lock-defaults (list 'p-font-lock-defaults))
  ;; don't let our missing indentation support mess up the snippets
  (setq-local yas-indent-line 'fixed)
  (unless (member p--yas-snippets-dir yas-snippet-dirs)
    (add-to-list 'yas-snippet-dirs p--yas-snippets-dir t)
    ;; we use an internal function here, but the `yasnippet-snippets' package
    ;; does the same; let's assume this is a de facto public API for now.
    (yas--load-snippet-dirs)))


;; NOTE: Adding ourselves to `auto-mode-alist' would be a bit unfriendly since
;; it shadows the file type association for the existing Pascal mode; make
;; this a user option for now.

(define-key p-mode-map (kbd "C-c C-c") 'p-transient)

;;;###autoload
(when p-override-pascal-file-type
  (add-to-list 'auto-mode-alist '("\\.p\\'" . p-mode)))

(provide 'p-mode)
;;; p-mode.el ends here
