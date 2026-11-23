'use strict';

// CLI of the accounting library (run by xguardd, xguardctl and the rpcd plugin; callers serialise with flock).
//   acct.uc harvest        read the kernel counters, update today's statistics (every few seconds)
//   acct.uc flush          harvest + write the day file to flash now (shutdown, ruleset changes)
//   acct.uc reset [key]    zero the usage of one quota user (key = ip:1.2.3.4 | mac:aa:..) or of all
//   acct.uc clear          forget the reports (day files); quota usage is kept
//   acct.uc report [day]   print the report as JSON

import { harvest, reset_user, clear_stats, report } from './acctlib.uc';

let cmd = ARGV[0];

switch (cmd) {
case 'harvest':
	harvest(false);
	break;
case 'flush':
	harvest(true);
	break;
case 'reset':
	print(reset_user(ARGV[1] || 'all'), '\n');
	break;
case 'clear':
	clear_stats();
	break;
case 'report':
	print(sprintf('%J', report(ARGV[1])), '\n');
	break;
default:
	die('usage: acct.uc harvest|flush|reset [key]|clear|report [day]');
}
