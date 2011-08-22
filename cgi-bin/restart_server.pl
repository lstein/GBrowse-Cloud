#!/usr/bin/perl
use strict;
use CGI;

# Create the CGI object
my $cgi = new CGI;

# Output the HTTP header
print $cgi->header ( );
my $password = $cgi->param("pass");

open (FILE, "/tmp/restart_pass");
my $saved_pass = <FILE>;
close FILE;

if($password eq $saved_pass){
 `sudo perl /tmp/restart_apache`;
}

open (FILE, ">/tmp/restart_pass");
print FILE;
close FILE;
