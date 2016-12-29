#!/bin/bash

set -eu

status () {
	echo "---> ${@}" >&2
}

set -x

DC='dc='$(echo ${LDAP_DOMAIN_BASE} | cut -d "." -f 1)',dc='$(echo ${LDAP_DOMAIN_BASE} | cut -d "." -f 2)

setValue() {
	sed -i "s/^#\?\($1[[:space:]]*=\).*$/\1$2/" $3
}

uncomment() { 
	sed -i "$1"' s/^ *#//' "$2"; 
}

comment() { 
	sed -i "$1"' s/^/#/' "$2"; 
}

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

if [ ! -e /root/vmail/docker_configured ]; then
	status "configuring docker for first run"

configPostfix(){ 
TMP=$(mktemp)
sed -r "s/^(smtpd_banner = ).*$/\1smtp.$LDAP_DOMAIN_BASE ESMTP Server ready/" /etc/postfix/main.cf > $TMP 
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


uncomment '/submission/,/-o milter/' /etc/postfix/master.cf;
uncomment '/smtps/,/-o milter/' /etc/postfix/master.cf; 
comment "/mua_client/,/mua_sender/" /etc/postfix/master.cf;

}

configIMAP(){
sed -i 's/^.*\(disable_plaintext_auth = \).*$/\1no/' /etc/dovecot/conf.d/10-auth.conf 
sed -i 's/^.*\(login_greeting = \).*$/\1Server ready/' /etc/dovecot/dovecot.conf
sed -i 's/^#\?\(mail_location = \).*$/\1\/vmail\/%d\/%n/' /etc/dovecot/conf.d/10-mail.conf
sed -i 's/^#\?\(mail_uid =\).*$/\1 2000/' /etc/dovecot/conf.d/10-mail.conf
sed -i 's/^#\?\(mail_gid =\).*$/\1 2000/' /etc/dovecot/conf.d/10-mail.conf

# Enable also login auth_mechanisms
sed -i 's/^.*\(auth_mechanisms.*\)$/\1 login/' /etc/dovecot/conf.d/10-auth.conf

# Enable authentication with ldap
sed -i 's/^.*\(!include auth-.*\)$/#\1/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^.*\(!include auth-ldap.*\)$/\1/' /etc/dovecot/conf.d/10-auth.conf

# Configure LDAP auth
setValue hosts ldap /etc/dovecot/dovecot-ldap.conf.ext
setValue dn "cn=admin,$DC" /etc/dovecot/dovecot-ldap.conf.ext
setValue dnpass $LDAP_PASSWORD /etc/dovecot/dovecot-ldap.conf.ext
setValue ldap_version 3 /etc/dovecot/dovecot-ldap.conf.ext
setValue base "dc=mail,$DC" /etc/dovecot/dovecot-ldap.conf.ext
setValue user_attrs "uidNumber=2000,gidNumber=2000" /etc/dovecot/dovecot-ldap.conf.ext
setValue user_filter "(\&(objectClass=CourierMailAccount)(mail=%u))" /etc/dovecot/dovecot-ldap.conf.ext
setValue pass_filter "(\&(objectClass=CourierMailAccount)(mail=%u))" /etc/dovecot/dovecot-ldap.conf.ext
setValue default_pass_scheme SSHA /etc/dovecot/dovecot-ldap.conf.ext

sed -i '/inbox = yes/a \
  mailbox Trash { \
    auto = no \
    special_use = \\Trash \
  } \
  mailbox Drafts { \
    auto = no \
    special_use = \\Drafts \
  } \
  mailbox Sent { \
    auto = subscribe # autocreate and autosubscribe the Sent mailbox \
    special_use = \\Sent \
  } \
  mailbox \"Sent Messages\" { \
    auto = no \
    special_use = \\Sent \
  } \
  mailbox Spam { \
    auto = create # autocreate Spam, but dont autosubscribe \
    special_use = \\Junk \
  } \
  mailbox virtual\/All { # if you have a virtual \"All messages\" mailbox \
    auto = no \
    special_use = \\All \
  }' /etc/dovecot/conf.d/10-mail.conf
}

configSSL() {
setValue smtpd_tls_cert_file "\/ssl\/smtp.${LDAP_DOMAIN_BASE}.cert.pem" /etc/postfix/main.cf
setValue smtpd_tls_key_file "\/ssl\/smtp.${LDAP_DOMAIN_BASE}.key.pem" /etc/postfix/main.cf
uncomment '/smtpd_tls_session_cache_database/,/smtp_tls_session_cache_database/' /etc/postfix/main.cf;
sed -i "/smtp_tls_session_cache_database/asmtpd_tls_auth_only=yes" /etc/postfix/main.cf

cat >> /etc/postfix/main.cf <<EOF
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
EOF

cat >> /etc/postfix/master.cf <<'EOF'
dovecot   unix  -       n       n       -       -       pipe
  flags=DRhu user=email:email argv=/usr/lib/dovecot/deliver -f ${sender} -d ${recipient}
EOF

setValue ssl 'required' /etc/dovecot/conf.d/10-ssl.conf
setValue ssl_cert "\/ssl\/imap.${LDAP_DOMAIN_BASE}.cert.pem" /etc/dovecot/conf.d/10-ssl.conf
setValue ssl_key "\/ssl\/imap.${LDAP_DOMAIN_BASE}.key.pem" /etc/dovecot/conf.d/10-ssl.conf
setValue disable_plaintext_auth 'yes' /etc/dovecot/conf.d/10-auth.conf

sed -i "/unix_listener \/var\/spool\/postfix\/private\/auth/,/}/"' d' /etc/dovecot/conf.d/10-master.conf 
sed -i "/smtp-auth/aunix_listener \/var\/spool\/postfix\/private\/auth {\n     mode = 0660\n    user = postfix\n    group = postfix\n}\n" /etc/dovecot/conf.d/10-master.conf
}

installCmd
configLDAP
configPostfix
configAuth
configIMAP
configSSL

/etc/init.d/saslauthd start
#kill -9 $(ps auwx | grep  "[/]usr/lib/postfix" | tr -s ' ' | cut -d ' ' -f 2)
/etc/init.d/postfix start
/etc/init.d/dovecot start 

touch /root/vmail/docker_configured


else
	status "found already-configured docker"
fi

set -x


