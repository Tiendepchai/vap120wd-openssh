#!/bin/ash
# SHARED, To be sourced only
DB_FILE="/etc/usp.db"
CHECK_INTERVAL=300
COMMAND_TIMEOUT=20
EP_MAX_SIZE=15000

check_obuspa_hang() {
    virmem=$(ps | grep '/usr/bin/obuspa -f /etc/usp.db' | grep -v grep | awk '{print $3}')
    timeout -t $COMMAND_TIMEOUT /usr/bin/obuspa -f $DB_FILE -c get Device.DeviceInfo.SerialNumber
	ret=$?
    if [[ $ret -ne 0  ||  $virmem -gt $EP_MAX_SIZE ]]; then
		logger "TMS obuspa hang. Reload obuspa"
		killall -9 obuspa
		/etc/init.d/obuspa stop
		sleep 5
        rm -f $DB_FILE
		/etc/init.d/obuspa start
    fi
}

check_obuspafm_hang() {
    text=$(/bin/ps | grep 'obuspaFM' | grep -v grep )
    substring="R"
    substr="%"

    if [[ -z "${text##*$substring*}" ]]; then
        sleep 5
        text=$(/usr/bin/top -b -n 1 -d 1 | grep 'obuspaFM' | grep -v grep )
        if [[ -z "${text##*$substring*}" ]]; then
            for word in $text
            do
                if [[ -z "${word##*$substr*}" ]]; then
                    num=$(echo $word | grep -Eo [0-9]+)
                    if [[ $num -gt 10 ]]; then
                        logger "TMS obuspaFM hang. Reload obuspaFM"
                        killall -9 obuspaFM
                        /etc/init.d/obuspafm reload
                    fi
                fi
            done
        fi
    fi
}


while [ 1 ]; do
    sleep $CHECK_INTERVAL 
    [ $(pidof obuspa) ] && {
        check_obuspa_hang
    }

    [ $(pidof obuspaFM) ] && {
        check_obuspafm_hang
    }
done
