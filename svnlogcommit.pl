#!/usr/bin/perl

=pod

=head1 NAME

svnlogcommit.pl

This script is the missing link between Subversion, JIRA and Slack, so that you can view a rolling display of your team's Subversion activities on a Slack channel of your choice.

The script needs to be executed every time someone commits a file in Subversion and does the following:

=over 4

=item Writes a message to Slack

=item Logs the event on the system log using Log4perl (see log file configuration notes)

=item Embellishes the message on Slack with any relevant information can be found on JIRA, if the JIRA Issue Id is specified as a check-in comment.

=back

=head1 CONFIGURATION

The options are configured in the configuration section of this script, and allow this script to do the following:

=head2 Writes a message to Slack

Posts something that looks like the following to Slack:

  POST https: //[myteamname].slack.com/services/hooks/subversion?token=xxxxxx
  Content-Type: application/x-www-form-urlencoded
  Host: [myteamname].slack.com
  Content-Length: [character count]
  payload=[URL-encoded text]

You need to set up a team on Slack if you have not already done so, a Slack channel
in which you want to display the running display of Subversion activties, and then
add Slack's Subversion app, at which point you can set a name for this integration,
like "Subversion Bot". This will also provide you with a token that you need to set
up in the configuration section of this script.

Configuration:

=over 4

=item $slack_domain = "[myteamname].slack.com";

Your team's domain

=item $slack_token = "[mytoken]";

The assigned token for the chosen channel, looks like this: 02xXxxx2XXX2XXxXXXxXXx5Xx

=item $slack_maxfiles = 5;

Max number of files to show before showing just a summary. Big check-ins can really fill up space here.

=back

=head2 System Logging using Log4Perl

Logs the code submission event to whatever system logger was set up in Log4perl in the code:

Configuration:

=over 4

=item $debug = 0;

Set to 1 for debug information about this script in the log files

=item Log4Perl Settings:

  Log::Log4perl->easy_init({
    level     => defined($debug)?$DEBUG:$INFO,
    file      => ">>/var/log/[mydevopslogfile]",
    layout    => "[%d][%p][%F{1}][%L][$environment] %m%n"},);

=back

Make sure the log file and directory is writable by this script. Also, consider setting up a logrotate scheme for this log file in /etc/logrotate.d

=head2 JIRA REST API Integration

Set the API tokens in the code for using the JIRA REST API. See
https://developer.atlassian.com/jiradev/jira-apis/jira-rest-apis/jira-rest-api-tutorials
for more details on the JIRA REST API.

Configuration:

=over 4

=item $jira_user

JIRA account's user name. If you use 'admin' to save on the number of JIRA accounts, remember that JIRA from
time to time challenges an admin login with a CAPTCHA. Once JIRA has decided to do this challenge,
you need to manually log into JIRA as user admin to reset this.
Until then, all REST functions cease to work. Possible remedies are:

=over 4

=item Use a non-admin account that does not require a CAPTCHA (recommended)

=item Manually log in to JIRA with this account to reset this condition whenever you get a login failure

=item Turn off the CAPTCHA setting altogether by setting 'Maximum Authentication Attempts Allowed' in JIRA in System->General Settings to blank.

=back

=item $jira_passwd
Password for this user

=item $jira_technicalurl

The 'Base URL' value from JIRA's System configuration screen.
It can be something like this: http://ipaddress:8080'

=item $jira_displayurl

A friendly URL that redirects to the Base URL

=item $jira_projectcode

A chosen three-letter Project Id from JIRA, e.g. XXX
This script only deals with one JIRA project.

=back

=head1 INSTALLATION ON YOUR SUBVERSION SERVER

=over 4

=item Copy this file to /usr/local/bin/svnlogcommit.pl on the subversion server

=item Make sure it is executable:

  sudo chmod +x /usr/local/bin/svnlogcommit.pl

=item Find the subversion repository's directory of hooks, e.g. '/var/www/svn/[subversionrepo]/hooks' on that subversion server

