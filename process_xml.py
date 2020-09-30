#!/usr/bin/env python
# -*- coding:utf-8 -*-

import sys
import os
import re
import getopt
import random
from xml.dom.minidom import parse

class Update_VM_Xml():
    def __init__(self , xml_file_path):
        self.xml_file_path = xml_file_path
        self.domTree = ""

    def genarate_mac(self):
        Maclist = ["54"]
        for i in range(1,6):
            RANDSTR = "".join(random.sample("0123456789abcdef",2))
            Maclist.append(RANDSTR)
        RANDMAC = ":".join(Maclist)
        print(RANDMAC)
        return RANDMAC
    
    def handle_xml(self):
        domTree = parse(self.xml_file_path)
        self.domTree = domTree
        #return domTree

    def update_name(self , new_name):
        #domTree = self.handle_xml()
        self.handle_xml()
        rootNode = self.domTree.documentElement
        print (rootNode.nodeName)
        name = rootNode.getElementsByTagName("name")
        name = name[0]
        print(name.firstChild.data)
        name.firstChild.data = new_name
        self.xml_write_in()

    def update_arch(self , arch):
        #domTree = self.handle_xml()
        self.handle_xml()
        rootNode = self.domTree.documentElement
        print (rootNode.nodeName)
        vos = rootNode.getElementsByTagName("os")
        vos = vos[0]
        type_arch = vos.getElementsByTagName("type")
        type_arch = type_arch[0]
        print(type_arch.getAttribute("arch"))
        if type_arch and type_arch.getAttribute("arch") != "":
            #sfile = source.getAttribute("file")
            print(type_arch.getAttribute("arch"))
            type_arch.setAttribute("arch" , arch)
            self.xml_write_in()

    def update_storage(self , storageFile):
        #domTree = self.handle_xml()
        self.handle_xml()
        rootNode = self.domTree.documentElement
        print (rootNode.nodeName)
        disks = rootNode.getElementsByTagName("disk")
        for disk in disks:
            target = disk.getElementsByTagName("target")
            target = target[0]
            if re.match(".da" , target.getAttribute("dev")):
                print(target.getAttribute("dev"))
                source = disk.getElementsByTagName("source")
                source = source[0]
                if source and source.getAttribute("file") != "":
                    #sfile = source.getAttribute("file")
                    print(source.getAttribute("file"))
                    source.setAttribute("file" , storageFile)
                    self.xml_write_in()

    def update_data(self , data_file):
        #domTree = self.handle_xml()
        print("data_file is %s" %(data_file))
        self.handle_xml()
        rootNode = self.domTree.documentElement
        print (rootNode.nodeName)
        disks = rootNode.getElementsByTagName("disk")
        for disk in disks:
            target = disk.getElementsByTagName("target")
            target = target[0]
            if re.match(".db" , target.getAttribute("dev")):
                print(target.getAttribute("dev"))
                source = disk.getElementsByTagName("source")
                source = source[0]
                if source and source.getAttribute("file") != "":
                    #sfile = source.getAttribute("file")
                    print(source.getAttribute("file"))
                    source.setAttribute("file" , data_file)
                    self.xml_write_in()

    def update_mac(self):
        #domTree = self.handle_xml()
        self.handle_xml()
        rootNode = self.domTree.documentElement
        print (rootNode.nodeName)
        interfaces = rootNode.getElementsByTagName("interface")
        for interface in interfaces:
            if "bridge" == interface.getAttribute("type"):
                mac = interface.getElementsByTagName("mac")
                mac = mac[0]
                if mac.getAttribute("address") != "":
                    #print(mac.getAttribute("address"))
                    temp_mac_addr = self.genarate_mac()
                    if temp_mac_addr != "":
                        mac.setAttribute("address" , temp_mac_addr)
                        self.xml_write_in()

    def xml_write_in(self):
        with open(self.xml_file_path , 'w') as f:
            self.domTree.writexml(f , encoding='utf-8')

def parse_param():
    global vm_xml
    global vm_storage
    global vm_name
    global vm_arch
    global temp_data
    temp_data = ""
    opts , args = getopt.getopt(sys.argv[1:],"f:s:n:a:d:","['vm_xml','vm_storage','vm_name','vm_arch','temp_data']")
    for op , value in opts:
        if op in ("-f" , "--vm_xml"):
            vm_xml = value
            print(vm_xml)
        elif op in ("-s" , "--vm_storage"):
            vm_storage = value
            print(vm_storage)
        elif op in ("-n" , "--vm_name"):
            vm_name = value
            print(vm_name)
        elif op in ("-a" , "--vm_arch"):
            vm_arch = value
            print(vm_arch)
        elif op in ("-d" , "--temp_data"):
            temp_data = value
            print(temp_data)
    
if __name__ == "__main__" :
    parse_param()
    up_handle = Update_VM_Xml(vm_xml)
    up_handle.update_storage(vm_storage)
    up_handle.update_name(vm_name)
    up_handle.update_mac()
    up_handle.update_arch(vm_arch)
    if temp_data != "":
        up_handle.update_data(temp_data)
