set vcbindir=`perl -F'/\s*=\s*/' -lane 'print $F[1] if $F[0] eq "VCtoolsBinDir"' /usr/local/etc/VCtools.conf`
set shellexec=$vcbindir/vcshellexec

if ( ! $?VCTOOLS_SHELL ) then
	alias vcshell "exec $shellexec"
else
	if ( "$VCTOOLS_SHELL" != 1 ) then
		exec $shellexec
	else
		setenv PATH `$shellexec -p $PATH`

		alias get vget

		if ( $?VCTOOLS_SHELL_STARTDIR ) then
			cd $VCTOOLS_SHELL_STARTDIR
		endif
		umask 2
	endif
endif

if ( -e ~/.vctoolsrc ) then
	source ~/.vctoolsrc
endif
