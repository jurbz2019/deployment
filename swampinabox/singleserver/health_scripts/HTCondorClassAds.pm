# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

package HTCondorClassAds;
use strict;
use warnings;
use parent qw(Exporter);
use lib '/opt/swamp/perl5';
use SWAMP::vmu_Support qw(getSwampConfig systemcall);

our (@EXPORT_OK);
BEGIN {
	require Exporter;
	@EXPORT_OK = qw(
		get_condor_collector_host
		show_collector_records
	);
}

my @assessment_fields = qw(
	Name 
	SWAMP_vmu_assessment_vmhostname
	SWAMP_vmu_assessment_status
	SWAMP_vmu_assessment_user_uuid 
	SWAMP_vmu_assessment_projectid 
);
my $assessment_constraint = qq{-constraint \"isString(SWAMP_vmu_assessment_status)\"};

my @viewer_fields = qw(
	Name 
	SWAMP_vmu_viewer_vmhostname
	SWAMP_vmu_viewer_name
	SWAMP_vmu_viewer_state 
	SWAMP_vmu_viewer_status 
	SWAMP_vmu_viewer_vmip 
	SWAMP_vmu_viewer_user_uuid 
	SWAMP_vmu_viewer_projectid
	SWAMP_vmu_viewer_instance_uuid 
	SWAMP_vmu_viewer_apikey 
	SWAMP_vmu_viewer_url_uuid
);
my $viewer_constraint = qq{-constraint \"isString(SWAMP_vmu_viewer_status)\"};

sub get_condor_collector_host {
	my $HTCONDOR_COLLECTOR_HOST = '';
	my $config = getSwampConfig();
	if ($config) {
		$HTCONDOR_COLLECTOR_HOST = $config->get('htcondor_collector_host');
	}
	return $HTCONDOR_COLLECTOR_HOST;
}

sub show_collector_records { my ($HTCONDOR_COLLECTOR_HOST, $title, $as_table, $newline, $submit_node) = @_ ;
	if (! $HTCONDOR_COLLECTOR_HOST) {
		return;
	}
	$newline = "\n" if (! $newline);
	my ($fields, $constraint, $sortfield);
	if ($title eq 'assessment') {
		$fields = \@assessment_fields;
		$constraint = $assessment_constraint;
	}
	elsif ($title eq 'viewer') {
		$fields = \@viewer_fields;
		$constraint = $viewer_constraint;
	}
	else {
		return;
	}
	$sortfield = "SWAMP_vmu_${title}_vmhostname";
	my $command = qq{condor_status -pool $HTCONDOR_COLLECTOR_HOST -sort $sortfield -any -af:V, };
	if ($submit_node) {
		$command = qq{ssh $submit_node condor_status -pool $HTCONDOR_COLLECTOR_HOST -sort $sortfield -any -af:V, };
	}
	foreach my $field (@$fields) {
		$command .= ' ' . $field;
	}
	if ($constraint) {
		if ($submit_node) {
			$constraint =~ s/\(/\\\(/g;
			$constraint =~ s/\)/\\\)/g;
		}
		$command .= ' ' . $constraint;
	}
	my ($output, $status) = systemcall($command);
	if ($status) {
		return;
	}
	my @lines = split "\n", $output;
	print "$title collector: [", scalar(@lines), "] $HTCONDOR_COLLECTOR_HOST", $newline;
	print "-" x length("$title collector:");
	print $newline;
	if ($as_table && @lines) {
		print "execrunuid\t\t\t";
		foreach my $field (@$fields) {
			next if ($field eq "Name");
			my $field_name = $field;
			$field_name =~ s/^SWAMP_vmu_${title}_//;
			print "\t$field_name";
		}
		print $newline;
	}
	foreach my $line (@lines) {
		my @parts = split ',', $line;
		s/\"//g for @parts;
		s/^\s+//g for @parts;
		s/\s+$//g for @parts;
		print "execrunuid: " if (! $as_table);
		print $parts[0];
		print $newline if (! $as_table);
		for (my $i = 1; $i < scalar(@parts); $i++) {
			if (! $as_table) {
				my $field_name = $fields->[$i];
				$field_name =~ s/^SWAMP_vmu_${title}_//;
				print "  $field_name: ", $parts[$i], $newline;
			}
			else {
				print "\t", $parts[$i];
			}
		}
		print $newline;
	}
	print $newline;
}

1;
