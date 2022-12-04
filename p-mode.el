;;; p-mode.el --- Major mode for the P model checker  -*- lexical-binding: t; -*-

;; Copyright (C) 2022  Rudolf Schlatte

;; Author: Rudolf Schlatte <rudi@constantly.at>
;; URL: https://github.com/rudi/p-mode
;; Version: 0.1
;; Package-Requires: ((emacs "28.1") (yasnippet "0.14.0"))
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

;; Customizations
(defgroup P nil
  "Major mode for editing files for the P model checker.")

(defcustom p-override-pascal-file-type nil
  "Toggle to choose whether to associate the `.P' file extension with `p-mode'.
By default, `.P' is associated with files written in the Pascal language.")

(defcustom p-mode-hook (list 'yas-minor-mode-on)
  "Hook run after entering P mode."
  :type 'hook
  :options (list 'yas-minor-mode-on))

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
  "Directory containing yasnippet snippets for p-mode.")

(defun p--initialize-yasnippets ()
  (add-to-list 'yas-snippet-dirs p--yas-snippets-dir t)
  ;; we use an internal function here, but the `yasnippet-snippets' package
  ;; does the same; let's assume it's a de facto public API for now.
  (yas--load-snippet-dirs))

;;;###autoload
(eval-after-load 'p-mode
  '(p--initialize-yasnippets))


;; Syntax highlighting
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
     "creates" "to"
     )
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

;;;###autoload
(define-derived-mode p-mode prog-mode "P"
  "Major mode for editing files for the P model checker."
  :group 'P
  (setq-local comment-use-syntax t
              comment-start "//"
              comment-end ""
              comment-start-skip "//+\\s-*")
  (setq font-lock-defaults (list 'p-font-lock-defaults))
  ;; don't let our missing indentation mess up the snippets
  (setq-local yas-indent-line 'fixed))

;; NOTE: Adding ourselves to `auto-mode-alist' would be a bit unfriendly since
;; it shadows the file type association for the existing Pascal mode

;;;###autoload
(when p-override-pascal-file-type
  (add-to-list 'auto-mode-alist '("\\.p\\'" . p-mode)))

(provide 'p-mode)
;;; p-mode.el ends here
