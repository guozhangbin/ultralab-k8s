# OpenSkills

Universal skills loader for AI coding agents - bring Claude Code skills to every agent.

## ✨ What Is OpenSkills?

OpenSkills brings Anthropic's skills system to every AI coding agent — Claude Code, Cursor, Windsurf, Aider, Codex, and anything that can read AGENTS.md.

Think of it as the universal installer for SKILL.md.

## 🚀 Quick Start

```bash
# Install default skills from Anthropic marketplace
npx openskills install anthropics/skills

# Sync skills to AGENTS.md
npx openskills sync

# List available skills
npx openskills list

# Read a skill
npx openskills read <skill-name>
```

## 📋 Features

- **Exact Claude Code compatibility** — same prompt format, same marketplace, same folder structure
- **Universal** — works with Claude Code, Cursor, Windsurf, Aider, Codex, and more
- **Progressive disclosure** — load skills only when needed (keeps context clean)
- **Repo-friendly** — skills live in your project and can be versioned
- **Private friendly** — install from local paths or private git repos

## 🛠️ Installation

### Prerequisites

- Node.js >= 18.0.0
- npm >= 8.0.0

### Install Node.js (if not already installed)

```bash
# For Linux (Debian/Ubuntu)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
sudo apt install -y nodejs

# For Linux (RHEL/CentOS)
sudo dnf install -y https://rpm.nodesource.com/pub_20.x/nodistro/repo/nodesource-release-nodistro-1.noarch.rpm
sudo dnf install -y nodejs --setopt=nodesource-nodejs.module_hotfixes=1

# For macOS
brew install node

# For Windows
# Download and install from https://nodejs.org/
```

### Verify Installation

```bash
node --version
npm --version
```

## 📚 Usage

### 1. Install Skills

#### From Anthropic Marketplace

```bash
npx openskills install anthropics/skills
```

#### From Any GitHub Repo

```bash
npx openskills install your-org/your-skills
```

#### From a Local Path

```bash
npx openskills install ./local-skills/my-skill
```

#### From Private Git Repos

```bash
npx openskills install git@github.com:your-org/private-skills.git
```

### 2. Sync Skills to AGENTS.md

```bash
# Default output: AGENTS.md
npx openskills sync

# Custom output path
npx openskills sync -o ./path/to/AGENTS.md

# Skip prompts
npx openskills sync -y
```

### 3. List Available Skills

```bash
npx openskills list
```

### 4. Read a Skill

```bash
npx openskills read <skill-name>

# Read multiple skills
npx openskills read skill-one,skill-two
```

### 5. Update Skills

```bash
# Update all skills
npx openskills update

# Update specific skills
npx openskills update pdf docx
```

### 6. Remove Skills

```bash
# Interactive removal
npx openskills manage

# Remove specific skill
npx openskills remove <skill-name>
```

## 🌍 Universal Mode (Multi-Agent Setups)

If you use Claude Code and other agents with one AGENTS.md, install to .agent/skills/ to avoid conflicts with Claude's plugin marketplace:

```bash
npx openskills install anthropics/skills --universal
```

### Priority Order (Highest Wins)

1. `./.agent/skills/`
2. `~/.agent/skills/`
3. `./.claude/skills/`
4. `~/.claude/skills/`

## 🧬 The SKILL.md Format

OpenSkills uses Anthropic's exact format:

```markdown
---
name: pdf
description: Comprehensive PDF manipulation toolkit for extracting text and tables, creating new PDFs, merging/splitting documents, and handling forms.
---

# PDF Skill Instructions

When the user asks you to work with PDFs, follow these steps:
1. Install dependencies: `pip install pypdf2`
2. Extract text using scripts/extract_text.py
3. Use references/api-docs.md for details
```

## 📁 Project Structure

```
./
├── AGENTS.md          # Generated skills index
├── .claude/
│   └── skills/        # Project-local skills
│       ├── pdf/
│       │   └── SKILL.md
│       └── docx/
│           └── SKILL.md
└── .agent/            # Universal mode skills
    └── skills/
```

## 🤖 Agent Integration

### For Agents That Can Read AGENTS.md

1. Ensure AGENTS.md is in your project root
2. Agents can now see the `<available_skills>` section
3. Use `npx openskills read <skill-name>` to load skills

### Example AGENTS.md Section

```xml
<skills_system priority="1">

## Available Skills

<!-- SKILLS_TABLE_START -->
<usage>
When users ask you to perform tasks, check if any of the available skills below can help complete the task more effectively. Skills provide specialized capabilities and domain knowledge.

How to use skills:
- Invoke: `npx openskills read <skill-name>` (run in your shell)
  - For multiple: `npx openskills read skill-one,skill-two`
- The skill content will load with detailed instructions on how to complete the task
- Base directory provided in output for resolving bundled resources (references/, scripts/, assets/)

Usage notes:
- Only use skills listed in <available_skills> below
- Do not invoke a skill that is already loaded in your context
- Each skill invocation is stateless
</usage>

<available_skills>

<skill>
<name>pdf</name>
<description>Comprehensive PDF manipulation toolkit for extracting text and tables, creating new PDFs, merging/splitting documents, and handling forms.</description>
<location>project</location>
</skill>

</available_skills>
<!-- SKILLS_TABLE_END -->

</skills_system>
```

## 📖 Command Reference

| Command | Description |
|---------|-------------|
| `npx openskills install <source> [options]` | Install from GitHub, local path, or private repo |
| `npx openskills sync [-y] [-o <path>]` | Update AGENTS.md (or custom output) |
| `npx openskills list` | Show installed skills |
| `npx openskills read <name>` | Load skill (for agents) |
| `npx openskills update [name...]` | Update installed skills (default: all) |
| `npx openskills manage` | Remove skills (interactive) |
| `npx openskills remove <name>` | Remove specific skill |

### Flags

| Flag | Description |
|------|-------------|
| `--global` | Install globally to ~/.claude/skills (default: project install) |
| `--universal` | Install to .agent/skills/ instead of .claude/skills/ |
| `-y, --yes` | Skip prompts (useful for CI) |
| `-o, --output <path>` | Output file for sync (default: AGENTS.md) |

## 🌟 Creating Your Own Skills

### Minimal Structure

```
my-skill/
└── SKILL.md
```

### With Resources

```
my-skill/
├── SKILL.md
├── references/
│   └── api-docs.md
├── scripts/
│   └── helper.py
└── assets/
    └── template.txt
```

### Install Your Custom Skill

```bash
npx openskills install ./my-skill
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Setup

```bash
# Clone the repo
git clone https://github.com/numman-ali/openskills.git
cd openskills

# Install dependencies
npm install

# Run tests
npm test

# Build
npm run build
```

## 📄 License

MIT License

## 🙏 Acknowledgements

- Inspired by Anthropic's Claude Code skills system
- Built with ❤️ for the AI developer community

## 📞 Support

- **GitHub Issues**: https://github.com/numman-ali/openskills/issues
- **Discord**: Join the OpenSkills community

---

Made with ❤️ by the OpenSkills team

*"Bringing skills to every agent, one SKILL.md at a time."*
