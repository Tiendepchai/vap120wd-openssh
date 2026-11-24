# Author: duongnt62@viettel.com.vn
# Description: check daemon
#!/bin/sh

echo "Check daemon !!!"
WAPP_FLAG=0
P1905_FLAG=0

# Fill daemon, which need to check
DAEMON='wapp p1905_managerd mapd'

# List process for start again
start_wappd(){
    killall -15 wapp
    wapp_openwrt.sh > /dev/null
}

start_p1905_managerd(){
    echo "start_p1905_managerd: map_dev_role $1."
    if [ $1 == 1 ]; then
        p1905_managerd -r0 -f "/etc/map_cfg.txt" -F "/etc/wts_bss_info_config" > /dev/console &
    elif [ $1 == 2 ]; then
        p1905_managerd -r1 -f "/etc/map_cfg.txt" -F "/etc/wts_bss_info_config" > /dev/console &
    else
        echo "start_p1905_managerd: map_dev_role $1 not match."
    fi
}

start_mapd(){
    mapd -G "/etc/wts_bss_info_config" -I "/etc/mapd_cfg.txt" -O "/etc/mapd_strng.conf" -f "/var/log_mapd" > /dev/console &
}

check_daemon(){
    for i in $DAEMON
    do
        #echo "Checking daemon: $i ..."
        pidof $i > /dev/null 2>&1
        RET=$?
        if [ $RET == "0" ]; then
            echo "Process $i is running."
            case $i in
                "wapp")
                    WAPP_FLAG=0
                    ;;
                "p1905_managerd")
                    P1905_FLAG=0
                    ;;
                *)
                    ;;
            esac
        else
            echo "Process $i was dead."
            echo "Start process: $i again."
            case $i in
                "wapp")
                    WAPP_FLAG=1
                    start_wappd
                    ;;
                "p1905_managerd")
                    P1905_FLAG=1
                    start_p1905_managerd $map_dev_role
                    ;;
                "mapd")
                    start_mapd
                    ;;
                *)
                    echo "Don't match process: $i."
                    ;;
            esac
        fi
    done
    echo ""
}

while true
do
    sleep 300 # sleep 300s
    map_enable=$(wificonf -f /etc/mapd_cfg.txt get MapEnable)
    map_dev_role=$(wificonf -f /etc/mapd_cfg.txt get DeviceRole)
    if [ $map_enable == "1" ]; then
        echo "MAP enable, check daemon."
        check_daemon
    fi
done
