"""Ansible's own templar for the unit harnesses: a task's Jinja rendered as Ansible renders it - its filters (bool,
quote, regex_search...) and native types - not plain Jinja, where an Ansible filter is missing and a bool is a string.

    sys.path.insert(0, "tests/ansible/unit"); from templar import render
    render("{{ x | bool }}", x="yes")  ->  True
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
