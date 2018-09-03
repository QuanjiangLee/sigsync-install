#! /bin/bash
#PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
#export PATH

SqlFileSendPath="/sigsync/"
#数据库用户
DBuser="root"

#数据库密码
DBpassword="sigsyncDb"

#数据库名
DBname="myDatabase"

#设置同步文件目录的binlog文件数量
FileNum=2

if [ ! -d $SqlFileSendPath ]; then
mkdir -p $SqlFileSendPath
fi
fileTime=`date +%Y%m%d%H%M%S`
#刷新生成新的binlog日志文件
mysqldump --user=$DBuser --password=$DBpassword $DBname > $SqlFileSendPath$DBname$fileTime.sql

if [ $? -eq 0 ];then
echo "刷新数据库备份成功！"
else
echo "刷新日志失败，请检查错误！"
fi
