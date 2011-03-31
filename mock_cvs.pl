#!/usr/bin/perl -w
# mock_cvs.pl - used to keep files inside and outside of Dropbox up to date

use strict;
use warnings;
use 5.010;        # smart matching
use Getopt::Long; # grab them parameters
use File::Find;   # find them files
use File::Spec;   # normalize pathnames for windows/unix
use File::Copy;   # allows for interactive overwrites
use Digest::MD5;  # generate MD5

# TODO
#      - if running in interactive, allow command line specification of files to look for. this will make skipping 'test.pl' and other known diffs possible
#      - add a timer to the indexing shiz

# hashes to be used:
#  %s       - contains general settings
#  %f       - holds the flags from Getopt::Long
#  %f_cvs   - HoH containing contents of the CVS dir (Dropbox)
#  %f_local - HoH containing files found local to the system (outside DB)

my (%s, %f, %f_cvs, %f_local);
my (@diff);
my ($f_cvs_count, $f_local_count);
$| = 1; # buffering hack

%s = (
    debug      => 0, # 0 <= n <= 3
    os         => m_determineos(),

    diff       => 1, # print the diff of the files, always works on unix, but you  need to have a diff.exe in your path on windows
    diff_flags => "-a -i -b", # -y is cool, but not so good on a small console

    interactive => 0, # prompting that allows updating of out-of-date files
    confirm     => 1, # controls confirmation prompt
	
    dir_uCVS   => [ "/home/you/", ],    # future proofing with arrays
    dir_ulocal => [ $ENV{HOME}, "/usr/local/apache2/cgi-bin", "/usr/lib/cgi-bin/"],
    #dir_uskip  => [ "", ], # skipping in all cases

    dir_wCVS   => [ "c:\\foo", ],
    dir_wlocal => [ "c:\\bar", "c:\\scratch", ],
    #dir_wskip  => [ "c:\\books", ],
    

    glob       => "(\.pl|\.conf)\$", # only look for these files, actually an RE
    );

# set some locations based on OS
if ($s{os} eq "Windows") {
    $s{dir_CVS}   = $s{dir_wCVS};
    $s{dir_local} = $s{dir_wlocal};
} else {
    $s{dir_CVS}   = $s{dir_uCVS};
    $s{dir_local} = $s{dir_ulocal};
}
# we have what we need, deleting for printing sanity
delete $s{dir_uCVS}; delete $s{dir_ulocal};
delete $s{dir_wCVS}; delete $s{dir_wlocal};

GetOptions(\%f, "debug:i", "help", "dir_local:s", "dir_cvs:s", "diff:i", "interactive:i", "confirm:i");

if ($f{help}) { m_help(); exit 0; }

$s{debug}       = $f{debug}                if defined $f{debug};
$s{dir_CVS}     = join(",", $f{dir_cvs})   if defined $f{cvs};
$s{dir_local}   = join(",", $f{dir_local}) if defined $f{local};
$s{diff}        = $f{diff}                 if defined $f{diff};
$s{interactive} = $f{interactive}          if defined $f{interactive};
$s{confirm}     = $f{confirm}              if defined $f{confirm};

m_sdump(\%s) if $s{debug} gt 0;

# populate the cvs and local file hashes
my @lt1 = localtime; # yeah, i like to optimize
foreach (@{$s{dir_CVS}}) {
    $s{method} = "cvs";
    next unless $_;
    unless (-d $_) { print "> CVS SKIPPING '$_', DNE\n"; next; }
    print "> CVS indexing '$_'...";
    find(\&m_populate, $_);
    print "\tdone.\n";
} 
foreach (keys %f_cvs) { $f_cvs_count++; }
#print "> CVS file count: $f_cvs_count\n";
print "\t file count: $f_cvs_count\n";

foreach (@{$s{dir_local}}) {
    $s{method} = "local";
    next unless  $_;
    unless (-d $_) { print "> local SKIPPING '$_', DNE\n"; next; }
    print "> local indexing '$_'...";
    find(\&m_populate, $_);
    print "\tdone.\n";
} 
foreach (keys %f_local) { $f_local_count++; }
#print "> local file count: ", $f_local_count, "\n";
print "\t file count: $f_local_count\n";
my @lt2 = localtime;
print "% indexing took: ", m_timetaken(\@lt1, \@lt2), "\n";

# dump the hashes for debugging/verbosity
if ($s{debug} gt 1) {
    print "DBG> \%f_cvs contents: \n";   
    m_shohdump(\%f_cvs);

    print "\nDBG> \%f_local contents: \n"; 
    m_shohdump(\%f_local);
}

