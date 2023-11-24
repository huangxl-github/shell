#!/usr/bin/env bash
#-*- coding: UTF-8 -*-
###################################################################
#Script Name    : main.sh
#Description    : Install [] system and environment configuration.
#Create Date    : 2023-03-13
#Author         : huangxl
#Email          : hxl8489@163.com
###################################################################

[[ -n $DEBUG ]] && set -x
set -o errtrace         # Make sure any error trap is inherited
set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline

######################################################################################################
# environment configuration
######################################################################################################
# 系统名称
SYS_NAME="视频管理系统"
# 版本
VERSION="v1.0"
# IP
ENV_IP="192.168.100.200"
# 数据库
DB_ADDR=""
DB_PORT=""
DB_NAME=""
DB_USER=""
DB_PASS=""

######################################################################################################
# source shell
######################################################################################################
SHELL_LOG=0
SHELL_MON=0
SHELL_CHE=0
SHELL_INS=0
#加载日志脚本
source log.sh
[ "$?" == "0" ] && log::success "加载 log.sh 成功" || (log::error "加载 log.sh 失败";SHELL_LOG=1)
[ -f ${LOG_FILE} ] && log::success "日志生成成功：${LOG_FILE}" || log::error "日志生成失败：${LOG_FILE} 不存在"
#加载系统监控脚本
log::exec "加载脚本: sys_monitor.sh"
source sys_monitor.sh
[ "$?" == "0" ] && log::success "加载 sys_monitor.sh 成功" || (log::error "加载 sys_monitor.sh 失败";SHELL_MON=1)
#加载环境检查脚本
log::exec "加载脚本: sys_check.sh"
source sys_check.sh
[ "$?" == "0" ] && log::success "加载 sys_check.sh 成功" || (log::error "加载 sys_check.sh 失败";SHELL_CHE=1)
#加载一键安装脚本
log::exec "加载脚本: install_centos7.9.sh"
source install_centos7.sh
[ "$?" == "0" ] && log::success "加载 install_centos7.sh 成功" || (log::error "加载 install_centos7.sh 失败";SHELL_INS=1)

######################################################################################################
# function
######################################################################################################

function help::usage {
  # 使用帮助

log::info "******************************************************************"
log::info "*** 使用一键安装脚本部署${SYS_NAME}系统"
log::info "******************************************************************"
log::info "*** 1:一键安装 `[ "$SHELL_INS" == "1" ] && echo "(不可用)"`"
log::info "*** 2:系统监控 `[ "$SHELL_MON" == "1" ] && echo "(不可用)"`"
log::info "*** 3:环境检查 `[ "$SHELL_CHE" == "1" ] && echo "(不可用)"`"
log::info "*** 4:删除服务 `[ "$SHELL_INS" == "1" ] && echo "(不可用)"`"
log::info "*** 5:重构服务 `[ "$SHELL_INS" == "1" ] && echo "(不可用)"`"
log::info "******************************************************************"
log::info "*** 0:退出脚本 "
log::info "******************************************************************"
log::read "请选择您想执行的操作：";read op
case ${op} in 
	1) log::exec "您选择了 1:一键安装"
	log::read "请输入当前设备IP：";read read_ip
	if [ ${read_ip} != '' ];then
		ENV_IP=${read_ip}
	fi
	log::success "当前执行设备IP：${ENV_IP}"
	script::install_centos7
	help::usage
	;;
	2) log::exec "您选择了 2:系统监控"
	script::history_monitor
	help::usage
	;;
	3) log::exec "您选择了 3:环境检查"
	script::sys_check
	help::usage
	;;
	4) log::exec "您选择了 4:删除服务"
	script::remove_centos7
	help::usage
	;;
	5) log::exec "您选择了 5:重构服务"
	log::read "请输入当前设备IP：";read read_ip
	if [ ${read_ip} != '' ];then
		ENV_IP=${read_ip}
	fi
	log::success "当前执行设备IP：${ENV_IP}"
	script::remove_centos7
	script::app_install_by_dockercompose
	help::usage
	;;
	0) log::exec "您选择了 0:退出脚本"
	log::success "退出,欢迎再次使用。"
	exit 0
	;;
	*) log::error "您没有选择范围内的操作"
	help::usage
	;;
esac
}

######################################################################################################
# main
######################################################################################################

[ "$#" == "0" ] && help::usage
