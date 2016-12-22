#!/bin/bash

set -eu

status () {
	echo "---> ${@}" >&2
}

set -x

DC='dc='$(echo ${LDAP_DOMAIN_BASE} | cut -d "." -f 1)',dc='$(echo ${LDAP_DOMAIN_BASE} | cut -d "." -f 2)

installCmd() {
	cd /tmp
	apt-get download slapd
	dpkg-deb --extract $(ls slapd*.deb) .
	cp -rf usr/lib/* /usr/lib
	cp usr/sbin/slappasswd /usr/sbin/
}

configLDAP () {
cd /root/vmail/
cat > mail.ldif <<EOF
dn:dc=mail,$DC
dc: mail
o: mail
objectClass: top
objectClass: dcObject
objectClass: organization
EOF

ldapadd -x -h ldap -D cn=admin,$DC -w ${LDAP_PASSWORD} -f /root/vmail/mail.ldif

PASS=$(slappasswd -s $DOMAIN_PASSWORD -h {SSHA})
TMP=$(mktemp)
O=$(echo $LDAP_DOMAIN_BASE | sed -r 's/(.*)\.(.*)/\1\2/')
cat > $TMP <<EOF
dn:dc=$LDAP_DOMAIN_BASE,dc=mail,$DC
o: $O
dc: $LDAP_DOMAIN_BASE
description: virtualDomain
userPassword: $PASS
objectClass: top
objectClass: dcObject
objectClass: organization

dn:dc=mailAccount,dc=$LDAP_DOMAIN_BASE,dc=mail,$DC
dc: mailAccount
o: mailAccount
objectClass: top
objectClass: dcObject
objectClass: organization

dn:dc=mailAlias,dc=$LDAP_DOMAIN_BASE,dc=mail,$DC
dc: mailAlias
o: mailAlias
objectClass: top
objectClass: dcObject
objectClass: organization
EOF
ldapadd -x -h ldap -D cn=admin,$DC -w ${LDAP_PASSWORD} -f $TMP
}

if [ ! -e /root/vmail/docker_bootstrapped ]; then
	status "configuring docker for first run"

configPostfix() { 
TMP=$(mktemp)
sed -r "s/^(smtpd_banner = ).*$/\1mail.$LDAP_DOMAIN_BASE ESMTP Server ready/" /etc/postfix/main.cf > $TMP 
TMP2=$(mktemp)
sed -r "s/^(smtpd?_tls_?.*)$/#\1/g" $TMP > /etc/postfix/main.cf
cat /root/vmail/postfix.main.cf >> /etc/postfix/main.cf

cat > /etc/postfix/ldap-domains.cf << EOF
server_host = ldap
server_port = 389
search_base = dc=mail,$DC
query_filter = (&(description=virtualDomain)(dc=%s))
result_attribute = dc
bind = yes
bind_dn = cn=admin,$DC
bind_pw = $LDAP_PASSWORD
version = 3
EOF

cat > /etc/postfix/ldap-aliases.cf << EOF
server_host = localhost
server_port = 389
search_base = dc=mail,$DC
query_filter = (&(objectClass=CourierMailAlias)(mail=%s))
result_attribute = maildrop
bind = yes
bind_dn = cn=admin,$DC
bind_pw = $LDAP_PASSWORD 
version = 3
EOF

cat > /etc/postfix/ldap-accounts.cf << EOF
server_host = localhost
server_port = 389
search_base = ou=people,$DC
query_filter = (&(objectClass=CourierMailAccount)(mail=%s))
result_attribute = mailbox
bind = yes
bind_dn = cn=admin,$DC
bind_pw = $LDAP_PASSWORD
version = 3
EOF
}

installCmd
configLDAP
configPostfix

touch /root/vmail/docker_bootstrapped


else
	status "found already-configured docker"
fi

set -x


