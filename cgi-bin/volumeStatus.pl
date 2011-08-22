#!/usr/bin/perl
use strict;
use CGI;
use VM::EC2;
use JSON;
use URI::Escape;

# Create the CGI object
my $cgi = new CGI;

# Output the HTTP header
print $cgi->header ( );

my $snapshot_id = $cgi->param("snapshot");
my $access_key = $cgi->param("access_key");
my $secret_key = uri_unescape($cgi->param("secret_key"));
my $endpoint = $cgi->param("endpoint");
chomp (my $instance_id = `curl -s http://169.254.169.254/latest/meta-data/instance-id`); 

# Connect to EC2
my $ec2 = VM::EC2->new(-access_key => $access_key,
                       -secret_key => $secret_key,
                       -endpoint   => $endpoint);

# Return the attachment status for the volume
my $volume = $ec2->describe_volumes(-filter => {"attachment.instance-id"=>$instance_id, "snapshot-id"=>$snapshot_id});
my $status = '';
my $attachment = $volume->attachment if $volume;
$status = $attachment->current_status if $volume;

# delete any volumes that were tagged for deleting
my @delete_volumes = $ec2->describe_volumes(-filter=>{'tag:Delete' => 'Yes'});
foreach(@delete_volumes){
      $ec2->delete_volume($_);
}

print "{\"status\":\"$status\"}";
