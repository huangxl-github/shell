#!/usr/bin/env bash
# 脚本设置
TMP_DIR="$(rm -rf /tmp/install_log* && mktemp -d -t install_log.XXXXXXXXXX)"
LOG_FILE="${TMP_DIR}/install.log"

LOG_ERROR="\033[31m[错误]\033[0m"
LOG_SUCCESS="\033[32m[成功]\033[0m"
LOG_WARNING="\033[33m[告警]\033[0m"
LOG_NOTICE="\033[33m[提示]\033[0m"
LOG_READ="\033[33m[输入]\033[0m"
LOG_INFO="\033[34m[信息]\033[0m"
LOG_EXEC="\033[35m[执行]\033[0m"
LOG_ACCESS="\033[36m[访问]\033[0m"

######################################################################################################
# log
######################################################################################################
function log::error() {
  # 错误日志
  printf "$LOG_ERROR[$(date +'%Y-%m-%d %H:%M:%S')] \033[31m%s\033[0m \n" "$*" | tee -a "$LOG_FILE"
}
function log::success() {
  # 成功日志
  printf "$LOG_SUCCESS[$(date +'%Y-%m-%d %H:%M:%S')] \033[32m%s\033[0m \n" "$*" | tee -a "$LOG_FILE"
}
function log::warning() {
  # 警告日志
  printf "$LOG_WARNING[$(date +'%Y-%m-%d %H:%M:%S')] \033[33m%s\033[0m \n" "$*" | tee -a "$LOG_FILE"
}
function log::info() {
  # 信息日志
  printf "$LOG_INFO[$(date +'%Y-%m-%d %H:%M:%S')] \033[34m%s\033[0m \n" "$*" | tee -a "$LOG_FILE"
}
function log::exec() {
  # 执行日志
  printf "$LOG_EXEC[$(date +'%Y-%m-%d %H:%M:%S')] \033[35m%s\033[0m \n" "$*" | tee -a "$LOG_FILE"
}
function log::access() {
  # 访问日志
  printf "$LOG_ACCESS[$(date +'%Y-%m-%d %H:%M:%S')] \033[36m%s\033[0m \n" "$*" | tee -a "$LOG_FILE"
}
function log::notice() {
  # 提示日志
  printf "$LOG_NOTICE[$(date +'%Y-%m-%d %H:%M:%S')] \033[33m%s\033[0m \n" "$*" | tee -a "$LOG_FILE"
}
function log::read() {
  # 提示日志
  printf "$LOG_READ[$(date +'%Y-%m-%d %H:%M:%S')] \033[38m%s\033[0m" "$*" | tee -a "$LOG_FILE"
}




# log::error "错误日志"
# log::succee "成功日志"
# log::warning "警告日志"
# log::access "访问日志"
# log::exec "执行日志"
# log::info "信息日志"
