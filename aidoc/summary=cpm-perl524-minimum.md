# Finding: cpm 0.999+ Requires Perl 5.24

`perlbrew install-cpm` always downloads the tip of `skaji/cpm`'s `main` branch, so upstream
changes reach fresh installs unannounced. That has broken `vc-perlbrew INSTALL` twice: first
through `Errno` (see `summary=cpm-errno-perl514-incompatibility.md`), then when 0.999.0
(2026-03-13) raised cpm's minimum to Perl v5.24 and every fresh install died with
`Perl v5.24.0 required--this is only v5.14.4`.

`bin/vc-perlbrew` now pins `cpmver=0.998003`, the last release that runs under our Perl 5.14.4,
and fetches that tag itself rather than calling `install-cpm`. Two things to know before
touching it:

- Any replacement has to run under `$perlver`. 0.999.0 and later need 5.24; raising `perlver`
  instead is a far bigger job (see `summary=app-cmd-perl-version-incompatibility.md`).
- `perlbrew install-cpanm` carries the identical tip-of-master exposure. cpanm 1.7049 still
  supports 5.8.1, so it hasn't bitten yet.
