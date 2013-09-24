VCtools
=======

This is a system of commands that you can use to replace your native version control system command
(e.g. `git` or `svn`).  Why would you want to do this?  Here are some reasons:

* You have to work with multiple version control systems (e.g. both CVS and Subversion, or both
Subversion and Git), and you'd like to use the same set of commands for all of them.
* You have a group of developers who need to do certain things the same way as each other (a.k.a. a
"policy"), and you want a convenient way for everyone to do that.
* You want to divide your working copy directories up differently than how your central repository
is divvied up.  (This is most common in CVS or Subversion, where one repo might contain several
different logical projects.)
* Your VC system doesn't work the way you want it to, and you'd like a better solution than just
cobbling together a bunch of scripts and aliases.

VCtools _aims_ to solve all of these issues, although it may not achieve them all yet.  See
"History" below for more details.


History
-------

The first version of VCtools was written in 1999, for CVS only (as Subversion and Git didn't exist
yet!).  In 2004, support for Subversion was added.  In 2011, some support for Git was added, but
integration with the other two proved tricky.  In 2013, a complete rewrite of the system was begun
with greater flexibility and customization as a goal.

For a whole lot more interesting info, check out [this overview of the
project](https://github.com/barefootcoder/VCtools/blob/master/attic/Overview.md) from circa 2008.
(Don't forget: that document predates any Git work.)


Installing
----------

Right now, installation isn't standardized.  In particular, you can't install this like a typical
CPAN-style distribution.  That having been said, some effort has been gone to to make sure you don't
really _need_ to install anything.  Try this simplistic process:

	cd ~/wherever/you/like
	git clone https://github.com/barefootcoder/VCtools.git

Then add this to your particular shell's startup script (typically `.bashrc` or `.tcshrc`):

	alias vc=~/wherever/you/like/VCtools/bin/vc			# for bash-style shells
	alias vc ~/wherever/you/like/VCtools/bin/vc			# for csh-style shells

And then all you need is a config file.  Which is non-trivial, but hopefully I'll have some examples
uploaded here soon.

Contributing
------------

Create an [issue for the GitHub repository](https://github.com/barefootcoder/VCtools/issues).  You
can also fork and make a pull request, but it might be helpful to discuss it first via an issue.

Copying
-------

Artistic License.  See the [`LICENSE`](https://github.com/barefootcoder/VCtools/blob/master/LICENSE)
file for full details.
