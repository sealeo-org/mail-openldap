FROM debian:8.2
LABEL maintainer="Pierre GUINAULT <speed@infinity.ovh>, Alexis Pereda <alexis@pereda.fr>"
LABEL version="0.2"

RUN apt-get update && apt-get upgrade -y && \
  LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -y \
	apt-utils \
	dovecot-imapd \
	dovecot-ldap \
	dovecot-pop3d \
	incron \
	ldap-utils \
	libodbc1 \
	libsasl2-modules-ldap \
	libslp1 \
	libwrap0 \
	mariadb-client \
	nginx \
	opendkim \
	opendkim-tools \
	php5-fpm \
	php5-mysql \
	postfix \
	postfix-ldap \
	rsyslog \
	sasl2-bin \
	supervisor \
	vim \
	wget \
	&& rm -rf /var/lib/apt/lists/*

RUN groupadd -g 2000 vmail && useradd -u 2000 -g 2000 -d /vmail -s /bin/false -m vmail

# Global
ENV TZ               Etc/UTC

# LDAP
ENV LDAP_PASSWORD    password
ENV LDAP_DOMAIN_BASE example.com

# Mail
ENV SSL_SMTP_CERT    smtp.cert
ENV SSL_SMTP_KEY     smtp.key
ENV SSL_IMAP_CERT    imap.cert
ENV SSL_IMAP_KEY     imap.key
ENV MAIL_DOMAIN      exemple.com
ENV DKIM_KEY_SIZE    2048

# Webmail (Roundcube)
ENV RC_NAME          "Roundcube Webmail"
ENV RC_SUPPORT_URL   ""
ENV RC_DB_HOST       localhost
ENV RC_DATABASE      roundcubemail
ENV RC_DB_USER       roundcube
ENV RC_DB_PASSWORD   password

COPY ./files /
ADD  roundcube.tar /opt

RUN LC_CTYPE=C.UTF-8

EXPOSE 25
EXPOSE 80
EXPOSE 587
EXPOSE 993

VOLUME ["/vmail"]
VOLUME ["/ssl"]

CMD ["/usr/bin/supervisord", "-c/etc/supervisord.conf"]
