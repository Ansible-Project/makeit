#!/usr/bin/perl

#
#	given a specifier,
#	generate "group_vars/all.yml" file telling
#	makeit what to make.
#
#	input:
#		-g group
#		-d DISTID
#		-l DATACENTERID
#		-p password
#		-s ssh-key
#		A B C D E F
#	A:
#		| [0-9]+ "x" ;	-- specify # of instances
#	B:
#		| [0-9]+ ;	-- planid
#	C:
#		[a-z]*		-- name, such as "rgw".
#	E:	| size ;	-- amount of disk for swap
#	F:	| F | "/" count "x" size | F "/" size	-- extra disk
#		| F "/" [jkmor]* ;	-- switches; jumphost etc.
#	count:	[0-9]*
#	size:	[ 0-9]+[kmg]
#
#

use common::sense;
use Clone qw(clone);

my $dflag;
my $gflag;
my $lflag;
my $pflag;
my $Pflag;
my $sflag;
my $rc;

my $tags = {
'j' => 'jumphost',
'k' => 'keystone',
'm' => 'mon',
'o' => 'osd',
'r' => 'radosgw',
};

my %counts;

sub generate_name
{
	my ($name) = @_;
	my $instance = ++$counts{$name};
	return "$name$instance";
}

sub get_size
{
	my ($j) = @_;
	my $multiplier = 1;
	if ($j =~ m%^([0-9]+)([kmg])$%) {
		my $count = substr($j, $-[1], $+[1]-$-[1]);
		my $type = substr($j, $-[2], $+[2]-$-[2]);
		if ($type eq 'm') {
			$multiplier = 1024;
		}
		elsif ($type eq 'g') {
			$multiplier = 1048576;
		}
		$count *= $multiplier;
		return $count;
	} else {
		die "Invalid size: $j\n";
	}
}

