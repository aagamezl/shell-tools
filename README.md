# Shell Tools

A collection of lightweight, dependency-free tools written in pure Bash.  
The goal of this project is to provide simple yet practical utilities for development, automation, and learning purposes.  

Each tool is self-contained and designed to be:
- **Minimal** – no external dependencies beyond standard UNIX utilities.
- **Portable** – works across most Linux and macOS systems.
- **Educational** – demonstrates practical shell scripting techniques.

---

## 🚀 Available Tools

### 1. HTTP Server (experimental)
A minimal HTTP server implemented in Bash using `netcat`.  
Currently supports:
- Handling basic `GET` requests for static content
- Parsing the request method and path
- Returning the static file content in the response

> ⚠️ This is a teaching/demo tool — not intended for production use.

---

## 🛠 Roadmap
Planned tools and enhancements:
- File management utilities (copy, sync, backup helpers)
- Process monitoring
- Networking helpers (port scanners, simple proxies, port killer)
- Extended HTTP server features (static files, error handling)

---

## 📦 Installation
Clone the repository:

```bash
git clone https://github.com/<your-username>/shell-tools.git
cd shell-tools
