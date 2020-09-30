#!/bin/bash

[ -f "./log.sh" ] && source ./log.sh

#host_ip=$1
#host_password=$2
#host_pswd_file="./host_info/host_pswd/${host_ip//./_}"
#host_ssh="sshpass -f ${host_pswd_file} ssh -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@${host_ip}"
host_ssh="sshpass -p "${host_pswd}" ssh -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@${host_ip}"

# need one paramter , VM's name
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

esxi_power_off(){
    vm_id=$1

    if [ -z "${vm_id}" ]
    then
        log error "esxi need a positive integer of vm_id"
        echo -1
        return
    fi
    interval_sec=20
    cycle_time=6
    i=0
    if [ $(esxi_power_getstate ${vm_id}) -ne 0 ]
    then
        while [ $i -lt ${cycle_time} ]
        do
            ${host_ssh} "vim-cmd vmsvc/power.off ${vm_id} >/dev/null 2>&1"

            if [ $(esxi_power_getstate ${vm_id}) -ne 0 ]
            then
                log warn "the vm ${vm_id} is still not off"
                let i=i+1
                sleep ${interval_sec}
                continue
            else
                echo 0
                return
            fi
            let i=i+1
        done
    else
        echo 0
        return
    fi

    if [ $(esxi_power_getstate ${vm_id}) -ne 0 ]
    then
        log error "esxi power off ${vm_id} err"
        echo -1
        return
    else
        echo 0
        return
    fi
}

esxi_power_shutdown(){
    vm_name=$1

    vm_id=$(esxi_get_vmid ${vm_name})
    if [ ${vm_id} -eq -1 ]
    then
        echo -1
        return
    fi
    interval_sec=30
    cycle_time=6
    i=0
    if [ $(esxi_power_getstate ${vm_id}) -ne 0 ]
    then
        while [ $i -lt ${cycle_time} ]
        do
            ${host_ssh} "vim-cmd vmsvc/power.shutdown ${vm_id} >/dev/null 2>&1"

            if [ $(esxi_power_getstate ${vm_id}) -ne 0 ]
            then
                log warn "the vm ${vm_id} is still not off"
                let i=i+1
                sleep ${interval_sec}
                continue
            else
                echo 0
                return
            fi
            let i=i+1
        done
    else
        echo 0
        return
    fi

    if [ $(esxi_power_getstate ${vm_id}) -ne 0 ]
    then
        log warn "use power.shutdown ${vm_id} err , try power.off again"
        if [ $(esxi_power_off ${vm_id}) -ne 0 ]
        then
            echo -1
            return
        else
            echo 0
            return
        fi
    fi
}