# figure out the differences between the two
@diff = m_difference(\%f_cvs, \%f_local); # really only care about files that are in cvs and local

if ($#diff == -1) {
    print "> RESULTS: success, all files in sync\n";
    exit 0;
} else {
    print "> RESULTS: found ", $#diff + 1, " difference[s]:\n"; 
    my $i;
    sleep 1 unless $s{interactive} == 1;
    @diff = ("\tdifferences already printed") if $s{interactive} == 1;
    foreach (@diff) { 
	$i++;
	if ($i gt 2) { print "> sleeping 2..\n"; sleep 1; $i = 0; } # sleeping while printing results
	print "$_\n";
    }
    exit 1;		      
}

exit 2; # this should never hit

###### subs below
#
# m_determineos()     - returns Windows/Unix  
# m_sdump(\%hash)     - prints out a list of key/value in %hash
# m_shohdump(\%hash)  - prints out a HoH (expecting name,folder,size,md5,mtime)
# m_populate($method) - populates an HoH depending on method       

sub m_determineos {
    # m_determineos() - returns Windows/Unix
    # going to key off of $ENV{Desktop}, Windows will have this defined
    my $os;

    if (($ENV{windir}) and (-d $ENV{windir})) { $os = "Windows"; }
    else { $os = "Unix"; }

    return $os;
}

sub m_sdump {
    # m_sdump(\%hash) - prints out a list of key/value pairs in %hash
    my $href = shift @_; my %h = %{$href};

    print "> m_sdump(): \n";

    while (my ($key, $value) = each %h) {
	if ($value =~ /ARRAY/) { 
	    next unless @{$value};
	    print "\t", $key, " " x (20 - length($key)), join(", ",@{$value}), "\n";
	    next;
	}
	print "\t", $key, " " x (20 - length($key)), $value, "\n";
    }
    return;
}

sub m_shohdump {
    # m_shohdump(\%hash) - prints out a HoH, expecting name,folder,size,md5,mtime
    # md5 is the key column
    my $href = shift @_; my %h = %{$href};

    foreach my $entry (sort { $h{$a}{dir} cmp $h{$b}{dir} } keys %h) {
	my $md5    = $entry;
	my $name   = $h{$entry}{name};
	my $folder = $h{$entry}{dir};
	my $size   = $h{$entry}{size};
	my $mtime  = $h{$entry}{mtime};

	print "name: $name\n", "\t",  $folder, "\n\t", $size, ",", $mtime, ",", $md5, "\n";
    }
    return %h;
}


