#!/usr/bin/env python3
"""upgrade-mail.py - an upgrade notice mailed straight out, not through Alertmanager (it may be what broke): the sender
and the address Alertmanager uses - Resend's SMTP (alerts@pmon.dev, STARTTLS on smtp.resend.com:587, user resend) to the
admin address (infra's production alertEmailTo, read by upgrade-notice.sh).

Env: TO, SUBJECT, BODY, RESEND_API_KEY. Exit 0 mailed, 1 not (said).
"""
import os
import smtplib
import ssl
import sys
from email.message import EmailMessage

HOST, PORT, SENDER, USER = "smtp.resend.com", 587, "alerts@pmon.dev", "resend"


def send(to, subject, body, key, smtp=smtplib.SMTP):
    m = EmailMessage()
    m["From"], m["To"], m["Subject"] = SENDER, to, subject
    m.set_content(body)
    with smtp(HOST, PORT, timeout=30) as s:
        s.starttls(context=ssl.create_default_context())
        s.login(USER, key)
        s.send_message(m)


def main():
    try:
        send(os.environ["TO"], os.environ["SUBJECT"], os.environ["BODY"], os.environ["RESEND_API_KEY"])
    except KeyError as e:
        print(f"NOT SENT: {e} missing")
        return 1
    except (OSError, smtplib.SMTPException) as e:
        print(f"NOT SENT: {e}")
        return 1
    print("MAILED directly")
    return 0


if __name__ == "__main__":
    sys.exit(main())