wget_vm_disk_file_to_local(){
    host_file_path="/vmfs/volumes/vDATA*"
    local_tmp_file_path=$1
    vm_name=$2
    host_port=$3
    if [ -z "${vm_name}" ]
    then
        log error "given a null esxi vm's name"
        echo -1
        return
    fi

    if [ ! -d ${local_tmp_file_path}/${vm_name} ]
    then
        log debug "${local_tmp_file_path}/${vm_name} is not exist , make it"
        mkdir -p ${local_tmp_file_path}/${vm_name} >/dev/null 2>&1
        if [ $? -ne 0 ]
        then
            log error "make local temp path err"
            echo -1
            return
        fi
    else
        log debug "${local_tmp_file_path}/${vm_name} is already exist , backup it"
        backup_nm=${vm_name}_$(date +%Y%m%d)
        mv ${local_tmp_file_path}/${vm_name} ${local_tmp_file_path}/${backup_nm} >/dev/null 2>&1
        if [ $? -ne 0 ]
        then
            log error "backup local temp path ${local_tmp_file_path}/${vm_name} err , coverage directly"
        else
            mkdir -p ${local_tmp_file_path}/${vm_name} >/dev/null 2>&1
            if [ $? -ne 0 ]
            then
                log error "make local temp path err after backup"
                echo -1
                return
            fi
        fi
    fi

    cd ${local_tmp_file_path}/${vm_name} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "change directory to ${local_tmp_file_path}/${vm_name} err"
        echo -1
        return
    fi

    disk_list=$(${host_ssh} "ls ${host_file_path}/${vm_name}*/*-flat.vmdk 2>/dev/null")
    if [ -z "${disk_list}" -o $? -ne 0 ]
    then
        log error "get ${vm_name} disk list on ${host_ip}:${host_file_path}/${vm_name}*/*-flat.vmdk err"
        echo -1
        return
    fi
    log debug "${vm_name} have disk file list ${disk_list}"

    disk_list=$(echo ${disk_list} | sed "s/ /@/g" | sed "s/vmdk@/vmdk /g")

    esxi_disk_num=0
    for i in `echo ${disk_list: }`
    do
        let esxi_disk_num=esxi_disk_num+1
    done
    if [ ! -z "$(echo ${esxi_disk_num} | grep -v '^[[:digit:]]*$')" -o -z "${esxi_disk_num}" ]
    then
        log error "count vm disk file is ${esxi_disk_num}"
        echo -1
        return
    fi
    if [ ${esxi_disk_num} -lt 1 -o ${esxi_disk_num} -ge 3 ]
    then
        log warn "vm disk file is too much , disk file num is ${esxi_disk_num}, manual process"
        echo -1 
        return
    fi

    for i in `echo ${disk_list: }`
    do
        log debug "copy file ${i//@/\\ }"
        current_vm_path=${i%/*}
        current_vm_path=${current_vm_path##*/}
        current_vm_path=${current_vm_path//@/%20}
        log debug "wget http://${host_ip}:${host_port}/${current_vm_path}/${i##*/}"
        esxi_file_size=$(${host_ssh} "ls -lrt ${host_file_path}/${current_vm_path%%@*}/${i##*/} | awk '{print \$5}'")
        #esxi_file_md5=$(${host_ssh} "md5sum ${i}")
        log debug "++++++++++++++++begin copy disk file ${i##*/}++++++++++++++++"
        wget http://${host_ip}:${host_port}/${current_vm_path}/${i##*/} &>/dev/null
        if [ $? -ne 0 ]
        then
            log error "wget http://${host_ip}:${host_port}/${current_vm_path}/${i##*/} err"
            echo -1
            return
        fi
        log debug "++++++++++++++++end copy disk file ${i##*/}++++++++++++++++"
        #libvirt_file_md5=$(md5sum ${i##*/})
        libvirt_file_size=$(ls -lrt ${i##*/} | awk '{print $5}')

        if [ "A${esxi_file_size}" == "A${libvirt_file_size}" ]
        then
            log debug "wget http://${host_ip}:${host_port}/${vm_name}*/${i##*/} compare file size success"
        else
            log error "wget http://${host_ip}:${host_port}/${vm_name}*/${i##*/} compare file size err"
            log error "esxi platform ${i} file size is ${esxi_file_size}"
            log error "libvirt platform ${i} file size is ${esxi_file_size}"
            echo -1
            return
        fi
    done
    echo 0
}

scp_vm_system_file_to_local(){
    host_file_path="/vmfs/volumes/vDATA*"
    local_tmp_file_path=$1
    vm_name=$2
    if [ -z "${vm_name}" ]
    then
        log error "given a null esxi vm's name"
        echo -1
        return
    fi

    if [ ! -d ${local_tmp_file_path}/${vm_name} ]
    then
        log debug "${local_tmp_file_path}/${vm_name} is not exist , make it"
        mkdir -p ${local_tmp_file_path}/${vm_name} >/dev/null 2>&1
        if [ $? -ne 0 ]
        then
            log error "make local temp path err"
            echo -1
            return
        fi
    else
        log debug "${local_tmp_file_path}/${vm_name} is already exist , backup it"
        backup_nm=${vm_name}_$(date +%Y%m%d)
        mv ${local_tmp_file_path}/${vm_name} ${local_tmp_file_path}/${backup_nm} >/dev/null 2>&1
        if [ $? -ne 0 ]
        then
            log error "backup local temp path ${local_tmp_file_path}/${vm_name} err , coverage directly"
        else
            mkdir -p ${local_tmp_file_path}/${vm_name} >/dev/null 2>&1
            if [ $? -ne 0 ]
            then
                log error "make local temp path err after backup"
                echo -1
                return
            fi
        fi
    fi

    sshpass -f ${host_pswd_file} scp -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@${host_ip}:${host_file_path}/${vm_name}/*flat.vmdk ${local_tmp_file_path}/${vm_name} >>${logfile} 2>&1
    if [ $? -ne 0 ]
    then
        log error "scp -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@${host_ip}:${host_file_path}/${vm_name}/*flat.vmdk to local path ${local_tmp_file_path}/${vm_name} err"
        echo -1
        return
    fi
    echo 0
}

#after esxi power on , need ping outer network IP
esxi_power_on(){
    vm_name=$1

    vm_id=$(esxi_get_vmid ${vm_name})
    if [ ${vm_id} -eq -1 ]
    then
        echo -1
        return
    fi
    interval_sec=30
    cycle_time=6
    i=0
    if [ $(esxi_power_getstate ${vm_id}) -ne 1 ]
    then
        while [ $i -lt ${cycle_time} ]
        do
            ${host_ssh} "vim-cmd vmsvc/power.on ${vm_id} >/dev/null 2>&1"

            if [ $(esxi_power_getstate ${vm_id}) -ne 1 ]
            then
                log warn "the vm ${vm_id} is still not on"
                let i=i+1
                sleep ${interval_sec}
                continue
            else
                break
            fi
            let i=i+1
        done
    else
        echo 0
        return
    fi

    if [ $(esxi_power_getstate ${vm_id}) -ne 1 ]
    then
        log error "esxi power on ${vm_id} err"
        echo -1
    else
        echo 0
    fi
    return
}

virsh_get_vm_state(){
    temp_vm_name=$1
    vmstate=$(virsh domstate ${temp_vm_name} | head -n 1 2>/dev/null)
    echo ${vmstate}
    return
}

virsh_wait_vm_shutdown(){
    vm_name=$1
    interval_sec=$2
    cycle_time=$3
    if [ -z "${vm_name}" ]
    then
        log error "wait vm shutdown have given a null vm name"
        echo -1
        return
    fi

    [ ! -z "${interval_sec}" ] && [ ! -z "$(echo ${interval_sec} | grep '^[[:digit:]]*$')" ] || interval_sec=20
    [ ! -z "${cycle_time}" ] && [ ! -z "$(echo ${cycle_time} | grep '^[[:digit:]]*$')" ] || cycle_time=20

    i=0
    if [ "A$(virsh_get_vm_state ${vm_name})" != "Ashut off" ]
    then
        while [ $i -lt ${cycle_time} ]
        do
            sleep ${interval_sec}

            if [ "A$(virsh_get_vm_state ${vm_name})" == "Ashut off" ]
            then
                log info "the vm ${vm_name} is shut off"
                echo 0
                return
            fi
            log debug "the vm ${vm_name} is still running"
            let i=i+1
        done
    else
        log error "vm ${vm_name} first startup state is not normal"
        echo -1
        return
    fi

    if [ "A$(virsh_get_vm_state ${vm_name})" != "Ashut off" ]
    then
        log warn "vm ${vm_name} still running"
        echo -1
        return
    fi
    echo 0
}

windows_03_32_auto_install_virtio(){
    vm_tmp_path=$1
    sys_file_nm=$2
    nbd_num=$3
    temp_xml_path="${vm_tmp_path}/test.xml"

    if [ -z "${vm_tmp_path}" -o ! -d ${vm_tmp_path} ]
    then
        log error "windows 2003 32bit ${vm_tmp_path} is not exist"
        echo -1
        return
    fi

    if [ -z "${sys_file_nm}" -o ! -f ${sys_file_nm} ]
    then
        log error "windows 2003 32bit system file ${sys_file_nm} is not exist in ${vm_tmp_path}"
        echo -1
        return
    fi

    cd ${vm_tmp_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "change directory to ${vm_tmp_path} err"
        echo -1
        return
    fi

    temp_data_disk=$(ls ${vm_tmp_path}/*_1-flat.vmdk 2>/dev/null)

    #process the xml that start the VM , use Python script
    python ./process_xml.py -f "${temp_xml_path}" -n "${sys_file_nm%.*}" -s "${vm_tmp_path}/${sys_file_nm}" -a "i686" -d "${temp_data_disk}" &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "xml file is [${temp_xml_path}]"
        log error "new name is [${sys_file_nm%.*}]"
        log error "new stroage is [${vm_tmp_path}/${sys_file_nm}]"
        log error "arch is [i686]"
        echo -1 
        return
    fi

    virsh undefine ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log debug "${sys_file_nm%.*} is not defined"
    fi

    virsh define ${temp_xml_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "define temp vm ${sys_file_nm%.*} err"
        echo -1
        return
    fi

    virsh start ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "start temp vm ${sys_file_nm%.*} first err"
        echo -1
        return
    fi

    sleep 2

    if [ $(virsh_wait_vm_shutdown ${sys_file_nm%.*} "20" "50") -ne 0 ]
    then
        log error "first timeout , after 1000 seconds , the vm ${sys_file_nm%.*} still running"
        echo -1
        return
    fi

    virsh start ${sys_file_nm%.*} >/dev/null 2>&1
    if [ $? -ne 0 ]
    then
        log error "start temp vm ${sys_file_nm%.*} second err"
        echo -1
        return
    fi

    sleep 2

    if [ $(virsh_wait_vm_shutdown ${sys_file_nm%.*} "20" "9") -ne 0 ]
    then
        log warn "second timeout , after three minute , the vm ${sys_file_nm%.*} still running."
        log warn "but may be the drivers is already installed success , so continue as normal after shutdown the vm"
        virsh destroy ${sys_file_nm%.*} &>/dev/null
    fi

    ./cleanup.sh ${sys_file_nm} ${nbd_num} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "${sys_file_nm%.*} after twice start , cleanup err , but continue as normal"
    fi

    virsh undefine ${sys_file_nm%.*} >/dev/null 2>&1
    if [ $? -ne 0 ]
    then
        log error "undefine temp vm ${sys_file_nm%.*} err"
        echo -1
        return
    fi

    echo 0
}

windows_03_64_auto_install_virtio(){
    vm_tmp_path=$1
    sys_file_nm=$2
    nbd_num=$3
    temp_xml_path="${vm_tmp_path}/test.xml"

    if [ -z "${vm_tmp_path}" -o ! -d ${vm_tmp_path} ]
    then
        log error "windows 2003 64bit ${vm_tmp_path} is not exist"
        echo -1
        return
    fi

    if [ -z "${sys_file_nm}" -o ! -f ${sys_file_nm} ]
    then
        log error "windows 2003 64bit system file ${sys_file_nm} is not exist in ${vm_tmp_path}"
        echo -1
        return
    fi

    cd ${vm_tmp_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "change directory to ${vm_tmp_path} err"
        echo -1
        return
    fi

    temp_data_disk=$(ls ${vm_tmp_path}/*_1-flat.vmdk 2>/dev/null)

    #process the xml that start the VM , use Python script
    python ./process_xml.py -f "${temp_xml_path}" -n "${sys_file_nm%.*}" -s "${vm_tmp_path}/${sys_file_nm}" -a "x86_64" -d "${temp_data_disk}" &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "xml file is [${temp_xml_path}]"
        log error "new name is [${sys_file_nm%.*}]"
        log error "new stroage is [${vm_tmp_path}/${sys_file_nm}]"
        log error "arch is [x86_64]"
        echo -1 
        return
    fi

    virsh undefine ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log debug "${sys_file_nm%.*} is not defined"
    fi

    virsh define ${temp_xml_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "define temp vm ${sys_file_nm%.*} err"
        echo -1
        return
    fi

    virsh start ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "start temp vm ${sys_file_nm%.*} first err"
        echo -1
        return
    fi

    sleep 2

    if [ $(virsh_wait_vm_shutdown ${sys_file_nm%.*} "20" "50") -ne 0 ]
    then
        log error "first timeout , after 1000 seconds , the vm ${sys_file_nm%.*} still running"
        echo -1
        return
    fi

    virsh start ${sys_file_nm%.*} >/dev/null 2>&1
    if [ $? -ne 0 ]
    then
        log error "start temp vm ${sys_file_nm%.*} second err"
        echo -1
        return
    fi

    sleep 2

    if [ $(virsh_wait_vm_shutdown ${sys_file_nm%.*} "20" "9") -ne 0 ]
    then
        log warn "second timeout , after three minute , the vm ${sys_file_nm%.*} still running."
        log warn "but may be the drivers is already installed success , so continue as normal after shutdown the vm"
        virsh destroy ${sys_file_nm%.*} &>/dev/null
    fi

    ./cleanup.sh ${sys_file_nm} ${nbd_num} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "${sys_file_nm%.*} after twice start , cleanup err , but continue as normal"
    fi

    virsh undefine ${sys_file_nm%.*} >/dev/null 2>&1
    if [ $? -ne 0 ]
    then
        log error "undefine temp vm ${sys_file_nm%.*} err"
        echo -1
        return
    fi

    echo 0
}

windows_08_64_auto_install_virtio(){
    vm_tmp_path=$1
    sys_file_nm=$2
    nbd_num=$3
    temp_xml_path="${vm_tmp_path}/test.xml"

    if [ -z "${vm_tmp_path}" -o ! -d ${vm_tmp_path} ]
    then
        log error "windows 2008 64bit ${vm_tmp_path} is not exist"
        echo -1
        return
    fi

    if [ -z "${sys_file_nm}" -o ! -f ${sys_file_nm} ]
    then
        log error "windows 2008 64bit system file ${sys_file_nm} is not exist in ${vm_tmp_path}"
        echo -1
        return
    fi

    cd ${vm_tmp_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "change directory to ${vm_tmp_path} err"
        echo -1
        return
    fi

    temp_data_disk=$(ls ${vm_tmp_path}/*_1-flat.vmdk 2>/dev/null)
    [ "A${temp_data_disk}" != "A" ] || temp_data_disk="${vm_tmp_path}/data_disk.qcow2"

    #process the xml that start the VM , use Python script
    python ./process_xml.py -f "${temp_xml_path}" -n "${sys_file_nm%.*}" -s "${vm_tmp_path}/${sys_file_nm}" -a "x86_64" -d "${temp_data_disk}" &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "xml file is [${temp_xml_path}]"
        log error "new name is [${sys_file_nm%.*}]"
        log error "new stroage is [${vm_tmp_path}/${sys_file_nm}]"
        log error "arch is [x86_64]"
        echo -1 
        return
    fi

    virsh undefine ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log debug "${sys_file_nm%.*} is not defined"
    fi

    virsh define ${temp_xml_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "define temp vm ${sys_file_nm%.*} err"
        echo -1
        return
    fi

    virsh start ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "start temp vm ${sys_file_nm%.*} first err"
        echo -1
        return
    fi

    sleep 2

    if [ $(virsh_wait_vm_shutdown ${sys_file_nm%.*} "20" "50") -ne 0 ]
    then
        log error "first timeout , after three minute , the vm ${sys_file_nm%.*} still running"
        echo -1
        return
    fi

    virsh undefine ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log debug "before second start ${sys_file_nm%.*}, undefine it error"
        echo -1
        return
    fi

    sed -i -e "/dev=.hda./s/hda/vda/" ${temp_xml_path} &>/dev/null && sed -i -e "/bus=.ide./s/ide/virtio/" ${temp_xml_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log debug "before second start ${sys_file_nm%.*}, modify disk driver from ide to virtio error"
        echo -1
        return
    fi

    virsh define ${temp_xml_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "second define temp vm ${sys_file_nm%.*} err"
        echo -1
        return
    fi

    virsh start ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "start temp vm ${sys_file_nm%.*} second err"
        echo -1
        return
    fi

    sleep 2

    if [ $(virsh_wait_vm_shutdown ${sys_file_nm%.*} "20" "9") -ne 0 ]
    then
        log warn "second timeout , after 400 secs, the vm ${sys_file_nm%.*} still running."
        log warn "but may be the drivers is already installed success , so continue as normal after shutdown the vm"
        virsh destroy ${sys_file_nm%.*} &>/dev/null
    fi

    ./cleanup.sh ${sys_file_nm} ${nbd_num} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "${sys_file_nm%.*} after twice start , cleanup err , but continue as normal"
    fi

    virsh undefine ${sys_file_nm%.*} >/dev/null 2>&1
    if [ $? -ne 0 ]
    then
        log error "undefine temp vm ${sys_file_nm%.*} err"
        echo -1
        return
    fi

    echo 0
}

windows_12_64_auto_install_virtio(){
    vm_tmp_path=$1
    sys_file_nm=$2
    nbd_num=$3
    temp_xml_path="${vm_tmp_path}/test.xml"

    if [ -z "${vm_tmp_path}" -o ! -d ${vm_tmp_path} ]
    then
        log error "windows 2012 64bit ${vm_tmp_path} is not exist"
        echo -1
        return
    fi

    if [ -z "${sys_file_nm}" -o ! -f ${sys_file_nm} ]
    then
        log error "windows 2012 64bit system file ${sys_file_nm} is not exist in ${vm_tmp_path}"
        echo -1
        return
    fi

    cd ${vm_tmp_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "change directory to ${vm_tmp_path} err"
        echo -1
        return
    fi

    temp_data_disk=$(ls ${vm_tmp_path}/*_1-flat.vmdk 2>/dev/null)
    [ "A${temp_data_disk}" != "A" ] || temp_data_disk="${vm_tmp_path}/data_disk.qcow2"

    #process the xml that start the VM , use Python script
    python ./process_xml.py -f "${temp_xml_path}" -n "${sys_file_nm%.*}" -s "${vm_tmp_path}/${sys_file_nm}" -a "x86_64" -d "${temp_data_disk}" &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "xml file is [${temp_xml_path}]"
        log error "new name is [${sys_file_nm%.*}]"
        log error "new stroage is [${vm_tmp_path}/${sys_file_nm}]"
        log error "arch is [x86_64]"
        echo -1 
        return
    fi

    virsh undefine ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log debug "${sys_file_nm%.*} is not defined"
    fi

    virsh define ${temp_xml_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "define temp vm ${sys_file_nm%.*} err"
        echo -1
        return
    fi

    virsh start ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "start temp vm ${sys_file_nm%.*} first err"
        echo -1
        return
    fi

    sleep 2

    if [ $(virsh_wait_vm_shutdown ${sys_file_nm%.*} "20" "50") -ne 0 ]
    then
        log error "first timeout , after three minute , the vm ${sys_file_nm%.*} still running"
        echo -1
        return
    fi

    virsh undefine ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log debug "before second start ${sys_file_nm%.*}, undefine it error"
        echo -1
        return
    fi

    sed -i -e "/dev=.hda./s/hda/vda/" ${temp_xml_path} &>/dev/null && sed -i -e "/bus=.ide./s/ide/virtio/" ${temp_xml_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log debug "before second start ${sys_file_nm%.*}, modify disk driver from ide to virtio error"
        echo -1
        return
    fi

    virsh define ${temp_xml_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "second define temp vm ${sys_file_nm%.*} err"
        echo -1
        return
    fi

    virsh start ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "start temp vm ${sys_file_nm%.*} second err"
        echo -1
        return
    fi

    sleep 2

    if [ $(virsh_wait_vm_shutdown ${sys_file_nm%.*} "20" "9") -ne 0 ]
    then
        log warn "second timeout , after 400 secs, the vm ${sys_file_nm%.*} still running."
        log warn "but may be the drivers is already installed success , so continue as normal after shutdown the vm"
        virsh destroy ${sys_file_nm%.*} &>/dev/null
    fi

    ./cleanup.sh ${sys_file_nm} ${nbd_num} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "${sys_file_nm%.*} after twice start , cleanup err , but continue as normal"
    fi

    virsh undefine ${sys_file_nm%.*} >/dev/null 2>&1
    if [ $? -ne 0 ]
    then
        log error "undefine temp vm ${sys_file_nm%.*} err"
        echo -1
        return
    fi

    echo 0
}

centos_6_64_auto_install_virtio(){
    vm_tmp_path=$1
    sys_file_nm=$2
    nbd_num=$3
    temp_xml_path="${vm_tmp_path}/test.xml"

    if [ -z "${vm_tmp_path}" -o ! -d ${vm_tmp_path} ]
    then
        log error "centos 6 64bit ${vm_tmp_path} is not exist"
        echo -1
        return
    fi

    if [ -z "${sys_file_nm}" -o ! -f ${sys_file_nm} ]
    then
        log error "centos 6 64bit system file ${sys_file_nm} is not exist in ${vm_tmp_path}"
        echo -1
        return
    fi

    cd ${vm_tmp_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "change directory to ${vm_tmp_path} err"
        echo -1
        return
    fi

    temp_data_disk=$(ls ${vm_tmp_path}/*_1-flat.vmdk 2>/dev/null)
    [ "A${temp_data_disk}" != "A" ] || temp_data_disk="${vm_tmp_path}/data_disk.qcow2"

    #process the xml that start the VM , use Python script
    python ./process_xml.py -f "${temp_xml_path}" -n "${sys_file_nm%.*}" -s "${vm_tmp_path}/${sys_file_nm}" -a "x86_64" -d "${temp_data_disk}" &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "xml file is [${temp_xml_path}]"
        log error "new name is [${sys_file_nm%.*}]"
        log error "new stroage is [${vm_tmp_path}/${sys_file_nm}]"
        log error "arch is [x86_64]"
        echo -1 
        return
    fi

    virsh undefine ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log debug "${sys_file_nm%.*} is not defined"
    fi

    virsh define ${temp_xml_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "define temp vm ${sys_file_nm%.*} err"
        echo -1
        return
    fi

    virsh start ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "start temp vm ${sys_file_nm%.*} first err"
        echo -1
        return
    fi

    sleep 2

    if [ $(virsh_wait_vm_shutdown ${sys_file_nm%.*} "10" "30") -ne 0 ]
    then
        log error "first timeout , after three hundreds sec , the vm ${sys_file_nm%.*} still running"
        echo -1
        return
    fi

    virsh undefine ${sys_file_nm%.*} &>/dev/null
    if [ $? -ne 0 ]
    then
        log debug "${sys_file_nm%.*} undefined error"
        echo -1
        return
    fi

    ./cleanup.sh ${sys_file_nm} ${nbd_num} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "${sys_file_nm%.*} after once start , cleanup err , but continue as normal"
    fi

    echo 0
}

local_vm_install_driver(){
    vm_tmp_path=$1
    vm_type=$2
    vm_version=$3
    vm_arch=$4
    nbd_num=$5
    tar_nm=$(ls *.tar.gz | grep -i ${vm_type} | grep -i "${vm_version}" | grep -i ${vm_arch})
    if [ -z "${tar_nm}" -o ! -f "${tar_nm}" ]
    then
        log error "can not find tar bag for ${vm_type} ${vm_version} ${vm_arch}"
        echo -1
        return
    fi

    if [ -z "${vm_tmp_path}" -o ! -d "${vm_tmp_path}" ]
    then
        log error "temp vm path is not exist"
        echo -1
        return
    fi

    tar -zxvf ${tar_nm} -C ${vm_tmp_path} >/dev/null 2>&1 && cp ./process_xml.py ${vm_tmp_path} &>/dev/null && cd ${vm_tmp_path} &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "uncompress tool's tar bag into ${vm_tmp_path} err"
        echo -1
        return
    fi

    disk_num=$(ls -l *-flat.vmdk | wc -l)
    if [ -z "${disk_num}" -o ${disk_num} -lt 1 ]
    then
        log error "count vm disk file error"
        echo -1
        return
    elif [ ${disk_num} -ge 3 ]
    then
        log warn "vm disk file is too much , manual process"
        echo -1 
        return
    fi

    # only copy system file
    #for i in `ls *-flat.vmdk`
    #do
    #    log debug "cp ${vm_tmp_path}/${i} ${vm_tmp_path}/${i%.*}.img"
    #    cp ${i} ${i%.*}.img >/dev/null 2>&1
    #    if [ $? -ne 0 ]
    #    then
    #        log error "copy vmdk to img type err"
    #        echo -1
    #        return
    #    fi
    #done
    sys_org_nm=$(ls *-flat.vmdk | grep -v "_.-flat.vmdk")
    if [ -z "${sys_org_nm}" ]
    then
        log error "can not find system file in ${vm_tmp_path}"
        echo -1
        return
    fi

    #cp ${sys_org_nm} ${sys_org_nm%.*}.img >/dev/null 2>&1
    #if [ $? -ne 0 ]
    #then
    #    log error "copy system file ${sys_org_nm} to ${sys_org_nm%.*}.img err"
    #    echo -1
    #    return
    #fi

    #sys_file_nm=$(ls *-flat.img | grep -v "_.-flat.img")
    #if [ -z "${sys_file_nm}" ]
    #then
    #    log error "can not find vm system file name"
    #    echo -1
    #    return
    #fi

    sys_file_nm=${sys_org_nm}

    ./auto_exec.sh "${sys_file_nm}" "${nbd_num}" &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "automatic process vm's system file err"
        echo -1
        return
    fi

    case ${vm_type} in
        Windows|windows)
            case ${vm_version} in
                03)
                    case ${vm_arch} in
                        32)
                            exec_ret=$(windows_03_32_auto_install_virtio ${vm_tmp_path} ${sys_file_nm} ${nbd_num})
                            ;;
                        64)
                            exec_ret=$(windows_03_64_auto_install_virtio ${vm_tmp_path} ${sys_file_nm} ${nbd_num})
                            ;;
                        *)
                            log error "Not supported Windows ${vm_arch}"
                            exec_ret=-1 
                            ;;
                    esac
                    ;;
                08R2)
                    case ${vm_arch} in
                        64)
                            exec_ret=$(windows_08_64_auto_install_virtio ${vm_tmp_path} ${sys_file_nm} ${nbd_num})
                            ;;
                        *)
                            log error "Not supported Windows ${vm_arch}"
                            exec_ret=-1 
                            ;;
                    esac
                    ;;
                12)
                    case ${vm_arch} in
                        64)
                            exec_ret=$(windows_12_64_auto_install_virtio ${vm_tmp_path} ${sys_file_nm} ${nbd_num})
                            ;;
                        *)
                            log error "Not supported Windows ${vm_arch}"
                            exec_ret=-1 
                            ;;
                    esac
                    ;;
                *)
                    log error "Not supported Windows ${vm_version}"
                    exec_ret=-1 
                    ;;
            esac
            ;;
        Centos|centos)
            case ${vm_version} in
                6)
                    case ${vm_arch} in
                        64)
                            #don't install qemu-ga, modify on 20200317
                            #exec_ret=$(centos_6_64_auto_install_virtio ${vm_tmp_path} ${sys_file_nm} ${nbd_num})
                            exec_ret=0
                            ;;
                        *)
                            log error "Not supported CentOS ${vm_arch}"
                            exec_ret=-1 
                            ;;
                    esac
                    ;;
                *)
                    log error "Not Supported CentOS ${vm_version}"
                    exec_ret=-1 
                    ;;
            esac
            ;;
        *) 
            log error "Not Supported ${vm_type}"
            exec_ret=-1 
            ;;
    esac

    echo ${exec_ret}
    return
}
