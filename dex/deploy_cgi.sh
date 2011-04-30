#!/bin/bash

run_dir=/home/conor/dex/
lib_dir=/home/conor/dex/lib/dex/

cgi=dex.cgi
bin1=dex-crawl.pl

echo "> -C check..."
perl -c $cgi
if [ $? != 0 ];
then
    echo "  $cgi failed -C check, bailing out"
    exit 1
fi
perl -c $bin1
if [ $? != 0 ];
then
    echo "  $bin1 failed -C check, bailing out"
    exit 1
fi

echo "> deploying.."
# copy the wrapper into apache
sudo cp -v dex.cgi /usr/local/apache2/cgi-bin/
sudo chmod -v +x /usr/local/apache2/cgi-bin/dex.cgi

# copy dex-crawl.pl into the running dir
cp -v dex-crawl.pl $run_dir

# copy util.pm
cp -v lib/dex/util.pm $lib_dir

# copy the latest db into the running dir
# cp -v dex.sqlite $run_dir
