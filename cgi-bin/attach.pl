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

#initialize all the parameters
my $selected = $cgi->param("selected");
my $type = $cgi->param("type");
my $access_key = $cgi->param("access_key");
my $secret_key = uri_unescape($cgi->param("secret_key"));
my $endpoint = $cgi->param("endpoint");
my $instance_id = $cgi->param("instance_id");

if ($type eq 'unattached'){
	attach($selected, $access_key, $secret_key, $endpoint, $instance_id);
} else {
	unattach($selected, $access_key, $secret_key, $endpoint, $instance_id);
}

sub attach
{
  my $selected = shift;
  my $access_key = shift;
  my $secret_key = shift;
  my $endpoint = shift;
  my $instance_id = shift;
  chomp (my $zone = `curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`);
  # chop $zone;  # remove trailing 'a','b'...

  #connect to EC2
  my $ec2 = VM::EC2->new(-access_key => $access_key,
                      -secret_key => $secret_key,
                      -endpoint   => $endpoint) or die $!;

  # Find the snapshot so that the volume we create can have the same tags
  my $snapshot = $ec2->describe_snapshots($selected);

  # Create our new volume and attach it with the tags and a device_id
  my $volume = $ec2->create_volume(-zone=>$zone, -snapshot_id=>$selected) or die $ec2->error;
  $volume->add_tags($snapshot->tags); 
  my $device_id = device_id($ec2, $instance_id);

  $volume->attach($instance_id, $device_id) or die $ec2->error;

  # Attach the volume to all the slave machines 
  my @slave_instances = $ec2->describe_instances(-filter=>{'tag:SlaveOf'=>$instance_id, 'instance-state-name'=>['running','pending']});

  foreach my $instance (@slave_instances){
  	# Create our new volume and attach it with the tags and a device_id
	my $volume = $ec2->create_volume(-zone=>$zone, -snapshot_id=>$selected) or die $ec2->error;
	$volume->add_tags($snapshot->tags);
	$volume->attach($instance->instanceId, $device_id) or die $ec2->error;
  	
	# Now we restart the instance so the volume is mounted
	$instance->reboot();
   }

}

sub unattach
{
  my $selected = shift;
  my $access_key = shift;
  my $secret_key = shift;
  my $endpoint = shift;
  my $instance_id = shift;

  #connect to ec2
  my $ec2 = VM::EC2->new(-access_key => $access_key,
                      -secret_key => $secret_key,
                      -endpoint   => $endpoint);

  #unattach and delete the volume that corresponds to the snapshot
  my @attached_volumes = $ec2->describe_volumes(-filter => ["attachment.instance-id=$instance_id"]) or die $ec2->error;
  my $volume;

  foreach my $attached (@attached_volumes){
	my $snapshot_id = $attached->snapshotId();
	if($snapshot_id eq $selected){
		$volume = $attached;
		last;
	}
  }

  my $status = $volume->detach;

  # Delete the volume once it is detached
  while($status->current_status ne 'detached'){
	sleep 2;
  }
  $ec2->delete_volume($volume); 

  # unattach the volume from all the slave machines 
  my @slave_instances = $ec2->describe_instances(-filter=>{'tag:SlaveOf'=>$instance_id, 'instance-state-name'=>['running','pending']});

  foreach my $instance (@slave_instances){
         my @attached_slave_volumes = $ec2->describe_volumes(-filter => ["attachment.instance-id=$instance"]);
  	 my $slave_volume;

	foreach my $attached (@attached_slave_volumes){
        	my $snapshot_id = $attached->snapshotId();
	        if($snapshot_id eq $selected){
        	        $slave_volume = $attached;
                	last;
        	}
  	}
	
	# Each volume needs to be detached before it can be deleted
  	my $vol_status = $slave_volume->detach if $slave_volume;
	$slave_volume->add_tags(Delete=>'Yes') if $slave_volume;
  }
}

sub device_id
{
  my $ec2 = shift;
  my $instance_id = shift;
  my @attached_volumes = $ec2->describe_volumes(-filter => ["attachment.instance-id=$instance_id"]) or die $ec2->error;
  my @letters = ("f","g","h","i","j","k","l","m","n","o","p");
  my $mounted = `df -h` or die $!;
  my $device_id;

  # Using an array of valid letters and a loop for the valid numbers, we find the first open device_id
  Device_name: foreach my $letter(@letters){
 	for(my $count = 1; $count < 17; $count++){
		$device_id = "/dev/sd$letter$count";

		if ($mounted =~ m/$device_id/){
			next;
		} else {
			last Device_name;
		}			
	}
  }

  return $device_id;
}