sub make_hosts
{
	my ($j) = @_;
	my $r = {};
	my @r;
	my $count = 1;
	my $name = '';
	my $size;
	my @extra;
	my @tags;
	my $nstorage;
	if ($j =~ m%^([0-9]+)x%) {
		$count = 0+substr($j, $-[1], $+[1]-$-[1]);
		substr($j, $-[1], 1+$+[1]-$-[1]) = '';
	}
	if ($j =~ m%^([-_a-z]+)%) {
		$name = substr($j, $-[1], $+[1]-$-[1], '');
	}
	if ($j =~ m%^([0-9]+)%) {
		$r->{planid} = substr($j, $-[1], $+[1]-$-[1], '');
	}
	$r->{password} = $pflag if defined($pflag);
	$r->{distribution} = $dflag if defined($dflag);
	$r->{datacenter} = $lflag if defined($lflag);
	$r->{sshkey} = $sflag if defined($sflag);
	$r->{group} = $gflag if defined($gflag);
	while ($j =~ m%^/%) {
		substr($j, $-[0], $+[0]-$-[0], '');
		$nstorage = 1;
		if ($j =~ m%^([jkmor]+)%) {
			my $jk = substr($j, $-[1], $+[1]-$-[1], '');
			for my $c ( split('', $jk ) ) {
				push @tags, $tags->{$c};
			}
			next;
		}
		if ($j =~ m%^([0-9]+)x%) {
			$nstorage = 0+substr($j, $-[1], $+[1]-$-[1]);
			substr($j, $-[1], 1+$+[1]-$-[1]) = '';
		}
		last if (!($j =~ m%^([0-9]+[kmg])%));
		$size = get_size(substr($j, $-[1], $+[1]-$-[1], ''));
		while ($nstorage > 0) {
			--$nstorage;
			if (!defined($r->{swap})) {
				$r->{swap} = $size;
			} else {
				my $e = {};
				push @extra, $e;
				$e->{label} = "storage-".(1+$#extra);
				$e->{size} = $size;
				$e->{type} = 'raw';
			}
		}
	}
	if ($j) {
		die "Did not eat all of host specifier, left: <$j>\n";
	}
	@{$r->{extra}} = @extra if @extra;
	@{$r->{tags}} = @tags;
	for my $i ( 1..$count) {
		my $q = clone($r);
		$q->{name} = generate_name($name);
		push @r, $q;
	}
	return @r;
}

sub process_opts
{
	my @r;
	my $f;
	for my $j ( @_ ) {
		if (defined($f)) {
			&$f($j);
			undef $f;
			next;
		}
#		if ($j eq "-k") {
#			++$kflag;
#			next;
#		}
		if ($j eq "-d") {
			$f = sub {
				my ($f) = @_;
				$dflag = $f;
			};
			next;
		}
		if ($j eq "-g") {
			$f = sub {
				my ($f) = @_;
				$gflag = $f;
			};
			next;
		}
		if ($j eq "-l") {
			$f = sub {
				my ($f) = @_;
				$lflag = $f;
			};
			next;
		}
		if ($j eq "-p") {
			$f = sub {
				my ($f) = @_;
				$pflag = $f;
			};
			next;
		}
		if ($j eq "-s") {
			$f = sub {
				my ($f) = @_;
				$sflag = $f;
			};
			next;
		}
		if ($j eq "-P") {
			++$Pflag;
			next;
		}
#		if ($j eq "-d") {
#			++$dflag;
#			next;
#		}
		push @r, make_hosts($j);
	}
	return @r;
}

sub write_hosts
{
	print ("---\nmake_some_stuff:\n");
	for my $j ( @_ ) {
		print "- name: ".$j->{name}."\n" if defined($j->{name});
		print "  plan: ".$j->{planid}."\n" if defined($j->{planid});
		print "  datacenter: ".$j->{datacenter}."\n" if defined($j->{datacenter});
		print "  distribution: ".$j->{distribution}."\n" if defined($j->{distribution});
		print "  password: ".$j->{password}."\n" if defined($j->{password});
		print "  private_ip: yes\n" if $Pflag;
		print "  ssh_pub_key: '".$j->{sshkey}."'\n" if defined($j->{sshkey});
		print "  swap: ".$j->{swap}."\n" if defined($j->{swap});
		print "  displaygroup: ".$j->{group}."\n" if defined($j->{group});
		if (exists($j->{extra})) {
		print "  additional_disks:\n";
			for my $i ( @{$j->{extra}}) {
				print "   - {";
				print "Label: '".$i->{label}."'";
				print ", Size: ".($i->{size}/1048576)."";
				print ", Type: '".$i->{type}."'";
				print "}\n";
			}
		}
		if (exists($j->{tags})) {
		print "  tags:\n";
			for my $i ( @{$j->{tags}}) {
				print "   - $i\n";
			}
		}
	}
	print "my_ssh_key: '".$sflag."'\n"
		if defined($sflag);
}

my @hosts = process_opts(@ARGV);
write_hosts(@hosts);
exit($rc);
__END__
---
make_some_stuff:
- name: my-linode-1
  plan: 1
  datacenter: 4
  distribution: 129
  password: sastmaugeleptuormegeltoilasympapsianhanicryonymordigmageoubeD6
  private_ip: yes
  ssh_pub_key: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3UgNoKnsDehvM195bhSr+7E8AdoYuM2OGrcWC5zwmASisufRmXT7nQwNKTLpYEe6SgHI39CWlRIUT9mqADXazpRlAT7mqBwwRUVc4/O5e41slPcRIZqEGVsnkxtMr1PsnV0NRRT1tOw/v+CMCa9JL5f70w+X231lzPK5j7EzAVfCtZCJKB+tEr0iW1zVEZgz5thb2l6j98KgRcS4fVoqVdKNGlDFPR+Bh3ywb1OQsyotnaY9dpHv60a8kMy7ImKYaqBh/DMj/WRpuJot5Leikak1zFqduJnsGoldmHP9lmf+kcmbqautzdI/FhAQMenJQ11UNg2aqPOlljID6EALN mdw@degu'
  swap: 768
  wait: yes
  wait_timeout: 600
  state: present
  additional_disks:
   - {Label: 'storage-1', Size: 3584, Type: 'raw'}
   - {Label: 'storage-2', Size: 3584, Type: 'raw'}
my_ssh_key: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3UgNoKnsDehvM195bhSr+7E8AdoYuM2OGrcWC5zwmASisufRmXT7nQwNKTLpYEe6SgHI39CWlRIUT9mqADXazpRlAT7mqBwwRUVc4/O5e41slPcRIZqEGVsnkxtMr1PsnV0NRRT1tOw/v+CMCa9JL5f70w+X231lzPK5j7EzAVfCtZCJKB+tEr0iW1zVEZgz5thb2l6j98KgRcS4fVoqVdKNGlDFPR+Bh3ywb1OQsyotnaY9dpHv60a8kMy7ImKYaqBh/DMj/WRpuJot5Leikak1zFqduJnsGoldmHP9lmf+kcmbqautzdI/FhAQMenJQ11UNg2aqPOlljID6EALN mdw@degu'
