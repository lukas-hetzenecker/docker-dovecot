#!/bin/bash

#judgement
if [[ -a /etc/supervisor/conf.d/supervisord.conf ]]; then
  exit 0
fi

#supervisor
cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[supervisord]
nodaemon=true

[program:dovecot]
command=/opt/dovecot.sh

[program:postfix]
command=/opt/postfix.sh

[program:rsyslog]
command=/usr/sbin/rsyslogd -n -c3
EOF

############
#  dovecot
############
cat >> /opt/dovecot.sh <<EOF
#!/bin/bash
dovecot
tail -f /var/log/mail.log
EOF
chmod +x /opt/dovecot.sh

############
#  postfix
############
cat >> /opt/postfix.sh <<EOF
#!/bin/bash
service postfix start
tail -f /var/log/mail.log
EOF
chmod +x /opt/postfix.sh

################
#  configuration
################

groupadd -g 1200 vmail
useradd -u 1200 -g 1200 -s /sbin/nologin vmail
chown vmail:vmail /var/mail

# mail relay
if [[ -n "$MAIL_RELAY" ]]; then 
   postconf -e "relayhost = $MAIL_RELAY"
fi

cat >> /etc/dovecot/dovecot.conf <<EOF
mail_location = maildir:~/
managesieve_notify_capability = mailto
managesieve_sieve_capability = fileinto reject envelope encoded-character vacation subaddress comparator-i;ascii-numeric relational regex imap4flags copy include variables body enotify environment mailbox date ihave
namespace inbox {
  inbox = yes
  location = 
  mailbox Drafts {
    special_use = \Drafts
  }
  mailbox Junk {
    special_use = \Junk
  }
  mailbox Sent {
    special_use = \Sent
  }
  mailbox "Sent Messages" {
    special_use = \Sent
  }
  mailbox Trash {
    special_use = \Trash
  }
  prefix = 
}
plugin {
  sieve = ~/.dovecot.sieve
  sieve_dir = ~/sieve
}
protocols = imap lmtp sieve
service imap-login {
  inet_listener imap {
    port = 143
  }
  inet_listener imaps {
    port = 993
    ssl = yes
  }
}
service lmtp {
  inet_listener lmtp {
    address = $(hostname -i ) 127.0.0.1 ::1
    port = 24
  }
  user = vmail
}
protocol lmtp {
  mail_plugins = sieve
  postmaster_address = postmaster@%d
}
ssl = required
ssl_cert = <$(find /etc/dovecot/certs -iname *.crt)
ssl_key = <$(find /etc/dovecot/certs -iname *.key)
ssl_ca = <$(find /etc/dovecot/certs -iname cacert.pem)
EOF

if [[ -n "$LDAP_HOST" && -n "$LDAP_BASE" ]]; then
  cat >> /etc/dovecot/dovecot.conf <<EOF
passdb {
  args = /etc/dovecot/dovecot-ldap.conf.ext
  driver = ldap
}
EOF

  cat >> /etc/dovecot/dovecot-ldap.conf.ext <<EOF
hosts = $LDAP_HOST
dn = $LDAP_BIND_DN
dnpass = $LDAP_BIND_PW
auth_bind = yes
auth_bind_userdn = $LDAP_USER_DN
ldap_version = 3
base = $LDAP_BASE
user_filter = $LDAP_USER_FILTER
default_pass_scheme = SSHA
EOF

fi

if [[ -n "$AUTH_INET_PORT" ]]; then
  cat >> /etc/dovecot/dovecot.conf <<EOF
service auth {
 inet_listener {
   port = $AUTH_INET_PORT
 }
}
EOF

fi


if [[ -n "$USERDB_FILE" && -n "$PASSDB_FILE" ]]; then
  cat >> /etc/dovecot/dovecot.conf <<EOF
passdb {
  driver = passwd-file
  args = scheme=plain-md5 username_format=%n $PASSDB_FILE
}
userdb {
  driver = passwd-file
  args = username_format=%n $PASSDB_FILE
  default_fields = uid=vmail gid=vmail home=/var/mail/%d/%n
}
EOF

fi


