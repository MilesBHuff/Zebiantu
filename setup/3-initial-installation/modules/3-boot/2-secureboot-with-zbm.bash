#!/usr/bin/env bash

## Set up SecureBoot
SBDIR='/etc/secureboot'
if efi-readvar -v PK | grep -q 'No PK present'; then

    ## Install dependencies
    echo ':: Installing SecureBoot dependencies...'
    apt install -y sbsigntool efitools openssl

    ## Set variables
    echo ':: Setting variables...'
    declare -a CERTS=('PK' 'KEK' 'db')
    declare -i SB_TTL_DAYS=7305 ## 20 years — comfortably longer than the maximum lifespan of any given machine, which ensures we never just randomly get locked-out of the system because some key expired.
    ## The Linux kernel supports modules using RSA-* (4096 by default), NIST P-384, SHA-{256,384,512}. (https://docs.kernel.org/admin-guide/module-signing.html).
    ## SecureBoot supports RSA-{2048,3072,4096}, NIST P-{256,384}, SHA-{256,384}. (https://uefi.org/specs/UEFI/2.10/32_Secure_Boot_and_Driver_Signing.html)
    ##     (In practice, though, not every SecureBoot implementation supports all of the possible algorithms.)
    ## We are using the same keys to handle both scenarios, so we are restricted to using only those algorithms which are supported by both the kernel and by SecureBoot.
    ## The overlapping algorithms are RSA-{2048,3072,4096}, NIST P-384, SHA-{256,384}.
    ##
    ## In terms of effective security, not one of the above algorithms will be crackable this century, which means they all provide identical lifetime security, which means:
    ## * We can mix-and-match keys to digests freely without worrying about weakening the overall model.
    ## * We should choose the smallest supported numbers, as they require the least amount of space and time.
    ## That whittles our effective options to just two:
    ## A. NIST P-384 + SHA-256 (best performance)
    ## B. RSA-2048 + SHA-256 (most compatibility)
    SB_ALGORITHM_CLASS='performance'
    declare -a SB_ALGORITHM_PARAMS=()
    SB_DIGEST_PARAM=''
    case "$SB_ALGORITHM_CLASS" in
        performance)
            SB_ALGORITHM_PARAMS=(
                -algorithm EC
                -pkeyopt ec_paramgen_curve:prime384v1
                -pkeyopt ec_param_enc:named_curve
            )
            SB_DIGEST_PARAM='-sha256'
            ;;
        compatibility)
            SB_ALGORITHM_PARAMS=(
                -algorithm RSA
                -pkeyopt rsa_keygen_bits:2048
            )
            SB_DIGEST_PARAM='-sha256'
            ;;
        *) exit 10
    esac
    unset SB_ALGORITHM_CLASS

    ## Create the directories
    echo ':: Creating directories...'
    install -m 755 -d "$SBDIR"
    cd "$SBDIR"
    install -m 755 -d 'auth' 'crt' 'csr' 'esl' 'uuid'
    install -m 700 -d 'key'

    ## Generate the keys.
    echo ':: Generating SecureBoot keys...'
    for CERT in "${CERTS[@]}"; do
        openssl genpkey "${SB_ALGORITHM_PARAMS[@]}" -out "key/$CERT.key"
    done
    unset SB_ALGORITHM_PARAMS

    ## Generate the certificates
    echo ':: Generating SecureBoot certificates...'
    ## PK
    openssl req -new -x509 \
        -key 'key/PK.key' \
        -out 'crt/PK.crt' \
        -subj '/CN=PK/' \
        -addext 'subjectAltName=URI:urn:secureboot:PK' \
        -addext 'authorityKeyIdentifier=keyid:always' \
        -addext 'subjectKeyIdentifier=hash' \
        -addext 'basicConstraints=critical,CA:TRUE,pathlen:1' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' \
        -days $SB_TTL_DAYS \
        "$SB_DIGEST_PARAM"
    ## KEK
    openssl req -new \
        -key  'key/KEK.key' \
        -out  'csr/KEK.csr' \
        -subj '/CN=KEK/'
    openssl x509 -req \
        -in    'csr/KEK.csr' \
        -out   'crt/KEK.crt' \
        -CA    'crt/PK.crt'  \
        -CAkey 'key/PK.key'  \
        -set_serial 0x$(openssl rand -hex 16) \
        -addext 'subjectAltName=URI:urn:secureboot:KEK' \
        -addext 'authorityKeyIdentifier=keyid,issuer:always' \
        -addext 'subjectKeyIdentifier=hash' \
        -addext 'basicConstraints=critical,CA:TRUE,pathlen:0' \
        -addext 'keyUsage=critical,digitalSignature,keyCertSign,cRLSign' \
        -days $SB_TTL_DAYS \
        "$SB_DIGEST_PARAM"
    ## db
    openssl req -new \
        -key  'key/db.key' \
        -out  'csr/db.csr' \
        -subj '/CN=db/'
    openssl x509 -req \
        -in    'csr/db.csr'  \
        -out   'crt/db.crt'  \
        -CA    'crt/KEK.crt' \
        -CAkey 'key/KEK.key' \
        -set_serial 0x$(openssl rand -hex 16) \
        -addext 'subjectAltName=URI:urn:secureboot:db' \
        -addext 'authorityKeyIdentifier=keyid,issuer:always' \
        -addext 'subjectKeyIdentifier=hash' \
        -addext 'basicConstraints=critical,CA:FALSE' \
        -addext 'keyUsage=critical,digitalSignature' \
        -addext 'extendedKeyUsage=codeSigning' \
        -days $SB_TTL_DAYS \
        "$SB_DIGEST_PARAM"
    ## Verify
    openssl verify 'crt/db.crt' \
        -CAfile    'crt/PK.crt' \
        -untrusted 'crt/KEK.crt'
    ## Cleanup
    unset SB_TTL_DAYS SB_DIGEST_PARAM

    ## Send to UEFI
    echo ':: Configuring SecureBoot...'
    for CERT in "${CERTS[@]}"; do
        uuidgen > "uuid/$CERT.uuid"
        cert-to-efi-sig-list -g "$(cat "uuid/$CERT.uuid")" "crt/$CERT.crt" "esl/$CERT.esl"
    done
    sign-efi-sig-list -k "key/PK.key"  -c "crt/PK.crt"  PK  "esl/PK.esl"  "auth/PK.auth"
    sign-efi-sig-list -k "key/PK.key"  -c "crt/PK.crt"  KEK "esl/KEK.esl" "auth/KEK.auth"
    sign-efi-sig-list -k "key/KEK.key" -c "crt/KEK.crt" db  "esl/db.esl"  "auth/db.auth"
    chmod 0644 "uuid/"* "crt/"* "esl/"* "auth/"*

    ## Enroll the keys
    echo ':: Enrolling SecureBoot keys...'
    test -d /sys/firmware/efi && echo "UEFI OK" || echo "UEFI NOT OKAY"
    for CERT in "${CERTS[@]}"; do
        efi-updatevar -f "esl/$CERT.esl" "$CERT"
        efi-readvar -v "$CERT"
    done
    unset CERTS
    echo "INFO: To update your BIOS's SecureBoot database, you will have to append to the 'DB.esl' file, sign it as a 'DB.auth' file, and run \`efi-updatevar -f $SBDIR/auth/db.auth db\`."
    cd "$CWD"