sub m_populate {
    # m_populate($method) - fills either %f_cvs or %f_local, depending on $mehtod
    # skipping unnecessary file
    return if      $_ eq "." or $_ eq ".."; # skipping symlinks
    return unless  $_ =~ /$s{glob}/i;       # skipping unless we match
    return if      (-d $_);                 # skip if it's a dir
    return  unless (-r File::Spec->canonpath($File::Find::name));  # skip unless we can read

    print "DBG> m_populate: \$_ : $_\n" if $s{debug} gt 2;

    my $method = $s{method}; # scope hacking for convenience
    #print "\$method: $method / \$_: $_\n";

    my $ffp      = File::Spec->canonpath($File::Find::name);
    my $dir      = File::Spec->canonpath($File::Find::dir);
    my $filename = $_;
    my $md5      = m_md5($ffp);
    my $size     = -s _;
    my $mtime    = (stat($ffp))[9]; 

    #if ($s{os} eq "Unix")    { foreach (@{$s{dir_uskip}}) { return if $dir =~ /$_/i; } }
    #if ($s{os} eq "Windows") { foreach (@{$s{dir_wskip}}) { return if $dir =~ /$_/i; } }

    print "\t $ffp, $dir, $filename, $md5, $size, $mtime\n" if $s{debug} gt 2;

    if    ($method eq "cvs")   { 
	# will be populating %f_cvs, md5 as primary key
	$f_cvs{$md5}{name}  = $filename;
	$f_cvs{$md5}{ffp}   = $ffp;
	$f_cvs{$md5}{dir}   = $dir;
	$f_cvs{$md5}{size}  = $size;    
	$f_cvs{$md5}{mtime} = $mtime;
	
	print(
	      "> adding \$_ to CVS hash: '$_'\n",
	      "\t fname: $filename\n",
	      "\t ffp  : $ffp\n",
	      "\t dir  : $dir\n",
	      "\t size : $size\n",
	      "\t mtime: $mtime\n",
	    ) if $s{debug} gt 1;

	if (0 and $ffp =~ /\/ensanity.pl/) {
            print "> adding ensanity.pl !!!! why isn't it showing in HoH later\n";
            print "\$f_cvs, md5: $md5\n";
            print "\tname: $f_cvs{$md5}{name}\n";
            print "\tdir : $f_cvs{$md5}{dir}\n";
	}
	

	

    }
    elsif ($method eq "local") { 
	# will be populating %f_local, md5 as primary key
	# need to skip files that are located in the CVS directory

    #print "> preadding \$dir\$_ to local hash: '$dir''$_'\n";
    
	foreach my $cvs_dir (@{$s{dir_CVS}}) {
	    #print "\n\$dir: $dir";
	    #print "\n\$_  : $_\n";

	    my $substr = substr($dir,0,length($cvs_dir)); # removed the + 1
	    
	    # substr = the current files directory chomped to the same length as
	    # the dynamic (current) CVS directory. this will prevent us from adding files
	    # to the local directory hash if the CVS directory is a subdir of it
	    print "\$ffp: $ffp / \$substr: $substr / \$cvs_dir: $cvs_dir \n" if $s{debug} gt 1;
    
	    return if $substr eq $cvs_dir;

	    #return if substr($dir,0,length($_)) eq $_;
	    #sleep 3; # wont sleep if we have a match
	}
	
	print(
		"> adding \$_ to local hash: '$_'\n",
		"\t fname: $filename\n",
		"\t ffp  : $ffp\n",
		"\t dir  : $dir\n",
		"\t size : $size\n",
		"\t mtime: $mtime\n",
	     ) if $s{debug} gt 1;
	
	$f_local{$md5}{name}  = $filename;
	$f_local{$md5}{ffp}   = $ffp;
	$f_local{$md5}{dir}   = $dir;
	$f_local{$md5}{size}  = $size;
	$f_local{$md5}{mtime} = $mtime;
	
    }
    else                       { die "ERROR: unknown method '$method'"; }

    return;
}

sub m_md5 {
    # m_md5($ffp) - takes an FFP and returns the md5 of it                                
    my $file = shift @_;
    open(FILE, $file) or die "m_md5> can't open '$file': $!";
    binmode(FILE);

    my $md5 = Digest::MD5->new->addfile(*FILE)->hexdigest;

    close(FILE);

    return $md5;
}


