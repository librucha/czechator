"""Port of czechator's `NumberedList`: the wire format between tool and model.

Items are escaped so a segment containing a real newline cannot break the list.
Behaviour mirrors the Swift implementation, including what it tolerates
(preamble, code fences, blank lines) and what it refuses.
"""

import re

# Swift `Character.isNewline`; CRLF is handled as one unit before this set.
_NEWLINES = frozenset("\n\r\x0b\x0c\x85  ")
_LINE_SPLIT = re.compile(r"\r\n|[\n\r\x0b\x0c\x85  ]")
_NUMBER = re.compile(r"[+-]?[0-9]+")


class NumberedListError(ValueError):
    pass


class CountMismatch(NumberedListError):
    def __init__(self, expected: int, got: int):
        super().__init__(f"expected {expected} items, got {got}")
        self.expected, self.got = expected, got


class BadNumbering(NumberedListError):
    def __init__(self, at_item: int):
        super().__init__(f"bad numbering at item {at_item}")
        self.at_item = at_item


class UnexpectedContinuation(NumberedListError):
    def __init__(self, after_item: int):
        super().__init__(f"unexpected continuation line after item {after_item}")
        self.after_item = after_item


def escape(s: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\":
            out.append("\\\\")
        elif c == "\t":
            out.append("\\t")
        elif c == "\r" and s[i + 1 : i + 2] == "\n":
            out.append("\\r\\n")
            i += 1
        elif c == "\r":
            out.append("\\r")
        elif c in _NEWLINES:
            out.append("\\n")
        else:
            out.append(c)
        i += 1
    return "".join(out)


def unescape(s: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(s):
        if s[i] != "\\" or i + 1 >= len(s):
            out.append(s[i])
            i += 1
            continue
        nxt = s[i + 1]
        if nxt == "u":
            hex_digits = s[i + 2 : i + 6]
            if len(hex_digits) == 4 and all(c in "0123456789abcdefABCDEF" for c in hex_digits):
                out.append(chr(int(hex_digits, 16)))
                i += 6
                continue
        mapped = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\"}.get(nxt)
        out.append(mapped if mapped is not None else s[i : i + 2])
        i += 2
    return "".join(out)


def encode(items: list[str]) -> str:
    return "\n".join(f"{n}. {escape(item)}" for n, item in enumerate(items, start=1))


def decode(text: str, expected_count: int) -> list[str]:
    items: list[str] = []
    for line in _LINE_SPLIT.split(text):
        structural = line.strip()
        if not structural or structural.startswith("```"):
            continue
        dot = line.find(".")
        head = line[:dot].strip() if dot >= 0 else ""
        if dot < 0 or not _NUMBER.fullmatch(head):
            # Before the first item this is a preamble; after it, the model
            # wrapped an item and dropping the line would truncate text.
            if not items:
                continue
            raise UnexpectedContinuation(len(items))
        if int(head) != len(items) + 1:
            raise BadNumbering(len(items) + 1)
        body = line[dot + 1 :]
        if body.startswith(" "):
            body = body[1:]
        items.append(unescape(body))
    if len(items) != expected_count:
        raise CountMismatch(expected_count, len(items))
    return items
