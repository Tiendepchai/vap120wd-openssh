#!bin/sh
# Author: phuongdv12@viettel.com.vn

mySN=$(sysHwInfo serialnumber r)
controllerSN="CONTROLLER"
controllerSN=$1

NowTime=$(date "+%Y-%m-%d_%T" | sed "s/:/./gi")

LOG="log"
logTmpDir="/tmp/log"
logDataDir="/data/log"
genLogFolder="LogFiles_${mySN}_${controllerSN}_${NowTime}"
genLogCompressFile="${genLogFolder}.tar.gz"
genLogDir="/data/${genLogFolder}"
genLogCompressFileDir="/data/${genLogCompressFile}"

ifconfigFile="ifconfig.txt"
iwconfigFile="iwconfig.txt"
netstatFile="netstat.txt"
psFile="ps.txt"

otherFiles="/etc/mapd_cfg.txt /etc/mapd_strng.conf /etc/map_cfg.txt -h /etc/config/network ${ifconfigFile} ${iwconfigFile} ${netstatFile} ${psFile}"

loginUserName=vsftpd11
loginUserPw=apdualbandproject
Server=vhtont.sytes.net
ServerLogDir=/home/${loginUserName}/ap_log/
Port=11496

echo ${controllerSN}
#echo ${genLogCompressFile}

# CMD="mkdir ${genLogDir}"
# ${CMD}
# echo ${CMD}

# Note: Always work at /data

CMD="cd /data"
${CMD}
echo ${CMD}

ifconfig > /data/${ifconfigFile}
echo "ifconfig > /data/${ifconfigFile}"

iwconfig > ${iwconfigFile}
echo "iwconfig > /data/${iwconfigFile}"

netstat -ap > ${netstatFile}
echo "netstat -ap > /data/${netstatFile}"

ps -w > ${psFile}
echo "ps -w > /data/${psFile}"

CMD="/usr/sbin/backup_log_when_downloading_log_from_web.sh"
${CMD}
echo ${CMD}

CMD="cd /data"
${CMD}
echo ${CMD}

CMD="tar -zcvf ${genLogCompressFileDir} log/ ${otherFiles}"
${CMD}
echo ${CMD}

# CMD="rm -rf ${genLogDir}"
# ${CMD}
# echo ${CMD}

CMD="rm -f ${ifconfigFile} ${iwconfigFile} ${netstatFile} ${psFile}"
${CMD}
echo ${CMD}

CMD="curl -T ${genLogCompressFile} -k -u ${loginUserName}:${loginUserPw} scp://${Server}:${Port}${ServerLogDir}"
${CMD}
echo ${CMD}

CMD="rm -f ${genLogCompressFile}"
${CMD}
echo ${CMD}
