#!/bin/bash

#### Update Repositories ####

apt-get -y update
apt-get -y upgrade


#### Variables ####

MYSQL_USER="admin"
MYSQL_PASS="dashboardpass"
GITHUB_SOURCE="master"
GITHUB_BASE_URL="https://raw.githubusercontent.com/Ferks-FK/ControlPanel.gg-Installer/$GITHUB_SOURCE"
PHP_SOCKET="/run/php/php8.0-fpm.sock"
NGINX="/etc/nginx"
FQDN=""

ask_informations() {
echo
echo
echo "*****************************"
echo "* Enter all data correctly. *"
echo "*****************************"
echo
echo
echo -n "* Username (admin): "
read -r MYSQL_USER_INPUT
[ -z "$MYSQL_USER_INPUT" ] && MYSQL_USER="admin" || MYSQL_USER=$MYSQL_USER_INPUT

echo -n "* Password (dashboardpass): "
read -r MYSQL_PASS_INPUT
[ -z "$MYSQL_PASS_INPUT" ] && MYSQL_PASS="dashboardpass" || MYSQL_PASS=$MYSQL_PASS_INPUT
while [ -z "$FQDN" ]; do
    echo -n "* Set the FQDN of this panel (panel.example.com): "
    read -r FQDN
    [ -z "$FQDN" ] && echo "FQDN cannot be empty"
done
echo
echo
}


#### Enable Firewall ####

enable_ufw() {
apt-get -y install ufw

echo -e "\n* Enabling Uncomplicated Firewall (UFW)"
echo "* Opening port 80 (HTTP), 443 (HTTPS) and 3306 (MYSQL)"

ufw allow http >/dev/null
ufw allow https >/dev/null
ufw allow mysql >/dev/null

ufw --force enable
ufw --force reload
ufw status numbered | sed '/v6/d'
echo
echo "***************************************************"
echo "* Firewall installed and configured successfully! *"
echo "***************************************************"
echo
}

#### Ask Firewall ####

ask_firewall() {
echo -n "* Do you want to automatically configure UFW (firewall)? (y/N): "
read -r CONFIRM_UFW

if [[ "$CONFIRM_UFW" =~ [Yy] ]]; then
#### Exec Enable Ufw ####
enable_ufw
else
echo 
echo "**********************************************************************"
echo "* You chose not to configure the Firewall, proceed at your own risk! *"
echo "**********************************************************************"
echo
#### Exec Not Ufw ####
ask_not_ufw
fi
}

#### Continue without UFW? ####

ask_not_ufw() {
echo -n "* Continue without configuring UFW? (y/N): "
read -r NOT_UFW

if [[ "$NOT_UFW" =~ [Yy] ]]; then
echo
echo "* Proceeding with the installation..."
echo
else
echo "Installation aborted!"
exit 1
fi
}

#### Exec Ask Informations ####
ask_informations


#### Exec Ask Firewall ####
ask_firewall
 

#### Review of settings ####

summary() {
echo "******************************"
echo "* FQDN: $FQDN"
echo "* Username: $MYSQL_USER"
echo "* Password: $MYSQL_PASS"
echo "******************************"
}

#### Exec summary ####
summary


#### Detect existing installation ####

continue_install() {
DEI=/var/www/dashboard

if [ -d "$DEI" ]; then
echo
echo "*******************************************************************"
echo "* There is already a panel installation on your system, aborting! *"
echo "*******************************************************************"
exit 1
else
echo
echo "**********************************************************************"
echo "* No existing installation detected, proceeding with installation... *"
echo "**********************************************************************"
echo
#### Install Dependencies ####
install_dependencies() {
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
add-apt-repository -y ppa:chris-lea/redis-server
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
apt-get -y update && apt-get -y upgrade
apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
apt-get -y install php8.0-intl
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
}
fi
}

#### Exec Installation ####

