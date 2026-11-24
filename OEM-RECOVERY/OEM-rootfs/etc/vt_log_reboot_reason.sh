#! /bin/sh
#Author:sonnh68@viettel.com.vn

#check if Reboot by power
RB_FLAG=$(reboot_reason r rb_flag)
KERNEL_PANIC_FLAG=$(cof_cli read KernelPanic)

DATE=$(date "+%F %H:%M:%S")
FILE_REBOOTREASON_MAXSIZE=10240 # 10kb
FILE_REBOOTREASON="/data/log/vt_rebootreason"
FILE_REBOOTREASON_0="/data/log/vt_rebootreason.0"

if [ $KERNEL_PANIC_FLAG != "1" ]
then
    echo "Reboot"
    if [ $RB_FLAG -eq 0 ]
    then
        reboot_reason w rb_reason RebootByPower
    fi
    reboot_reason w rb_flag 0
    RB_REASON=$(reboot_reason r rb_reason)
    RB_TIME=$(reboot_reason r rb_time)
else
    echo "Kernel Panic"
    cof_cli write KernelPanic 0
    RB_REASON="RebootByKernelPanic"
    RB_TIME="00:00:00"
fi

# write Reboot reason to the log file
if [[ "$RB_REASON" == "RebootByPower" || "$RB_REASON" == "RebootByKernelPanic" ]]; then
    RB_STRING="######## reboot reason: $RB_REASON at $DATE"
else
    RB_STRING="######## reboot reason: $RB_REASON at $RB_TIME"
fi
/usr/bin/logger -p err $RB_STRING

# write reboot reason to folder /data/log/
mkdir -p /data/log
if [ -f "$FILE_REBOOTREASON" ]; then
    size_file=$(wc -c <"$FILE_REBOOTREASON")
    if [ $size_file -le $FILE_REBOOTREASON_MAXSIZE ]; then
         echo $RB_STRING >> $FILE_REBOOTREASON
    else
        mv -f $FILE_REBOOTREASON $FILE_REBOOTREASON_0
        echo $RB_STRING > $FILE_REBOOTREASON
    fi
else
    echo $RB_STRING > $FILE_REBOOTREASON
fi

