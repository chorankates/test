#!/bin/bash

run_dir=/home/conor/dex/

# copy the wrapper into apache
cp -v dex.cgi /usr/local/apache2/cgi-bin/
chmod -v +x /usr/local/apache2/cgi-bin/dex.cgi

# copy dex-crawl.pl into the running dir
cp -v dex-crawl.pl $run_dir

# copy the latest db into the running dir
cp -v dex.sqlite $run_dir
