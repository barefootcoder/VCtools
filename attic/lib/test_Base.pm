package test_Debug;

use VCtools::Base;

die("DEBUG value didn't fall through") unless DEBUG == 2;

1;
