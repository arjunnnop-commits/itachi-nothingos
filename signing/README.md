# Signing

This directory must never contain the private key.

Keep the private key outside the repository, for example:

```text
~/Downloads/ITACHI-DUCHAMP-AUTH/itachi_duchamp_private.pem
```

Use `../scripts/sign_itachi4.sh` to create a manifest/signature after both binaries are final.

A signature/public key may be published. The private key must not be.
