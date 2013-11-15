This is a super-brief guide to writing action directives for VCtools.  More complete documentation will be coming soon.

Types of "Scriptlets"
=====================

A VCtools config file can contain two different sections that will be executed.  Each line in such a section is called an "action directive."

Info Methods
------------

The actions of an info method are executed and its output is gathered.  That output is substituted in other action directives when it's referenced with a leading `%`.  There are several internal info methods:

* %user
* %status
* %is_dirty
* %has_staged
* %mod_files
* %cur_branch
* %branches
* %remote_branches
* %tags

There are also some other things which act like info methods:

* %running_nested
* %project
* %proj_root
* %vc
* %Mainline

A definition of an internal info method looks like this:

	<info>
		status <<---
			git status
		---
	</info>

You can also create custom info methods.  Their definition looks like this:

	<CustomInfo trunk_version>
		Type = Str
		action <<---
			git fetch -q origin
			git show origin/trunk:etc/version.txt
		---
	</CustomInfo>

Info methods are always run, even in pretend mode, so they should always be non-destructive.

Commands
--------

The actions of a command are executed and its output goes to the user.  If any action fails, the command stops, the user is informed, and also given a list of any remaining commands so that they can do manual recovery.

A definition of a custom command looks like this:

	<CustomCommand feature-start>
		Description = This command creates a new feature branch
		Argument = branch_name						<the name of the feature branch you want to create>
		Verify = project
		Verify = clean
		Files = 0
		action <<---
			NEW_BRANCH="feature/" . %branch_name
			git checkout -b $NEW_BRANCH
		---
	</CustomCommand>

The `Argument` directive may be repeated multiple times.  Arguments are available as info methods: `Argument branch_name` would create `%branch_name` available to all action directives in that command.

The `Verify` directive may be repeated multiple times; it currently only knows two modes:

* `verify project` : make sure the user is in a directory that VCtools recognizes
* `verify clean` : make sure the working copy is in a clean state (no uncommited changes)

The `Files` argument is optional, and can specify a range (e.g. `0..2` meaning 0, 1, or 2 files, or `1..` meaning any number of files but at least 1).


Types of Action Directives
==========================

Blank lines or lines starting with `#` are ignored.  Note that you may **not** put comments on the same line as an action directive.

There are 8 types of actions:

* shell directives (Ex: `git branch`)
* code directives (Ex: `@ %trunk_version - 1`)
* nested commands (Ex: `= publish`)
* message directives (Ex: `> current branch is %cur_branch`)
* confirmation directives (Ex: `? This could be dangerous.`)
* fatal directives (Ex: `! Cannot continue; sorry.`)
* env assignments (Ex: `STG_BRANCH="staging/" . %stg_branch`)
* conditionals (Ex: `%cur_branch ne %Mainline -> ! You must start on trunk.`)

Shell Directives
----------------

	git branch

Any directive that is not identified as another type of directive is passed on to the shell for execution.  Shell directives pass if they are successfully executed and return 0; otherwise they fail.

Code Directives
---------------

	@ %trunk_version - 1

Starts with `@` followed by whitespace.  Code directives are evaluated as Perl code (after expansions; see below).  They fail if the final expression is false (by Perl's defintion); otherwise they pass.  Code directives should only be used when no other directives will work, or sometimes in info methods.

Nested Commands
---------------

	= publish

Starts with `=` followed by whitespace.  Nested commands are a way to have one command run another.  However, VCtools is not respawned, and most command-line switches (e.g. pretend mode, interactive mode, etc) are passed through.  This is a simple form of code reuse.

Message Directives
------------------

	> current branch is %cur_branch

Starts with `>` followed by whitespace.  Just prints a message to the user.  Always passes.

Confirmation Directives
-----------------------

	? This could be dangerous.

Starts with `?` followed by whitespace.  Prints a message to the user then asks if they wish to proceed.  If they do not answer yes, the command exits.

Fatal Directives
----------------

	! Cannot continue; sorry.

Starts with `!` followed by whitespace.  Prints a message to the user, in red, then exits with an unsuccessful return value.  Generally only useful in conditionals (see below).

Env Assignments
---------------

	STG_BRANCH="staging/" . %stg_branch

Contains `=` **not** surrounded by whitespace.  The left side is taken as an env varname.  The right side is taken as a Perl expression.  Always passes.

Conditionals
------------

	%cur_branch ne %Mainline -> ! You must start on trunk.

Contains `->` surrounded by whitespace.  The left side is taken as a Perl expression.  The right side is any action directive (even another conditional).  If condition evaluates to true (by Perl's defintion), the action is executed.  If it evalutes to false, the command moves on to the next action.


Expansions
==========

Action directives can have several types of expansions.  Expansions are performed in this order:

Info Expansion
--------------

	%cur_branch

A `%` followed by a name (two or more letters or digits).  Replaced with the value of that info method.  Info expansion is performed on all actions.  Info expansion into code directives or expressions (i.e. the right-hand sides of env assignments and the left-hand sides of conditionals) does the right thing.

Env Expansion
-------------

	$STG_BRANCH

A `$` followed by a name (two or more letters or digits).  Replaced with the value of that env variable.  Env expansion is performed on: nested commands, message directives, confimation directives, fatal directives, and expressions (i.e. the right-hand sides of env assignments and the left-hand sides of conditionals).  Env expansion is not performed on shell directives, but the shell will most likely expand them anyway.  It is not performed on code directives; in expressions, they often need quotes to avoid syntax errors.

PID Expansion
-------------

	$$

Only done in shell directives.  Expanded to the PID of the current VCtools instance.

Color Expansions
----------------

	*+Success!+*

A `*` followed by some punctuation to start; the same punctuation followed by a `* to end.  Replaced with the intervening text in the color determined by the secondary punctuation mark.  Color expansion is performed on message directives and confirmation directives.  Here are the colors recognized and their punctuation:

* `*!red text!*`
* `*~yellow text~*`
* `*+green text+*`
* `*-cyan text-*`
* `*=white text=*`

All colors are bold/bright.
