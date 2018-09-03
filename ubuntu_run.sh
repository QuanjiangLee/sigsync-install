#!/bin/bash
set -e

#install_type=0
#recv_ip="127.0.0.1"
#recv_mac="08:00:27:f0:bd:92"
mysqlPasswd="sigsyncDb"
sql_file1="./sigsync/database/sig_file_list.txt"
sql_file2="./sigsync/database/sig_log.txt"

if [ $EUID -ne 0 ]; then
    echo "错误:请在root用户权限下运行!" 1>&2;
    exit 1;
fi

if [ ! -x $0 ]; then
    chmod +x $0
    echo "已为此文件添加可执行权限，请再次运行安装命令！";
    exit 1;
fi

while :;
do
read -r -p "请输入安装类型? [0(发送端输入0) /1(接收端输入1)] " install_type
case $install_type in
    0)
        echo "您选择了发送端安装！"
        break;
;;
    1)
        echo "您选择了接收端安装！"
        break;
;;
    *)
        echo "你选择了其他选项，请重新输入！"
;;
esac
done

while :;
do
read -r -p "请输入需要设置ip的网卡名："   card_name
    echo "$card_name"
read -r -p "请输入要设置的网卡ip："   card_ip
    echo "$card_ip"
read -r -p "请输入要设置的网卡子网掩码(按回车键默认为255.255.255.0)："  card_mask
    echo "$card_mask"
if [ -z $card_name ];then
    echo "需要设置ip的网卡名不能为空，请重新输入！";
elif [ -z $card_ip ];then
    echo "网卡ip不能为空，请重新输入！";
elif [ -z $card_mask ]; then
    card_mask="255.255.255.0"
    break;
else
    break;
fi
done

if [ $install_type -eq 0 ]; then
while :;
do
read -r -p "请输入接收端主机ip："   recv_ip
    echo "$recv_ip"
read -r -p "请输入接收端主机mac地址："  recv_mac
    echo "$recv_mac"
if [ -z $recv_ip ];then
    echo "接收端主机ip不能为空，请重新输入！";
elif [ -z $recv_mac ]; then
    echo "接收端主机MAC不能为空，请重新输入！";
else
    ifconfig $card_name $card_ip netmask $card_mask up
    arp -s $recv_ip $recv_mac >/dev/null
    if [ $? -ne 0 ]; then
        echo "接收端ip和mac地址输入有误，请重新输入！";
    else
        break;
    fi
fi
done
fi

clear
echo "设置本机网卡名:  [$card_name]"
echo "设置本机网卡ip:  [$card_ip]"
echo "设置本机网卡子网掩码:  [$card_mask]"
if [ $install_type -eq 0 ]; then
    echo "您选择的安装类型:  [发送端脚本安装]"
    echo "接收端主机ip:  [$recv_ip]"
    echo "接收端主机mac:  [$recv_mac]"
else
    echo "您选择的安装类型:  [接收端脚本安装]"
fi

read -r -p "您确定要运行安装项目程序吗? [Y/n] " input
case $input in
    [yY][eE][sS]|[yY])
        echo "您选择了YES!"
;;
*)
        echo "你选择了其他选项，安装停止！"
        exit 1;
;;
esac

#apt-get update
echo "安装依赖软件环境..."
apt-get install mariadb-server mariadb-client gcc libmysqlclient-dev inotify-tools -y

echo "设置数据库和生成表..."
#"sigsyncDb" is sigsync project database and "myDatabase" is wana to sync database
databaseSQL="create database if not exists sigsyncDb;create database if not exists myDatabase;";
mysql -u root -h localhost -p$mysqlPasswd -s -e "${databaseSQL}"
if [ $? -ne 0 ]; then
    echo "生成数据库sigsyncDb, myDatabase失败！"
else echo "生成数据库sigsyncDb, myDatabase成功！"
fi

