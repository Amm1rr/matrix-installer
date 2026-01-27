# Matrix Installer User Guide

Welcome to Matrix Installer. This guide will walk you through everything you need to know to set up your own Matrix homeserver using this system.

## What is Matrix Installer?

Matrix Installer is a tool that makes it easier to install Matrix homeservers by handling the complicated parts—specifically, managing SSL certificates so your servers can talk to each other securely. It uses a modular system called "addons," so you can choose how you want to install Matrix.

Think of it this way: Matrix Installer is like a project manager that coordinates everything, and the addons are the specialists who do the actual work.

## The Basic Idea

Here's how it works:

1. **First**, you create a Root Key (Certificate Authority)—this is like being your own certificate company
2. **Then**, you create certificates for each server you want to run
3. **Finally**, you pick an addon to handle the actual installation

The beauty of this approach is that when you use the same Root Key for multiple servers, they can automatically trust each other and communicate securely—this is called "federation."

## How It Works

Matrix Installer adapts based on what's available:

| What You Have | What It Does |
|---------------|--------------|
| **Just the script** (`matrix-installer.sh` alone) | Creates Root Keys and server certificates—you manage installation manually |
| **With `addons/` folder** | Same as above, plus displays addons in menu for one-click installation |
| **With Root Key files next to script** (`*.key` + `*.crt`) | Prompts to import your existing Root Key, then creates certificates under it |

**Key point**: The script works perfectly with just itself—you only need what's relevant for your use case.

## Getting Started

### Step 1: Run the Script

Open your terminal and navigate to where you have Matrix Installer:

```bash
cd /path/to/matrix-second/script
./matrix-installer.sh
```

You'll see a welcome banner and the main menu.

### Step 2: Your First Time - Create a Root Key

If this is your first time, you won't have a Root Key yet. The menu will look simple:

```
Root Key: Not Available

  1) Generate new Root Key
  2) Exit
```

Choose option 1. You'll be asked for some information about your Root Key:

- **Organization**: A name for your organization (like "MatrixCA" or your company name)
- **Country**: A two-letter country code (like "IR" for Iran, "US" for United States)
- **State/Province**: Your state or province
- **City**: Your city
- **Validity**: How long the Root Key should be valid (default is 10 years)

Most of these have defaults you can accept by just pressing Enter. The important one is the organization name—pick something memorable.

Once created, you'll see confirmation with the file locations. Keep these files safe! They're the keys to your entire Matrix federation.

### Step 3: Generate a Server Certificate

Now that you have a Root Key, the menu expands. You'll see:

```
Root Key: Available
  | Subject: Matrix Root Key
  | Expires: 2034-01-25 (in 3650 days)
  | Country: UK

  1) Generate server certificate

  2) Install Docker Synapse (Let's Encrypt)
  3) Install Docker Synapse (Private Key)
  4) Install Zanjir Synapse (Private Key+Dendrite)
  5) Install Synapse by Ansible (Private Key)


  ---------------------------
  S) Switch active Root Key (MatrixUK)
  N) Create new Root Key
  0) Exit
```

The middle section shows available addons—this list will grow if you add more addons to the `addons/` folder.

Choose option 1 to create a server certificate. The script will try to detect your server's IP address automatically. You can:

- Accept the detected IP
- Type a different IP address
- Type a domain name if you have one

After confirming, the script generates:
- A private key for your server
- A certificate signed by your Root Key
- A full-chain file that includes both

These files are stored in `certs/<your-server-ip-or-domain>/` so you can have certificates for multiple servers.

### Step 4: Install Matrix with an Addon

Now go back to the main menu (it returns automatically after creating a certificate). Choose the addon you want to use. Let's say you pick `Install Zanjir Synapse` (option 4):

The addon will take over from here. It already knows where your certificates are because Matrix Installer passes that information to it automatically. The addon will:

1. Check that you have the necessary tools (Ansible, Docker, etc.)
2. Ask you a few questions about how you want to install
3. Do the actual installation

Each addon is different, but they all follow this same pattern of getting the certificate information from Matrix Installer.

## Using an Existing Root Key

If you already have a Root Key from another Matrix Installer installation (or you created one separately), you can reuse it. Just place `rootCA.key` and `rootCA.crt` in the same directory as `matrix-installer.sh` before running it.

When you start the script, you'll see:

```
[INFO] Root Key found at: /path/to/script
Use this Root Key for Matrix Installer? [y/N]:
```

Type `y` to use it. This is useful when:
- You're setting up multiple servers that need to federate
- You want to keep your Root Key in a central, secure location
- You're moving to a new machine but want to use the same certificates

