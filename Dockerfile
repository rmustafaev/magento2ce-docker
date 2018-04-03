FROM php:7.0-fpm

ENV NGINX_VERSION=1.13.10-1~jessie \
    NJS_VERSION=1.13.10.0.1.15-1~jessie

RUN set -x \
	&& \
	NGINX_GPGKEY=573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62; \
	found=''; \
	for server in \
		ha.pool.sks-keyservers.net \
		hkp://keyserver.ubuntu.com:80 \
		hkp://p80.pool.sks-keyservers.net:80 \
		pgp.mit.edu \
	; do \
		echo "Fetching GPG key $NGINX_GPGKEY from $server"; \
		apt-key adv --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$NGINX_GPGKEY" && found=yes && break; \
	done; \
	test -z "$found" && echo >&2 "error: failed to fetch GPG key $NGINX_GPGKEY" && exit 1; \
	dpkgArch="$(dpkg --print-architecture)" \
	&& nginxPackages=" \
		nginx=${NGINX_VERSION} \
		nginx-module-xslt=${NGINX_VERSION} \
		nginx-module-geoip=${NGINX_VERSION} \
		nginx-module-image-filter=${NGINX_VERSION} \
		nginx-module-njs=${NJS_VERSION} \
	" \
	&& case "$dpkgArch" in \
		amd64|i386) \
# arches officialy built by upstream
			echo "deb http://nginx.org/packages/mainline/debian/ jessie nginx" >> /etc/apt/sources.list \
			&& apt-get update \
			;; \
		*) \
# we're on an architecture upstream doesn't officially build for
# let's build binaries from the published source packages
			echo "deb-src http://nginx.org/packages/mainline/debian/ jessie nginx" >> /etc/apt/sources.list \
			\
# new directory for storing sources and .deb files
			&& tempDir="$(mktemp -d)" \
			&& chmod 777 "$tempDir" \
# (777 to ensure APT's "_apt" user can access it too)
			\
# save list of currently-installed packages so build dependencies can be cleanly removed later
			&& savedAptMark="$(apt-mark showmanual)" \
			\
# build .deb files from upstream's source packages (which are verified by apt-get)
			&& apt-get update \
			&& apt-get build-dep -y $nginxPackages \
			&& ( \
				cd "$tempDir" \
				&& DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" \
					apt-get source --compile $nginxPackages \
			) \
# we don't remove APT lists here because they get re-downloaded and removed later
			\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
# (which is done after we install the built packages so we don't have to redownload any overlapping dependencies)
			&& apt-mark showmanual | xargs apt-mark auto > /dev/null \
			&& { [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; } \
			\
# create a temporary local APT repo to install from (so that dependency resolution can be handled by APT, as it should be)
			&& ls -lAFh "$tempDir" \
			&& ( cd "$tempDir" && dpkg-scanpackages . > Packages ) \
			&& grep '^Package: ' "$tempDir/Packages" \
			&& echo "deb [ trusted=yes ] file://$tempDir ./" > /etc/apt/sources.list.d/temp.list \
# work around the following APT issue by using "Acquire::GzipIndexes=false" (overriding "/etc/apt/apt.conf.d/docker-gzip-indexes")
#   Could not open file /var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages - open (13: Permission denied)
#   ...
#   E: Failed to fetch store:/var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages  Could not open file /var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages - open (13: Permission denied)
			&& apt-get -o Acquire::GzipIndexes=false update \
			;; \
	esac \
	\
	&& apt-get install --no-install-recommends --no-install-suggests -y \
						$nginxPackages \
						gettext-base \
	&& rm -rf /var/lib/apt/lists/* \
	\
# if we have leftovers from building, let's purge them (including extra, unnecessary build deps)
	&& if [ -n "$tempDir" ]; then \
		apt-get purge -y --auto-remove \
		&& rm -rf "$tempDir" /etc/apt/sources.list.d/temp.list; \
	fi
# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log

COPY conf_ng/ /tmp/

RUN mv /tmp/conf/nginx.conf /etc/nginx/ && \
    mv /tmp/conf/conf.d/mage.conf /etc/nginx/conf.d/ 

EXPOSE 80

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
  su -c "composer update" -s /bin/sh www-data 
  /usr/local/bin/mage-setup && \
  apt-get purge -y mariadb-server && \
  rm -rf /tmp/composer_home && \
  rm -rf /var/lib/mysql && \
  apt-get clean

WORKDIR /srv/www

  CMD ["/usr/local/bin/start"]
