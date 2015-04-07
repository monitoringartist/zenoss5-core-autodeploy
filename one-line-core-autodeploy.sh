#!/bin/bash

cd /tmp
curl -O https://raw.githubusercontent.com/jangaraj/zenoss5-core-autodeploy/master/core-autodeploy.sh
chmod +x core-autodeploy.sh
./core-autodeploy.sh