#!/bin/bash
#可将log函数单独放一个文件，通过.命令引入，这样就可以共用了
#. log.sh 
#设置日志级别
loglevel=0 #debug:0; info:1; warn:2; error:3
#logfile=$0".log"
function log {
    local msg;local logtype
    logtype=$1
    msg=$2
    datetime=`date +'%F %H:%M:%S'`
    #使用内置变量$LINENO不行，不能显示调用那一行行号
    #logformat="[${logtype}]\t${datetime}\tfuncname:${FUNCNAME[@]} [line:$LINENO]\t${msg}"
    logformat="[${logtype}]\t${datetime}\tfuncname: ${FUNCNAME[@]/log/}\t[line:`caller 0 | awk '{print$1}'`]\t${msg}"
    #funname格式为log error main,如何取中间的error字段，去掉log好办，再去掉main,用echo awk? ${FUNCNAME[0]}不能满足多层函数嵌套
    {  
    case $logtype in 
        debug)
            [[ $loglevel -le 0 ]] && echo -e "${logformat}" ;;
        info)
            [[ $loglevel -le 1 ]] && echo -e "${logformat}" ;;
        warn)
            [[ $loglevel -le 2 ]] && echo -e "${logformat}" ;;
        error)
            [[ $loglevel -le 3 ]] && echo -e "${logformat}" ;;
        *)
            logger migrate "${logformat}" ;;
    esac
    } >>$logfile 2>&1
}
