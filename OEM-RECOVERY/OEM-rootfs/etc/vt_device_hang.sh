#!/bin/sh
state=LOW
count=0

calculate_percent()
{
    cat /proc/stat > /tmp/cpu
    free > /tmp/mem

    cpu_idle=`cat /tmp/cpu | grep "cpu " | awk '{print $5}'`
    cpu_total=`cat /tmp/cpu | grep "cpu " | awk '{print $2+$4+$5+$6+$8}'`
    cpu_usage=`expr $cpu_total - $cpu_idle`
    percent_cpu=$((100*cpu_usage/cpu_total))

    mem_use=`cat /tmp/mem | grep "\-\/\+" | awk '{print $3}'`
    mem_total=`cat /tmp/mem | grep "Mem:" | awk '{print $2}'`
    percent_mem=$((100*mem_use/mem_total))
    rm -rf /tmp/cpu /tmp/mem
}

write_infomation()
{   
    echo -n "count = " >> /data/cpu_ram_info
    echo $count >> /data/cpu_ram_info
    date >> /data/cpu_ram_info
    echo ------------------------------------------ >> /data/cpu_ram_info
    echo CPU $percent_cpu >> /data/cpu_ram_info
    echo RAM $percent_mem >> /data/cpu_ram_info
    echo ------------------------------------------ >> /data/cpu_ram_info
    top -n1 | grep -v "PID" >> /data/cpu_ram_info
    echo "*************************************************************" >> /data/cpu_ram_info
    echo "" >> /data/cpu_ram_info
}

while true
do
    #set log file limited about 1MB
    size=`ls -la /data/cpu_ram_info | awk '{print $5}'` > /dev/null 2>&1
    if [[ $size -gt 1000000 ]]; then
        mv /data/cpu_ram_info /data/cpu_ram_info.old
    fi

    count=`expr $count + 1`
    calculate_percent
    if [[ $percent_cpu -gt 80 || $percent_mem -gt 80 ]]; then
        state=HIGH
        write_infomation
    else
        if [[ $state == "HIGH" ]]; then
            echo -n "After over threshold: count = " >> /data/cpu_ram_info
            echo $count >> /data/cpu_ram_info
            state=LOW
            write_infomation
        fi
    fi
    sleep 300
done
