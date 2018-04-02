FROM php:7.0-fpm

ENV M2SETUP_DB_HOST=127.0.0.1 \
    M2SETUP_DB_NAME=magento2 \
    M2SETUP_DB_USER=root \
    M2SETUP_DB_PASSWORD=magento2 \
    M2SETUP_BASE_URL=http://localhost:1881 \
    M2SETUP_ADMIN_FIRSTNAME=Admin \
    M2SETUP_ADMIN_LASTNAME=User \
    M2SETUP_ADMIN_EMAIL=dummy@setronica.com \
    M2SETUP_ADMIN_USER=magento2 \
    M2SETUP_ADMIN_PASSWORD=magento2 \
    M2SETUP_ADMIN_URI=admin_1111 \
    M2SETUP_VERSION=2.2.2

#Add custom php config and operational scripts
COPY conf/* /usr/local/etc/
COPY bin/* /usr/local/bin/

#Install dependencies, start mysql db, clone magento from git, install and setup magento
RUN apt-get update &&  \
  export COMPOSER_HOME=/tmp/composer_home/ && \
  export DEBIAN_FRONTEND=noninteractive && apt-get install -y \
  cron \
  libfreetype6-dev \
  libicu-dev \
  libjpeg62-turbo-dev \
  libmcrypt-dev \
  libpng12-dev \
  libxslt1-dev \
  vim \
  crudini \
  zip \
  git \
  mariadb-server && \
  docker-php-ext-configure \
  gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ && \
  docker-php-ext-install \
  bcmath \
  gd \
  intl \
  mbstring \
  mcrypt \
  opcache \
  pdo_mysql \
  soap \
  xsl \
  gettext \
  zip && \
  mv /usr/local/etc/php.ini /usr/local/etc/php/ && \
  service mysql start && \
  /usr/bin/mysqladmin -u $M2SETUP_DB_USER password $M2SETUP_DB_PASSWORD && \
  /usr/bin/mysql -u $M2SETUP_DB_USER -p$M2SETUP_DB_PASSWORD -h $M2SETUP_DB_HOST -e "CREATE DATABASE $M2SETUP_DB_NAME;" && \
  curl -sS https://getcomposer.org/installer | \
  php -- --install-dir=/usr/local/bin --filename=composer && \
  rm -rf /srv/www && mkdir -p /srv/www && \
  rm -rf /tmp/composer_home && mkdir -p /tmp/composer_home/ && \
  mv /usr/local/etc/auth.json /tmp/composer_home/ && \ 
  chmod 775 /tmp/composer_home/ && \
  chown www-data:www-data -R /tmp/composer_home/ && \
  chmod 775 /srv/www/ && \
  chown www-data:www-data -R /srv/www/ && \
  cd /srv/www/ && \
  su -c "/usr/local/bin/composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition ./ $M2SETUP_VERSION" -s /bin/sh www-data && \
  mv /usr/local/etc/composer.json /srv/www/ && \
  su -c "composer update" -s /bin/sh www-data && \
  ls -l /usr/local/bin/ && \
  /usr/local/bin/mage-setup && \
  apt-get purge -y mariadb-server && \
  rm -rf /tmp/composer_home && \
  rm -rf /var/lib/mysql && \
  apt-get clean

WORKDIR /srv/www

  CMD ["/usr/local/bin/start"]