echo -e -n "\n* Initial configuration completed. Continue with installation? (y/N): "
read -r CONFIRM
if [[ "$CONFIRM" =~ [Yy] ]]; then
    #### Continue Install ####
    continue_install
  else
    echo "Installation aborted!"
    exit 1
fi

#### Exec Install_Dependencies ####
install_dependencies

#### Download Files ####

download_files() {
mkdir -p /var/www/dashboard
cd /var/www/dashboard || exit
git clone https://github.com/ControlPanel-gg/dashboard.git ./
chmod -R 755 storage/* bootstrap/cache/
}

#### Exec Download_Files ####
download_files

#### Installation ####

installation() {
rm -R .env.example
curl -o example.env $GITHUB_BASE_URL/configs/example.env
cp example.env .env
rm -R example.env
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
php artisan storage:link
}

#### Exec Installation ####
installation

#### Database ####

setup_database() {
echo "* Creating user..."
mysql -u root -e "CREATE USER '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASS}';"

echo "* Creating database..."
mysql -u root -e "CREATE DATABASE dashboard;"

echo "* Grant privileges..."
mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER}'@'127.0.0.1' WITH GRANT OPTION;"

echo "* Flush privileges..."
mysql -u root -e "FLUSH PRIVILEGES;"

#### Restart MySQL Service ####

echo "* Restarting MySQL..."
systemctl restart mysql

echo "* MySQL user created and configured successfully!"
echo
echo "**************************************************"
}

#### Exec Database Setup ####
setup_database

#### Run command after database creation ####
php artisan key:generate --force
#### Other general commands ####
cd || exit
sed -i -e "s@dashboarduser@${MYSQL_USER}@g" /var/www/dashboard/.env
sed -i -e "s@mysecretpassword@${MYSQL_PASS}@g" /var/www/dashboard/.env
cd /var/www/dashboard || exit
php artisan migrate --seed --force
php artisan db:seed --class=ExampleItemsSeeder --force
#### Set Permissions ####
cd || exit
chown -R www-data:www-data /var/www/dashboard/*
#### Create Queue Worker ####
cd /etc/systemd/system || exit
curl -o /etc/systemd/system/dashboard.service $GITHUB_BASE_URL/configs/dashboard.service
systemctl enable dashboard.service
systemctl start dashboard.service

#### Config Cronjob ####

insert_cronjob() {
  echo "* Installing cronjob.. "

  crontab -l | {
    cat
    echo "* * * * * php /var/www/dashboard/artisan schedule:run >> /dev/null 2>&1"
  } | crontab -

  echo "* Cronjob installed!"
}

#### Exec Cronjob ####
insert_cronjob


nginx_configs() {
if [ -d "$NGINX" ]; then
systemctl stop nginx

rm -rf /etc/nginx/sites-enabled/default

curl -o /etc/nginx/sites-available/dashboard.conf $GITHUB_BASE_URL/configs/dashboard.conf

sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-available/dashboard.conf

sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" /etc/nginx/sites-available/dashboard.conf

ln -sf /etc/nginx/sites-available/dashboard.conf /etc/nginx/sites-enabled/dashboard.conf

systemctl start nginx
else
exit 1
fi
}

#### Exec Nginx Configs ####
nginx_configs


#### Create First User ####

create_user() {
echo
echo "*********************************"
echo "* Let's create your login user. *"
echo "*********************************"
echo
echo "************************************************************"
echo "* You will need the pterodactyl panel user ID to continue. *"
echo "************************************************************"
echo
echo "******************************************************************"
echo "* You can find this information in the users tab of your pterodactyl panel [/admin/users]"
echo "******************************************************************"
echo
cd /var/www/dashboard || exit
php artisan make:user
}

#### Enable All Services ####

systemctl enable nginx
systemctl enable mariadb

#### Start All Services ####

systemctl start nginx
systemctl start mariadb


#### Exec Create User ####
create_user
