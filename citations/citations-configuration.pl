#!/usr/bin/perl

# This script updates publisher & questionable configurations based on DOI redirects

use warnings;
use strict;

use Benchmark;
use File::Basename;
use HTML::Entities;
use Sort::Key::Natural qw( natkeysort );

use lib dirname(__FILE__) . '/../modules';

use citations qw( initial removeControlCharacters );

use mybot;

use utf8;

#
# Validate Environment Variables
#

unless (exists $ENV{'WIKI_CONFIG_DIR'}) {
    die "ERROR: WIKI_CONFIG_DIR environment variable not set\n";
}

#
# Configuration & Globals
#

my $BOTINFO = $ENV{'WIKI_CONFIG_DIR'} .  '/bot-info.txt';

my $CATEGORY = 'Category:Redirects from DOI prefixes';

my $PUBLISHERS   = 'User:JL-Bot/Publishers.cfg';
my $QUESTIONABLE = 'User:JL-Bot/Questionable.cfg';

#
# Subroutines
#

sub findRegistrant {

    # extract the registrant field (if present) from the redirect

    my $text = shift;

    my $registrant;

    if ($text =~ /\|\s*registrant\s*=\s*(.*?)(?:\||\})/) {
        $registrant = $1;
    }

    return $registrant;
}

sub findTarget {

    # extract the redirect target from the redirect

    my $redirect = shift;
    my $text = shift;

    if ($text =~ /^\s*#redirect\s*:?\s*\[\[\s*:?\s*(.+?)\s*(?:\]|(?<!&)#|\n|\|)/i) {
        my $target = $1;
        $target = decode_entities($target);
        $target =~ s/%26/&/;
        $target =~ tr/_/ /;
        $target =~ s/ {2,}/ /g;
        $target =~ s/^ //;
        $target =~ s/ $//;
        $target = ucfirst $target;
        return $target;
    }
    else {
        die "ERROR: redirect target not detected for $redirect!\n\n";
    }
}

sub sortPrefixes {

    # Sort prefixes so that order is 4-digits, 5-digits

    return  0 if ($a eq $b);

    return  1 if (($a =~ /^10\.\d{5}$/) and ($b =~ /^10\.\d{4}$/));
    return -1 if (($b =~ /^10\.\d{5}$/) and ($a =~ /^10\.\d{4}$/));
    return $a <=> $b;
}

sub sortTemplates {

    # sort templates in selected, pattern, doi order

    return -1 if ($a eq 'JCW-selected');
    return  1 if ($b eq 'JCW-selected');
    return  1 if ($a eq 'JCW-doi-redirects');
    return -1 if ($b eq 'JCW-doi-redirects');
}

sub updatePublisher {

    # update the publisher configuration

    my $bot = shift;
    my $targets = shift;
    my $page = shift;

    print "  updating publisher configuration...\n";

    my ($original, $timestamp) = $bot->getText($page);
    $original = removeControlCharacters($original);

    my $updated;
    my $templates;
    my $section;

    for my $line (split "\n", $original) {
        if ($line =~ /^==(.+)==\s*$/) {
            # save section
            $section = $1;
            $section = 'Non' if ($section eq 'Diacritics & Non-Latin');
            $section = 'Num' if ($section eq 'Number & Symbols');
            $updated .= "$line\n";
        }
        elsif ($line =~ /^\s*\{\{\s*JCW-(selected|pattern)\s*\|\s*(.*?)\s*(?:\|.*?)?\s*\}\}\s*$/i) {
            # save selected & pattern templates within a section
            my $template = $1;
            my $target   = $2;
            $templates->{$target}->{$template}->{$line} = 1;
        }
        elsif ($line =~ /^\s*\{\{\s*JCW-doi-redirects\s*\|/i) {
            # drop prior DOI redirect configuration
            next;
        }
        elsif ($line =~ /^\s*\}\}\s*$/) {
            # end of section so add in doi redirects
            for my $target (keys %{$targets->{$section}}) {
                # build doi-redirect template line
                my $line = "{{JCW-doi-redirects|$target";
                for my $redirect (sort sortPrefixes keys %{$targets->{$section}->{$target}}) {
                    $line .= "|$redirect";
                }
                $line .= "}}";
                # add to templates
                $templates->{$target}->{'JCW-doi-redirects'}->{$line} = 1;
            }
            # and output templates
            for my $target (natkeysort { lc $_ } keys %$templates) {
                for my $template (sort sortTemplates keys %{$templates->{$target}}) {
                    for my $line (sort keys %{$templates->{$target}->{$template}}) {
                        $updated .= "$line\n";
                    }
                }
            }
            $updated .= "}}\n";
            $templates = {};
        }
        else {
            # pass through other fields
            $updated .= "$line\n";
        }
    }

    $bot->saveText($page, $timestamp, $updated, 'updating Wikipedia citation configuration based on DOI redirects', 'NotMinor', 'Bot');

    return;
}

