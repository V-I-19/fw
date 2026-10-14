#!/bin/bash
hostnamectl set-hostname hq-srv.au-team.irpo

apt-get update && apt-get install -y chrony tzdata

apt-get install sshpass
        
# Настрока часового пояса
timedatectl set-timezone Asia/Krasnoyarsk


systemctl enable --now chronyd
        systemctl restart chronyd

# Установка wget
apt-get update && apt-get install wget
#Настройка ДНС
wget raw.githubusercontent.com/CryEshka/2027/main/dnsmasq.conf
apt-get install -y dnsmasq
systemctl enable --now dnsmasq
rm -rf /etc/dnsmasq.conf
cp -r dnsmasq.conf /etc/
systemctl restart dnsmasq
ping HQ-SRV.au-team.irpo

echo "Настройка SSH"

# Создание пользователя sshuser с UID 2027 (МЕНЯЙТЕ ИМЯ И Т.Д В ЗАВИСИМОСТИ ОТ ЗАДАНИЯ)
useradd -u 2027 -m sshuser

# Установка пароля P@ssw0rd без подтверждения
echo "sshuser:P@ssw0rd" | chpasswd

# Добавление в группу wheel
gpasswd -a sshuser wheel

# Настройка sudo без пароля
echo "sshuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Настройка SSH
sed -i 's/#Port 22/Port 2027/' /etc/openssh/sshd_config
sed -i 's/#PermitRootLogin without-password/PermitRootLogin no/' /etc/openssh/sshd_config
echo "AllowUsers sshuser" >> /etc/openssh/sshd_config
echo "MaxAuthTries 2" >> /etc/openssh/sshd_config
echo "Banner /etc/openssh/banner" >> /etc/openssh/sshd_config

# Создание баннера
echo "Authorized access only" > /etc/openssh/banner

# Перезапуск SSH
systemctl restart sshd

echo "Настройка завершена:"
echo "- Пользователь: sshuser (пароль: P@ssw0rd)"
echo "- SSH порт: 2027"
echo "- Root-логин запрещен"
echo "- Баннер создан"


echo "Настройка RAID"
# Создание RAID 0 
mdadm --create --verbose /dev/md0 -l 0 -n 3 /dev/sd[b-d]

# Сохранение конфигурации
mdadm --detail -scan > /etc/mdadm.conf

# Работа с fdisk (автоматический ввод 'n' и 'w')
echo -e "n\n\n\n\n\nw" | fdisk /dev/md0

# Форматирование раздела
mkfs.ext4 /dev/md0p1

# Создание директории и монтирование
mkdir /raid

# Добавление в fstab
echo "/dev/md0p1 /raid ext4 defaults 0 0" >> /etc/fstab
mount -a

# Установка NFS
apt-get install -y nfs-server
systemctl enable --now nfs

# Настройка NFS
mkdir /raid/nfs
chown -R 99:99 /raid/nfs
chmod 777 /raid/nfs

# Добавление экспорта NFS МЕНЯЙТЕ НА СВОИ СЕТИ
echo "/raid/nfs 192.168.200.0/28(rw,sync,no_subtree_check)" >> /etc/exports

# Перезапуск NFS и создание тестового файла
systemctl restart nfs
touch /raid/nfs/test

echo "Готово! RAID 5 и NFS настроены."


echo "- Настройка RESOLV"
# Файл /etc/resolv.conf
cat > /etc/resolv.conf <<EOF
    nameserver 127.0.0.1
    search au-team.irpo

EOF
chattr +i /etc/resolv.conf

apt-get install -y lamp-server

mount /dev/sr1 /mnt || true

cp /mnt/web/index.php /var/www/html/
cp /mnt/web/logo.png /var/www/html/

sed -i "s/\$username = \"user\";/\$username = \"web1\";/" /var/www/html/index.php
sed -i "s/\$password = \"password\";/\$password = \"P@ssw0rd\";/" /var/www/html/index.php
sed -i "s/\$dbname = \"db\";/\$dbname = \"webdb\";/" /var/www/html/index.php

systemctl enable --now mariadb

mariadb -u root <<EOF
CREATE DATABASE IF NOT EXISTS webdb;
CREATE USER IF NOT EXISTS 'web1'@'localhost' IDENTIFIED BY 'P@ssw0rd';
GRANT ALL PRIVILEGES ON webdb.* TO 'web1'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

mariadb -u web1 -p'P@ssw0rd' webdb < /mnt/web/dump.sql

mariadb -u root <<EOF
USE webdb;
SHOW TABLES;
EOF

systemctl enable --now httpd2

apt-get install atop -y
systemctl enable --now atop
cat <<EOF > /etc/default/atop
LOGOPTS="-R"
LOGINTERVAL=420
LOGGENERATIONS=28
LOGPATH=/var/log/atop
EOF

apt-get install -y cups cups-pdf
systemctl enable --now cups
cupsctl --share-printers --remote-any
systemctl restart cups

apt-get install -y fail2ban python3-module-systemd
sed -i 's/before = paths-altlinux.conf/before = paths-altlinux-systemd.conf/' /etc/fail2ban/jail.conf
sed -i '/^\[sshd\]/a\enabled = true' /etc/fail2ban/jail.conf
sed -i '/^\[sshd\]/,/^\[/{s/^port.*/port    = 2027/}' /etc/fail2ban/jail.conf
sed -i '/^\[sshd\]/,/^\[/s/port.*2027/&\nmaxretry = 3/' /etc/fail2ban/jail.conf
sed -i '/^\[sshd\]/,/^\[/s/maxretry.*3/&\nfindtime = 10m/' /etc/fail2ban/jail.conf
sed -i '/^\[sshd\]/,/^\[/s/findtime.*10m/&\nbantime = 1m/' /etc/fail2ban/jail.conf
systemctl enable --now fail2ban
systemctl restart fail2ban
