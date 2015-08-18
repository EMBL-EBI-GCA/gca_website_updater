#!/bin/sh

WU_HOME=/nfs/public/rw/reseq-info/static_website_updater/gca_website_updater

mkdir -p $WU_HOME/local/

#cpanm -L local git@github.com:Ensembl/ensembl-git-tools.git \
cpanm -L local git@github.com:istreeter/ensembl-git-tools.git \
&& carton install --deployment \
&& curl https://codeload.github.com/git/git/tar.gz/v2.5.0 >git.tar.gz \
&& tar -xzf git.tar.gz \
&& cd git-2.5.0/ \
&&  make prefix=$WU_HOME/local/ \
&&  make prefix=$WU_HOME/local/

rm -fr git.tar.gz git-2.5.0