=item Create a file 'post-commit' (no extension) in directory '/hooks' and make it executable, e.g. chmod +x post-commit

=item Add the following to the file 'post-commit' using your favourite editor:

  #!/bin/bash
  REPOS="$1"  # physical subversion repository path e.g. /var/www/svn/[subversionrepo]
  REV="$2"    # revision committed  e.g. 3087
  /usr/local/bin/svnlogcommit.pl $REPOS $REV

=back

=head1 SLACK OUTPUT

With all the pieces integrated, the message on Slack will be in this form:

  [Subversion bot name]
  [Rev Number + link to code]: [username] - committed files:
  [File action] [File 1]
  [File action] [File 2]
  ....
  [Checkin Comment + link to JIRA issue]

=head1 ENVIRONMENTAL NOTICE

This work was created from 100%-recycled electrons.
No animals were hurt during the production of this work, except when
I forgot to feed my cats that one time. The cats and I are on speaking terms again.

=cut

use warnings;
use strict;

use HTTP::Request::Common qw(POST);
use HTTP::Status qw(is_client_error);
use LWP::UserAgent;
use JSON;
use JIRA::REST;
use Log::Log4perl qw/:easy/;

# Command line parameters:
my ($repo,$rev)=($ARGV[0],$ARGV[1]);

# {{ BEGIN CONFIGURATION

# Subversion Repository Integration
# Assume we alway work our of 'trunk'
my $subversion_url="http://[domain]/svn/[subversionrepo]/trunk"; #

# System log file integration
my $environment = "DEV"; # Set this to anything that will distinguish this from other messages in the log files
my $debug = 0; # Set to 1 for debug information about this script in the log files
Log::Log4perl->easy_init({  level     => defined($debug)?$DEBUG:$INFO,
                            file      => ">>/var/log/[mydevopslogfile]",
                            layout    => "[%d][%p][%F{1}][%L][$environment] %m%n"
                          },
                          );
# LOGDIE "$0 should only be run a user root" if ($< != 0);

# Customizable vars. Set these to the information for your team
my $slack_domain = "[myteamname].slack.com"; # Your team's domain
my $slack_token = "[mytoken]"; # The assigned token for the chosen channel, looks like this: 02xXxxx2XXX2XXxXXXxXXx5Xx
my $slack_maxfiles = 5; # Max number of files to show before showing just a summary

# JIRA integration
my $jira_user="[jirauser]"; # usually 'admin to save on JIRA accounts
my $jira_passwd="[jirapassword]";
my $jira_technicalurl='[IP address]:[port of JIRA]';   # Looks like: http://[IP address]:8080
my $jira_displayurl="jira.[mydomain.com]";  # Usually looks like jira.[domain name]
my $jira_projectcode="XXX"; # The JIRA project codes to include for

# END OF CONFIGURATION }}


# Get check-indetails:
# 1. Commit message
my $log = `/usr/bin/svnlook log -r $rev $repo`;
# Extract JIRA project code from subversion check-in comment
my $issuecode=$log;
$issuecode =~ s/\n/ /g; # Flatten multiple lines
$issuecode =~ s/.*($jira_projectcode-[0-9]{3,4}).*/$1/g;
$issuecode =~ s/\s*//g; # trim whitespace

$log =~ s/(\s|\n)*$//; # Remove trialing whitespace
$log = "(no comments on check-in)" if (! defined $log || ! length $log);
# Convert Issue code to a  - URL is in Slack format.
$log =~ s/($jira_projectcode-[0-9]{3,4})/<http:\/\/$jira_displayurl\/browse\/$1|$1>/g;

# 2. Person who checked in
my $who = `/usr/bin/svnlook author -r $rev $repo`;
chomp $who;

# 3. Files that got changed
my $files = `/usr/bin/svnlook changed -r $rev $repo`;
my @files = split(/\n/,$files);
my $numfiles = scalar @files;
if( scalar @files > $slack_maxfiles ) {
  $files = sprintf("%s\n...follow the Revision link for the full list.", join("\n",splice(@files,0,$slack_maxfiles)));
}

