#!/usr/bin/perl
use strict;
use VM::EC2;
use Bio::Graphics::Browser2::Cloud::Userdata;

use Term::ReadLine;

use constant RENDERFARM_CONF         => '/srv/gbrowse/etc/renderfarm.conf';
use constant IMAGE_MAP               => '/srv/gbrowse/etc/ami_map.txt';
use constant SLAVE_SECURITY_GROUP    => 'GBrowseSlave';
use constant MASTER_SECURITY_GROUP   => 'GBrowseMaster';
use constant PORT_RANGE              => '8101-8103';

# This is called on the master to launch instances.
# It discovers which species are mounted
# on the current instance, snapshots them, and
# attaches them to the slave(s).
# EC2_ACCESS_KEY and EC2_SECRET_KEY must be defined
# or passed in as parameters (for administration site)

$ENV{PYTHONPATH}='/usr/local/lib/python2.6/dist-packages';

if ($ARGV[0] =~ /^--?h/) {
    die <<END;
Usage: gbrowse_attach_slaves.pl [number of slaves]

For use with the Amazon GBrowse image.
Launch indicated number of gbrowse slaves and attach the current set of
mounted data directories to them. Relaunch server in render slave mode.
END
}

my $TERM;

# Pass in the keys and url from the administration page or else check eucarc 
my $SLAVE_COUNT = shift || 1;
my $ACCESS_KEY  = shift;
my $SECRET_KEY  = shift;
my $URL         = shift;
my $website;

if(defined($ACCESS_KEY) && defined($SECRET_KEY) && defined($URL)){
    $ENV{EC2_URL}        = $URL;
    $ENV{EC2_ACCESS_KEY} = $ACCESS_KEY;
    $ENV{EC2_SECRET_KEY} = $SECRET_KEY;
    $website = 1;    
} else {
    check_eucarc();
    $website = 0;
}

# Creating the ec2 object for easier configuration using amazon tools
my $ec2 = VM::EC2->new(-access_key => $ENV{EC2_ACCESS_KEY}, 
                       -secret_key => $ENV{EC2_SECRET_KEY}, 
		       -endpoint => $ENV{EC2_URL});

my @mounts       = get_species_mounts();
my $snapshot_map = get_snapshot_map(\@mounts);
my $ami_map      = get_ami_map();

# Set up the block devices that need to be attached
my @devices = map {"/dev/sd$_"} ('h'..'z');
my $i = 0;
my @block_args    = ('-block_devices =>','\'/dev/sdg=:0:true\',',map {
    my $device    = $devices[$i++];
    my $species   = $_->[1];
    my $snapshot  = $snapshot_map->{$species};
    $snapshot ? ('-block_devices =>',"\'${device}=${snapshot}:0:true\',") : ();  # all these volumes are terminate-on-delete
} @mounts);

my $ami      = $ami_map->{GBROWSE_SLAVE} or die "Couldn't look up current AMI for the slave";
my $key      = get_keypair();
my $security = get_security_group();

# Now get the IP addresses of these instances using VM::EC2
my $image = $ec2->describe_images($ami);
chomp (my $master    =`curl -s http://169.254.169.254/latest/meta-data/instance-id`);
chomp (my $placement =`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`);

my @instances = $image->run_instances(-key_name       => $key, 
                                      -instance_type  => 't1.micro', 
                                      -min_count      => $SLAVE_COUNT, 
                                      -zone           => "$placement", 
                                      -security_group => $security,
                                      -userdata       => "masterid:$master",
                                      @block_args ) or die $ec2->error;

# insert code to tag all slaves to the master instance_id and mark them as registered -aelnaiem
foreach(@instances){
    # We wait because some instance ids are not defined right away
    while(!defined($_)){
	sleep 2;
    }
    $_->add_tags(SlaveOf => $master);
}

my %ips;
while (keys %ips < $SLAVE_COUNT) {
    print "waiting for instance to start....\n";
    sleep 5;
    chomp (my $output = `euca-describe-instances @instances`);
    for my $line (split "\n",$output) {
	next unless $line =~ /^INSTANCE/;
	my @fields = split "\t",$line;
	$ips{$fields[4]}++ if $fields[4];
    }
}

open F,'>',RENDERFARM_CONF or die "Can't write ",RENDERFARM_CONF,": $!";
print F "renderfarm = 1\n";
print F "remote renderer =\n";
my ($low,$hi) = split /-/,PORT_RANGE;
foreach my $ip ('localhost',keys %ips) {
    my $slaves = join ' ',map {"http://${ip}:$_"} ($low..$hi);
    print F " $slaves\n";
}
close F;

