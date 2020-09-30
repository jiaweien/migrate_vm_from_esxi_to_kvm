#!/bin/bash

[ -f ./log.sh ] && source ./log.sh
classify_path="/var/lib/libvirt/qemu/ssd/migrate_log"
logfile="${classify_path}/classify.log"

esxi_get_vmid(){
    vm_name=$1
    if [ -z "${vm_name}" ]
    then
        log error "given a null esxi vm's name"
        echo -1
        return
    fi
    vm_id=$(${host_ssh} "vim-cmd vmsvc/getallvms | grep ${vm_name} | awk '{print \$1}' 2>/dev/null")
    if [ $? -ne 0 -o -z "${vm_id}" ]
    then
        log error "get esxi vm's ID err"
        echo -1
        return
    fi
    log debug "vm ID is ${vm_id}"
    echo ${vm_id}
}

esxi_power_getstate(){
    vm_id=$1
    if [ -z "${vm_id}" ]
    then
        log error "given a null esxi vm's ID"
        echo -1
        return
    fi
    vm_stat=$(${host_ssh} "vim-cmd vmsvc/power.getstate ${vm_id} | tail -n 1")
    if [ $? -ne 0 -o -z "${vm_stat}" ]
    then
        log error "get vm state err"
        echo -1
        return
    fi

    # 0 is poweroff , 1 is power on , 2 is other
    if [ ! -z "$(echo ${vm_stat} | grep -i 'powered off')" ]
    then
        log debug "VMID ${vm_id} is ${vm_stat}"
        echo 0
    elif [ ! -z "$(echo ${vm_stat} | grep -i 'powered on')" ]
    then
        log debug "VMID ${vm_id} is ${vm_stat}"
        echo 1
    else
        log debug "VMID ${vm_id} is ${vm_stat}"
        echo 2
    fi
    return
}

wait_migrate_list_sum=$1

file_count=0
file_count=$(wc -l ${wait_migrate_list_sum} | awk '{print $1}')
if [ ${file_count} -le 0 ]
then
    log error "give a empty file"
    exit 1
fi

line_serial=1
while [ ${line_serial} -le ${file_count} ]
do
    host_ip=$(sed -n ${line_serial}p ${wait_migrate_list_sum} | awk '{print $1}' 2>/dev/null)
    host_pswd=$(sed -n ${line_serial}p ${wait_migrate_list_sum} | awk '{print $2}' 2>/dev/null)
    vm_name=$(sed -n ${line_serial}p ${wait_migrate_list_sum} | awk '{print $3}' 2>/dev/null)
    if [ -z "${host_ip}" ] || [ -z "${host_pswd}" ] || [ -z "${vm_name}" ]
    then
        log error "check vm ${vm_name} state error"
        continue
    fi
    host_ssh="sshpass -p "${host_pswd}" ssh -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@${host_ip}"
    vm_id=$(esxi_get_vmid ${vm_name})
    if [ $? -ne 0 -o -z "{vm_id}" ]
    then
        log error "get vm ${vm_name} vm id error"
        continue
    fi
    vm_stat=$(esxi_power_getstate ${vm_id})
    if [ $? -ne 0 -o -z "{vm_state}" ]
    then
        log error "get vm ${vm_name} vm state error"
        continue
    fi
    file_name=$(echo ${host_ip} | tr '.' '_')
    if [ ${vm_stat} -eq 0 ]
    then
        $(sed -n ${line_serial}p ${wait_migrate_list_sum} >> ${file_name}.poweroff 2>/dev/null)
        if [ $? -ne 0 ]
        then
            log error "vm ${vm_name} classify error"
            continue
        fi
    elif [ ${vm_stat} -eq 1 ]
    then
        $(sed -n ${line_serial}p ${wait_migrate_list_sum} >> ${file_name}.running 2>/dev/null)
        if [ $? -ne 0 ]
        then
            log error "vm ${vm_name} classify error"
            continue
        fi
    else
        $(sed -n ${line_serial}p ${wait_migrate_list_sum} >> ${file_name}.unknow 2>/dev/null)
        if [ $? -ne 0 ]
        then
            log error "vm ${vm_name} classify error"
            continue
        fi
    fi
    let line_serial=line_serial+1
done
