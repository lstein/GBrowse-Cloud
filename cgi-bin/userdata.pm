package userdata;

our $VERSION = 0.01;
use strict;
use warnings;

use VM::EC2;

our %userdata;

sub aws_keys {
    userdata();
    if (defined $userdata{'access_key'} && defined $userdata{'secret_key'}) {
        return ($userdata{'access_key'},$userdata{'secret_key'});
    }
    else {
        die "failed to get access and secret keys";
    }
}

sub password {
    userdata();
    if (defined $userdata{'password'}) {
        return $userdata{'password'};
    }
    else {
        die "failed to get password from userdata";
    }
}

sub endpoint {
    chomp (my $zone = `curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`);
    chop $zone;  # remove trailing 'a','b'...
    my $endpoint = "http://ec2.$zone.amazonaws.com";
    return $endpoint;
}


sub userdata {
    return if defined %userdata;

    my $metadata_obj = VM::EC2->instance_metadata;
    my $userdata     = $metadata_obj->userData;

    %userdata =  map {split /\s*\:\s*/, $_ } split "\n", $userdata;
    return;
}

1;
