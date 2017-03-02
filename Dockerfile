FROM debian:8.2
MAINTAINER Pierre GUINAULT <speed@infinity.ovh>

RUN apt-get update && apt-get upgrade -y
RUN apt-get install apt-utils -y
RUN apt-get install supervisor -y
RUN apt-get install rsyslog -y
RUN LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -y postfix postfix-ldap
RUN apt-get install wget -y
RUN apt-get install ldap-utils && apt-get install vim -y
RUN apt-get install libodbc1 libslp1 libwrap0 -y
RUN apt-get install sasl2-bin libsasl2-modules-ldap -y
RUN apt-get install -y dovecot-imapd dovecot-pop3d dovecot-ldap -y

ENV LDAP_PASSWORD password
ENV LDAP_DOMAIN_BASE example.com
ENV DOMAIN_PASSWORD password
ENV SSL_SMTP_CERT smtp.cert
ENV SSL_SMTP_KEY  smtp.key
ENV SSL_IMAP_CERT imap.cert
ENV SSL_IMAP_KEY  imap.key

RUN echo "[supervisord]" > /etc/supervisord.conf && \
    echo "nodaemon=true" >> /etc/supervisord.conf && \
    echo "" >> /etc/supervisord.conf && \
    echo "[program:init]" >> /etc/supervisord.conf && \
    echo "command=/root/vmail/init.sh" >> /etc/supervisord.conf && \
    echo "autorestart=false" >> /etc/supervisord.conf && \
    echo "[program:rsyslog]" >> /etc/supervisord.conf && \
    echo "command=/etc/init.d/rsyslog start" >> /etc/supervisord.conf && \
    echo "autorestart=false" >> /etc/supervisord.conf

EXPOSE 25
EXPOSE 587
EXPOSE 993

VOLUME ["/vmail"]
VOLUME ["/ssl"]

RUN mkdir /root/vmail
ADD postfix.main.cf /root/vmail
RUN groupadd -g 2000 vmail
RUN useradd -u 2000 -g 2000 -d /vmail -s /bin/false -m vmail
ADD init.sh /root/vmail
ADD script /root/vmail
RUN chown -R 2000:2000 /vmail/

RUN chmod +x /root/vmail/script
RUN ln -s /root/vmail/script /usr/local/bin/add_domain
RUN ln -s /root/vmail/script /usr/local/bin/add_alias
RUN ln -s /root/vmail/script /usr/local/bin/add_account

CMD ["/usr/bin/supervisord"]
