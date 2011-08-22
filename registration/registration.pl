#!/usr/bin/perl
use strict;
use VM::EC2;

use constant PORT_RANGE              => '8101-8103';

if (-r "/home/gbrowse/.eucarc") {
   open my $f,"/home/gbrowse/.eucarc" or die "~/.eucarc: $!";
   while (<$f>) {
	chomp;
        my ($key,$value) = /^(EC2\w+)\s*=\s*(.+)/ or next;
	$ENV{$key}=$value;
   }

   my $registration_file = '/home/gbrowse/registration/registration.txt';
   chomp (my $master_id = `curl -s http://169.254.169.254/latest/meta-data/instance-id`);
   # Creating the ec2 object for easier configuration of amazon tools
   my $ec2 = VM::EC2->new(-access_key => $ENV{EC2_ACCESS_KEY}, -secret_key => $ENV{EC2_SECRET_KEY},
                        -endpoint => $ENV{EC2_URL});

   # Removal of slave instances that are no longer available
   # aws_registered is the slaves on amazon, registered are the ones in the registered file
   my @aws_instances = $ec2->describe_instances(-filter=>{'tag:RegisteredTo'=>$master_id});
   my @aws_Dns = map($_->privateDnsName, @aws_instances);

   my @registered_Dns;
   open (REGISTER, "$registration_file") or die $!;	
   while(<REGISTER>){
	my $line = $_;
	$line =~ /:(.*)$/;
	$line = $1;
	chomp $line;
	push(@registered_Dns, $line);
   }
   close REGISTER;

   my %differences;
   @differences{@registered_Dns} = @registered_Dns;
   delete @differences{@aws_Dns};
   my @old_Dns = keys %differences;

   # go through all the renderconf files looking for these ids
   my @organisms = split("\n", `ls /srv/gbrowse/species`);
   foreach my $organism (@organisms){
	my $filename = "/srv/gbrowse/species/$organism/renderfarm.conf";
	if(-e $filename){
		foreach my $Dns (@old_Dns){
		`grep -v $Dns $filename > $filename` if $Dns;
		}
	}
   }

   # Remove the Dns from the registered files list
   my $filename = "$registration_file";
   foreach my $Dns (@old_Dns){
   	`grep -v $Dns $filename > $filename` if $Dns;
    }

   # Registration of new slave instances
   my @new_slaves = $ec2->describe_instances(-filter=>{'tag:RegisterTo'=>$master_id});   
   foreach my $slave (@new_slaves){
	my @volumes = $ec2->describe_volumes(-filter => {"attachment.instance-id"=>$slave});

	foreach my $volume (@volumes){
		my $slave_DNS = $slave->privateDnsName;
		my $organism = $volume->tags->{'Storage'};
		my $filename = "/srv/gbrowse/species/$organism/renderfarm.conf";

		if($organism){
			open F,'>>', $filename or die "Can't write ",$filename,": $!";
			my ($low,$hi) = split /-/,PORT_RANGE;
		    	my $entry = join ' ',map {"http://${slave_DNS}:$_"} ($low..$hi);
			print F " $entry\n";
		} else {
			warn "$volume 'Storage' tag has not been set, check if you want this volume registered";
		}
	}
	$slave->delete_tags(RegisterTo => $master_id);
	$slave->add_tags(RegisteredTo => $master_id);
   }

   # Add the slave to a file containing all individually added slaves
   open (REGISTER, ">>$registration_file") or die $!;	
   foreach(@new_slaves){
	my $slave_DNS = $_->privateDnsName;
   	print REGISTER "$_:$slave_DNS\n";
   }
   close REGISTER;

  # Restart apache to account for the new slaves if it's supposed to be restarted
  if(@new_slaves || @old_Dns){
	system "sudo /etc/init.d/apache2 restart";
  }
}

