#!/usr/bin/env python3
"""
generate_infoview.py

Reads the section of ../README.md between <!-- INFO_SCREEN_START --> and
<!-- INFO_SCREEN_END -->, parses it as simple Markdown, and regenerates
../MyFeelsLike/InfoView.swift (the in-app Info screen).

Usage (from the repo root):
    python3 tools/generate_infoview.py

Markdown rules:
  ## Heading           →  Text("Heading").font(.headline).id("heading-slug")
  blank line           →  paragraph separator
  - [label](#anchor)   →  Button that scrolls to that heading (table of contents)
  1. text              →  Text("1. text")  (in a VStack)
     https://url       →  Link(...)         (indented URL under a numbered item)
     - bullet          →  Text("    • bullet")  (indented, in a nested VStack)
  [label](url)         →  Link("label", destination: URL(string: "url")!)
  https://url          →  Link("url", ...)   (bare URL on its own line)
  plain text           →  Text("text")
"""

import re
import sys
from pathlib import Path

MARKER_START = "<!-- INFO_SCREEN_START -->"
MARKER_END   = "<!-- INFO_SCREEN_END -->"

HEADING  = "HEADING"
PARA     = "PARA"
NUMBERED = "NUMBERED"
BULLET   = "BULLET"
LINK     = "LINK"
TOC      = "TOC"      # table-of-contents entry: "- [label](#anchor) — desc"


def slug(text: str) -> str:
    """GitHub-style heading anchor: lowercase, drop non [a-z0-9 -], spaces→hyphens."""
    s = text.strip().lower()
    s = re.sub(r"[^a-z0-9 \-]", "", s)
    return s.replace(" ", "-")


def extract_section(md: str) -> str:
    start = md.find(MARKER_START)
    end   = md.find(MARKER_END)
    if start == -1 or end == -1:
        sys.exit("ERROR: INFO_SCREEN_START / INFO_SCREEN_END markers not found in README.md")
    return md[start + len(MARKER_START):end].strip()


def parse_items(section: str) -> list:
    items = []
    para_lines: list[str] = []

    def flush():
        text = " ".join(para_lines).strip()
        if text:
            items.append((PARA, text, 0))
        para_lines.clear()

    for raw in section.splitlines():
        line = raw.rstrip()

        if not line:
            flush()
            continue

        # ## Heading
        if line.startswith("## "):
            flush()
            items.append((HEADING, line[3:].strip(), 0))
            continue

        # Table-of-contents entry: "- [label](#anchor)" optionally "— description"
        m = re.match(r'^\-\s*\[([^\]]+)\]\(#([^)]+)\)\s*(?:[—-]\s*(.*))?$', line)
        if m:
            flush()
            label, anchor, desc = m.group(1).strip(), m.group(2).strip(), (m.group(3) or "").strip()
            items.append((TOC, f"{label}|{anchor}|{desc}", 0))
            continue

        # Numbered: "1. text"
        m = re.match(r'^(\d+)\.\s+(.*)', line)
        if m:
            flush()
            items.append((NUMBERED, f"{m.group(1)}. {m.group(2).strip()}", 0))
            continue

        # Indented bullet: 2+ leading spaces then "- text"
        m = re.match(r'^(\s{2,})-\s+(.*)', line)
        if m:
            flush()
            items.append((BULLET, m.group(2).strip(), len(m.group(1))))
            continue

        # Bare URL (possibly indented): "   https://..."
        m = re.match(r'^\s*(https?://\S+)\s*$', line)
        if m:
            flush()
            items.append((LINK, m.group(1), 0))
            continue

        # Markdown link on its own line: "[label](url)"
        m = re.match(r'^\s*\[([^\]]+)\]\((https?://[^)]+)\)\s*$', line)
        if m:
            flush()
            items.append((LINK, f"{m.group(1)}|{m.group(2)}", 0))
            continue

        # Plain paragraph text
        para_lines.append(line.strip())

    flush()
    return items


