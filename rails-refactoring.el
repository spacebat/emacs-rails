;;; rails-refactoring.el -- common refactoring operations on rails projects

;; Copyright (C) 2009 by Remco van 't Veer

;; Author: Remco van 't Veer
;; Keywords: ruby rails languages oop refactoring

;;; License

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 2
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

(require 'cl)
(require 'rails-core)


;; Customizations

(defcustom rails-refactoring-source-extensions '("builder" "erb" "haml" "liquid" "mab" "rake" "rb" "rhtml" "rjs" "rxml" "yml")
  "List of file extensions for refactoring search and replace operations."
  :group 'rails
  :type '(repeat string))


;; Helper functions

(defun directory-files-recursive (dirname &optional base)
  "Return a list of names of files in directory named by
DIRNAME. If the directory contains directories these are
traversed recursively.  The returned list of file names are
relative to DIRNAME and only includes regular files.

If BASE is provided, it is interpreted as a subdirectory to
traverse.  This subdirectory is included the returned file
names."
  (apply #'append
         (mapcar (lambda (file)
                   (cond ((file-regular-p (concat dirname "/" file))
                          (list (concat base file)))
                         ((and (file-directory-p (concat dirname "/" file))
                               (not (string-match "^\\." file)))
                          (directory-files-recursive (concat dirname "/" file) (concat base file "/")))))
                 (ignore-errors (directory-files dirname)))))

(defmacro rails-refactoring:disclaim (name)
  `(when (interactive-p)
     (when (not (y-or-n-p (concat "Warning! " ,name " can not be undone! Are you sure you want to continue? ")))
       (error "cancelled"))
     (save-some-buffers)))

(defun rails-refactoring:decamelize (name)
  "Translate Ruby class name to corresponding file name."
  (replace-regexp-in-string "::" "/" (decamelize name)))

(assert (string= "foo_bar/quux" (rails-refactoring:decamelize "FooBar::Quux")))

(defun rails-refactoring:camelize (name)
  "Translate file name into corresponding Ruby class name."
  (replace-regexp-in-string "/" "::"
                            (replace-regexp-in-string "_\\([a-z]\\)" (lambda (match)
                                                                       (upcase (substring match 1)))
                                                      (capitalize name))))

(assert (string= "FooBar::Quux" (rails-refactoring:camelize "foo_bar/quux")))

(defun rails-refactoring:source-file-p (name)
  "Test if file has extension from `rails-refactoring-source-extensions'."
  (find-if (lambda (ext) (string-match (concat "\\." ext "$") name))
           rails-refactoring-source-extensions))

(defun rails-refactoring:source-files ()
  "Return a list of all the source files in the current rails
project.  This includes all the files in the 'app', 'config',
'lib' and 'test' directories."
  (apply #'append
         (mapcar (lambda (dirname)
                   (delete-if (lambda (file) (string-match "_flymake.rb" file))
                              (delete-if-not 'rails-refactoring:source-file-p
                                             (directory-files-recursive (rails-core:file dirname) dirname))))
                 '("app/" "config/" "lib/" "test/" "spec/"))))

(defun rails-refactoring:class-files ()
  "Return list of all Ruby class files."
  (delete-if-not (lambda (file) (string-match "\\.rb$" file)) (rails-refactoring:source-files)))

(defun rails-refactoring:class-from-file (file)
  "Return corresponding class/module name for given FILE."
  (let ((path (find-if (lambda (path) (string-match (concat "^" (regexp-quote path)) file))
                       '("app/models/" "app/controllers/" "app/helpers/" "lib/"
                         "test/unit/helpers/" "test/unit/" "test/functional/"
                         "spec/models/" "spec/controllers/" "spec/helpers/ spec/lib/"))))
    (when path
      (rails-refactoring:camelize
       (replace-regexp-in-string path "" (replace-regexp-in-string "\\.rb$" "" file))))))

(assert (string= "FooBar" (rails-refactoring:class-from-file "app/models/foo_bar.rb")))
(assert (string= "Foo::BarController" (rails-refactoring:class-from-file "app/controllers/foo/bar_controller.rb")))
(assert (string= "Foo::Bar::Quux" (rails-refactoring:class-from-file "lib/foo/bar/quux.rb")))
(assert (string= "FooTest" (rails-refactoring:class-from-file "test/unit/foo_test.rb")))
(assert (string= "FooHelperTest" (rails-refactoring:class-from-file "test/unit/helpers/foo_helper_test.rb")))


;; Refactoring methods

(defun rails-refactoring:query-replace (from to &optional dirs)
  "Replace some occurrences of FROM to TO in all the project
source files.  If DIRS argument is given the files are limited to
these directories."
  (interactive "sFrom: \nsTo: ")
  (let ((keep-going t)
        (files (mapcar #'rails-core:file
                       (if dirs
                         (delete-if-not (lambda (file)
                                          (find-if (lambda (dir)
                                                     (string-match (concat "^" (regexp-quote dir)) file))
                                                   dirs))
                                        (rails-refactoring:source-files))
                         (rails-refactoring:source-files)))))
    (while (and keep-going files)
      (let* ((file (car files))
             (flymake-start-syntax-check-on-find-file nil)
             (existing-buffer (get-file-buffer file)))
        (set-buffer (or existing-buffer (find-file-noselect file)))
        (goto-char (point-min))
        (if (re-search-forward from nil t)
          (progn
            (switch-to-buffer (current-buffer))
            (goto-char (point-min))
            (unless (perform-replace from to t t nil)
              (setq keep-going nil)))
          (unless existing-buffer (kill-buffer nil))))
      (setq files (cdr files)))))

(defun rails-refactoring:rename-class (from-file to-file)
  "Rename class given their file names; FROM-FILE to TO-FILE.
The file is renamed and the class or module definition is
modified."
  (interactive (list (completing-read "From: " (rails-refactoring:class-files) nil t)
                     (read-string "To: ")))
  (rails-refactoring:disclaim "Rename class")

  (let ((from (rails-refactoring:class-from-file from-file))
        (to (rails-refactoring:class-from-file to-file)))
    (message "rename file from %s to %s" from-file to-file)
    (rename-file (rails-core:file from-file) (rails-core:file to-file))
    (let ((buffer (get-file-buffer (rails-core:file from-file))))
      (when buffer (kill-buffer buffer)))

    (message "change definition from %s to %s" from to)
    (let ((buffer (get-file-buffer (rails-core:file to-file))))
      (when buffer (kill-buffer buffer)))
    (find-file (rails-core:file to-file))
    (goto-char (point-min))
    (while (re-search-forward (concat "^\\(class\\|module\\)[ \t]+" from) nil t)
      (replace-match (concat "\\1 " to) nil nil))
    (save-buffer))

  (when (interactive-p)
    (ignore-errors (rails-refactoring:query-replace (concat "\\b" (regexp-quote from)) to))
    (save-some-buffers)))

(defun rails-refactoring:rename-layout (from to)
  "Rename all named layouts from FROM to TO."
  (interactive (list (completing-read "From: " (rails-refactoring:layouts) nil t)
                     (read-string "To: ")))
  (rails-refactoring:disclaim "Rename layout")

  (mapc (lambda (from-file)
          (let ((to-file (concat to (substring from-file (length from)))))
            (message "renaming layout from %s to %s" from-file to-file)
            (rename-file (rails-core:file (format "app/views/layouts/%s" from-file))
                         (rails-core:file (format "app/views/layouts/%s" to-file)))))
        (delete-if-not (lambda (file) (string-match (concat "^" (regexp-quote from) "\\.") file))
                       (directory-files-recursive (rails-core:file "app/views/layouts"))))
  (when (interactive-p)
    (let ((case-fold-search nil))
      (ignore-errors (rails-refactoring:query-replace from to)))
    (save-some-buffers)))

(defun rails-refactoring:rename-controller (from to)
  "Rename controller from FROM to TO.  All appropriate files and
directories are renamed and `rails-refactoring:query-replace' is
started to do the rest."
  (interactive (list (completing-read "Rename controller: "
                                      (mapcar (lambda (name) (remove-postfix name "Controller"))
                                              (rails-core:controllers))
                                      nil t
                                      (ignore-errors (rails-core:current-controller)))
                     (read-string "To: ")))
  (rails-refactoring:disclaim "Rename controller")

  (mapc (lambda (func)
          (when (file-exists-p (rails-core:file (funcall func from)))
            (rails-refactoring:rename-class (funcall func from)
                                            (funcall func to))))
        '(rails-core:controller-file rails-core:functional-test-file rails-core:rspec-controller-file
                                     rails-core:helper-file rails-core:helper-test-file))

  (when (file-exists-p (rails-core:file (rails-core:views-dir from)))
    (let ((from-dir (rails-core:views-dir from))
          (to-dir (rails-core:views-dir to)))
      (message "rename view directory from %s to %s" from-dir to-dir)
      (rename-file (rails-core:file from-dir) (rails-core:file to-dir))))

  (rails-refactoring:rename-layout (rails-refactoring:decamelize from)
                                   (rails-refactoring:decamelize to))

  (when (interactive-p)
    (let ((case-fold-search nil))
      (rails-refactoring:query-replace (concat "\\b" (regexp-quote from))
                                     to
                                     '("app/controllers/"
                                       "app/helpers/"
                                       "app/views/"
                                       "test/functional/"
                                       "spec/controllers/"))
      (rails-refactoring:query-replace (concat "\\b" (regexp-quote (rails-refactoring:decamelize from)) "\\b")
                                       (rails-refactoring:decamelize to)
                                       '("app/controllers/"
                                         "app/helpers/"
                                         "app/views/"
                                         "test/functional/"
                                         "spec/controllers/"
                                         "config/routes.rb")))
    (save-some-buffers)))


;; Tie up in UI

(require 'rails-ui)

(define-keys rails-minor-mode-map
  ((rails-key "\C-c R q") 'rails-refactoring:query-replace)
  ((rails-key "\C-c R c") 'rails-refactoring:rename-controller)
  ((rails-key "\C-c R l") 'rails-refactoring:rename-layout))


(provide 'rails-refactoring)