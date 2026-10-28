"""Shared option schema for hand-added character evolution plans."""


def option(ability, branch, tier, oid, name, desc, brief, **params):
    return dict(ability=ability, branch=branch, tier=tier, id=oid, name=name, desc=desc, brief=brief, params=params)
