#!/usr/bin/env bash
#-*- coding: UTF-8 -*-
###################################################################
#Script Name    : install-centos7.9.sh
#Description    : Install system and environment configuration.
#Create Date    : 2022-11-28
#Author         : huangxl
#Email          : hxl8489@163.com
###################################################################

######################################################################################################
# environment configuration
######################################################################################################
# 版本
DOCKER_VERSION="-${DOCKER_VERSION:-latest}"
DOCKER_VERSION="${DOCKER_VERSION#-latest}"
DOCKER_COMPOSE_VERSION=${DOCKER_COMPOSE_VERSION:-latest}

CURRENT_DIR=$(cd $(dirname $0); pwd)
targetdir="${CURRENT_DIR}/package"
pipdir="${CURRENT_DIR}/pip_whls"
BUILD_DIR="/usr/local/docker"
APP_DIR="/ITAI"

######################################################################################################
# function
######################################################################################################

function script::install_docker() {
    cd ${CURRENT_DIR}
    tar -xzf docker-20.10.0.tgz
    \cp -rf docker/* /usr/bin
    mkdir -p /usr/lib/systemd/system
    cat << EOF > /usr/lib/systemd/system/docker.service
[Unit]

Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target
 
[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP \$MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s
 
[Install]
 
WantedBy=multi-user.target

EOF
    chmod +x /usr/lib/systemd/system/docker.service
 
    systemctl daemon-reload
    systemctl start docker
    systemctl enable docker
    
}

function script::install_dockercompose() {
    cd ${CURRENT_DIR}
    \cp ${CURRENT_DIR}/docker-compose /usr/bin/docker-compose
    chmod +x /usr/bin/docker-compose
}

function script::app_install_by_dockercompose() {
    cd ${CURRENT_DIR}
    mkdir -p ${BUILD_DIR}${APP_DIR}/mysql/sql/data
    cp *.sql ${BUILD_DIR}${APP_DIR}/mysql/sql/data/install.sql
    mkdir -p ${BUILD_DIR}${APP_DIR}/nginx/html
    mkdir -p ${BUILD_DIR}${APP_DIR}/nginx/log
    cp nginx.conf ${BUILD_DIR}${APP_DIR}/nginx/nginx.conf
    cat << EOF > ${BUILD_DIR}${APP_DIR}/mysql/sql/init.sql
    create database \`storeDB\`;
    use storeDB;
    source /docker-entrypoint-initdb.d/data/install.sql;
EOF
    cat << EOF > ${BUILD_DIR}${APP_DIR}/mysql/my.conf
[client]
default-character-set=utf8

[mysql]
default-character-set=utf8

[mysqld]
init_connect='SET collation_connection = utf8_unicode_ci'
init_connect='SET NAMES utf8'
character-set-server=utf8
collation-server=utf8_unicode_ci
skip-character-set-client-handshake
skip-name-resolve
EOF

    cd ${CURRENT_DIR}
    docker_images=(mysql.tar.gz nginx.tar.gz)
    for file in "${docker_images[@]}"; do
        if [ -f $file ]; then
            docker load -i $file
            [ "$?" == "0" ] && log::success "$file 镜像导入执行成功" || log::error "$file 镜像导入执行失败"
        else
            log::error "$file 镜像文件不存在"
        fi
    done
    cat << EOF > ${BUILD_DIR}${APP_DIR}/docker-compose.yml
version: '3.1'
services:
  
  mysql:
    restart: always
    image: "mysql"
    container_name: store_mysql
    ports:
      - "3306:3306"
    command:
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_general_ci
      --explicit_defaults_for_timestamp=true
      --lower_case_table_names=1
      --max_allowed_packet=128M
    volumes:
      - ${BUILD_DIR}${APP_DIR}/mysql/sql/data:/docker-entrypoint-initdb.d/data
      - ${BUILD_DIR}${APP_DIR}/mysql/my.cnf:/etc/mysql/my.cnf
      - ${BUILD_DIR}${APP_DIR}/mysql/sql/init.sql:/docker-entrypoint-initdb.d/init.sql
    environment:
      TZ: Asia/Shanghai
      MYSQL_ROOT_PASSWORD: root
  nginx:
    restart: always
    image: 'nginx'
    container_name: store_nginx
    ports:
      - "80:80"
    volumes:
      - ${BUILD_DIR}${APP_DIR}/nginx/nginx.conf:/etc/nginx/nginx.conf
      - ${BUILD_DIR}${APP_DIR}/nginx/log:/var/log/nginx
      - ${BUILD_DIR}${APP_DIR}/nginx/html:/usr/share/nginx/html
EOF

    cd ${BUILD_DIR}${APP_DIR}
    docker-compose up -d
}

function script::install_centos7() {
    log::exec "执行方法:script::install_docker [安装docker]"
    script::install_docker
    if [ "$?" == "0" ];then
        log::success "执行方法:script::install_docker [安装docker]" 
    else
        log::error "执行方法:script::install_docker [安装docker]"
        exit 101
    fi
    log::exec "执行方法:script::install_dockercompose [安装docker-compose]"
    script::install_dockercompose
    if [ "$?" == "0" ];then
        log::success "执行方法:script::install_dockercompose [安装docker-compose]" 
    else
        log::error "执行方法:script::install_dockercompose [安装docker-compose]"
        exit 102
    fi
    script::app_install_by_dockercompose
    if [ "$?" == "0" ];then
        log::success "执行方法:script::app_install_by_dockercompose [安装docker镜像]" 
    else
        log::error "执行方法:script::install_dockercompose [安装docker镜像]"
        exit 103
    fi
    sleep 10
    cd ${BUILD_DIR}${APP_DIR}
    docker-compose restart
}
function script::remove_centos7() {
    log::exec "执行方法:script::remove_centos7 [删除全部相关docker]"
    cd ${BUILD_DIR}${APP_DIR}
    docker-compose down && rm * -rf
    if [ "$?" == "0" ];then
        log::success "执行方法:script::remove_centos7 [删除全部相关docker]" 
    else
        log::error "执行方法:script::remove_centos7 [删除全部相关docker]"
    fi
}
