#!/bin/sh
# Check number of argument
if [ $# != 1 ]; then
 echo "Invalid arg"
 exit 1
fi

ifname=$1

SSID=$(iwconfig $ifname | grep 'ESSID:' | awk '{print $4}' | sed 's/ESSID://g' | sed 's/"//g')
echo $SSID



