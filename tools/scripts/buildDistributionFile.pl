#!/usr/bin/perl
binmode STDOUT, ":utf8";
binmode STDIN, ":utf8";

use utf8;
use strict;
use Getopt::Long;

# Variables 
my @zimPaths;
my $filePath;
my $tmpDirectory = "/tmp/";
my $lang = "en";
my $type;
my $cmd;

# Instance logger
use Log::Log4perl;
Log::Log4perl->init("../conf/log4perl");
my $logger = Log::Log4perl->get_logger("buildDistributionFile.pl");

# Get arguments
GetOptions('zimPath=s' => \@zimPaths,
	   'tmpDirectory=s' => \$tmpDirectory,
	   'filePath=s' => \$filePath,
	   'type=s' => \$type,
	   'lang=s' => \$lang,
    );

# Check if we have all the mandatory variable set
if (!scalar(@zimPaths) || !$filePath || (!($type eq "iso") && !($type eq "portable"))) {
    print "usage: ./buildIso.pl --filePath=dvd.iso --zimPath=articles.zim --type=[iso|portable] [--tmpDirectory=/tmp/] [--lang=en|fr]\n";
    exit
}

# Check if the zim files exist
$logger->info("Will check if the ZIM file exists...");
foreach my $zimPath (@zimPaths) {
    $logger->info("Check ZIM file $zimPath");
    unless (-f $zimPath) {
	exit 1;
    }
}

# Clear and create the directory to build the iso
my $distributionDirectory = $tmpDirectory."kiwix_iso_tmp_directory/";
$logger->info("Deleting and creating $distributionDirectory");
$cmd = "rm -rf $distributionDirectory"; `$cmd`; 
$cmd = "mkdir $distributionDirectory"; `$cmd`; 

# Checkout the default ISO directory tree structure
$logger->info("Checkout the SVN dvd directory template");
$cmd = "svn co https://kiwix.svn.sourceforge.net/svnroot/kiwix/moulinkiwix/dvd $distributionDirectory"; `$cmd`;
$cmd = "rm -rf \`find $distributionDirectory -name \"*.svn\"\`"; `$cmd`;

# Copy the ZIMs
$logger->info("Copying the ZIM files");
foreach my $zimPath (@zimPaths) {
    $logger->info("Check ZIM file $zimPath");
    $cmd = "cp $zimPath $distributionDirectory/data/content/"; `$cmd`;
}

# Update @zimPaths
my $output = `find /tmp/kiwix_iso_tmp_directory/data/content/ -name \"*.zim\" 2>&1`;
@zimPaths = split (/\n/, $output);

# Compute and compact the indexes
$logger->info("Compute and compact the indexes");
foreach my $zimPath (@zimPaths) {

    # Extract the zimFile
    $zimPath =~ /.*\/([^\/]*)$/;
    my $zimFile = $1;

    # Index
    my $zimFileIndex = "$distributionDirectory/data/index/$zimFile.idx";
    $logger->info("Compute index for $zimFile");
    $cmd = "kiwix-index $zimPath $zimFileIndex"; `$cmd`;

    # Compact
    $logger->info("Compact index $zimFileIndex");
    $cmd = "kiwix-compact $zimFileIndex"; `$cmd`;

    # Compute the zimId
    $cmd = "zimdump -F $zimPath | grep uuid | sed 's/uuid: //'";
    my $zimFileId = `$cmd 2>&1`;
    $zimFileId =~ s/\r|\n//g;

    # Create the library
    $logger->info("Create new library file ro $zimFile.");
    my $libraryPath = "$distributionDirectory/data/library/$zimFile.library";
    $logger->info("Create the library for $zimFile : ");
    my $xmlContent = "<library current=\"$zimFileId\"><book id=\"$zimFileId\" path=\"$zimFile\" indexPath=\"$zimFile.idx\" indexType=\"xapian\"/></library>\n";
    writeFile($libraryPath, $xmlContent);
}

 # Download the source code
$logger->info("Download Kiwix source code");
$cmd = "cd $distributionDirectory ; wget \`curl --silent http://sourceforge.net/projects/kiwix/ | grep \"/download\" | sed 's/\\?.*//' | sed 's/.*http/http/'\`"; `$cmd`;

# Download deb files
$logger->info("Download Kiwix deb packages");
$cmd = "curl --silent http://ppa.launchpad.net/kiwixteam/ppa/ubuntu/pool/main/k/kiwix/ | grep deb | sed 's/.*href=\\\"//' | sed 's/deb.*/deb/'";
my @debFiles = split(/\n/, `$cmd 2>&1`);

foreach my $debFile (@debFiles) {
    $cmd = "wget http://ppa.launchpad.net/kiwixteam/ppa/ubuntu/pool/main/k/kiwix/$debFile -O $distributionDirectory/install/$debFile"; `$cmd`;
}

# Download the file with DLL for Visual Studio redit. binaries
$logger->info("Download vcredist_x86.exe");
$cmd = "wget http://download.kiwix.org/dev/vcredist_x86.exe -O $distributionDirectory/bonus/vcredist_x86.exe"; `$cmd`;

# Download and unzip Windows binary
$logger->info("Download and unzip Windows binary");
$cmd = "wget \`curl --silent --user-agent \"Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.7.5) Gecko/20041202 Firefox/1.0\" http://sourceforge.net/projects/kiwix/ | grep \"/download\" |  sed 's/\\?.*//' | sed 's/.*http/http/'\` -O $distributionDirectory/kiwix.zip"; `$cmd`;
$cmd = "cd $distributionDirectory/ ; unzip -n kiwix.zip" ; `$cmd`;
$cmd = "rm $distributionDirectory/kiwix.zip" ; `$cmd`;

# Download the autorun
$logger->info("Download autorun");
$cmd = "cd $distributionDirectory/autorun/ ; wget http://download.kiwix.org/dev/launcher/mingwm10.dll"; `$cmd`;
$cmd = "cd $distributionDirectory/autorun/ ; wget http://download.kiwix.org/dev/launcher/libgcc_s_dw2-1.dll"; `$cmd`;
$cmd = "cd $distributionDirectory/autorun/ ; wget http://download.kiwix.org/dev/launcher/QtGui4.dll"; `$cmd`;
$cmd = "cd $distributionDirectory/autorun/ ; wget http://download.kiwix.org/dev/launcher/QtCore4.dll"; `$cmd`;
$cmd = "cd $distributionDirectory/autorun/ ; wget http://download.kiwix.org/dev/launcher/autorun-$lang.exe -O autorun.exe"; `$cmd`;

# Build ISO
if ($type eq "iso") {
    $logger->info("Build ISO $filePath");
    $cmd = "mkisofs -r -J -o  $filePath $distributionDirectory"; `$cmd`;
} else { # portable
    $logger->info("Build the portable compacted file");
    $cmd = "7za a -tzip -mx9 $filePath $distributionDirectory/*"; `$cmd`;
}

sub writeFile {
    my $file = shift;
    my $data = shift;
    
    open (FILE, ">:utf8", "$file") or die "Couldn't open file: $file";
    print FILE $data;
    close (FILE);
}

exit 0;