def esc(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def swift_text(content: str) -> str:
    return f'Text("{esc(content)}")'


def swift_link(content: str) -> str:
    if "|" in content:
        label, url = content.split("|", 1)
        return f'Link("{esc(label)}", destination: URL(string: "{esc(url)}")!)'
    return f'Link("{esc(content)}", destination: URL(string: "{esc(content)}")!)'


def swift_toc(content: str) -> str:
    label, anchor, desc = (content.split("|", 2) + ["", ""])[:3]
    text = label if not desc else f"{label} — {desc}"
    return (f'Button {{ withAnimation {{ proxy.scrollTo("{esc(anchor)}", anchor: .top) }} }} '
            f'label: {{ {swift_text(text)}.frame(maxWidth: .infinity, alignment: .leading) }}')


def generate(items: list) -> str:
    # Split items into per-section groups (each group starts with a HEADING)
    groups: list[list] = []
    current: list = []
    for item in items:
        if item[0] == HEADING and current:
            groups.append(current)
            current = [item]
        else:
            current.append(item)
    if current:
        groups.append(current)

    # Indentation levels (cosmetic only)
    L4 = "    " * 4
    L5 = "    " * 5
    L6 = "    " * 6
    L7 = "    " * 7

    out = [
        "import SwiftUI",
        "",
        "// AUTO-GENERATED — edit README.md and run tools/generate_infoview.py to update.",
        "",
        "struct InfoView: View {",
        "    var body: some View {",
        "        ScrollViewReader { proxy in",
        "            ScrollView {",
        "                VStack(alignment: .leading, spacing: 16) {",
    ]

    for group in groups:
        out.append(f"{L4}Group {{")

        i = 0
        while i < len(group):
            typ, content, indent = group[i]

            if typ == HEADING:
                out.append(f'{L5}{swift_text(content)}.font(.headline).id("{slug(content)}")')
                i += 1
                continue

            if typ == PARA:
                out.append(f'{L5}{swift_text(content)}')
                i += 1
                continue

            if typ == LINK:
                out.append(f'{L5}{swift_link(content)}')
                i += 1
                continue

            # Collect a consecutive run of list / toc items
            block = []
            while i < len(group) and group[i][0] in (NUMBERED, BULLET, LINK, TOC):
                block.append(group[i])
                i += 1

            has_outer = any(t in (NUMBERED, LINK, TOC) or (t == BULLET and bi == 0)
                            for t, _, bi in block)
            has_indented = any(t == BULLET and bi > 0 for t, _, bi in block)

            if has_outer or has_indented:
                out.append(f'{L5}VStack(alignment: .leading, spacing: 8) {{')
                j = 0
                while j < len(block):
                    bt, bc, bi = block[j]
                    if bt == NUMBERED:
                        out.append(f'{L6}{swift_text(bc)}')
                        j += 1
                    elif bt == TOC:
                        out.append(f'{L6}{swift_toc(bc)}')
                        j += 1
                    elif bt == LINK:
                        out.append(f'{L6}{swift_link(bc)}')
                        j += 1
                    elif bt == BULLET and bi > 0:
                        subs = []
                        while j < len(block) and block[j][0] == BULLET and block[j][2] > 0:
                            subs.append(block[j])
                            j += 1
                        if len(subs) == 1:
                            out.append(f'{L6}{swift_text("    • " + subs[0][1])}')
                        else:
                            out.append(f'{L6}VStack(alignment: .leading, spacing: 4) {{')
                            for _, sc, _ in subs:
                                out.append(f'{L7}{swift_text("    • " + sc)}')
                            out.append(f'{L6}}}')
                    else:
                        out.append(f'{L6}{swift_text("    • " + bc)}')
                        j += 1
                out.append(f'{L5}}}')
            else:
                for bt, bc, bi in block:
                    if bt == NUMBERED:
                        out.append(f'{L5}{swift_text(bc)}')
                    elif bt == TOC:
                        out.append(f'{L5}{swift_toc(bc)}')
                    elif bt == LINK:
                        out.append(f'{L5}{swift_link(bc)}')
                    else:
                        out.append(f'{L5}{swift_text("    • " + bc)}')

        out.append(f"{L4}}}")
        out.append("")

    while out and out[-1] == "":
        out.pop()

    out += [
        "                }",
        "                .padding(.horizontal, 16)",
        "                .padding(.vertical, 16)",
        "            }",
        "        }",
        '        .navigationTitle("Info")',
        "        .navigationBarTitleDisplayMode(.inline)",
        "        .textSelection(.enabled)",
        "    }",
        "}",
        "",
        "#Preview {",
        "    NavigationStack {",
        "        InfoView()",
        "    }",
        "}",
    ]

    return "\n".join(out) + "\n"


def main():
    root = Path(__file__).resolve().parent.parent   # repo root (tools/ is one level down)
    readme   = root / "README.md"
    infoview = root / "MyFeelsLike" / "InfoView.swift"

    md = readme.read_text(encoding="utf-8")
    section = extract_section(md)
    items = parse_items(section)
    swift = generate(items)
    infoview.write_text(swift, encoding="utf-8")
    print(f"✓  Generated {infoview}")


if __name__ == "__main__":
    main()
