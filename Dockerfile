FROM debian:8.8

LABEL maintainer="Pierre GUINAULT <speed@infinity.ovh>, Alexis Pereda <alexis@pereda.fr>"
LABEL version="0.3"

RUN apt-get update && \
  LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -y \
	ca-certificates \
	dovecot-imapd \
	dovecot-ldap \
	ldap-utils \
	libodbc1 \
	libsasl2-modules-ldap \
	libslp1 \
	libwrap0 \
	opendkim \
	opendkim-tools \
	postfix \
	postfix-ldap \
	rsyslog \
	sasl2-bin \
	supervisor \
	&& rm -rf /var/lib/apt/lists/*

RUN groupadd -g 2000 vmail && useradd -u 2000 -g 2000 -d /vmail -s /bin/false -m vmail

# Global
ENV TZ               Etc/UTC

# LDAP
ENV LDAP_ADMIN_PASSWORD    password
ENV LDAP_DOMAIN_BASE example.com
ENV LDAP_USE_TLS 1

# Mail
ENV SSL_SMTP_CERT    smtp.cert
ENV SSL_SMTP_KEY     smtp.key
ENV SSL_IMAP_CERT    imap.cert
ENV SSL_IMAP_KEY     imap.key
ENV MAIL_DOMAIN      exemple.com
ENV DKIM_KEY_SIZE    2048

COPY ./files /

RUN LC_CTYPE=C.UTF-8

EXPOSE 25
EXPOSE 587
EXPOSE 993

VOLUME ["/vmail"]
VOLUME ["/ssl"]

CMD ["/usr/bin/supervisord", "-c/etc/supervisord.conf"]
