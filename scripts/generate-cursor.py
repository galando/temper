#!/usr/bin/env python3
"""
Temper — Cursor IDE Generator

Mirrors .claude/ → .cursor/ for Cursor IDE support.
Usage: python3 scripts/generate-cursor.py [--output DIR]

Default output: .cursor/ in the repository root.
"""

import json
import os
import re
import sys
import argparse
from pathlib import Path


def resolve_repo_root():
    """Find the repository root by walking up from this script's location."""
    current = Path(__file__).resolve().parent
    while current != current.parent:
        if (current / ".claude-plugin" / "plugin.json").exists():
            return current
        current = current.parent
    # Fallback: script is in scripts/ dir, repo root is one level up
    return Path(__file__).resolve().parent.parent


def read_version(repo_root):
    """Read version from plugin.json."""
    plugin_json = repo_root / ".claude-plugin" / "plugin.json"
    if plugin_json.exists():
        try:
            with open(plugin_json, encoding="utf-8") as f:
                data = json.load(f)
                return data.get("version", "0.0.0")
        except (json.JSONDecodeError, OSError):
            return "0.0.0"
    return "0.0.0"


def convert_askuserquestion_to_numbered(content):
    """Convert AskUserQuestion tool calls to conversational numbered prompts."""
    # Replace AskUserQuestion blocks with numbered options
    pattern = r'AskUserQuestion:\s*\n\s*question:\s*"([^"]+)"\s*\n\s*options:\s*\n((?:\s*-\s*label:\s*"[^"]+"\s*\n\s*description:\s*"[^"]+"\s*\n?)+)'

    def replacer(match):
        question = match.group(1)
        options_block = match.group(2)
        options = re.findall(r'label:\s*"([^"]+)"', options_block)
        descriptions = re.findall(r'description:\s*"([^"]+)"', options_block)

        lines = [f'**{question}**\n']
        for i, (label, desc) in enumerate(zip(options, descriptions), 1):
            lines.append(f'{i}. **{label}** — {desc}')
        lines.append(f'{len(options) + 1}. Type your own response\n')
        return '\n'.join(lines)

    return re.sub(pattern, replacer, content)


def convert_agent_to_sequential(content):
    """Convert Agent tool references to sequential focus pattern."""
    # Replace "Use the Agent tool" with sequential focus instructions
    content = content.replace(
        'Use the Agent tool with this prompt:',
        'Load the following context files, then execute the instructions sequentially:'
    )
    content = re.sub(
        r'Use the Agent tool\b',
        'Execute sequentially (load all referenced files first)',
        content
    )
    return content


def convert_commands_to_hyphenated(content):
    """Convert /temper:command to /temper-command format."""
    content = re.sub(r'/temper:(\w+)', r'/temper-\1', content)
    return content


def process_command_file(content, filename):
    """Process a command file for Cursor compatibility."""
    content = convert_askuserquestion_to_numbered(content)
    content = convert_agent_to_sequential(content)
    content = convert_commands_to_hyphenated(content)

    # Convert colon-separated command names in filenames to hyphenated
    # e.g., plan.md -> temper-plan.md
    return content


def generate_cursor_rules_mdc(name, content, description=""):
    """Wrap content in Cursor MDC format."""
    frontmatter = f'---\ndescription: "{description}"\nalwaysApply: false\n---\n\n'
    return frontmatter + content


