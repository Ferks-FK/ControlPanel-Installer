#!/bin/bash


#### Variables ####

MYSQL_USER="admin"
MYSQL_PASS="dashboardpass"
GITHUB_SOURCE="master"
GITHUB_BASE_URL="https://raw.githubusercontent.com/Ferks-FK/ControlPanel.gg-Installer/$GITHUB_SOURCE"
NGINX="/etc/nginx"
FQDN=""
EMAIL=""
CONFIGURE_UFW=false
CONFIGURE_FIREWALL_CMD=false
CONFIGURE_FIREWALL=false
ASSUME_SSL=false
CONFIGURE_LETSENCRYPT=false



#### Detect existing installation ####

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
fi

#### OS check ####

check_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$(echo "$ID")
    OS_VER=$VERSION_ID
  elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si)
    OS_VER=$(lsb_release -sr)
  elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$(echo "$DISTRIB_ID")
    OS_VER=$DISTRIB_RELEASE
  elif [ -f /etc/debian_version ]; then
    OS="debian"
    OS_VER=$(cat /etc/debian_version)
  elif [ -f /etc/SuSe-release ]; then
    OS="SuSE"
    OS_VER="?"
  elif [ -f /etc/redhat-release ]; then
    OS="Red Hat/CentOS"
    OS_VER="?"
  else
    OS=$(uname -s)
    OS_VER=$(uname -r)
  fi

  OS=$(echo "$OS")
  OS_VER_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
}

#### Exec Check Distro ####
check_distro

check_os_comp() {
  CPU_ARCHITECTURE=$(uname -m)
  if [ "${CPU_ARCHITECTURE}" != "x86_64" ]; then # check the architecture
    echo "Detected CPU architecture $CPU_ARCHITECTURE"
    echo "Using any other architecture than 64 bit (x86_64) will cause problems."

    echo -e -n "* Are you sure you want to proceed? (y/N):"
    read -r choice

    if [[ ! "$choice" =~ [Yy] ]]; then
      echo "Installation aborted!"
      exit 1
    fi
  fi

  case "$OS" in
  ubuntu)
    PHP_SOCKET="/run/php/php8.0-fpm.sock"
    [ "$OS_VER_MAJOR" == "18" ] && SUPPORTED=true
    [ "$OS_VER_MAJOR" == "20" ] && SUPPORTED=true
    ;;
  debian)
    PHP_SOCKET="/run/php/php8.0-fpm.sock"
    [ "$OS_VER_MAJOR" == "9" ] && SUPPORTED=true
    [ "$OS_VER_MAJOR" == "10" ] && SUPPORTED=true
    ;;
  centos)
    PHP_SOCKET="/var/run/php-fpm/dashboard.sock"
    [ "$OS_VER_MAJOR" == "7" ] && SUPPORTED=true
    [ "$OS_VER_MAJOR" == "8" ] && SUPPORTED=true
    ;;
  *)
    SUPPORTED=false
    ;;
  esac

  # exit if not supported
  if [ "$SUPPORTED" == true ]; then
	echo
	echo "*****************************"
    	echo "* $OS $OS_VER is supported. *"
	echo "*****************************"
	echo
  else
    echo "* $OS $OS_VER is not supported!"
	echo
	echo "*****************************"
    	echo "* Unsupported OS, aborting! *"
	echo "*****************************"
	echo
    exit 1
  fi
}

#### Exec Check OS Comp ####
check_os_comp


#### Update Repositories ####
case "$OS" in
debian | ubuntu)
apt-get -y update
apt-get -y upgrade
;;

centos)
[ "$OS_VER_MAJOR" == "7" ] && yum -y update && yum -y upgrade
[ "$OS_VER_MAJOR" == "8" ] && dnf -y update && dnf -y upgrade
;;
esac


print_warning() {
  COLOR_YELLOW='\033[1;33m'
  COLOR_NC='\033[0m'
  echo ""
  echo -e "* ${COLOR_YELLOW}WARNING${COLOR_NC}: $1"
  echo ""
}

print_error() {
  COLOR_RED='\033[0;31m'
  COLOR_NC='\033[0m'

  echo ""
  echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: $1"
  echo ""
}

regex="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"

