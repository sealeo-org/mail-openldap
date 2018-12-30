# sealeo/mail-openldap

Main features:
* use postfix, dovecot
* manage multidomain emails
* connects to an existing LDAP (see: [OpenLDAP](https://hub.docker.com/r/osixia/openldap))

Mail: postfix, dovecot - [Docker Hub](https://hub.docker.com/r/sealeo/mail-openldap/) 

# Installation
## Docker

### Mountpoints
- /vmail: all mailboxes
- /ssl/...: the SSL certificates for SMTP and IMAP (see SSL section)
- /etc/opendkim: storage for opendkim keys

### Ports
- 25 and 587 are for SMTP
- 993 is for IMAP

### Environment variables
- TZ: the timezone
- MAIL_DOMAIN: the domain of the mail server
- LDAP_DOMAIN_BASE: the URL to access the LDAP
- LDAP_ADMIN_PASSWORD: the password for LDAP
- DKIM_KEY_SIZE: DKIM key size in bits

### Examples
#### Docker CLI
```bash
docker run -d --name mail \
 -v /home/mail/mailboxes:/vmail \
 -v /home/mail/ssl/smtp.domain.com:/ssl/smtp.domain.com:ro \
 -v /home/mail/ssl/imap.domain.com:/ssl/imap.domain.com:ro \
 -v /home/mail/dkim:/etc/opendkim \
 -p 25:25 -p 587:587 -p 993:993 \
 --link ldap
 -e TZ=Etc/UTC -e MAIL_DOMAIN=domain.com \
 -e LDAP_DOMAIN_BASE=ldapdomain.com -e LDAP_ADMIN_PASSWORD=password \
 -e DKIM_KEY_SIZE=2048 \
 sealeo/mail-openldap
```

#### docker-compose.yml
```yaml
version: '3'
services:
  mail:
    container_name: mail
    image: sealeo/mail-openldap
    volumes:
    - /home/mail/mailboxes:/vmail
    - /home/mail/ssl/smtp.domain.com:/ssl/smtp.domain.com:ro
    - /home/mail/ssl/imap.domain.com:/ssl/imap.domain.com:ro
    - /home/mail/dkim:/etc/opendkim
    ports:
    - "25:25"
    - 587:587
    - 993:993
    external_links:
    - ldap
    environment:
    - TZ=Etc/UTC
    - MAIL_DOMAIN=domain.com
    - LDAP_DOMAIN_BASE=domain.com
    - LDAP_ADMIN_PASSWORD=password
    - DKIM_KEY_SIZE=2048
```

## DNS
### Minimal configuration for main domain
Minimal DNS zone configuration for the `MAIL_DOMAIN` (e.g. *domain.com* as above)
```
smtp 300 IN A x.x.x.x
imap 300 IN A x.x.x.x
mail 10800 IN A x.x.x.x
@ 10800 IN MX 10 mail.domain.com.
```
x.x.x.x is the IP address of your mail server.

### Configurations for other domains
```
@ 10800 IN MX 10 mail.domain.com.
autoconfig IN CNAME autoconfig.domain.com
```
where *domain.com* is the **main** domain.
the *autoconfig* line is for Thunderbird (see section below)

You will also need to configure each new domain for SPF, DKIM, ... (see below)

### More advanced configuration
#### SPF
See: [SPF on Wikipedia](https://en.wikipedia.org/wiki/Sender_Policy_Framework)
See: [SPF Wizard](https://www.spfwizard.net/)

Example of possible configuration:
```
domain.com. IN TXT "v=spf1 mx a ptr ip4:x.x.x.x ~all"
```
x.x.x.x is the IP address of your mail server.

#### DKIM
See: [DKIM on Wikipedia](https://en.wikipedia.org/wiki/DomainKeys_Identified_Mail)
See the **Add domain** section that explains what is required in DNS for DKIM

#### DMARC
See: [DMARC on Wikipedia](https://en.wikipedia.org/wiki/DMARC)

Example of possible configuration:
```
_dmarc IN TXT "v=DMARC1; p=none"
```

#### Automatic parameters for Thunderbird
```
autoconfig IN A x.x.x.x
```
and you must have a running webserver on *autoconfig.domain.com* which serves the content of `https://github.com/sealeo-org/mail-openldap/tree/master/etc/autoconfig.domain.com` (you must adapt the `mail/config-v1.1.xml` content to match your configuration)

## SSL
You need to provide SSL certificates for SMTPS and IMAPS in `/ssl`, in directories `smtp.domain.com` and `imap.domain.com` respectively.
Minimal files are `fullchain.pem` and `privkey.pem`. Any other file will be ignored.
You must ensure that these certificates are up to date.

Examples below are with Let's Encrypt but they must be easy to adapt to anything.
Note: this configuration is to be done on the **host**

### First installation
if you have any service listening on port 80: (example: nginx)
```bash
certbot certonly --pre-hook 'systemctl stop nginx' --post-hook 'systemctl start nginx' --standalone --agree-tos --rsa-key-size 4096 -d smtp.domain.com
certbot certonly --pre-hook 'systemctl stop nginx' --post-hook 'systemctl start nginx' --standalone --agree-tos --rsa-key-size 4096 -d imap.domain.com
```
**else**
```bash
certbot certonly --standalone --agree-tos --rsa-key-size 4096 -d smtp.domain.com
certbot certonly --standalone --agree-tos --rsa-key-size 4096 -d imap.domain.com
```

You now have certificates in `/etc/letsencrypt/live/`
To copy these for the container, you can run the two lines below.
Note: `/container/ssl` must be replaced by the mountpoint corresponding to inner `/ssl`
```bash
cp -TLrf /etc/letsencrypt/live/smtp.domain.com /container/ssl/smtp.domain.com
cp -TLrf /etc/letsencrypt/live/imap.domain.com /container/ssl/imap.domain.com
```
### Keep certificates up to date
This section will describe a way to keep easily up to date the certificates

#### Requirements
```bash
apt update
apt install -y incron
```

#### Setup
```bash
cat>/etc/incron.d/certs.mail.domain.com<<EOF
/etc/letsencrypt/live/smtp.domain.com/fullchain.pem IN_CLOSE_WRITE cp -LTrf /etc/letsencrypt/live/smtp.domain.com /data/containers/email/ssl/smtp.domain.com && docker exec mail update_smtp_ssl
/etc/letsencrypt/live/imap.domain.com/fullchain.pem IN_CLOSE_WRITE cp -LTrf /etc/letsencrypt/live/imap.domain.com /data/containers/email/ssl/imap.domain.com && docker exec mail update_imap_ssl
EOF
```

# Usage
Scripts are available in the container to add a new domain, email address or alias

## Add domain
```bash
docker exec -it mail add_domain
Domain? mydomain2.com
```

It will eventually show the required additional DNS zone configuration to enable DKIM for the new domain.
You will find it in you `/home/mail/dkim/keys/mydomain2.com/mail.txt` also, if you mounted like described above.
Note: your main domain DKIM key is automatically generated at container boot if non-existant.

## Add alias
```bash
docker exec -it mail add_alias
Domain? domain.com
User? admins
Name? Administrator list

Recipient list? CTRL+D to finish
alice@domain.com
bob@domain.com
```

## Add email
```bash
docker exec -it mail add_email
Domain? domain.com
User? bob
Password?
```

## (Re)generate DKIM for a domain
```bash
docker exec -it mail gen_dkim
Domain? domain.com
```
See **Add domain**
