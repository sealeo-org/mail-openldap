# sealeo/mail-openldap

Main features:
* use postfix, dovecot
* manage multidomain emails
* connects to an existing LDAP (see: [OpenLDAP](https://hub.docker.com/r/sealeo/openldap/))

Mail: postfix, dovecot - [Docker Hub](https://hub.docker.com/r/sealeo/mail-openldap/) 

# Installation
## Docker

### Docker CLI
```bash
docker run -d --name mail \
 -v /home/mail/mailboxes:/vmail \
 -v /home/mail/ssl/smtp.mydomain.com:/ssl/smtp.mydomain.com:ro \
 -v /home/mail/ssl/imap.mydomain.com:/ssl/imap.mydomain.com:ro \
 -v /home/mail/dkim:/etc/opendkim \
 -p 25:25 -p 587:587 -p 993:993 \
 --link ldap
 -e TZ=Etc/UTC -e MAIL_DOMAIN=mydomain.com \
 -e LDAP_DOMAIN_BASE=ldapdomain.com -e LDAP_PASSWORD=password \
 -e DKIM_KEY_SIZE=2048 \
 sealeo/mail-openldap
```

### docker-compose.yml
```yaml
version: '3'
services:
  mail:
    image: sealeo/mail-openldap
    volumes:
    - /home/mail/mailboxes:/vmail
    - /home/mail/ssl/smtp.mydomain.com:/ssl/smtp.mydomain.com:ro
    - /home/mail/ssl/imap.mydomain.com:/ssl/imap.mydomain.com:ro
		- /home/mail/dkim:/etc/opendkim
    ports:
    - "25:25"
    - 587:587
    - 993:993
    external_links:
    - ldap
    environment:
		- TZ=Etc/UTC
		- MAIL_DOMAIN=mydomain.com
    - LDAP_DOMAIN_BASE=mydomain.com
    - LDAP_PASSWORD=password
		- DKIM_KEY_SIZE=2048
```

## DNS
### Minimal configuration
Minimal DNS zone configuration for the `MAIL_DOMAIN` (e.g. *mydomain.com* as above)
```
smtp 300 IN A x.x.x.x
imap 300 IN A x.x.x.x
mail 10800 IN A x.x.x.x
@ 10800 IN MX 10 mail.mydomain.com.
```
x.x.x.x is the IP address of your mail server.

### More advanced configuration
#### SPF
See: [SPF on Wikipedia](https://en.wikipedia.org/wiki/Sender_Policy_Framework)
See: [SPF Wizard](https://www.spfwizard.net/)

Example of possible configuration:
```
mydomain.com. IN TXT "v=spf1 mx a ptr ip4:x.x.x.x ~all"
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

## SSL
soon described

# Usage
Scripts are available in the container to add a new domain, email address or alias

## Add domain
```bash
docker exec -it mail add_domain
Domain? mydomain2.com
```

It will eventually show the required additional DNS zone configuration to enable DKIM for the new domain.
You will find it in you `/home/mail/dkim/keys/mydomain2.com/mail.txt` also, if you mounted like described above.

## Add alias
```bash
docker exec -it mail add_alias
Domain? mydomain.com
User? admins
Name? Administrator list

Recipient list? CTRL+D to finish
alice@mydomain.com
bob@mydomain.com
```

## Add email
```bash
docker exec -it mail add_email
Domain? mydomain.com
User? bob
Password?
```

## (Re)generate DKIM for a domain
```bash
docker exec -it mail gen_dkim
Domain? mydomain.com
```
See **Add domain**

# Possible issues

## Not receiving e-mails from a specific client
If you do not receive e-mails from a specific client, like e.g. gmail.com, check your logs (`/var/log/mail.info`) and see if something like
```
450 4.7.1 Client host rejected: cannot find your hostname, [IP]
```
occurs. If so, you probably need to fix your inner `/etc/resolv.conf`
After that, you will need to restart postfix:
```bash
postfix stop; /etc/init.d/postfix start
```
