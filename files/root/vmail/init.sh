#!/bin/bash

source /root/vmail/common

set -eux
LC_CTYPE=C.UTF-8
CONFD=/root/conf/init

configTZ() {
	ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
	echo>/etc/timezone $TZ
}

configLDAP() {
	if ! ldapsearch $LDAP_OPTS -b $DC dc=mail | grep -q dc:; then 
		replaceValues>/root/vmail/mail.ldif $CONFD/mail.ldif DC "$DC"
		ldapadd $LDAP_OPTS -f /root/vmail/mail.ldif
	fi

	CLEAR_DOVECOT_PASS=$(genPwd)
	DOVECOT_PASS=$(slappasswd -s $CLEAR_DOVECOT_PASS -h {SSHA})
	if ! ldapsearch $LDAP_OPTS -b $DC cn=dovecot | grep -q cn:; then
		replaceValues>/root/vmail/dovecot.ldif $CONFD/dovecot.ldif DC "$DC" LDAP_DOMAIN_BASE "$LDAP_DOMAIN_BASE" DOVECOT_PASS "$DOVECOT_PASS"
		ldapadd $LDAP_OPTS -f /root/vmail/dovecot.ldif
	else
		replaceValues>/root/vmail/dovecot.ldif $CONFD/modify_dovecot.ldif DC "$DC" DOVECOT_PASS "$DOVECOT_PASS"
		ldapmodify $LDAP_OPTS -f /root/vmail/dovecot.ldif
	fi

	if ! ldapsearch $LDAP_OPTS -b dc=mail,$DC dc=$MAIL_DOMAIN | grep -q dc:; then 
		TMP=$(mktemp)
		O=$(echo $MAIL_DOMAIN | sed -r 's/(.*)\.(.*)/\1\2/')
		replaceValues>$TMP $CONFD/mail_domain.ldif MAIL_DOMAIN "$MAIL_DOMAIN" DC "$DC" O "$O"
		ldapadd $LDAP_OPTS -f $TMP
	fi
}

configPostfix() { 
	setValue myhostname $MAIL_DOMAIN /etc/postfix/main.cf
	TMP=$(mktemp)
	sed -r "s/^(smtpd_banner = ).*$/\1smtp.$MAIL_DOMAIN ESMTP Server ready/" /etc/postfix/main.cf > $TMP 
	TMP2=$(mktemp)
	sed -r "s/^(smtpd?_tls_?.*)$/#\1/g" $TMP > /etc/postfix/main.cf
	cat /root/vmail/postfix.main.cf >> /etc/postfix/main.cf

	replaceValues>/etc/postfix/ldap-domains.cf $CONFD/ldap-domains.cf DC "$DC" CN_ADMIN "$CN_ADMIN" LDAP_PASSWORD "$LDAP_PASSWORD"
	replaceValues>/etc/postfix/ldap-aliases.cf $CONFD/ldap-aliases.cf DC "$DC" CN_ADMIN "$CN_ADMIN" LDAP_PASSWORD "$LDAP_PASSWORD"
	replaceValues>/etc/postfix/ldap-accounts.cf $CONFD/ldap-accounts.cf DC "$DC" CN_ADMIN "$CN_ADMIN" LDAP_PASSWORD "$LDAP_PASSWORD"
}

