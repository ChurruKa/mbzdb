# We need this for all scripts.
use DBI;

$g_version = "7.2";
$g_build_date = "2019-10-31";

# System commands
$g_mv = (($^O eq "MSWin32") ? "move" : "mv");
$g_rm = (($^O eq "MSWin32") ? "del" : "rm");
