# Manual SSL Certificate Management

This guide walks you through exactly what `main.sh` does behind the scenes when it creates and manages SSL certificates. Understanding this helps you troubleshoot issues, customize your setup, or do everything manually if you prefer.

## Why This Matters

Matrix federation between servers requires SSL/TLS certificates. Normally, you'd use a service like Let's Encrypt to get these certificates automatically. But what if you don't have a domain name? Or you're on a private network? Or you want full control over your certificate infrastructure?

That's where having your own Certificate Authority (CA) comes in. You become your own little certificate company, issuing certificates that all your servers trust. This is exactly what Matrix Installer does for you.

## The Big Picture

Here's the hierarchy:

```
Root Key (your certificate authority)
    └── Server Certificate (for server1)
    └── Server Certificate (for server2)
    └── Server Certificate (for server3)
```

The Root Key signs each server certificate. When servers need to talk to each other, they verify that the certificate was signed by a CA they trust (yours).

## Directory Structure

All certificates live in the `certs/` directory:

```
certs/
├── rootCA.key              # Root Key private key (VERY IMPORTANT - keep safe!)
├── rootCA.crt              # Root Key certificate (share this)
├── rootCA.srl              # Serial number file (auto-generated)
│
├── 192.168.1.100/          # Server 1 certificates
│   ├── server.key          # Private key for this server
│   ├── server.crt          # Public certificate for this server
│   └── cert-full-chain.pem # server.crt + rootCA.crt combined
│
└── 192.168.1.101/          # Server 2 certificates
    ├── server.key
    ├── server.crt
    └── cert-full-chain.pem
```

## Step 1: Creating a Root Key

The Root Key is the foundation. Everything else builds on this.

### What You're Doing

You're creating a certificate that identifies *you* as a trusted certificate authority. This certificate will be used to sign all your server certificates.

### The Commands

```bash
# Navigate to your certs directory
cd /path/to/script/certs

# Generate a 4096-bit RSA private key
openssl genrsa -out rootCA.key 4096

# Set restrictive permissions (only you can read it)
chmod 600 rootCA.key

# Create the Root Key certificate (valid for 10 years)
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 \
  -subj "/C=IR/ST=Tehran/L=Tehran/O=MatrixCA/OU=IT/CN=Matrix Root Key" \
  -out rootCA.crt

# Make the certificate readable
chmod 644 rootCA.crt
```

### Understanding the Parameters

