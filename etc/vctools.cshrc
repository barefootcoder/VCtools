setenv VCTOOLS_CONFIG `vctools-config --config`

set vcbindir=`vctools-config --bin`
set shellexec=$vcbindir/vcshell

alias vcshell "exec $shellexec"

if ( ! $?VCTOOLS_SHELL ) then
	alias vbuild "$shellexec -b --"
else
	switch ("$VCTOOLS_SHELL")
		case "proj:*":
			# $shellexec seems to have found something it's happy with
			setenv PATH `$shellexec -p`

			alias commit vcommit
			alias get vget
			alias log vlog
			alias new vnew
			alias rel vrel
			alias tag vtag
			alias sync vsync
			alias stat vstat
			alias unget vunget

			alias vrm vdel

			# these require a bit more work
			alias vcshell "unsetenv VCTOOLS_SHELL ; exec $shellexec"
			alias vcd 'cd `vfind -dirfind \!^`'

			# newgrp often seems to trash $SHELL, so put it back
			if ( ! $?SHELL ) then
				setenv SHELL `which $0`
			endif

			if ( $?VCTOOLS_SHELL_STARTDIR ) then
				cd $VCTOOLS_SHELL_STARTDIR
				unsetenv VCTOOLS_SHELL_STARTDIR
			endif
			umask 2
			breaksw

		default:
			# obviously $shellexec has more work to do
			# let it try again
			exec $shellexec
			breaksw
	endsw
endif

if ( -e ~/.vctoolsrc ) then
	source ~/.vctoolsrc
endif
