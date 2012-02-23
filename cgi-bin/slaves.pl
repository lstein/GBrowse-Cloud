#!/usr/bin/perl
use strict;
use CGI;
use VM::EC2;
use URI::Escape;

use userdata;

# Create the CGI object
my $cgi = new CGI;

# Output the HTTP header
print $cgi->header ( );

my $type = $cgi->param("type");
my $number = $cgi->param("number");
my $endpoint = $cgi->param("endpoint");
chomp (my $instance_id = `curl -s http://169.254.169.254/latest/meta-data/instance-id`);

my ($access_key, $secret_key) = userdata->aws_keys();

if ($type eq 'add'){
	add($number, $access_key, $secret_key, $endpoint, $instance_id);
} else {
	remove($number, $access_key, $secret_key, $endpoint, $instance_id);
}

sub add
{
  my $number = shift;
  my $access_key = shift;
  my $secret_key = shift;
  my $endpoint = shift;
  my $instance_id = shift;

  my $ec2 = VM::EC2->new(-access_key => $access_key,
                      -secret_key => $secret_key,
                      -endpoint   => $endpoint) or die "slaves.pl VM::EC2 object creation failed:$!";

  #Find the slave instances currently running and then find the ones that are new after more are added and return them
  my @init_instances = $ec2->describe_instances(-filter=>{'tag:SlaveOf'=>$instance_id, 'instance-state-name'=>['running', 'pending']});

  # Running the script that attached gbrowse slaves
  `/home/gbrowse/GBrowse/bin/gbrowse_attach_slaves.pl $number $endpoint`;
  my @final_instances =  $ec2->describe_instances(-filter=>{'tag:SlaveOf'=>$instance_id, 'instance-state-name'=>['running', 'pending']});

  my %differences;
  @differences{@final_instances} = @final_instances;
  delete @differences{@init_instances};
  my @instance_ids = keys %differences;
  my $return = '';
  
  foreach(@instance_ids){
  	$return .= "$_&";
  }
  chop($return);

  my $pass = rand(10000000);
  open (FILE, ">/tmp/restart_pass");
  print FILE $pass;
  close FILE;

  print "{\"instances\":\"$return\",\"code\":\"$pass\"}";
}

sub remove 
{
  my $number = shift;
  my $access_key = shift;
  my $secret_key = shift;
  my $endpoint = shift;
  my $instance_id = shift;

  my $ec2 = VM::EC2->new(-access_key => $access_key,
                    -secret_key => $secret_key,
                    -endpoint   => $endpoint) or die "slaves.pl remove VM::EC2 object creation failed:$!";
  
  # Running the script to detach and delete the request number of slaves
  `/home/gbrowse/GBrowse/bin/gbrowse_detach_slaves.pl $number $endpoint`;

  # We return the number of pending instances to confirm how many were deleted
  my @pending_instances = $ec2->describe_instances(-filter=>{'tag:SlaveOf'=>$instance_id, 'instance-state-name'=>'pending'});

  my $pass = rand(100000000);
  open (FILE, ">/tmp/restart_pass");
  print FILE $pass;
  close FILE;
  my $pending = $#pending_instances + 1;
  print "{\"pending\":\"$pending\",\"code\":\"$pass\"}";
}