- **4096**: The key size in bits. Larger = more secure but slower. 4096 is a good balance.
- **3650**: How many days the certificate is valid (10 years).
- **-subj**: The certificate subject. Replace with your own values:
  - `C`: Country code (two letters)
  - `ST`: State or province
  - `L`: City or locality
  - `O`: Organization name
  - `OU`: Organizational unit (like "IT" or "Security")
  - `CN`: Common name (the CA's name)

### Verifying Your Root Key

```bash
# Check the certificate details
openssl x509 -in rootCA.crt -noout -text

# Check the expiration date
openssl x509 -in rootCA.crt -noout -dates

# Verify the certificate matches the key
openssl x509 -in rootCA.crt -noout -modulus | openssl md5
openssl rsa -in rootCA.key -noout -modulus | openssl md5
```

The last two commands should output the same hash, proving the certificate and key match.

## Step 2: Creating a Server Certificate

Now you'll create a certificate for one of your servers.

### What You're Doing

You're generating a certificate specifically for one server, signed by your Root Key. This certificate will include the server's IP address or domain name so other servers can verify they're talking to the right place.

### The Commands

```bash
# Navigate to your certs directory
cd /path/to/script/certs

# Create a directory for this server
mkdir 192.168.1.100
cd 192.168.1.100

# Generate a private key for this server
openssl genrsa -out server.key 4096
chmod 600 server.key

# Create an OpenSSL configuration file for the certificate
cat > openssl.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = IR
ST = Tehran
L = Tehran
O = Matrix
OU = Server
CN = 192.168.1.100

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = matrix.local
DNS.2 = localhost
IP.1 = 192.168.1.100
IP.2 = 127.0.0.1
EOF

# Generate a certificate signing request (CSR)
openssl req -new -key server.key -out server.csr -config openssl.cnf

# Sign the CSR with your Root Key
openssl x509 -req -in server.csr \
  -CA ../rootCA.crt -CAkey ../rootCA.key \
  -CAcreateserial -out server.crt \
  -days 365 -sha256 \
  -extensions v3_req -extfile openssl.cnf

# Create the full chain certificate
cat server.crt ../rootCA.crt > cert-full-chain.pem

# Clean up temporary files
rm server.csr openssl.cnf

# Set proper permissions
chmod 644 server.crt cert-full-chain.pem
```

### Understanding the Subject Alternative Names (SAN)

The `[alt_names]` section is crucial. It tells clients what names and IP addresses this certificate is valid for:

- **DNS.1 = matrix.local**: A local hostname that works on any network
- **DNS.2 = localhost**: For local testing
- **IP.1 = 192.168.1.100**: Your actual server IP
- **IP.2 = 127.0.0.1**: Local loopback

You can add more entries if needed—just increment the numbers (DNS.3, IP.3, etc.).

For domain-based certificates, you'd do:

```bash
[alt_names]
DNS.1 = matrix.example.com
DNS.2 = server.example.com
DNS.3 = matrix.local
DNS.4 = localhost
```

### Verifying the Server Certificate

```bash
# Check the certificate details
openssl x509 -in server.crt -noout -text

# Verify the certificate chain
openssl verify -CAfile ../rootCA.crt server.crt

# Check what the certificate is valid for
openssl x509 -in server.crt -noout | grep -A1 "Subject Alternative Name"
```

## Step 3: Using Certificates in Matrix

Now that you have certificates, here's how they're used:

### In the Ansible Playbook

When using `ansible-synapse`, the playbook copies your certificates to the server:

```yaml
# From vars.yml
aux_file_definitions:
  - dest: "{{ traefik_ssl_dir_path }}/privkey.pem"
    src: /path/to/certs/192.168.1.100/server.key
    mode: "0600"

  - dest: "{{ traefik_ssl_dir_path }}/cert.pem"
    src: /path/to/certs/192.168.1.100/cert-full-chain.pem
    mode: "0644"
```

Traefik (the reverse proxy) then uses these files to terminate SSL connections.

### Installing the Root Key on Servers

For federation to work properly, each server needs to trust your Root Key. The ansible-synapse addon does this automatically:

```bash
# On Debian/Ubuntu systems
sudo cp rootCA.crt /usr/local/share/ca-certificates/matrix-root-ca.crt
sudo update-ca-certificates

# On Arch/Manjaro systems
sudo cp rootCA.crt /etc/ca-certificates/trust-source/anchors/matrix-root-ca.crt
sudo trust extract-compat
```

This tells the operating system to trust any certificate signed by your Root Key.

## Understanding Certificate Expiration

Certificates don't last forever. Here's the timeline:

- **Root Key**: Valid for 10 years (3650 days)
- **Server Certificates**: Valid for 1 year (365 days)

### Checking Expiration

```bash
# Check Root Key expiration
openssl x509 -in certs/rootCA.crt -noout -enddate

# Check server certificate expiration
openssl x509 -in certs/192.168.1.100/server.crt -noout -enddate
```

### Renewing a Server Certificate

When a server certificate expires, regenerate it:

```bash
cd certs/192.168.1.100

# Generate a new CSR (you can reuse the existing key)
openssl req -new -key server.key -out server.csr -config openssl.cnf

# Sign it with your Root Key
openssl x509 -req -in server.csr \
  -CA ../rootCA.crt -CAkey ../rootCA.key \
  -CAcreateserial -out server.crt \
  -days 365 -sha256 \
  -extensions v3_req -extfile openssl.cnf

# Recreate the full chain
cat server.crt ../rootCA.crt > cert-full-chain.pem
```

## Troubleshooting Certificate Issues

### Problem: "Certificate verify failed"

**Cause**: The server doesn't trust your Root Key.

**Solution**: Install the Root Key in the system trust store (see above).

### Problem: "Hostname mismatch"

**Cause**: The certificate doesn't include the hostname or IP you're using.

**Solution**: Check the SAN in your certificate:
```bash
openssl x509 -in server.crt -noout | grep -A1 "Subject Alternative Name"
```

If the name/IP you need isn't there, regenerate the certificate with the correct SAN entries.

### Problem: "Certificate expired"

**Cause**: The certificate has passed its expiration date.

**Solution**: Check the expiration date and renew if needed:
```bash
openssl x509 -in server.crt -noout -enddate
```

### Problem: Private key doesn't match certificate

**Cause**: The key and certificate files are from different pairs.

**Solution**: Verify they match:
```bash
# These should output the same hash
openssl x509 -in server.crt -noout -modulus | openssl md5
openssl rsa -in server.key -noout -modulus | openssl md5
```

If they don't match, you'll need to generate a new certificate-key pair.

## Security Best Practices

1. **Protect the Root Key key**: The `rootCA.key` file should never leave your control. Anyone with this file can issue certificates that your servers will trust.

2. **Use strong passphrases**: For production, consider adding a passphrase to your private keys (though this adds complexity to automation).

3. **Limit certificate validity**: Don't make certificates valid for longer than necessary. One year for server certificates is reasonable.

4. **Keep backups**: Store encrypted backups of your Root Key key and certificate in a secure location.

5. **Monitor expiration**: Set up reminders or monitoring to alert you before certificates expire.

6. **Revoke if compromised**: If a private key is ever compromised, you'll need to revoke the certificate (though a full PKI with revocation is beyond the scope of this guide).

## From Theory to Practice

Everything `main.sh` does in the SSL Manager is what you've just learned manually. The script automates these exact steps:

1. Creates the Root Key with the settings you provide
2. Generates server certificates with proper SAN entries
3. Combines certificates into full-chain files
4. Sets correct permissions on all files
5. Passes the certificate paths to addons for installation

Understanding these manual steps gives you full control. You can customize certificates, troubleshoot issues, or even build your own tools that work with the same certificate infrastructure.

---

**Next Steps**: Once you're comfortable with certificates, check out the [Addon Development Guide](ADDON_DEVELOPMENT_GUIDE.md) to learn how to create your own installation addons.