else
    echo ':: Setting up SecureBoot...'
    echo "WARN: SecureBoot not in Setup Mode; may be unable to proceed."
fi

## Add support for SecureBoot to DKMS
echo ':: Configuring DKMS for SecureBoot...'
## Checking module signatures helps protect against the following: evil maid, root hack persistence, poisoned upstream package.
## #1 is eliminated by not storing the kernel in unencrypted /boot.
## #2 is, largely, too little too late — they already have root! And to get this kind of protection, I'd have to store the private key off-system, which would kill automation.
## #3 is *virtually* eliminated by package integrity checks, and it requires using upstream signatures (which I'm explicitly not doing).
## Accordingly, in this situation, there is no meaningful benefit to enforcing module signatures.
## But we might as well do so anyway.
## It's worth noting that, for this to work, the kernel must be built accepting `.platform` (UEFI-provided) keys. This is almost all kernels.
KERNEL_COMMANDLINE="$KERNEL_COMMANDLINE module.sig_enforce=1"
cat > /usr/local/sbin/dkms-sign-file <<'EOF'; chmod +x '/usr/local/sbin/dkms-sign-file'
#!/bin/sh
set -euo pipefail
SIGN_FILE=$(ls -1 /usr/lib/linux-kbuild-*/scripts/sign-file 2>/dev/null | sort -V | tail -n 1)
[ -x "$SIGN_FILE" ] || exit 1
exec "$SIGN_FILE" "$@"
EOF
FWCONF='/etc/dkms/framework.conf'
idempotent_append 'sign_tool="/usr/local/sbin/dkms-sign-file"' "$FWCONF"
idempotent_append "private_key=\"$SBDIR/key/db.key\"" "$FWCONF"
idempotent_append "public_key=\"$SBDIR/crt/db.crt\"" "$FWCONF"
unset FWCONF
dkms autoinstall --force
modinfo zfs | grep -E 'signer|sig_key|sig_hashalgo'

## Make ZBM work with SecureBoot
echo ':: Configuring ZBM for SecureBoot...'
cat > /etc/zfsbootmenu/generate-zbm.post.d/98-sign-efi.sh <<EOF ; chmod +x '/etc/zfsbootmenu/generate-zbm.post.d/98-sign-efi.sh'
#!/bin/sh
set -e
KEY_FILE=$SBDIR/key/db.key
CRT_FILE=$SBDIR/crt/db.crt
EFI_DIR=$ZBM_EFI_DIR
[ -s "\$KEY_FILE" -a -s "\$CRT_FILE" ] || exit 1
openssl pkey -in "\$KEY_FILE" -check -noout >/dev/null 2>&1 || exit 2
for EFI_FILE in "\$EFI_DIR"/*.EFI; do
    [ -s "\$EFI_FILE" ] || continue
    sbsign --output "\$EFI_FILE.signed" --key "\$KEY_FILE" --cert "\$CRT_FILE" "\$EFI_FILE" &&\\
    mv -f "\$EFI_FILE.signed" "\$EFI_FILE"
done
EOF
generate-zbm
sbverify --list /boot/esp/EFI/ZBM/*.EFI
sbverify --list /boot/esp/EFI/BOOT/BOOTX64.EFI

## Cleanup
unset SBDIR ZBM_EFI_DIR