# Set up message to Slack so far
if ($numfiles == 1) {
  $log = sprintf("committed this file:\n%s\n%s", $files, $log);
}else{
  $log = sprintf("committed %d files:\n%s\n%s", $numfiles, $files, $log);
}

# Line details
my $lines_removed = `/usr/bin/svnlook diff -r $rev $repo | grep "^-" | wc -l`;
my $lines_added   = `/usr/bin/svnlook diff -r $rev $repo | grep "^+" | wc -l`;
my $lines_changed = ($lines_added - $lines_removed > 0)?$lines_removed:$lines_added;
$lines_added   = abs($lines_added-$lines_changed);
$lines_removed = abs($lines_removed-$lines_changed);
$log = sprintf("%s\nLines: %d changed, %d added, %d removed.\n", $log, $lines_changed, $lines_added, $lines_removed);

# 4. Get JIRA issue detail if possible
my $issue;
if (defined $issuecode && length $issuecode && $issuecode =~ /$jira_projectcode-[0-9]{1,5}/ ) {
  # JIRA can be slow sometimes
  my $jira = JIRA::REST->new($jira_technicalurl,$jira_user,$jira_passwd,
                             {timeout => 10}
                             );

  foreach my $retries (1..5){
    # Get the details from JIRA
    eval { $issue = $jira->GET("/issue/$issuecode"); };
    last if(! $@);
  }

  if ( $@ ) {
    # Still a problem even after a few retries!
    WARN "$@. This may be because JIRA demands a CAPTCHA for the account that you are using here, '$jira_user'. Possible remedies: 1. Manually log in to JIRA with this account to reset this condition 2. Use an account that does not require a CAPTCHA  3.Turn off the 'Maximum Authentication Attempts Allowed' setting.";
    undef $issue;
  } else {
    if (defined $issue) {
      $log = sprintf("%s\nIssue: %s\nAssigned to: %s\nIssue Status: %s\nPriority: %s",
                     $log,
                     $issue->{'fields'}->{'summary'},
                     $issue->{'fields'}->{'assignee'}->{'name'},
                     $issue->{'fields'}->{'status'}->{'name'},
                     $issue->{'fields'}->{'priority'}->{'name'});
    }
  }
}

# Set up URL to actual code revision to be hyperlinked from the revision number
my $url = "$subversion_url/?op=revision&rev=$rev";

# Slack REST API
my $payload = {
  'revision'   => "Revision $rev",
  'url'        => $url,
  'author'     => $who,
  'log'        => $log,
};

my $ua = LWP::UserAgent->new;
$ua->timeout(15);

my $req = POST( "https://$slack_domain/services/hooks/subversion?token=$slack_token", ['payload' => encode_json($payload)] );
my $s = $req->as_string;
#DEBUG "Slack Request:\n$s";

my $resp = $ua->request($req);
$s = $resp->as_string;
#DEBUG "Slack Response:\n$s";

# System Log message
my $sysmsg = sprintf("Subversion rev: %s checked in by %s.", $rev,$who);
if (defined $issuecode && length $issuecode && $issuecode =~ /$jira_projectcode-[0-9]{3,4}/ ) {
  if (defined $issue){
    $sysmsg = sprintf("%s Issue Code: %s Issue: %s. Assigned to: %s Issue Status: %s  Priority: %s  Files: %s",
                        $sysmsg,
                        $issuecode,
                        $issue->{'fields'}->{'summary'},
                        $issue->{'fields'}->{'assignee'}->{'name'},
                        $issue->{'fields'}->{'status'}->{'name'},
                        $issue->{'fields'}->{'priority'}->{'name'},
                        $files);
  }else{
    # No details for issue code found,
    $sysmsg = sprintf("%s Issue Code: %s (not found on JIRA). Files: %s",
                        $sysmsg,
                        $issuecode,
                        $files);
  }
}
INFO $sysmsg;
