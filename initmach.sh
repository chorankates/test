#!/bin/bash
# initmach.sh - apt-get and CPAN packages that will almost always be needed

packages=(
    "emacs23-nox"
    "git-core"
    "lynx"
    "nmap"
    "libterm-readline-gnu-perl"
    "libX11-dev"
    "libpcap-dev"
    "libssl-dev"
    "openssh-server"
    "wireshark"
    "tshark"
    
    # need java package names, sqlite db name
    "sqlitebrowser"
    "openjdk-6-jre"
)

modules=(
    "Archive::Zip"
    "Crypt::SSLeay"
    "Data::Dumper"
    "DBD::SQLite"
    "Digest::MD5"
    "Digest::SHA1"
    "Imager"
    "Imager::Screenshot"
    "Mail::RFC822::Address"
    "Math::Base36"
    "MIME::Lite"
    "Net::SCP"
    "Net::SSH"
    "Net::SSH::Expect"
    "Net::Twitter::Lite"
    "PadWalker"
    "SOAP::Lite"
    "Unicode::String"
    "XML::Simple"
    "Win32::Exe"
)

urls = (
    ""
)

package_str="sudo apt-get install"

for (( i = 0 ; i < ${#packages[@]} ; i++ )); do
    #echo "package$i: ${packages[$i]}"
    package_str="$package_str ${packages[$i]}"
done

echo "installing packages.. $package_str"
$package_str
echo ""

module_str="perl -mCPAN -e install"

for (( i = 0 ; i < ${#modules[@]} ; i++ )); do
    #echo "module$i: ${modules[$i]}"
    module_str="$module_str ${modules[$i]}"
done

echo "installing modules.. $module_str"
$module_str
echo ""

exit 0