sub m_difference {
    # m_difference(\%cvs, \%local) - 
    my (@diff, $href1, $href2);
    $href1 = shift @_;  $href2 = shift @_;
    my %h1 = %{$href1}; my %h2 = %{$href2};

    # h1 = f_cvs
    # h2 = f_local

    foreach (sort { $h1{$a}{ffp} cmp $h1{$b}{ffp} } keys %h1) { 
	
	# examine each key in cvs
	my $c_name  = $h1{$_}{name};
	my $c_md5   = $_;
	my $c_ffp   = $h1{$_}{ffp};
	my $c_size  = $h1{$_}{size};  my $c_nsize  = m_nicesize($c_size);
	my $c_mtime = $h1{$_}{mtime}; my $c_nmtime = localtime($c_mtime);
	my $c_dir   = $h1{$_}{dir};

	if (exists $h2{$_}) {
	    # file is identical (md5) in cvs and local
	    print "DBG> m_difference(): '$c_ffp' is an MD5 match in CVS and local, next..\n" if $s{debug} gt 1;
	} else {
	    foreach (sort { $h2{$a}{ffp} cmp $h2{$b}{ffp} } keys %h2) {
		#print "\$_ : $_ and \$cname: $c_name\n"; sleep 2;
		if ($c_name eq $h2{$_}{name}) {
		    # file is in both cvs and local, but not identical
		    my $l_name  = $h2{$_}{name};
		    my $l_md5   = $_;
		    my $l_ffp   = $h2{$_}{ffp};
		    my $l_size  = $h2{$_}{size};  my $l_nsize  = m_nicesize($l_size);
		    my $l_mtime = $h2{$_}{mtime}; my $l_nmtime = localtime($l_mtime);
		    my $l_dir   = $h2{$_}{dir};

			# TODO enclose the larger filesize and newer mtime in []
			# these may or may not be the same, and will make comparisons easier
		
			my @t_size  = ($c_nsize, $l_nsize);
			$t_size[0] = "[" . $t_size[0] . "]" if $c_size gt $l_size;
			$t_size[1] = "[" . $t_size[1] . "]" if $l_size gt $c_size;
			
			my @t_mtime = ($c_nmtime, $l_nmtime); 
			$t_mtime[0] = "[" . $t_mtime[0] . "]" if $c_mtime gt $l_mtime;
			$t_mtime[1] = "[" . $t_mtime[1] . "]" if $l_mtime gt $c_mtime;
			
		    my $diffstring = "[$c_name] different in \n\t$c_dir\n\t\tmd5:$c_md5\n\t\tsize: $t_size[0]\n\t\tmtime: $t_mtime[0]\n\t$l_dir\n\t\tmd5: $l_md5\n\t\tsize: $t_size[1]\n\t\tmtime: $t_mtime[1]\n";
		    push @diff, $diffstring;

			if ($s{diff} eq 1) { 
				# running diff against the different files
				my @diff = `diff $s{diff_flags} \"$c_ffp\" \"$l_ffp\"`; 
				@diff = ("[NULL]\n") unless $#diff > 0;
				print "<diff $c_ffp>\n";
				foreach (@diff) { print $_; }
				print "</diff>\n";
			}
			
			if ($s{interactive} eq 1) { 
				# interactive mode
				print "interactive> $diffstring";
				#if ($l_mtime gt $c_mtime) { print "local file [$l_ffp]\n is newer than $c_ffp\n"; }
				#if ($c_mtime gt $l_mtime) { print "cvs file [$c_ffp]\n is newer than $l_ffp\n"; }
				
				#if ($l_size gt $c_size) { print "local size [$l_nsize]\n is bigger than $c_nsize\n"; }
				#if ($c_size gt $l_size) { print "cvs size [$c_nsize]\n is bigger than $l_nsize\n"; }
				print "interactive>\n\t1 overwrites local file   [$l_dir]\n\t2 overwrites cvs file     [$c_dir]\n\t3 skip this file\n> ";
				chomp(my $choice = <STDIN>);
				if ($choice eq 1) {
					my $confirmation;
					if ($s{confirm}) {
					    print "> confirm overwrite of '$l_ffp' with '$c_ffp'? [Y/N] "; 
					    chomp($confirmation = <STDIN>);
					} else { $confirmation = "y"; } # overloads the confirmation variable
					
					copy("$c_ffp","$l_ffp") or die "die> unable to overwrite '$l_ffp':$!, skipping" if $confirmation =~ /y/i;
					next if $confirmation =~ /n/i;
					print "> successfully overwrote '$l_ffp' with '$c_ffp'\n";
				}
				elsif ($choice eq 2) { 
					my $confirmation;
					if ($s{confirm}) {
					    print "> confirm overwrite of '$c_ffp' with '$l_ffp'? [Y/N] "; 
					    chomp($confirmation = <STDIN>);
					} else { $confirmation = "y"; } # overloads the confirmation variable
					
					copy("$l_ffp","$c_ffp") or die "die> unable to overwrite '$c_ffp':$!, skipping" if $confirmation =~ /y/i;
					next if $confirmation =~ /n/i;
					print "> successfully overwrote '$c_ffp' with '$l_ffp'\n";
				}
				elsif ($choice eq 4) { print "> exiting based on '4', OK.\n"; exit 0; }
				else { print "> skipping '$c_name', OK\n"; }
			}

		}
		   # print "this should not happen: $c_name \ $h2{$_}{name}\n";
	    }
	}
	# not going to handle files that are not in both locations

    }
    return @diff;
}

sub m_nicesize {
	# nicesize($size) - takes 1024 and returns 1mb (input is assumed to be bytes)
	my ($b, $k, $m, $g);
	my (@out, $output, $max_type);

	$max_type = "0"; # 4=gb, 3=mb, 2=kb, 1=b

	$b = shift @_;
	$g = int($b / (1024 * 1024 * 1024)); # there are 1073471824 bytes in each GB
	$b %= 1024*1024*1024;
	$m = int($b / (1024 * 1024));        # there are 1048576 bytes in each MB
	$b %= 1024*1024;
	$k = int($b / 1024);                 # there are 1024 bytes in each KB
	$b %= 1024;

	# build the return
	# start by finding the biggest class (MB or GB usually)
	if ($g gt 0) { 
	    push @out, $g;
	    if ($max_type lt 4) { $max_type = 4; }
	}
	if ($m gt 0) {
	    push @out, $m;
	    if ($max_type lt 3) { $max_type = 3; }
	}
	if ($k gt 0) {
	    push @out, $k;
	    if ($max_type lt 2) { $max_type = 2; }
	}
	if (($g eq 0) and ($m eq 0) and ($k eq 0)) {
	    push @out, $b;
	    if ($max_type lt 1) { $max_type = 1; }
	}

	if ($max_type eq 4) { $max_type = "gb"; }
	elsif ($max_type eq 3) { $max_type = "mb"; } 
	elsif ($max_type eq 2) { $max_type = "kb"; }
	elsif ($max_type eq 1) { $max_type = "b"; }

	$output = join(".",@out);
	$output = $output . $max_type;

	return $output;
}