valid_email() {
  [[ $1 =~ ${regex} ]]
}

email_input() {
  local __resultvar=$1
  local result=''

  while ! valid_email "$result"; do
    echo -n "* ${2}"
    read -r result

    valid_email "$result" || print_error "${3}"
  done

  eval "$__resultvar="'$result'""
}

#### Main information ####

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
email_input EMAIL "Provide the email address that will be used to configure Let's Encrypt: " "Email cannot be empty or invalid"
}

#### Exec Ask Informations ####
ask_informations


#### Not Ufw ####

not_ufw() {
echo
echo
echo "**********************************************************************"
echo "* You chose not to configure the Firewall, proceed at your own risk! *"
echo "**********************************************************************"
echo
echo
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

#### Ask Firewall ####

ask_firewall() {
case "$OS" in
ubuntu | debian)
echo -n "* Do you want to automatically configure UFW (firewall)? (y/N): "
read -r CONFIRM_UFW

if [[ "$CONFIRM_UFW" =~ [Yy] ]]; then
CONFIGURE_UFW=true
CONFIGURE_FIREWALL=true
elif [[ "$CONFIRM_UFW" == [Nn] ]]; then
# Exec Not Ufw #
not_ufw
fi
;;
centos)
echo -e -n "* Do you want to automatically configure firewall-cmd (firewall)? (y/N): "
read -r CONFIRM_FIREWALL_CMD

if [[ "$CONFIRM_FIREWALL_CMD" =~ [Yy] ]]; then
CONFIGURE_FIREWALL_CMD=true
CONFIGURE_FIREWALL=true
fi
;;
esac
}

#### Exec Ask Firewall ####
ask_firewall


#### Ask Letsencrypt ####

ask_letsencrypt() {
if [ "$CONFIGURE_UFW" == false ] && [ "$CONFIGURE_FIREWALL_CMD" == false ]; then
  print_warning "Let's Encrypt requires port 80/443 to be opened! You have opted out of the automatic firewall configuration; use this at your own risk (if port 80/443 is closed, the script will fail)!"
fi

print_warning "You cannot use Let's Encrypt with your hostname as an IP address! It must be a FQDN (e.g. panel.example.org)."

echo -e -n "* Do you want to automatically configure HTTPS using Let's Encrypt? (y/N): "
read -r CONFIRM_SSL

if [[ "$CONFIRM_SSL" =~ [Yy] ]]; then
  CONFIGURE_LETSENCRYPT=true
  ASSUME_SSL=false
fi
}

#### Exec Ask Letsencrypt ####
ask_letsencrypt


#### SSL Question ####

ask_assume_ssl() {
echo
echo
echo "* Let's Encrypt is not going to be automatically configured by this script (user opted out)."
echo
echo "* You can 'assume' Let's Encrypt, which means the script will download a nginx configuration that is configured to use a Let's Encrypt certificate but the script won't obtain the certificate for you."
echo
echo "* If you assume SSL and do not obtain the certificate, your installation will not work."
echo
echo -n "* Assume SSL or not? (y/N): "
read -r ASSUME_SSL_INPUT
echo
echo

[[ "$ASSUME_SSL_INPUT" =~ [Yy] ]] && ASSUME_SSL=true
true
}

#### Exec SSL Question ####
ask_assume_ssl


