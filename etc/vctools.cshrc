set vcbindir=`perl -F'/\s*=\s*/' -lane 'print $F[1] if $F[0] eq "VCtoolsBinDir"' /usr/local/etc/VCtools/VCtools.conf`
set shellexec=$vcbindir/vcshellexec

if ( ! $?VCTOOLS_SHELL ) then
	alias vcshell "exec $shellexec"
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
