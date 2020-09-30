#!/bin/bash

wait_migrate_list=$1
nbd=0
process_num=0

insure_nbd_little_three(){
    while true
    do
        process_num=$(ps -ef | grep -Po 'nbd[0-9]+' | grep -v grep | sort | uniq | wc -l)
        if [ ${process_num} -lt 3 ]
        then
            break
        else
            sleep 60
        fi
    done
}

get_next_use_nbd(){
    for((i=0;i<=11;i++))
    do
        #ps -ef | grep nbd | grep migrate_scheduler | grep -v grep | grep -Po 'nbd[0-9]+' | sort | uniq | sed "s/nbd//"
        ps -ef | grep nbd$i | grep -v grep &>/dev/null
        if [ $? -ne 0 ]
        then
            echo $i
            return
        fi
    done
    echo -1
}

if [ -f ${wait_migrate_list} ]
then
    echo 1 > /proc/sys/vm/drop_caches &>/dev/null
    line_num=1
    line_count=0
    line_count=$(wc -l ${wait_migrate_list} | awk '{print $1}' 2>/dev/null)
    if [ ${line_count} -ge 1 ]
    then
        while [ ${line_num} -le ${line_count} ]
        do
            insure_nbd_little_three
            nbd=$(get_next_use_nbd)
            if [ ${nbd} -lt 0 -o ${nbd} -gt 11 ]
            then
                echo "get error nbd num ${nbd}" &>>startup.log
                exit -1
            fi
            line=$(sed -n ${line_num}p ${wait_migrate_list} 2>/dev/null)
            param_list=$line" "nbd${nbd}
            echo ${param_list} &>>startup.log
            nohup sh ./migrate_scheduler.sh ${param_list} &>>startup.log &
            let line_num=line_num+1
        done
    fi
fi