## Working with Multiple Servers

One of the powerful features of Matrix Installer is managing certificates for multiple servers. Each server gets its own folder in `certs/`:

```
certs/
├── rootCA.key          # Your master private key
├── rootCA.crt          # Your master certificate
├── 192.168.1.100/      # First server's certificates
│   ├── server.key
│   ├── server.crt
│   └── cert-full-chain.pem
├── 192.168.1.101/      # Second server's certificates
│   ├── server.key
│   ├── server.crt
│   └── cert-full-chain.pem
└── matrix.example.com/ # Domain-based server
    ├── server.key
    ├── server.crt
    └── cert-full-chain.pem
```

When you run an addon, it will ask which server you want to install to (if you have multiple), or use the only one available if there's just a single certificate.

## Understanding the Addons

Addons are the actual installation methods. Here's what you'll typically find:

- **Ansible synapse**: Uses the official Matrix Docker Ansible Deploy playbook. This is the most full-featured option and works with the official upstream project.

- **Docker synapse**: A simpler Docker Compose setup. Good if you prefer straightforward Docker Compose files over Ansible.

- **Private Key Docker Synapse**: Similar to Docker Compose-synapse but specifically designed for private Root Key setups.

- **Zanjir Synapse**: Uses the [Zanjir project](https://github.com/MatinSenPai/Zanjir/) with Federation support.

The great thing about this system is that anyone can write an addon. If you have a specific way you want to install Matrix, you can create your own addon and drop it in the `addons/` folder—Matrix Installer will automatically find it and add it to the menu.

## After Installation

Once your addon finishes, you should have a working Matrix homeserver. Here's what you typically need to do next:

### Access Your Server

Open a web browser and go to:
- `https://<your-server-ip>/` or `https://<your-domain>/`

The first time, you'll get a security warning because you're using self-signed certificates. This is normal and expected. You can:
- Proceed anyway (you'll need to do this each time)
- Import the Root Key certificate into your browser to permanently trust it

To import the Root Key permanently:
- **Chrome/Edge**: Go to Settings → Privacy and security → Security → Manage certificates → Authorities → Import
- **Firefox**: Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import

The Root Key file is at `certs/rootCA.crt`.

### Log In

When Element Web loads, you can create your account or log in with the admin account that was created during installation (the addon should have provided you with the username and password).

## Common Questions

### Which addon should I use?

For most people, **Docker Synapse** is the best choice. It's based on the official upstream project, has the most features, and is well-maintained. The other options exist for specific use cases or preferences.

### Do I need a domain name?

No, you can use an IP address. This is actually one of the main benefits of Matrix Installer—it's designed to work perfectly with IP addresses for private network setups. If you do have a domain, the system works with that too.

### Is this secure?

Yes, provided you:
- Keep your `rootCA.key` file safe and private
- Don't share it with anyone who shouldn't have it
- Use strong passwords for your admin accounts
- Keep your server updated

The certificates Matrix Installer generates are just as secure as ones from a commercial certificate authority—they're just not trusted by default in web browsers, which is why you get the security warning.

### Can I change my certificates later?

Yes. If you need to regenerate a server certificate, just run `matrix-installer.sh` again and choose to generate a new certificate for that server. The old one will be replaced. If you need to create a new Root Key entirely, choose option NEW ROOT KEY from the main menu (but be aware this will require updating all your servers).

### What happens if something goes wrong?

Check the log files:
- `matrix-installer.log` - The main script log
- `docker-synapse.log` - The Docker Synapse addon log (if using that addon)

These files contain detailed information about what happened and can help identify issues.

## Tips for a Smooth Experience

1. **Start fresh**: If you've tried installing Matrix before and it didn't work, clean up any old Docker containers or configuration files before starting.

2. **Take notes**: Write down your passwords, server addresses, and any choices you make during installation.

3. **Test federation**: Once you have two servers set up with the same Root Key, try creating a room on one and joining it from the other to verify federation is working.

4. **Backup your Root Key**: Keep a safe copy of `rootCA.key` and `rootCA.crt` in a secure location. Without these, you can't create new certificates for your federation.

## Getting Help

If you run into issues:

1. Check the log files mentioned above
2. Review the [Federation Troubleshooting Guide](FEDERATION_TROUBLESHOOTING.md) for federation-specific issues
3. Look at the [Root Key Workflow](ROOT_KEY_WORKFLOW.md) for more details on certificate management
4. Check the addon-specific documentation if available

---

Matrix Installer is designed to make Matrix server installation approachable while still giving you full control over your infrastructure. Take it step by step, and don't hesitate to experiment—that's what the sandbox is for.
