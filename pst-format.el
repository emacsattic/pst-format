;;; pst-format.el --- view perl Storable files as human readable text

;; Copyright 2008, 2009 Kevin Ryde

;; Author: Kevin Ryde <user42@zip.com.au>
;; Version: 4
;; Keywords: data
;; URL: http://user42.tuxfamily.org/pst-format/index.html
;; EmacsWiki: PerlLanguage

;; pst-format.el is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the
;; Free Software Foundation; either version 3, or (at your option) any later
;; version.
;;
;; pst-format.el is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
;; Public License for more details.
;;
;; You can get a copy of the GNU General Public License online at
;; <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This is a bit of fun turning perl "Storable" module binary data into
;; something human readable, just with Data::Dumper.  There's no re-writing
;; as yet, it's only meant for browsing Storable files.

;;; Install:

;; To make `pst-format' format available, put pst-format.el in one of your
;; `load-path' directories and the following in your .emacs
;;
;;     (require 'pst-format)
;;
;; Or you can defer loading until needed by adding an entry to
;; `format-alist' and autoloads for the functions,
;;
;;     (autoload 'pst-format-decode "pst-format")
;;     (add-to-list 'format-alist
;;                  '(pst-format
;;                    "Perl \"Storable\" module data."
;;                    "\\`\\(pst0\\|perl-store\\)"
;;                    pst-format-decode
;;                    pst-format-encode
;;                    t
;;                    nil))
;;
;; There's autoload cookies below for this latter style, if you know how to
;; use `update-file-autoloads' and friends.
;;
;; Storable files are basically binary but the code here should cope with
;; either a unibyte like `raw-text-unix' or some reversible multibyte.
;; There's no conventional filename suffix for Storable, it's just whatever
;; a given program makes up, so if you set a coding system it'd be on a
;; case-by-case basis.
;;
;; There's no major mode set for the final human readable text;
;; pst-format.el is just a decode.  Since it's Data::Dumper output
;; `perl-mode' or `cperl-mode' are good and can be turned on from
;; auto-mode-alist in the usual way
;;
;;     (add-to-list 'auto-mode-alist
;;                  '(".*/.someprog/cache.file\\'" . cperl-mode))


;;; History:

;; Version 1 - the first version
;; Version 2 - cope with non-existent default-directory
;; Version 3 - hyperlink home page in the docstring
;; Version 4 - use pipe rather than pty for subprocess

;;; Emacsen:

;; Designed for Emacs 21 and 22, works in XEmacs 21.


;;; Code:

;; xemacs lack
(defalias 'pst-format-make-temp-file
  (if (eval-when-compile (fboundp 'make-temp-file))
      'make-temp-file   ;; emacs
    ;; xemacs21
    (autoload 'mm-make-temp-file "mm-util") ;; from gnus
    'mm-make-temp-file))

(defmacro pst-format-with-errorfile (&rest body)
  "Create an `errorfile' for use by the BODY forms.
An `unwind-protect' ensures the file is removed no matter what
BODY does."
  `(let ((errorfile (pst-format-make-temp-file "pst-format-")))
     (unwind-protect
         (progn ,@body)
       (delete-file errorfile))))

;;;###autoload
(add-to-list 'format-alist
             '(pst-format
               "Perl \"Storable\" module data."

               ;; "perl-store" is v0.6
               ;; "pst0" is v0.7 and up
               ;;
               ;; Storable 2.18 read_magic() applies a sanity check
               ;; demanding format major version <= 4 on the pst0 form.
               ;; Is that worth enforcing here too?  Hopefully unnecessary.
               ;;
               "\\`\\(pst0\\|perl-store\\)"
               pst-format-decode
               pst-format-encode
               t     ;; encode modifies the region
               nil)) ;; write removes from buffer-file-formats

(defun pst-format-encode (beg end buffer)
  "Sorry, cannot re-encode Storable.
This function is for use from `format-alist'.

There's no support as yet for writing back dumped Storable
contents.  Simple stuff wouldn't be hard, but self-referential
structures would need a better form to edit and almost a perl
eval to get right, and if there's blessed stuff that might need
the originating classes and it could be a very big security hole
..."
  (error "Sorry, `pst' format is read-only"))


(defconst pst-format-decode-command
  "
use strict;
use warnings;
use Storable;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Useqq    = 1;
$Data::Dumper::Indent   = 1;

# This is a moderately nasty hack to make Dumper print utf-8 for
# strings marked as utf-8.  Control chars in such strings get
# \\x{00} escapes.  Non-utf8 strings get Dumper's normal
# action (octal).  There's no way to know what, if any encoding,
# those non-utf8 strings might be, so escapes are safest.
#
my $orig_qquote = \\&Data::Dumper::qquote;
sub my_qquote {
  my ($str) = @_;
  if (utf8::is_utf8($str)) {
    $str=~s/([\\x00-\\x08\\x0B-\\x1F\\x7F-\x9F])/sprintf('\\\\x{%02x}',ord($1))/ge;
    return '\"' . $str . '\"';
  } else {
    goto $orig_qquote;
  }
}

# if emacs and perl both do utf-8 then generate that with
# my_qquote(), otherwise leave it all to Dumper
my $utf8 = ($ARGV[0] eq 'utf-8'          # emacs from command line
            && defined &utf8::is_utf8);  # new enough perl
if ($utf8) {
  binmode (STDOUT, ':encoding(utf-8)') or die 'Oops, binmode error';
  no warnings;
  *Data::Dumper::qquote = \\&my_qquote;
}
my $coding_cookie = ($utf8 ? '    -*- coding: utf-8 -*-' : '');
my $coding = ($utf8 ? '[utf8 shown]' : '[qq shown]');

my $data = Storable::fd_retrieve(\\*STDIN);
my $order = Storable::last_op_in_netorder()
            ? '[file in host byte order]' : '[file in network byte order]';

print \"# pst-format.el decoded Storable file$coding_cookie\\n\";
print \"# $order $coding\\n\";
if ($utf8) { print \"use utf8;\\n\"; }
print Data::Dumper->Dump([$data],['data']);
"

  "Perl code string to decode Storable stdin to human stdout.
In principle you can change this for the dump options or dumper
module you prefer, but it's a bit hairy.  The current
implementation runs

    perl -e PST-FORMAT-DECODE-COMMAND CODING

and it should read Storable from stdin and write human text to
stdout.  The CODING argument, ie. $ARGV[0], is the Emacs read
coding system.  It's either \"utf-8\" if that's possible (meaning
Emacs 21 and up, or XEmacs 21 with mule-ucs), otherwise
\"undecided\".  But don't rely on any of this.

$Data::Dumper::Sortkeys makes the output consistent.  You might
wonder if keys should be shown in the order they appear in the
file, but in practice they're written in random hash order, so
may as well sort for readability.

Data::Dumper isn't blindingly fast on big files, for various
reasons, including string concats and its work detecting circular
structures.  So don't try it on say a huge .cpan/Metadata unless
you've got a very fast computer with lots of memory!")

;;;###autoload
(defun pst-format-decode (beg end)
  "Decode raw Storable bytes in the current buffer.
This function is for use from `format-alist'.

The buffer can be either unibyte or multibyte, as long as any
multibyte is reversible, so it writes out the original contents
unchanged.  But unibyte probably makes most sense.

`pst-format-decode-command' holds the perl code to crunch the
Storable bytes to human readable text.  An error is thrown if the
buffer contents are somehow invalid.

For more on Storable see \"man Storable\" or
URL `http://perldoc.perl.org/Storable.html'

The pst-format.el home page is
URL `http://user42.tuxfamily.org/pst-format/index.html'"

  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      (pst-format-with-errorfile

       ;; `with-temp-message' is not in xemacs21, and in emacs21 it doesn't
       ;; clear a message when done, so avoid
       (message "Decoding perl Storable ...")

       ;; The unibyte handling here is moderately nasty.  If the buffer is
       ;; unibyte then want it to go out that way but come back with decode,
       ;; but `call-process-region' doesn't seem to allow that.  So for
       ;; unibyte do the read as bytes then explicitly convert.  Is that
       ;; right?
       ;;
       ;; If the buffer is already multibyte then it can be written out and
       ;; read back that way with no special action, presuming
       ;; buffer-file-coding-system gives back the original.  Dunno if that
       ;; can be relied on if there's multiple formats decoded.
       ;;
       (let* ((read-coding (if (memq 'utf-8 (coding-system-list))
                               'utf-8
                             'undecided))
              (unibyte-p (and (eval-when-compile ;; not in xemacs
                                (boundp 'enable-multibyte-characters))
                              (not enable-multibyte-characters)))
              (status (let ((coding-system-for-read
                             (if unibyte-p 'raw-text-unix read-coding))
                            (default-directory "/") ;; in case non-existant
                            (process-connection-type nil)) ;; pipe
                        (call-process-region (point-min) (point-max)
                                             "perl"
                                             t                ;; delete old
                                             (list t          ;; stdout here
                                                   errorfile) ;; stderr to file
                                             nil              ;; no redisplay
                                             ;; args ...
                                             "-e" pst-format-decode-command
                                             (symbol-name read-coding)))))
         (message nil)

         (with-current-buffer (get-buffer-create "*pst-format-errors*")
           (erase-buffer)
           (insert-file-contents errorfile)
           (goto-char (point-min)))
         (unless (eq 0 status)
           (switch-to-buffer "*pst-format-errors*")
           (error "Storable retrieve error, see *pst-format-errors* buffer"))

         (when unibyte-p
           (decode-coding-region (point-min) (point-max) read-coding)
           (set-buffer-multibyte t))

         ;; This explicit set-buffer-file-coding-system tells emacs21
         ;; after-insert-file-set-buffer-file-coding-system not to touch the
         ;; buffer multibyte flag.  Without this it looks at
         ;; last-coding-system-used or whatever and will switch to unibyte
         ;; if it's a bytes one.  Think buffer-file-coding-system is the
         ;; right thing here, ie. no change, since that's what it should be
         ;; after formats are undone.  Is that right?  But there's no
         ;; re-encoding yet so it doesn't matter.
         ;;
         (set-buffer-file-coding-system buffer-file-coding-system)

         (point-max))))))

(provide 'pst-format)

;;; pst-format.el ends here
