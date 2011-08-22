#!/usr/bin/perl
use strict;
use VM::EC2;

use Term::ReadLine;

use constant RENDERFARM_CONF         => '/srv/gbrowse/etc/renderfarm.conf';
use constant PORT_RANGE              => '8101-8103';

# This is called on the master to terminate instances.
# EC2_ACCESS_KEY and EC2_SECRET_KEY must be defined
# or passed in as parameters (for administration site)

$ENV{PYTHONPATH}='/usr/local/lib/python2.6/dist-packages';

if ($ARGV[0] =~ /^--?h/) {
    die <<END;
Usage: gbrowse_detach_slaves.pl [number of slaves]

For use with the Amazon GBrowse image.
Terminate indicated number of gbrowse slaves. Relaunch server in render slave mode.
END
}

my $TERM;

# Pass in the keys and url from the administration page or else check eucarc
my $SLAVE_COUNT = shift || 1;
my $ACCESS_KEY = shift;
my $SECRET_KEY = shift;
my $URL = shift;
my $website;

# When called from the webserver, the keys are passed to the script
if(defined($ACCESS_KEY) && defined($SECRET_KEY) && defined($URL)){
    $ENV{EC2_URL}        = $URL;
    $ENV{EC2_ACCESS_KEY} = $ACCESS_KEY;
    $ENV{EC2_SECRET_KEY} = $SECRET_KEY;
    $website = 1;
} else {
    check_eucarc();
    $website = 0;
}

# Creating the ec2 object for easier configuration of amazon tools
my $ec2 = VM::EC2->new(-access_key => $ENV{EC2_ACCESS_KEY}, -secret_key => $ENV{EC2_SECRET_KEY}, 
			-endpoint => $ENV{EC2_URL});

# Find the master instances id and return all the slave instances for that master
chomp (my $master = `curl -s http://169.254.169.254/latest/meta-data/instance-id`);
my @slave_instances = $ec2->describe_instances(-filter=>{'tag:SlaveOf'=>$master, 'instance-state-name' => ['running', 'pending']});

# You cannot remove slaves that don't exist
if($#slave_instances + 1 < $SLAVE_COUNT){
 	$SLAVE_COUNT = $#slave_instances + 1;
}

# Isolate the desired number of slave instances
my @terminated = splice(@slave_instances, 0, $SLAVE_COUNT);

# Terminate the instances their attached volumes are automatically deleted
my @terminated_ids = map($_->instanceId, @terminated);
my @slave_volumes;
foreach (@terminated_ids){
	# keep track of the volumes to be deleted before terminating the instance
	@slave_volumes = $ec2->describe_volumes(-filter => ["attachment.instance-id=$_"]);
	foreach (@slave_volumes){
        	$_->add_tags(Delete=>'Yes');
	}
	$ec2->terminate_instances($_);
}

my $NEW_COUNT = $#slave_instances + 1;
my @instances = map($_->instanceId, @slave_instances);

# Update the renderconf file with information from the remaining slaves
my %ips;
while (keys %ips < $NEW_COUNT) {
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

# Restarting apache to apply changes. The administration site does it later
if(!$website){
    system "sudo /etc/init.d/apache2 restart";
}

exit 0;

sub check_eucarc {
    if (-r "$ENV{HOME}/.eucarc") {
	open my $f,"$ENV{HOME}/.eucarc" or die "~/.eucarc: $!";
	while (<$f>) {
	    chomp;
	    my ($key,$value) = /^(EC2\w+)\s*=\s*(.+)/ or next;
	    $ENV{$key}=$value;
	}
    }

    $ENV{EC2_URL}        ||= get_ec2_url();
    $ENV{EC2_ACCESS_KEY} ||= get_access_key();
    $ENV{EC2_SECRET_KEY} ||= get_secret_key();
}

sub get_ec2_url {
    chomp (my $zone = `curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`);
    chop $zone;  # remove trailing 'a','b'...
    return "http://ec2.$zone.amazonaws.com";
}

sub get_access_key {
    print STDERR "\n";
    print STDERR "I need your EC2 access key id. You can find this under \"Security Credentials\" on your Amazon account page.\n";
    print STDERR "To avoid this prompt in the future, create a ~/.eucarc file containing the line EC2_ACCESS_KEY=<access key>\n";
    return prompt ('EC2_ACCESS_KEY:');
}

sub get_secret_key {
    print STDERR "\n";
    print STDERR "I need your EC2 secret key. You can find this under \"Security Credentials\" on your Amazon account page.\n";
    print STDERR "To avoid this prompt in the future, create a ~/.eucarc file containing the line EC2_SECRET_KEY=<access key>\n";
    return prompt ('EC2_SECRET_KEY:');
}

sub prompt {
    my $prompt = shift;
    $TERM ||= Term::ReadLine->new('gbrowse_detach_slaves.pl');
    return $TERM->readline($prompt);
}
