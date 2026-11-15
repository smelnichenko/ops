#!/usr/bin/env python3
"""upgrade-mail.py - an upgrade notice mailed straight out, not through Alertmanager (it may be what broke): the sender
and the address Alertmanager uses - Resend's SMTP (alerts@pmon.dev, STARTTLS on smtp.resend.com:587, user resend) to the
admin address (infra's production alertEmailTo, read by upgrade-notice.sh).

Env: TO, SUBJECT, BODY, RESEND_API_KEY. Exit 0 mailed, 1 not (said) - whatever failed (a log's end cut inside a
character among them: its bytes replaced, never the mail lost to them).
"""
import os
import smtplib
import ssl
import sys
from email.message import EmailMessage

HOST, PORT, SENDER, USER = "smtp.resend.com", 587, "alerts@pmon.dev", "resend"


def clean(text):
    """The environment's text as UTF-8, a byte that is none (a log's end cut inside a character) replaced."""
    return text.encode("utf-8", "surrogateescape").decode("utf-8", "replace")


def send(to, subject, body, key, smtp=None):
    m = EmailMessage()
    m["From"], m["To"], m["Subject"] = SENDER, to, clean(subject).replace("\n", " ")
    m.set_content(clean(body))
    with (smtp or smtplib.SMTP)(HOST, PORT, timeout=30) as s:
        s.starttls(context=ssl.create_default_context())
        s.login(USER, key)
        s.send_message(m)


def main():
    try:
        send(os.environ["TO"], os.environ["SUBJECT"], os.environ["BODY"], os.environ["RESEND_API_KEY"])
    except KeyError as e:
        print(f"NOT SENT: {e} missing")
        return 1
    except Exception as e:  # noqa: BLE001 - the page's last way out: whatever stopped it is said, never a traceback
        print(f"NOT SENT: {type(e).__name__}: {e}")
        return 1
    print("MAILED directly")
    return 0


if __name__ == "__main__":
    sys.exit(main())
