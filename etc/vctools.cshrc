setenv VCTOOLS_CONFIG `vctools-config --config`

set vcbindir=`vctools-config --bin`
set shellexec=$vcbindir/vcshellexec

alias vcshell "exec $shellexec"

if ( ! $?VCTOOLS_SHELL ) then
	alias vbuild "$shellexec -b --"
else
	if ( "$VCTOOLS_SHELL" != 1 ) then
		exec $shellexec
	else
		setenv PATH `$shellexec -p`

		alias get vget
		alias sync vsync
		alias commit vcommit

		alias vcd 'cd `vprojdir \!^`'

		if ( $?VCTOOLS_SHELL_STARTDIR ) then
			cd $VCTOOLS_SHELL_STARTDIR
			unsetenv VCTOOLS_SHELL_STARTDIR
		endif
		umask 2
	endif
endif

if ( -e ~/.vctoolsrc ) then
	source ~/.vctoolsrc
endif
