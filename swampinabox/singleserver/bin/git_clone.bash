#!/bin/bash

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

# This script assumes that the deployment project has been boot strapped as follows:
# git clone git@swa-scm-1.mirsam.org:vendor/deployment-dependencies.git deployment

BINDIR=`dirname $0`
echo "BINDIR: $BINDIR"
cd $BINDIR/../../../..
echo -n "PWD: "
pwd

git clone git@swa-scm-1.mirsam.org:swamp/db-config.git db
git clone git@swa-scm-1.mirsam.org:swamp/service.git services
git clone git@swa-scm-1.mirsam.org:vendor/proprietary.git proprietary

git clone git@swa-scm-1.mirsam.org:swamp/swamp-web-server.git swamp-web-server
git clone git@swa-scm-1.mirsam.org:swamp/www-front-end.git www-front-end
