VCtools -- A set of scripts for making CVS and Subversion easier

Introduction
============

VCtools is a set of Unix-based scripts which are wrappers around corresponding CVS or Subversion
commands.  They are designed to fulfill the following needs:

Policy
------

The first itch scratched by the first, primitive version of VCtools was to make sure that all
members of the development team were performing the same commands, in the same order, using the same
switches, to maintain consistency across the repository.  Back in those days, we had a policy that
whenever you started editing a file, you should use `cvs edit` to let the others on the team know
you were working on it.  To help you remember that, we used `cvs -r co` and `cvs -r update` to make
sure that all the files were read-only (this kept you from starting to edit something without
remembering to run `cvs edit` first).  And of course, before you started editing, it would be nice
to check `cvs editors` to see  if other people were working on the same file so that perhaps you
could go ask them what they were working on and discuss any potential conflicts.  That's a lot to
remember.  But `vget` did it all for you.  Similar policies evolved around other commands.

Dealing with Unix Permissions
-----------------------------

Another lesson you quickly learn with CVS is that it's important to get your Unix permissions for
files correct, including what groups files belong to.  Especially when you want other developers to
have access to your working copy, to look at your code or help you test something, you want to make
sure they have access.  The `vcshell` command was invented to insure that your primary group and
umask was set properly for this purpose.

Simplifying Output
------------------

The output of commands such as `cvs update` (or even `svn update`, which is better, but still not
great) can be cryptic.  Wouldn't it be nice to have some scripts to reformat that output and make it
a bit smarter?

Working Around Stupidities
--------------------------

One of the first major annoyances we ever discovered with CVS was that, if you did `cvs diff myfile
| less`, CVS would lock the directory that file was in.  If you wandered away from your keyboard
(or, heaven forfend, went home) with that still up on your screen, no one could do anything with
that directory any more.  The `vdiff` command was created almost solely for that reason.

A Place for Hooks
-----------------

Although Subversion in particular has a decent hook-in system at the repository level, there are
times where having a place to hook in at the user level is important.  For instance, `vget` has the
ability to filter code as it comes out of the repository acording to your personal specifications:
perhaps you want to convert those pesky spaces to tabs.  (And of course `vcommit` has a
corresponding hook to make sure your tabs don't corrupt the pristine space-only repository.)

Easing Conversion
-----------------

A secondary goal of VCtools was to have a consistent set of commands that work the same way on CVS
as on Subversion.  So if you have to work with both, or switch from one to the other, you can keep
using the commands you're familiar with.  Admittedly, this is still a work in progress, and the
Subversion side of VCtools is much more well-developed that the CVS side, but for basics, it still
works well.


History of Development
======================

VCtools was first developed for CVS.  Most of its basic commands were created during this time.
Later, it was adapted for Subversion.  Then it was used for CVS again, while still being used for
Subversion.

As a result of this, most of the "advanced" commands, particularly those for branching and merging,
were developed solely for Subversion, and just plain don't work on CVS.  Additionally, certain
quirks of CVS (such as not having a useful way to get a list of all files in the working copy
without going back to the repository server, and not having a good concept of directories) make some
things (particularly vfind) work poorly in CVS.

Contrariwise, sometimes basic concepts (like projects and project root paths) are derived from CVS
and then adapted to Subversion, making them perhaps a bit foreign to those raised on svn.

Also, internally, the idea of having VCtools be portable across different VCs was an afterthought,
with the result that the implementation for switching between VCs is a pretty crude one (for those
braving the source code, that is; from the user's perspective, switching from one to the other is
very simple).

Nonetheless, you should find that VCtools is quite useable for CVS, and performs extremely well for
Subversion.


Installation
============
Prerequisites
-------------

Here's what you need to make VCtools work.

You'll need Perl, and a few Perl modules: Config::General, Date::Format, Date::Parse, File::HomeDir,
Getopt::Declare, Mail::Sendmail, Perl6::Form, and Perl6::Slurp.

You'll need either CVS or Subversion, obviously, or both.  Whatever you need to access your
repository/ies.  If you want to do merging on Subversion, `svnmerge.py` is strongly recommended.

If you want to use vcshell, you'll need the `newgrp` command, which most Unix variants seem to have.
(No guarantees about OSX though.)

You'll need to have root access on your machine to add just a few things.  Config files go in
`/usr/local/etc/VCtools`, which you'll probably have to make.  You can put the commands anywhere you
like, but you should put (or symlink) the `vctools-config` command into somewhere standard, such as
`/usr/local/bin`.

Instructions
------------

You'll want to look at the
[`INSTALL`](https://github.com/barefootcoder/VCtools/blob/master/attic/INSTALL) file for always
updated instructions on how to download and install VCtools.  Please note that the URL given in
INSTALL is different from what GoogleCode will tell you; ignore GoogleCode and listen to us.
