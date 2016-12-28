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

configPostfix(){ 
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
server_host = ldap
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
server_host = ldap
server_port = 389
search_base = dc=mail,$DC
query_filter = (&(objectClass=CourierMailAccount)(mail=%s))
result_attribute = mailbox
bind = yes
bind_dn = cn=admin,$DC
bind_pw = $LDAP_PASSWORD
version = 3
EOF
}

configAuth(){
TMP=$(mktemp)
sed -r "s/^(START=)no$/\1yes/" /etc/default/saslauthd > $TMP
sed -r "s/^(MECHANISMS=\")pam(\")$/\1ldap\2/" $TMP > /etc/default/saslauthd

cat > /etc/saslauthd.conf <<EOF
ldap_servers: ldap://ldap:389/
ldap_search_base: dc=mail,$DC
ldap_timeout: 10
ldap_filter: (&(objectClass=CourierMailAccount)(mail=%U@%d))
ldap_bind_dn: cn=admin,$DC
ldap_password: $LDAP_PASSWORD
ldap_deref: never
ldap_restart: yes
ldap_scope: sub
ldap_use_sasl: no
ldap_start_tls: no
ldap_version: 3
ldap_auth_method: bind
EOF

cat > /etc/postfix/sasl/smtpd.conf << EOF
pwcheck_method: saslauthd
mech_list: plain login
EOF

cat >> /etc/postfix/main.cf <<EOF
# SASL Support
smtpd_sasl_local_domain =
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
broken_sasl_auth_clients = yes
smtpd_recipient_limit = 100
smtpd_helo_restrictions = reject_invalid_hostname
smtpd_sender_restrictions = reject_unknown_address
smtpd_recipient_restrictions = permit_sasl_authenticated,
 permit_mynetworks,
 reject_unauth_destination,
 reject_unknown_sender_domain,
 reject_unknown_client,
 reject_rbl_client zen.spamhaus.org,
 reject_rbl_client bl.spamcop.net,
 reject_rbl_client cbl.abuseat.org,
 permit
EOF

TMP=$(mktemp)
sed -r 's/^(OPTIONS="-c -m )\/var\/run\/saslauthd(")$/\1\/var\/spool\/postfix\/var\/run\/saslauthd\2/' /etc/default/saslauthd > $TMP
cp $TMP /etc/default/saslauthd

rm -rf /var/run/saslauthd
mkdir -p /var/spool/postfix/var/run/saslauthd
ln -s /var/spool/postfix/var/run/saslauthd /var/run
chgrp sasl /var/spool/postfix/var/run/saslauthd
adduser postfix sasl

/etc/init.d/saslauthd start
/etc/init.d/postfix restart
}

installCmd
configLDAP
configPostfix
configAuth

touch /root/vmail/docker_bootstrapped


else
	status "found already-configured docker"
fi

set -x