configAuth() {
	TMP=$(mktemp)
	sed -r "s/^(START=)no$/\1yes/" /etc/default/saslauthd > $TMP
	sed -r "s/^(MECHANISMS=\")pam(\")$/\1ldap\2/" $TMP > /etc/default/saslauthd

	replaceValues>/etc/saslauthd.conf $CONFD/saslauthd.conf DC "$DC" CN_ADMIN "$CN_ADMIN" LDAP_PASSWORD "$LDAP_PASSWORD"
	cp $CONFD/smtpd.conf /etc/postfix/smtpd.conf
	cat>>/etc/postfix/main.cf $CONFD/append_main.cf

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

configIMAP() {
	sed -i 's/^.*\(disable_plaintext_auth = \).*$/\1no/' /etc/dovecot/conf.d/10-auth.conf 
	sed -i 's/^.*\(login_greeting = \).*$/\1Server ready/' /etc/dovecot/dovecot.conf
	sed -i 's/^#\?\(mail_location = \).*$/\1maildir:\/vmail\/%d\/%n/' /etc/dovecot/conf.d/10-mail.conf
	sed -i 's/^#\?\(mail_uid =\).*$/\1 2000/' /etc/dovecot/conf.d/10-mail.conf
	sed -i 's/^#\?\(mail_gid =\).*$/\1 2000/' /etc/dovecot/conf.d/10-mail.conf

	# Enable also login auth_mechanisms
	sed -i 's/^.*\(auth_mechanisms.*\)$/\1 login/' /etc/dovecot/conf.d/10-auth.conf

	# Enable authentication with ldap
	sed -i 's/^.*\(!include auth-.*\)$/#\1/' /etc/dovecot/conf.d/10-auth.conf
	sed -i 's/^.*\(!include auth-ldap.*\)$/\1/' /etc/dovecot/conf.d/10-auth.conf

	# Configure LDAP auth
	setValue hosts ldap /etc/dovecot/dovecot-ldap.conf.ext
	setValue dn "cn=dovecot,$DC" /etc/dovecot/dovecot-ldap.conf.ext
	setValue dnpass "$CLEAR_DOVECOT_PASS" /etc/dovecot/dovecot-ldap.conf.ext
	setValue debug_level -1 /etc/dovecot/dovecot-ldap.conf.ext
	setValue auth_debug "yes" /etc/dovecot/conf.d/10-logging.conf
	setValue auth_debug_passwords "yes" /etc/dovecot/conf.d/10-logging.conf
	setValue ldap_version 3 /etc/dovecot/dovecot-ldap.conf.ext
	setValue base "dc=mail,$DC" /etc/dovecot/dovecot-ldap.conf.ext
	setValue user_attrs "uidNumber=2000,gidNumber=2000" /etc/dovecot/dovecot-ldap.conf.ext
	setValue user_filter "(&(objectClass=CourierMailAccount)(mail=%u))" /etc/dovecot/dovecot-ldap.conf.ext
	setValue pass_filter "(&(objectClass=CourierMailAccount)(mail=%u))" /etc/dovecot/dovecot-ldap.conf.ext
	setValue default_pass_scheme SSHA /etc/dovecot/dovecot-ldap.conf.ext

	sed -i '/inbox = yes/a \
  mailbox Trash { \
    auto = subscribe \
    special_use = \\Trash \
  } \
  mailbox Drafts { \
    auto = subscribe \
    special_use = \\Drafts \
  } \
  mailbox Sent { \
    auto = subscribe # autocreate and autosubscribe the Sent mailbox \
    special_use = \\Sent \
  } \
  mailbox Spam { \
    auto = subscribe # autocreate Spam, but dont autosubscribe \
    special_use = \\Junk \
  }' /etc/dovecot/conf.d/10-mail.conf
}

configSSL() {
	setValue smtpd_tls_cert_file "/ssl/smtp.${MAIL_DOMAIN}/fullchain.pem" /etc/postfix/main.cf
	setValue smtpd_tls_key_file "/ssl/smtp.${MAIL_DOMAIN}/privkey.pem" /etc/postfix/main.cf
	uncomment '/smtpd_tls_session_cache_database/,/smtp_tls_session_cache_database/' /etc/postfix/main.cf;
	sed -i "/smtp_tls_session_cache_database/asmtpd_tls_auth_only=no" /etc/postfix/main.cf

	cat>>/etc/postfix/main.cf <<EOF
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
EOF

	cat >> /etc/postfix/master.cf <<'EOF'
dovecot   unix  -       n       n       -       -       pipe
  flags=DRhu user=email:email argv=/usr/lib/dovecot/deliver -f ${sender} -d ${recipient}
EOF

	setValue ssl 'required' /etc/dovecot/conf.d/10-ssl.conf
	setValue ssl_cert "</ssl/imap.${MAIL_DOMAIN}/fullchain.pem" /etc/dovecot/conf.d/10-ssl.conf
	setValue ssl_key "</ssl/imap.${MAIL_DOMAIN}/privkey.pem" /etc/dovecot/conf.d/10-ssl.conf
	setValue disable_plaintext_auth 'yes' /etc/dovecot/conf.d/10-auth.conf

	sed -i "/unix_listener \/var\/spool\/postfix\/private\/auth/,/}/"' d' /etc/dovecot/conf.d/10-master.conf 
	sed -i "/smtp-auth/aunix_listener /var/spool/postfix/private/auth {\n     mode = 0660\n    user = postfix\n    group = postfix\n}\n" /etc/dovecot/conf.d/10-master.conf
}

configDKIM() {
	DKIMDIR=/etc/opendkim
	mkdir -p $DKIMDIR/keys
	[ ! -e $DKIMDIR/keytable ]     && echo>$DKIMDIR/keytable -n
	[ ! -e $DKIMDIR/signingtable ] && echo>$DKIMDIR/signingtable -n
	[ ! -e $DKIMDIR/trustedosts ]  && echo>$DKIMDIR/trustedhosts 127.0.0.1 localhost
}

# ensure correct writing into configuration files
/etc/init.d/opendkim stop; pkill opendkim||:
/etc/init.d/dovecot stop
postfix stop # avoid an issue with postfix start
/etc/init.d/saslauthd stop

if [ ! -e /root/vmail/docker_configured ]; then
	status "configuring docker for first run"
	chown -R vmail: /vmail
	configTZ
	configLDAP
	configPostfix
	configAuth
	configIMAP
	configSSL
	configDKIM
	touch /root/vmail/docker_configured
else
	status "found already-configured docker"
fi

/etc/init.d/saslauthd start
/etc/init.d/postfix start
/etc/init.d/dovecot start 
/etc/init.d/opendkim start
