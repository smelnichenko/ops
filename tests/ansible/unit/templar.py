"""Ansible's own templar for the unit harnesses: a task's Jinja rendered as Ansible renders it - its filters (bool,
quote, regex_search...) and native types - not plain Jinja, where an Ansible filter is missing and a bool is a string.

    sys.path.insert(0, "tests/ansible/unit"); from templar import render, condition
    render("{{ x | bool }}", x="yes")  ->  True
    condition("x is match('^\\S+ ')", x="a b")  ->  True    (when, failed_when, until, assert's that)

A conditional is evaluated as Ansible evaluates one, not as a template: the two differ - in a template a string
literal's backslash escapes stay as written ('^\\s' is a backslash and an s to a regex), in a conditional they are
read as Jinja reads them.
"""
from ansible.parsing.dataloader import DataLoader
from ansible.template import Templar

try:
    from ansible.template import trust_as_template  # ansible-core 2.19+: only text marked trusted is a template
except ImportError:
    def trust_as_template(text):
        return text


def render(text, **variables):
    return Templar(loader=DataLoader(), variables=variables).template(trust_as_template(text))


def condition(expr, **variables):
    """A when/failed_when/until/that as Ansible evaluates it: a bool - a list of them all true (as a task's when: list
    and assert's that: are read), a bare bool as itself."""
    if isinstance(expr, bool):
        return expr
    if isinstance(expr, list):
        return all(condition(e, **variables) for e in expr)
    return Templar(loader=DataLoader(), variables=variables).evaluate_conditional(trust_as_template(str(expr)))
