#!/bin/bash

[ -f ./log.sh ] && source ./log.sh

_IPV4_SUBNET_ID=''
_FLAVOR_ID=''

_RC_FILE='/var/lib/libvirt/qemu/ssd/.laoyun'
_PROJECT_ID='d6bbc17def0a4c6e8ebaebfd55d7ae11'
_IPV4_NETID='8870ed5d-7eca-4ce7-8a35-0f679a382deb'
_SECURITY_GROUP_ID='49630f30-df74-4c9d-a8c1-53ec58228c26'
_IMAGE_ID='271ae9d6-c3f5-4b36-95a6-26c863531292'
_POOL_NAME='cinder-sas'
_VOLUME_TYPE='ceph-ssd'
ARP_RECORD_FILE="/var/lib/libvirt/qemu/ssd/last/monitor_arp_data/monitor_arp_record.data"
if [ ! -f ${_RC_FILE} ]
then
    log error "user laoyun profile is not exist"
    echo -1
    return
fi
source $_RC_FILE &>/dev/null

uc_tmp_vm_replace_system_file(){
    QCOW2_FILE=$1
    instance_id=$2

    volume_id=$(nova volume-attachments $instance_id |awk 'NR==4{print $8}')
    snap_nm=$(rbd snap ls ${_POOL_NAME}/volume-${volume_id} | awk 'NR==2{print $2}')
    if [ ! -z "${snap_nm}" ]
    then
        child_snap=$(rbd children ${_POOL_NAME}/volume-${volume_id}@${snap_nm})
        if [ ! -z "${child_snap}" ]
        then
            rbd flatten ${child_snap} &>/dev/null
            if [ $? -ne 0 ]
            then
                log error "execute rbd flatten ${child_snap} error"
                echo -1
                return
            fi
            rbd snap unprotect ${_POOL_NAME}/volume-${volume_id}@${snap_nm} &>/dev/null
            if [ $? -ne 0 ]
            then
                log error "execute rbd snap unprotect ${_POOL_NAME}/volume-${volume_id}@${snap_nm} error"
                echo -1
                return
            fi
            rbd snap purge ${_POOL_NAME}/volume-${volume_id} &>/dev/null
            if [ $? -ne 0 ]
            then
                log error "execute rbd snap purge ${_POOL_NAME}/volume-${volume_id} error"
                echo -1
                return
            fi
            rbd rm ${_POOL_NAME}/volume-${volume_id} &>/dev/null
            if [ $? -ne 0 ]
            then
                log error "execute rbd rm ${_POOL_NAME}/volume-${volume_id} error"
                echo -1
                return
            fi
        elif [ $? -ne 0 ]
        then
            log error "execute rbd children ${_POOL_NAME}/volume-${volume_id}@${snap_nm} error"
            echo -1
            return
        else
            rbd snap unprotect ${_POOL_NAME}/volume-${volume_id}@${snap_nm} &>/dev/null
            if [ $? -ne 0 ]
            then
                log error "execute rbd snap unprotect ${_POOL_NAME}/volume-${volume_id}@${snap_nm} error"
                echo -1
                return
            fi
            rbd snap purge ${_POOL_NAME}/volume-${volume_id} &>/dev/null
            if [ $? -ne 0 ]
            then
                log error "execute rbd snap purge ${_POOL_NAME}/volume-${volume_id} error"
                echo -1
                return
            fi
            rbd rm ${_POOL_NAME}/volume-${volume_id} &>/dev/null
            if [ $? -ne 0 ]
            then
                log error "remove the pre-create disk which use ide driver error"
                echo -1
                return
            fi
        fi
    elif [ $? -ne 0 ]
    then
        log error "execute rbd snap ls ${_POOL_NAME}/volume-${volume_id} error"
        echo -1
        return
    fi
    rbd rm $_POOL_NAME/volume-$volume_id &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "execute rbd rm $_POOL_NAME/volume-$volume_id error"
        echo -1
        return
    fi
    rbd import $QCOW2_FILE $_POOL_NAME/volume-$volume_id &>/dev/null
    if [ $? -ne 0 ]
    then
        log error "execute rbd import $QCOW2_FILE $_POOL_NAME/volume-$volume_id error"
        echo -1
        return
    fi
    echo 0
}
uc_tmp_vm_replace_system_file $1 $2
