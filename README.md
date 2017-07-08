# sealeo/mail-openldap

**A docker container to manage multidomain emails based on LDAP architecture with our container : [OpenLDAP](https://hub.docker.com/r/sealeo/openldap/)**

[hub]: https://hub.docker.com/r/sealeo/mail-openldap/mail

Mail : postfix, dovecot - [Docker Hub](https://hub.docker.com/r/sealeo/mail-openldap/) 

# Installation

## Docker

If you run your container with docker CLI :
```bash
docker run -d -v /home/mail/mailboxes:/vmail -v /home/mail/ssl/smtp.mydomain.com:/ssl/smtp.mydomain.com:ro \
-v /home/mail/ssl/imap.mydomain.com:/ssl/imap.mydomain.com:ro -p "25:25" -p "587:587" -p "993:993" -e LDAP_PASSWORD=password \
-e LDAP_DOMAIN=mydomain.com --name mail sealeo/mail-openldap
```

Or if you use *docker-compose*

```yaml
version: '3'

services:
  mail:
    image : sealeo/mail-openldap
    volumes:
      - /home/mail/mailboxes:/vmail
      - /home/mail/ssl/imap.mydomain.com:/ssl/imap.mydomain.com:ro
      - /home/mail/ssl/smtp.mydomain.com:/ssl/smtp.mydomain.com:ro
    ports:
      - "25:25"
      - "587:587"
      - "993:993"
    external_links:
      - ldap:ldap
    environment:
      - LDAP_PASSWORD=password
      - LDAP_DOMAIN_BASE=mydomain.com
```

## DNS

You need to update DNS zone of the domain which correspond to your LDAP domain, in this case *mydomain.com*

```
smtp 300 IN A xxx.xxx.xxx.xxx
imap 300 IN A xxx.xxx.xxx.xxx
mail 10800 IN A xxx.xxx.xxx.xxx
@ 10800 IN MX 10 mail.mydomain.com.
```
xxx.xxx.xxx.xxx is IP address of your mail server.

## SSL



# Usage

To add domain, email or alias address, 3 scripts are available and you can execute 
with *docker exec* command

## Add domain

```bash
docker exec -it mail add_domain

Domain ?mydomain2.com
adding new entry "dc=mydomain2.com,dc=mail,dc=mydomain,dc=com"

adding new entry "dc=mailAccount,dc=mydomain2.com,dc=mail,dc=mydomain,dc=com"

adding new entry "dc=mailAlias,dc=mydomain2.com,dc=mail,dc=mydomain,dc=com"
```

## Add alias

```bash
docker exec -it mail add_alias

Domain ?mydomain.com
User ?admins
Name ?Administrator list

Recipient list ? CTRL+D to finish
alice@mydomain.com
bob@mydomain.com

adding new entry "mail=admins@mydomain.com,dc=mailAlias,dc=mydomain2.com,dc=mail,dc=mydomain,dc=com"
```

## Add email

```bash
docker exec -it mail add_email

Domain ?mydomain.com
User ?bob
Password ?

adding new entry "mail=bob@mydomain.com,dc=mailaccount,dc=mydomain.com,dc=mail,dc=mydomain,dc=com"
```

