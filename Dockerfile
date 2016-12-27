FROM debian:8.2
MAINTAINER Speed03 <infinity.speed03@gmail.com>

RUN apt-get update&&apt-get upgrade -y
RUN apt-get install apt-utils -y
RUN apt-get install supervisor -y
RUN LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -y postfix postfix-ldap
RUN apt-get install wget -y
RUN apt-get install ldap-utils && apt-get install vim -y
RUN apt-get install libodbc1 libslp1 libwrap0 -y

ENV LDAP_PASSWORD password
ENV LDAP_DOMAIN_BASE example.com
ENV DOMAIN_PASSWORD password

RUN echo "[supervisord]" > /etc/supervisord.conf && \
    echo "nodaemon=true" >> /etc/supervisord.conf && \
    echo "" >> /etc/supervisord.conf && \
    echo "[program:init]" >> /etc/supervisord.conf && \
    echo "command=/root/vmail/init.sh" >> /etc/supervisord.conf && \
    echo "autorestart=false" >> /etc/supervisord.conf

EXPOSE 25
EXPOSE 565

VOLUME ["/vmail"]

RUN mkdir /root/vmail
ADD postfix.main.cf /root/vmail
RUN groupadd -g 2000 vmail
RUN useradd -u 2000 -g 2000 -d /vmail -s /bin/false -m vmail
ADD init.sh /root/vmail
ADD script /root/vmail

RUN ln -s /root/vmail/script /add_domain
RUN ln -s /root/vmail/script /add_alias
RUN ln -s /root/vmail/script /add_account

CMD ["/usr/bin/supervisord"]
