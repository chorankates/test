#!/usr/bin/perl -w
#  ternary.pl - demonstrates simple and complex ways of using the ternary operator

# expression ? if_true : if_false

use strict;
use warnings;
use 5.010;

# simple method
my ($foo, $bar, $simple);
$foo = 10;
$bar = 5;

print(
	"ternary: \$foo > \$bar \> \$foo : \$bar\n",
	"\t \$foo: $foo\n",
	"\t \$bar: $bar\n",
	);

$simple = $foo > $bar ? $foo : $bar;

print "> simple: $simple\n";

# complex
my ($width, $complex);
$width = 15;

print(
	"ternary: multi branch, look at the source\n",
	"\t \$width: $width\n",
);

$complex =
	($width < 10) ? "small"  :
	($width < 20) ? "medium" :
	($width < 50) ? "large"  :
								"extra-large"; # default..

print "> complex: $complex\n";

exit 0;