def main():
    parser = argparse.ArgumentParser(description="Generate Cursor IDE files from .claude/")
    parser.add_argument("--output", "-o", default=None, help="Output directory (default: .cursor/ in repo root)")
    args = parser.parse_args()

    repo_root = resolve_repo_root()
    output_dir = Path(args.output) if args.output else repo_root / ".cursor"
    version = read_version(repo_root)

    print(f"Temper v{version} — Generating Cursor IDE files")
    print(f"  Repo root: {repo_root}")
    print(f"  Output:    {output_dir}")
    print()

    # Create output directories
    (output_dir / "commands").mkdir(parents=True, exist_ok=True)
    (output_dir / "rules").mkdir(parents=True, exist_ok=True)

    # --- 1. Write VERSION ---
    version_file = output_dir / "VERSION"
    version_file.write_text(version + "\n", encoding="utf-8")
    print(f"  [VERSION] {version_file}")

    # --- 2. Generate commands ---
    commands_dir = repo_root / ".claude" / "commands"
    if commands_dir.exists():
        for cmd_file in sorted(commands_dir.glob("*.md")):
            content = cmd_file.read_text(encoding="utf-8")
            # Convert filename: pack.md -> temper-pack.md, temper.md -> temper.md
            name = cmd_file.stem
            if name == "temper":
                cursor_name = "temper.md"
            else:
                cursor_name = f"temper-{name}.md"

            processed = process_command_file(content, cursor_name)
            out_path = output_dir / "commands" / cursor_name
            out_path.write_text(processed, encoding="utf-8")
            print(f"  [CMD] {cursor_name}")

    # --- 3. Generate rules from skills ---
    skills_dir = repo_root / ".claude" / "skills"
    if skills_dir.exists():
        for skill_dir in sorted(skills_dir.iterdir()):
            if skill_dir.is_dir():
                skill_file = skill_dir / "SKILL.md"
                if skill_file.exists():
                    content = skill_file.read_text(encoding="utf-8")
                    # Extract description from frontmatter
                    desc_match = re.search(r'description:\s*"([^"]+)"', content)
                    desc = desc_match.group(1) if desc_match else f"Temper {skill_dir.name}"
                    mdc_content = generate_cursor_rules_mdc(
                        f"temper-{skill_dir.name}",
                        content,
                        desc
                    )
                    out_path = output_dir / "rules" / f"temper-{skill_dir.name}.mdc"
                    out_path.write_text(mdc_content, encoding="utf-8")
                    print(f"  [RULE] temper-{skill_dir.name}.mdc")

    # --- 4. Generate rules from packs ---
    packs_dir = repo_root / ".claude" / "packs"
    if packs_dir.exists():
        for pack_dir in sorted(packs_dir.iterdir()):
            if pack_dir.is_dir() and pack_dir.name != "stacks":
                rules_file = pack_dir / "rules.md"
                if rules_file.exists():
                    content = rules_file.read_text(encoding="utf-8")
                    mdc_content = generate_cursor_rules_mdc(
                        f"temper-pack-{pack_dir.name}",
                        content,
                        f"Temper quality pack: {pack_dir.name}"
                    )
                    out_path = output_dir / "rules" / f"temper-pack-{pack_dir.name}.mdc"
                    out_path.write_text(mdc_content, encoding="utf-8")

    # --- 5. Generate rules from reference docs ---
    ref_dir = repo_root / ".claude-plugin" / "reference"
    if ref_dir.exists():
        for ref_file in sorted(ref_dir.glob("*.md")):
            content = ref_file.read_text(encoding="utf-8")
            mdc_content = generate_cursor_rules_mdc(
                f"temper-ref-{ref_file.stem}",
                content,
                f"Temper reference: {ref_file.stem}"
            )
            out_path = output_dir / "rules" / f"temper-ref-{ref_file.stem}.mdc"
            out_path.write_text(mdc_content, encoding="utf-8")
            print(f"  [REF]  temper-ref-{ref_file.stem}.mdc")

    # --- 6. Generate MCP config template ---
    mcp_config = {
        "mcpServers": {}
    }
    mcp_file = output_dir / "mcp.json"
    mcp_file.write_text(json.dumps(mcp_config, indent=2) + "\n", encoding="utf-8")
    print(f"  [MCP]  mcp.json (template)")

    print()
    print(f"Done. Generated Cursor IDE files in {output_dir}/")
    print(f"Version: {version}")


if __name__ == "__main__":
    main()