ufw_ubuntu_debian() {
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


ufw_centos() {
[ "$OS_VER_MAJOR" == "7" ] && yum -y -q install firewalld >/dev/null
[ "$OS_VER_MAJOR" == "8" ] && dnf -y -q install firewalld >/dev/null

systemctl --now enable firewalld >/dev/null

echo -e "\n* Enabling Firewall..."
echo "* Opening port 80 (HTTP), 443 (HTTPS) and 3306 (MYSQL)"
firewall-cmd --add-service=http --permanent -q
firewall-cmd --add-service=https --permanent -q
firewall-cmd --add-service=mysql --permanent -q
firewall-cmd --reload -q
echo
echo "*************************************"
echo "* Firewall configured successfully! *"
echo "*************************************"
echo
}


#### Review of settings ####

summary() {
echo
echo
echo "****************************************"
echo "* FQDN: $FQDN"
echo "* Username: $MYSQL_USER"
echo "* Password: $MYSQL_PASS"
echo "* Email: $EMAIL"
echo "* Configure UFW: $CONFIGURE_UFW"
echo "* Configure Let's Encrypt: $CONFIGURE_LETSENCRYPT"
echo "* Assume SSL: $ASSUME_SSL"
echo "****************************************"
echo
echo
}

#### Exec summary ####
summary


apt_update() {
apt-get -y update && apt-get -y upgrade
}

yum_update() {
yum -y update
}

dnf_update() {
dnf -y upgrade
}


services_centos() {
systemctl enable mariadb
systemctl enable nginx
systemctl enable redis
systemctl start mariadb
systemctl start redis
}


#### Install Dependencies for Ubuntu 20 ####

ubuntu20_dep() {
echo
echo "*******************************************"
echo "* Installing dependencies for Ubuntu 20.. *"
echo "*******************************************"
echo
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
add-apt-repository -y ppa:chris-lea/redis-server
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
apt-get -y update && apt-get -y upgrade
apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
apt-get -y install php8.0-intl
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
}

#### Install Dependencies for Ubuntu 18 ####

ubuntu18_dep() {
echo
echo "*******************************************"
echo "* Installing dependencies for Ubuntu 18.. *"
echo "*******************************************"
echo
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
add-apt-repository -y ppa:chris-lea/redis-server
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
apt-get -y update && apt-get -y upgrade
apt-add-repository universe
apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
apt-get -y install php8.0-intl
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
}

#### Install Dependencies for Debian 9 ####

debian9_dep() {
echo
echo "******************************************"
echo "* Installing dependencies for Debian 9.. *"
echo "******************************************"
echo
apt-get -y install dirmngr
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release -y
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
apt-get -y update && apt-get -y upgrade
apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
apt-get -y install php8.0-intl
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
}

#### Install Dependencies for Debian 10 ####

debian10_dep() {
echo
echo "*******************************************"
echo "* Installing dependencies for Debian 10.. *"
echo "*******************************************"
echo
apt-get -y install dirmngr
apt-get -y install software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
apt-get -y update && apt-get -y upgrade
apt-get -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
apt-get -y install php8.0-intl
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
}

#### Install Dependencies for Debian 11 ####

debian11_dep() {
echo
echo "*******************************************"
echo "* Installing dependencies for Debian 11.. *"
echo "*******************************************"
echo
apt-get -y install dirmngr
apt-get -y install ca-certificates apt-transport-https lsb-release
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
apt_update
apt-get -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx curl tar unzip git redis-server cron
apt-get -y install php8.0-intl
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
}

#### Install Dependencies for CentOS 7 ####

centos7_dep() {
echo
echo "******************************************"
echo "* Installing dependencies for CentOS 7.. *"
echo "******************************************"
echo
yum update -y
yum install -y policycoreutils policycoreutils-python selinux-policy selinux-policy-targeted libselinux-utils setroubleshoot-server setools setools-console mcstrans
yum install -y epel-release http://rpms.remirepo.net/enterprise/remi-release-7.rpm
yum install -y yum-utils
yum-config-manager -y --disable remi-php54
yum-config-manager -y --enable remi-php80
yum_update
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
yum -y install php php-common php-tokenizer php-curl php-fpm php-cli php-json php-mysqlnd php-mcrypt php-gd php-mbstring php-pdo php-zip php-bcmath php-dom php-opcache mariadb-server nginx curl tar zip unzip git redis
yum --enablerepo=remi install -y php-intl
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
services_centos
setsebool -P httpd_can_network_connect 1 || true
setsebool -P httpd_execmem 1 || true
setsebool -P httpd_unified 1 || true
}

#### Install Dependencies for CentOS 8 ####

centos8_dep() {
echo
echo "******************************************"
echo "* Installing dependencies for CentOS 8.. *"
echo "******************************************"
echo
dnf install -y policycoreutils selinux-policy selinux-policy-targeted setroubleshoot-server setools setools-console mcstrans
dnf install -y epel-release http://rpms.remirepo.net/enterprise/remi-release-8.rpm
dnf module enable -y php:remi-8.0
dnf_update
dnf install -y php php-common php-fpm php-cli php-json php-mysqlnd php-gd php-mbstring php-pdo php-zip php-bcmath php-dom php-opcache php-intl
dnf install -y mariadb mariadb-server
dnf install -y nginx curl tar zip unzip git redis
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
services_centos
setsebool -P httpd_can_network_connect 1 || true
setsebool -P httpd_execmem 1 || true
setsebool -P httpd_unified 1 || true
}

centos_php() {
curl -o /etc/php-fpm.d/www-dashboard.conf $GITHUB_BASE_URL/configs/www-dashboard.conf

systemctl enable php-fpm
systemctl start php-fpm
}

#### Download Files ####

download_files() {
mkdir -p /var/www/dashboard
cd /var/www/dashboard || exit
git clone https://github.com/ControlPanel-gg/dashboard.git ./
chmod -R 755 storage/* bootstrap/cache/
# Installation #
rm -R .env.example
curl -o example.env $GITHUB_BASE_URL/configs/example.env
cp example.env .env
rm -R example.env
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
php artisan storage:link
}

#### Database ####

setup_database() {
if [ "$OS" == "centos" ] && [ "$OS_VER_MAJOR" == "7" ]; then
echo "* MariaDB secure installation. The following are safe defaults."
echo "* Set root password? [Y/n] Y"
echo "* Remove anonymous users? [Y/n] Y"
echo "* Disallow root login remotely? [Y/n] Y"
echo "* Remove test database and access to it? [Y/n] Y"
echo "* Reload privilege tables now? [Y/n] Y"
echo "*"

mariadb-secure-installation

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

echo "***************************************************"
echo "* MySQL user created and configured successfully! *"
echo "***************************************************"
fi
if [ "$OS" == "centos" ] && [ "$OS_VER_MAJOR" == "8" ]; then
echo "* MariaDB secure installation. The following are safe defaults."
echo "* Set root password? [Y/n] Y"
echo "* Remove anonymous users? [Y/n] Y"
echo "* Disallow root login remotely? [Y/n] Y"
echo "* Remove test database and access to it? [Y/n] Y"
echo "* Reload privilege tables now? [Y/n] Y"
echo "*"

mysql_secure_installation

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

echo "***************************************************"
echo "* MySQL user created and configured successfully! *"
echo "***************************************************"
fi
case "$OS" in
debian | ubuntu)

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

echo "***************************************************"
echo "* MySQL user created and configured successfully! *"
echo "***************************************************"
;;
esac
}

#### SSL Or Not? ####

configure() {
app_url="http://$FQDN"
[ "$ASSUME_SSL" == true ] && app_url="https://$FQDN"
[ "$CONFIGURE_LETSENCRYPT" == true ] && app_url="https://$FQDN"
}

#### Set Permissions ####

set_permissions() {
case "$OS" in
debian | ubuntu)
cd || exit
chown -R www-data:www-data /var/www/dashboard/*
;;
centos)
cd || exit
chown -R nginx:nginx /var/www/dashboard/*
;;
esac
}

#### Create Queue Worker ####

install_dashboard() {
curl -o /etc/systemd/system/dashboard.service $GITHUB_BASE_URL/configs/dashboard.service
case "$OS" in
debian | ubuntu)
sed -i -e "s@<user>@www-data@g" /etc/systemd/system/dashboard.service
;;
centos)
sed -i -e "s@<user>@nginx@g" /etc/systemd/system/dashboard.service
;;
esac
systemctl enable dashboard.service
systemctl start dashboard.service
}

letsencrypt() {
FAILED=false

case "$OS" in
debian | ubuntu)
apt-get -y install certbot python3-certbot-nginx
;;
centos)
[ "$OS_VER_MAJOR" == "7" ] && yum -y -q install certbot python-certbot-nginx
[ "$OS_VER_MAJOR" == "8" ] && dnf -y -q install certbot python3-certbot-nginx
;;
esac

certbot --nginx --redirect --no-eff-email --email "$EMAIL" -d "$FQDN" || FAILED=true

if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == true ]; then
echo -n "The process of obtaining a Let's Encrypt certificate failed!"
echo -n "* Still assume SSL? (y/N) "
read -r CONFIGURE_SSL

if [[ "$CONFIGURE_SLL" =~ [Yy] ]]; then
ASSUME_SSL=true
CONFIGURE_LETSENCRYPT=false
nginx_configs
else
ASSUME_SSL=false
CONFIGURE_LETSENCRYPT=false
fi
fi
}

#### Nginx Configs

nginx_configs() {
if [ "$ASSUME_SSL" == true ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then
DL_FILE="dashboard_ssl.conf"
else
DL_FILE="dashboard.conf"
fi

if [ "$OS" == "centos" ]; then
rm -rf /etc/nginx/conf.d/default
curl -o /etc/nginx/conf.d/dashboard.conf $GITHUB_BASE_URL/configs/$DL_FILE
sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/conf.d/dashboard.conf
sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" /etc/nginx/conf.d/dashboard.conf
else
rm -rf /etc/nginx/sites-enabled/default
curl -o /etc/nginx/sites-available/dashboard.conf $GITHUB_BASE_URL/configs/$DL_FILE
sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-available/dashboard.conf
sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" /etc/nginx/sites-available/dashboard.conf
[ "$OS" == "debian" ] && [ "$OS_VER_MAJOR" == "9" ] && sed -i 's/ TLSv1.3//' /etc/nginx/sites-available/dashboard.conf
ln -sf /etc/nginx/sites-available/dashboard.conf /etc/nginx/sites-enabled/dashboard.conf
fi

if [ "$ASSUME_SSL" == false ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then
systemctl restart nginx
fi
}

#### Exec Perform Install ####

perform_install() {
echo
echo "****************************************************"
echo "* Starting installation.. this might take a while! *"
echo "****************************************************"
echo

case "$OS" in
debian | ubuntu)
apt_update

[ "$CONFIGURE_UFW" == true ] && ufw_ubuntu_debian

if [ "$OS" == "ubuntu" ]; then
 [ "$OS_VER_MAJOR" == "20" ] && ubuntu20_dep
 [ "$OS_VER_MAJOR" == "18" ] && ubuntu18_dep
elif [ "$OS" == "debian" ]; then
 [ "$OS_VER_MAJOR" == "9" ] && debian9_dep
 [ "$OS_VER_MAJOR" == "10" ] && debian10_dep
 [ "$OS_VER_MAJOR" == "11" ] && debian11_dep
fi
;;

centos)
[ "$OS_VER_MAJOR" == "7" ] && yum_update
[ "$OS_VER_MAJOR" == "8" ] && dnf_update

[ "$CONFIGURE_FIREWALL_CMD" == true ] && ufw_centos

[ "$OS_VER_MAJOR" == "7" ] && centos7_dep
[ "$OS_VER_MAJOR" == "8" ] && centos8_dep
;;
esac

[ "$OS" == "centos" ] && centos_php
download_files
setup_database
set_permissions
install_dashboard
nginx_configs
[ "$CONFIGURE_LETSENCRYPT" == true ] && letsencrypt
true
}


exec_installation() {
#### Confirm Installation ####
echo -e -n "\n* Initial configuration completed. Continue with installation? (y/N): "
read -r CONFIRM
if [[ "$CONFIRM" =~ [Yy] ]]; then
    #### Continue Install ####
    perform_install
  else
    echo "Installation aborted!"
    exit 1
fi
}

#### Exec Installation ####
exec_installation



#### Other general commands ####
cd || exit
sed -i -e "s@dashboarduser@${MYSQL_USER}@g" /var/www/dashboard/.env
sed -i -e "s@mysecretpassword@${MYSQL_PASS}@g" /var/www/dashboard/.env
sed -i -e "s@http://localhost@${FQDN}@g" /var/www/dashboard/.env
cd /var/www/dashboard || exit
php artisan migrate --seed --force
php artisan db:seed --class=ExampleItemsSeeder --force
php artisan key:generate --force

#### Config Cronjob ####

insert_cronjob() {
  echo "* Installing cronjob.. "

  crontab -l | {
    cat
    echo "* * * * * php /var/www/dashboard/artisan schedule:run >> /dev/null 2>&1"
  } | crontab -
  echo
  echo "**********************"
  echo "* Cronjob installed! *"
  echo "**********************"
  echo
}

#### Exec Cronjob ####
insert_cronjob


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
