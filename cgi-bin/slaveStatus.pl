#!/usr/bin/perl
use strict;
use CGI;
use VM::EC2;
use JSON;
use URI::Escape;

use userdata;
# Create the CGI object
my $cgi = new CGI;

# Output the HTTP header
print $cgi->header ( );

my $instance_id = $cgi->param("slave");
my $endpoint = $cgi->param("endpoint");

# Connect to EC2

my ($access_key, $secret_key) = userdata->aws_keys();


my $ec2 = VM::EC2->new(-access_key => $access_key,
                       -secret_key => $secret_key,
                       -endpoint   => $endpoint) or die $!;

warn $ec2;
warn $instance_id;

my $instance = $ec2->describe_instances($instance_id);

my $status = $instance->current_status;
my $private_ip = $instance->privateIpAddress;
my $private_dns = $instance->privateDnsName;
my $public_dns = $instance->dnsName;

# Return the status and other information for the slave
print "{\"status\":\"$status\",\"private_ip\":\"$private_ip\",\"private_dns\":\"$private_dns\",\"public_dns\":\"$public_dns\"}";
