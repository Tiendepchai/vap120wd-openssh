#!/bin/sh
iface_list="ra0 ra1 ra2 rax0 rax1 rax2 rax3"
parental_status=$(uci get parental.global.enabled)
if [ $parental_status != "1" ]; then 
    logger "Parental control is disable, flush wifi acl"
    for iface in $iface_list
    do
        #logger "flush iface $iface"
        iwpriv $iface set AccessPolicy=0
        iwpriv $iface set ACLClearAll=1
    done
fi