sub updateQuestionable {

    # update the questionable configuration

    my $bot = shift;
    my $targets = shift;
    my $page = shift;

    print "  updating questionable configuration...\n";

    my ($original, $timestamp) = $bot->getText($page);
    $original = removeControlCharacters($original);

    my $updated;
    my $templates;

    for my $line (split "\n", $original) {
        if ($line =~ /^\s*\{\{\s*JCW-(selected|pattern)\s*\|\s*(.*?)\s*(?:\|.*?)?\s*\}\}\s*$/i) {
            # save selected & pattern templates within a section
            my $template = $1;
            my $target   = $2;
            $templates->{$target}->{$template}->{$line} = 1;
        }
        elsif ($line =~ /^\s*\{\{\s*JCW-doi-redirects\s*\|/i) {
            # drop prior DOI redirect configuration
            next;
        }
        elsif ($line =~ /^\s*\}\}\s*$/) {
            # end of section so output sorted templates
            for my $target (natkeysort { lc $_ } keys %$templates) {
                for my $template (sort sortTemplates keys %{$templates->{$target}}) {
                    for my $line (sort keys %{$templates->{$target}->{$template}}) {
                        $updated .= "$line\n";
                    }
                }
                my $letter = initial($target);
                if (exists $targets->{$letter}->{$target}) {
                    $updated .= "{{JCW-doi-redirects|$target";
                    for my $redirect (sort sortPrefixes keys %{$targets->{$letter}->{$target}}) {
                        $updated .= "|$redirect";
                    }
                    $updated .= "}}\n";
                }
            }
            $updated .= "}}\n";
            $templates = {};

        }
        else {
            # pass through other fields
            $updated .= "$line\n";
        }
    }

    $bot->saveText($page, $timestamp, $updated, 'updating Wikipedia citation configuration based on DOI redirects', 'NotMinor', 'Bot');

    return;
}

#
# Main
#

# handle UTF-8

binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# auto-flush output

$| = 1;

# generate output

print "Updating DOI configuration ...\n";

my $b0 = Benchmark->new;

my $bot = mybot->new($BOTINFO);

# process DOI redirects

print "  processing DOI redirects ...\n";

my $redirects = $bot->getCategoryMembers($CATEGORY);

my $targets;

for my $redirect (keys %$redirects) {
    if ($redirect !~ /^10\.\d{4,5}$/) {
        warn "WARNING: unexpected redirect format --> $redirect\n";
        next;
    }

    my ($text, ) = $bot->getText($redirect);

    my $target = findTarget($redirect, $text);
    my $initial = initial($target);
    $targets->{$initial}->{$target}->{$redirect} = 1;

    my $registrant = findRegistrant($text);
    if ($registrant) {
        $initial = initial($registrant);
        $targets->{$initial}->{$registrant}->{$redirect} = 1;
    }
}

# update configuration pages

updatePublisher($bot, $targets, $PUBLISHERS);
updateQuestionable($bot, $targets, $QUESTIONABLE);

my $b1 = Benchmark->new;
my $bd = timediff($b1, $b0);
my $bs = timestr($bd);
$bs =~ s/^\s*(\d+)\swallclock secs.*$/$1/;
print "  DOI targets processed in $bs seconds\n";