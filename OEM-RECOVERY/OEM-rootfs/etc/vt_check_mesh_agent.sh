#!/bin/sh
# Author: duongnt62@viettel.com.vn
echo "[INFO] Program check mesh status at agent."

count=0
count_1=0
FILE="/data/vt_log_lost_mesh_at_agent.txt"
FILE_DEFAULT_ROUTER="/tmp/vt_default_router"
br_lan=$(uci get network.lan.ipaddr)
default_router=$br_lan

check_backhaul_connection() {
    sleep 60 # sleep 60s

    br_lan_now=$(ifconfig br-lan | grep -m1 "inet addr" | awk '{print $2}' | awk -F: '{print $2}')
    echo "=> br_lan_now: $br_lan_now"

    bh_apcli0=$(iwconfig apcli0 | grep -m1 "ESSID" | awk '{print $4}' | awk -F: '{print $2}' | sed 's/"//g')
    echo "=> bh_apcli0: $bh_apcli0"

    if [ -f "$FILE_DEFAULT_ROUTER" ]; then
        echo "=> File $FILE_DEFAULT_ROUTER exits"
        default_router=$(cat $FILE_DEFAULT_ROUTER)
    else
        echo "=> File $FILE_DEFAULT_ROUTER don't exits"
        default_router="0.0.0.0"
    fi
    echo "=> default_router: $default_router"

    if [ $br_lan_now != $br_lan ]; then
        if ping -c 1 $default_router > /dev/null ; then
            # ping success
            echo "Ping to $default_router success !!!"
            bh_connect_status=1
        else
            # ping failure
            echo "Ping to $default_router failure !!!"
            bh_connect_status=0
        fi
    else
        if [ $default_router == "0.0.0.0" ]; then
            # For agent reboot
            bh_connect_status=1
        else
            bh_connect_status=0
        fi
    fi

    #rm -f /tmp/vt_bh_info.txt
    #mapd_cli /tmp/mapd_ctrl bh_info
    #cat /tmp/vt_bh_info.txt | grep "Connected"
    #bh_connect_status=$?

    if [ $bh_connect_status -eq 0 ]
    then
        echo "[INFO] Backhaul fail -> LOST MESH"
        count=`expr $count + 1`
    else
        echo "[INFO] Backhaul ready -> OK"
        count=0
    fi
    echo $count > /tmp/vt_count.txt 
}

while true
do
    map_enable=$(wificonf -f /etc/mapd_cfg.txt get MapEnable)
    dev_role=$(wificonf -f /etc/mapd_cfg.txt get DeviceRole)
    bh_valid=$(wificonf -f /etc/mapd_cfg.txt get BhProfile0Valid)
    
    if [ $map_enable == "1" ] && [ $dev_role == "2" ] && [ $bh_valid == "1" ]
    then
        # Agent in mesh network
        check_backhaul_connection

        # check if lost mesh 300s at agent -> reload wifi
        if [ $count -eq 5 ]
        then
            timestamp=$(date)
            string="Agent lost mesh, reload wifi at: "
            string="$string $timestamp"
            echo $string > $FILE
            echo "[INFO] Reload wifi because lost mesh at Agent."
            #killall -15 mapd
            #killall -15 wapp
            #killall -15 p1905_managerd
            #killall -15 bs20
            echo 1 > /tmp/vt_check_mesh_agent.x
            /sbin/wifi reload
            rm -f /tmp/vt_check_mesh_agent.x
        elif [ $count -gt 60 ]
        then
            # fix count=60
            count=60
        fi
        count_1=0
    elif [ $map_enable == "0" ] && [ $dev_role == "2" ] && [ $bh_valid == "1" ]
    then
        # disable mesh at agent when Agent in mesh network
        # After 300s, reload network
        echo "[INFO] Sleep 60s (MAP disable, role agent, backhaul valid)"
        sleep 60
        count_1=`expr $count_1 + 1`
        if [ $count_1 -eq 5 ]
        then
            /sbin/wifi reload
        elif [ $count_1 -gt 60 ]
        then
            # fix count_1=60
            count_1=60
        fi
    else
        # Controller or agent don't in mesh network
        echo "[INFO] ==> Sleep 60s"
        sleep 60
        count_1=0
    fi   
done
