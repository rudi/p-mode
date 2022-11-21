# An Emacs major mode for P

This mode provides support for editing files for the [P model
checker](https://p-org.github.io/P/) in Emacs.  Currently supports syntax
highlighting and expansion of snippets.  For a list of snippets, check the
p-mode submenu in the "YASnippet" pull-down menu.

## Installation

Currently, the easiest way to install and set up `p-mode` is via
[`use-package`](https://elpa.gnu.org/packages/use-package.html).  To install
`use-package` itself, type:

    M-x package-install RET use-package RET

The package `p-mode` itself is not currently available via `package-install`.
To use it, first check out the source from github, e.g., below the directory
`~/source`:

```bash
mkdir ~/source/
cd ~/source
git checkout https://github.com/rudi/p-mode
```

Then, add the following to your emacs init file (typically `~/.emacs` or
`~/.emacs.d/init.el`), using the directory where you checked out `p-mode`:

```elisp
(use-package p-mode
  :load-path "~/source/p-mode"
  :mode "\\.p\\'"
  :commands (p-mode))
```

NOTE: The above form associates files with extension `.p` with `p-mode`,
thereby overriding the pre-existing binding of such types with `pascal-mode`.
To avoid this, remove the line beginning with `:mode`.