mysql -uroot -p$mysqlPasswd sigsyncDb -e "flush privileges;" >/dev/null 2>error.log &
if [ $? -ne 0 ]; then
    mysqladmin -u root -h localhost password "$mysqlPasswd"
    if [ $? -ne 0 ]; then
        echo "数据库密码设置可能错误,请在error.log中查看错误！"
    else echo "成功设置数据库密码！"
    fi
else echo "您已经设置过数据库密码！"
fi

cmd1="select count(*) from information_schema.tables where table_name='sig_file_list';"
tablecount1=$(mysql -u root -h localhost -p$mysqlPasswd -s -e "${cmd1}");
if [ $tablecount1 -eq 0 ]; then
    sql1=`cat $sql_file1`
    ret1=$(mysql -u root -h localhost -p$mysqlPasswd sigsyncDb -s -e "${sql1}"); >/dev/null 2>error.log &
    if [ $ret1 -eq 0 ]; then
        echo "生成数据表1失败！"
    else echo "生成数据表1成功！"
    fi
fi

cmd2="select count(*) from information_schema.tables where table_name='sig_log';"
tablecount2=$(mysql -u root -h localhost -p$mysqlPasswd -s -e "${cmd2}");
if [ $tablecount2 -eq 0 ]; then
    sql2=`cat $sql_file2`
    ret2=$(mysql -u root -h localhost -p$mysqlPasswd sigsyncDb -s -e "${sql2}"); >/dev/null 2>error.log &
    if [ $ret2 -eq 0 ]; then
        echo "生成数据表2失败！"
    else echo "生成数据表2成功！"
    fi
fi
mysql -uroot -p$mysqlPasswd sigsyncDb -e "flush privileges;"

echo "重新编译源码和设置网卡信息..."
cd ./sigsync 
gcc *.c -o sigsync -pthread  $(mysql_config --cflags --libs) >/dev/null 2>error.log &
cd ../
sysctl -w net.core.netdev_max_backlog=20000
sysctl -w net.ipv4.udp_mem="754848 1006464 1509096"
sysctl -w net.core.rmem_max=67108864

#创建同步目录和迁移源码
mkdir -p /sigsync

if [ ! -d "/opt/sigsync" ]; then
cp -r ./sigsync /opt/
chmod -R 755 /opt/sigsync
fi

echo "安装supervisor..."
apt-get install supervisor -y

if [ $install_type -eq 0 ]; then
    echo "配置发送端..."
    echo "auto $card_name" >> /etc/network/interfaces
    echo "iface $card_name inet static" >> /etc/network/interfaces
    echo "address $card_ip" >> /etc/network/interfaces
    echo "netmask $card_mask" >> /etc/network/interfaces 
    #ifconfig $card_name $card_ip netmask $card_mask up
    arp -s $recv_ip $recv_mac >/dev/null
    echo "#!/bin/bash" > arp.sh
    echo "arp -s $recv_ip $recv_mac" >> arp.sh
    chmod +x ./arp.sh && cp ./arp.sh /etc/init.d/
    update-rc.d arp.sh defaults 99 
    cp ./db_binlog.cnf /etc/mysql/mariadb.conf.d/
    systemctl restart mysql
    cp ./sigsync_send.conf /etc/supervisor/conf.d/
    echo "3 * * * * root /bin/sh /opt/sigsync/publish.sh >> /var/log/sigsync_send.log" >> /etc/crontab
    service cron reload   
else 
    echo "配置接收端..."
    echo "auto $card_name" >> /etc/network/interfaces
    echo "iface $card_name inet static" >> /etc/network/interfaces
    echo "address $card_ip" >> /etc/network/interfaces
    echo "netmask $card_mask" >> /etc/network/interfaces 
    cp ./sigsync_recv.conf /etc/supervisor/conf.d/
    echo "3 * * * * root /bin/sh /opt/sigsync/local.sh >> /var/log/sigsync_recv.log" >> /etc/crontab
    service cron reload 
fi

echo "启动项目进程..."
systemctl restart supervisor
#supervisorctl reread && supervisorctl update
systemctl enable supervisor
echo "success! waiting reboot"
#sleep 5
#reboot
