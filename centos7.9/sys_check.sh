#!/usr/bin/env bash
#-*- coding: UTF-8 -*-
###################################################################
#Script Name    : sys_check.sh
#Description    : 检查系统参数：更新系统时间,判断ffmpeg是否安装
#Create Date    : 2022-11-28
#Author         : huangxl
#Email          : hxl8489@163.com
###################################################################
CURRENT_DIR=$(cd $(dirname $0); pwd)
######################################################################################################
# function
######################################################################################################
function system:chrony {
	yum install -y chrony
	systemctl start chronyd
	systemctl enable chronyd
	cat << EOF > /etc/chrony.conf
# Use public servers from the pool.ntp.org project.
# Please consider joining the pool (http://www.pool.ntp.org/join.html).
# pool 2.centos.pool.ntp.org iburst
server ntp.aliyun.com iburst
server cn.ntp.org.cn iburst

# Record the rate at which the system clock gains/losses time.
driftfile /var/lib/chrony/drift

# Allow the system clock to be stepped in the first three updates
# if its offset is larger than 1 second.
makestep 1.0 3

# Enable kernel synchronization of the real-time clock (RTC).
rtcsync

# Enable hardware timestamping on all interfaces that support it.
#hwtimestamp *

# Increase the minimum number of selectable sources required to adjust
# the system clock.
#minsources 2

# Allow NTP client access from local network.
#allow 192.168.0.0/16

# Serve time even if not synchronized to a time source.
#local stratum 10

# Specify file containing keys for NTP authentication.
keyfile /etc/chrony.keys

# Get TAI-UTC offset and leap seconds from the system tz database.
leapsectz right/UTC

# Specify directory for log files.
logdir /var/log/chrony

# Select which information is logged.
#log measurements statistics tracking
EOF
systemctl restart chronyd.service
timedatectl set-timezone Asia/Shanghai
date
chronyc sources -v
}

function system:install_ffmpeg() {
	# cd $CURRENT_DIR
	# if [ -f "${CURRENT_DIR}/ffmpeg-release-amd64-static.tar.xz" ];then
	# 	xz -d ffmpeg-release-amd64-static.tar.xz
	# 	tar -xvf ffmpeg-release-amd64-static.tar
	# 	echo "export PATH=\$PATH:/opt/ffmpeg/ffmpeg-release-amd64-static" >> /etc/profile
	# 	source /etc/profile
	# fi
	yum install -y epel-release rpm
    rpm --import http://li.nux.ro/download/nux/RPM-GPG-KEY-nux.ro
    rpm -Uvh http://li.nux.ro/download/nux/dextop/el7/x86_64/nux-dextop-release-0-1.el7.nux.noarch.rpm
    yum repolist
	yum install -y ffmpeg
}

function script::update_yum() {
    cd /etc/yum.repos.d/
    if [ ! -d "repo_bak" ];then
        mkdir repo_bak
        mv *.repo ./repo_bak
        log::notice "script::update_yum [wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo]"
        wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
        if [ "$?" == "0" ];then
            log::notice "script::update_yum [yum makecache]"
            yum makecache
        fi
    else
        log::notice "script::update_yum: 源备份文件夹已存在，无需更新源"
    fi
}

function script::sys_check() {
	script::update_yum
	chronyc sources -v
	if [ "$?" == "0" ];then
		log::success "执行方法:script::sys_check [chrony已经安装]"
	else
		log::exec "执行方法:script::sys_check [更新时间: system:chrony]"
		system:chrony
		if [ "$?" == "0" ];then
			log::success "执行方法:cript::sys_check [更新时间: system:chrony]"
		else
			log::error "执行方法:cript::sys_check [更新时间: system:chrony]"
			exit 301
		fi
	fi
	ffmpeg -version
	if [ "$?" == "0" ];then
		log::success "执行方法:script::sys_check [ffmpeg已经安装]"
	else
		log::exec "执行方法:script::sys_check [安装ffmpeg: system:install_ffmpeg]"
		system:install_ffmpeg
		if [ "$?" == "0" ];then
			log::success "执行方法:cript::sys_check [更新时间: system:install_ffmpeg]"
		else
			log::error "执行方法:cript::sys_check [更新时间: system:install_ffmpeg]"
			exit 302
		fi
	fi
}