sub m_help {
    # n_help() - prints a helpful explanation, no return
    # include some sample command line entries
    
    print(
        "[$0] - syntax: --help, --debug=N, --dir_local=CSV, --dir_cvs=CSV, --diff=N, ",
        "--interactive=N, --confirm=N",
        "\n\n",
        "> general: \n",
        "   - all parameters are optional, but script falls back to coded defaults if unspecified\n",
        "\n",
        "> specific:\n",
        "   --debug=N        level of debugging, 1 <= n <= 3\n",
	"   --dir_local=CSV  sets the local dirs to search\n",
	"   --dir_cvs=       sets the CVS dir (typically Dropbox)\n",
	"   --diff=N         runs a system 'diff' against the files\n",
	"   --interactive=N  allows user to bring files into sync, recommend diff=1\n",
	"   --confirm=N      allows user to skip confirmation in interactive mode (0 is don't confirm)\n",
        
        "\n",
        "examples:\n",
        "  $0 --diff=1 --i=1 --c=0\n",
        "\t [most commonly used syntax, displays file differences, allows updates and skips confirmation]\n",
        "  $0 --debug=1 --local_dir=c:\\test --diff=0 --i=1\n",
        "\t [sets local dir to a Win32 dir, just displays a binary difference in interactive mode]\n",
	"  $0 --local_dir=/home/conor/scratch,/home/conor/test, --diff=1 --i=0\n",
	"\t [sets local dir on Unix dir, prints out differences and quits]\n",
    );

}


sub m_nicetime {
    # nicetime(\@time, type) - returns time/date according to the type 
    # types are: time, date, both
    my $aref = shift @_; my @time = @{$aref};
    my $type = shift @_ || "both"; # default variables ftw.
    warn "warn>  e_nicetime: type '$type' unknown" unless ($type =~ /time|date|both/);

    my $hour = $time[2]; my $minute = $time[1]; my $second = $time[0];
    $hour    = 0 . $hour   if $hour   < 10;
    $minute  = 0 . $minute if $minute < 10;
    $second  = 0 . $second if $second < 10;

    my $day = $time[3]; my $month = $time[4] + 1; my $year = $time[5] + 1900;
    $day   = 0 . $day   if $day   < 10;
    $month = 0 . $month if $month < 10;

    my $time = $hour .  "." . $minute . "." . $second;
    my $date = $month . "." . $day    . "." . $year;

    my $full = $date . "-" . $time;

    if ($type eq "time") { return $time; }
    if ($type eq "date") { return $date; }
    if ($type eq "both") { return $full; }
}

sub m_timetaken {
    # timetaken(\@time1, \@time2) - returns the difference between times
    # right now only supporting diffs measured in hours, and will break on wraparound hours
    my ($aref1, $aref2, @time1, @time2);
    $aref1 = shift @_;  $aref2 = shift @_;
    @time1 = @{$aref1}; @time2 = @{$aref2};
	
	my ($diff_second, $diff_minute, $diff_hour);
    # main handling
    if ($time1[0] <= $time2[0]) {
		$diff_second = $time2[0] - $time1[0];
		$diff_minute = $time2[1] - $time1[1];
	} else {
		$diff_second = ($time2[0] + 60) - $time1[0];
		$diff_minute = ($time2[1] - 1) - $time1[1];
	}
    # still need to resolve the hour wraparound, but low priority
    $diff_hour   = $time2[2] - $time1[2];

    # stickler for leading 0 if 1 < N > 10, flexing some regex muscle
    foreach ($diff_second, $diff_minute, $diff_hour) { $_ =~ /^(\d{1})$/; if (($1) and length($1) eq 1) { $_ = 0 . $_; } }


    my $return = $diff_hour . "h" . $diff_minute . "m" . $diff_second . "s";
    return $return;

}