# attach to the slaves all the volumes that are on the master
my @attached_volumes = $ec2->describe_volumes(-filter => {"attachment.instance-id"=>$master});
foreach my $instance (@instances){
	# tag all slaves to the master instance_id
	$instance->add_tags(SlaveOf => $master);

	foreach my $volume (@attached_volumes){
		# We don't copy over the Root volumes
		  unless($volume->tags->{'Name'} eq 'Root' || $volume->tags->{'Name'} eq '/srv/gbrowse'){
		  # get the device mapping for the volume
	 	  my @mapping = $volume->attachment->instance->blockDeviceMapping;
             	  my ($map) = grep {$volume eq $_->volumeId} @mapping;

                  # Create our new volume and attach it the same as the master
       	 	  my $new_volume = $ec2->create_volume(-zone=>$placement, -snapshot_id=>$volume->snapshotId);
        	  $new_volume->attach($instance->instanceId, $map->deviceName) or die $ec2->error;
		}
	}
	$instance->reboot();
  }



# Restarting apache to apply changes. The administration site does it later
if(!$website){
    system "sudo /etc/init.d/apache2 restart";
}

exit 0;

sub get_snapshot_map {
    my $mounts = shift;
    my (%vol2snap,%mount2vol,%map);

    print "Identifying slave AMI...\n";

    chomp (my $instance = `curl -s http://169.254.169.254/latest/meta-data/instance-id`);
    chomp (my $volumes  = `euca-describe-volumes`);

    # get volume and snapshot id for each mounted volume
    for my $line (split "\n",$volumes) {
	if ($line =~ /^VOLUME/) {
	    my ($vol,$snap) = (split /\t/,$line)[1,3];
	    $vol2snap{$vol} = $snap;
	} elsif ($line =~ /^ATTACHMENT/) {
	    next unless $line =~ /\s$instance\s/;
	    my ($vol,$mount) = (split /\t/,$line)[1,3];
	    $mount2vol{$mount} = $vol;
	}
    }

    for my $m (@$mounts) {
	my ($device,$species) = @$m;
	$device =~ s/\d+$//;
	my $vol  = $mount2vol{$device} or next;
	my $snap = $vol2snap{$vol};
	$snap  ||= make_snap($vol);
	$map{$species} = $snap;
    }

    return \%map;
}

sub make_snap {
    die "make_snap() unimplemented";
}

sub get_species_mounts {
    print "Determining which volumes to mount...\n";
    my @mounts;
    open F,'/proc/mounts' or die "Can't open /proc/mounts: $!";
    while (<F>) {
	chomp;
	my ($dev,$mount_point,@etc) = split /\s+/;
	next unless $mount_point =~ m!/srv/gbrowse/species/([^/]+)!;
	push @mounts,[$dev,$1];
    }
    close F;
    return @mounts;
}

sub get_ami_map {
    my %map;
    open F,IMAGE_MAP or die "Can't open ",IMAGE_MAP,": $!";
    while (<F>) {
	chomp;
	next if /^#/;
	my ($role,$ami) = split /\s+/;
	$map{$role} = $ami;
    }
    close F;
    return \%map;
}

sub get_keypair {
    my $out = `curl -s http://169.254.169.254/latest/meta-data/public-keys/`;
    my ($keyname) = $out =~ /0=(.+)/;
    return $keyname;
}

sub get_security_group {
    print <<END;
Creating appropriate security group...
If you see duplication warnings, it is because there are already (possibly inactive)
slave instances defined for this master. This will not adversely affect the new slaves,
but you may wish to terminate the old ones to recover storage space.
END

    my $ssg        = SLAVE_SECURITY_GROUP;
    my $range      = PORT_RANGE;
    chomp (my $ip = `curl -s http://169.254.169.254/latest/meta-data/local-ipv4/`);
    chomp (my $instance = `curl -s http://169.254.169.254/latest/meta-data/instance-id`);
    $ssg   .= "-$instance";
    chomp (my $result   = `euca-delete-group $ssg`);
    chomp ($result = `euca-add-group -d'security group for gbrowse render slaves allows ssh and ports $range' $ssg`);
    warn   $result unless $result =~ /^GROUP/;
    chomp ($result = `euca-authorize -P tcp -p 22 -s $ip/32 $ssg`);	
    warn   $result unless $result =~ /PERMISSION/;
    chomp ($result = `euca-authorize -P tcp -p $range -s $ip/32 $ssg`);
    warn   $result unless $result =~ /PERMISSION/;
    return $ssg;
}

sub check_eucarc {
    $ENV{EC2_URL} = userdata->endpoint();
    ($ENV{EC2_ACCESS_KEY}, $ENV{EC2_SECRET_KEY}) = userdata->aws_keys();
}

