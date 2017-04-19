# svnlogcommit
This is the missing link between Subversion, JIRA and Slack, so that you can view a rolling display of your team's Subversion activities on a Slack channel of your choice.

The script needs to be executed every time someone commits a file in Subversion and does the following:

- Writes a message to Slack
- Logs the event on the system log using Log4perl (see log file configuration notes)
- Embellishes the message on Slack with any relevant information can be found on JIRA, if the JIRA Issue Id is specified as a check-in comment.

# CONFIGURATION

The options are configured in the configuration section of this script, and allow this script to do the following:

## Writes a message to Slack

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

- $slack\_domain = "\[myteamname\].slack.com";

    Your team's domain

- $slack\_token = "\[mytoken\]";

    The assigned token for the chosen channel, looks like this: 02xXxxx2XXX2XXxXXXxXXx5Xx

- $slack\_maxfiles = 5;

    Max number of files to show before showing just a summary. Big check-ins can really fill up space here.

## System Logging using Log4Perl

Logs the code submission event to whatever system logger was set up in Log4perl in the code:

Configuration:

- $debug = 0;

    Set to 1 for debug information about this script in the log files

- Log4Perl Settings:

        Log::Log4perl->easy_init({
          level     => defined($debug)?$DEBUG:$INFO,
          file      => ">>/var/log/[mydevopslogfile]",
          layout    => "[%d][%p][%F{1}][%L][$environment] %m%n"},);

Make sure the log file and directory is writable by this script. Also, consider setting up a logrotate scheme for this log file in /etc/logrotate.d

## JIRA REST API Integration

Set the API tokens in the code for using the JIRA REST API. See
https://developer.atlassian.com/jiradev/jira-apis/jira-rest-apis/jira-rest-api-tutorials
for more details on the JIRA REST API.

Configuration:

- $jira\_user

    JIRA account's user name. If you use 'admin' to save on the number of JIRA accounts, remember that JIRA from
    time to time challenges an admin login with a CAPTCHA. Once JIRA has decided to do this challenge,
    you need to manually log into JIRA as user admin to reset this.
    Until then, all REST functions cease to work. Possible remedies are:

    - Use a non-admin account that does not require a CAPTCHA (recommended)
    - Manually log in to JIRA with this account to reset this condition whenever you get a login failure
    - Turn off the CAPTCHA setting altogether by setting 'Maximum Authentication Attempts Allowed' in JIRA in System->General Settings to blank.

- $jira\_passwd
Password for this user
- $jira\_technicalurl

    The 'Base URL' value from JIRA's System configuration screen.
    It can be something like this: http://ipaddress:8080'

- $jira\_displayurl

    A friendly URL that redirects to the Base URL

- $jira\_projectcode

    A chosen three-letter Project Id from JIRA, e.g. XXX
    This script only deals with one JIRA project.

# INSTALLATION ON YOUR SUBVERSION SERVER

- Copy this file to /usr/local/bin/svnlogcommit.pl on the subversion server
- Make sure it is executable:

        sudo chmod +x /usr/local/bin/svnlogcommit.pl

- Find the subversion repository's directory of hooks, e.g. '/var/www/svn/\[subversionrepo\]/hooks' on that subversion server
- Create a file 'post-commit' (no extension) in directory '/hooks' and make it executable, e.g. chmod +x post-commit
- Add the following to the file 'post-commit' using your favourite editor:

        #!/bin/bash
        REPOS="$1"  # physical subversion repository path e.g. /var/www/svn/[subversionrepo]
        REV="$2"    # revision committed  e.g. 3087
        /usr/local/bin/svnlogcommit.pl $REPOS $REV

# SLACK OUTPUT

With all the pieces integrated, the message on Slack will be in this form:

    [Subversion bot name]
    [Rev Number + link to code]: [username] - committed files:
    [File action] [File 1]
    [File action] [File 2]
    ....
    [Checkin Comment + link to JIRA issue]

# ENVIRONMENTAL NOTICE

This work was created from 100%-recycled electrons.
No animals were hurt during the production of this work, except when
I forgot to feed my cats that one time. The cats and I are on speaking terms again.
