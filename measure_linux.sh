

set -euo pipefail



# Точка монтирования SYSVOL для замера T_SYSVOL
SYSVOL_MOUNT="/tmp/sysvol_probe_$$"
mkdir -p "$SYSVOL_MOUNT"

cleanup() {
    umount "$SYSVOL_MOUNT" 2>/dev/null || true
    rmdir "$SYSVOL_MOUNT" 2>/dev/null || true
}
trap cleanup EXIT

echo "DC_IP=$DC_IP | SYSVOL=$SYSVOL_PATH | DOMAIN=$DOMAIN | N=$N_RUNS"
echo "Результаты → $RESULTS_FILE"
echo ""
echo "run,T_total_ms,T_LDAP_ms,T_SYSVOL_ms,T_CSE_ms" | tee "$RESULTS_FILE"

for i in $(seq 1 "$N_RUNS"); do


    ldap_start=$(date +%s%3N)
    ldapsearch \
        -H "ldap://${DC_IP}" \
        -Y GSSAPI \
        -b "dc=${DOMAIN//./ dc=}" \
        "(objectClass=groupPolicyContainer)" \
        distinguishedName displayName gPCFileSysPath \
        > /dev/null 2>&1
    ldap_end=$(date +%s%3N)
    T_LDAP=$(( ldap_end - ldap_start ))




    mount -t cifs "$SYSVOL_PATH" "$SYSVOL_MOUNT" \
        -o sec=krb5,cruid="$(id -u)",ro 2>/dev/null || true

    sysvol_start=$(date +%s%3N)
    ls "$SYSVOL_MOUNT/$DOMAIN/Policies/" > /dev/null 2>&1 || true
    sysvol_end=$(date +%s%3N)
    T_SYSVOL=$(( sysvol_end - sysvol_start ))

    umount "$SYSVOL_MOUNT" 2>/dev/null || true

    total_start=$(date +%s%3N)
    gpupdate > /dev/null 2>&1
    total_end=$(date +%s%3N)
    T_total=$(( total_end - total_start ))


    T_CSE=$(( T_total - T_LDAP - T_SYSVOL ))

    [ "$T_CSE" -lt 0 ] && T_CSE=0

    echo "run $i: total=${T_total}ms  LDAP=${T_LDAP}ms  SYSVOL=${T_SYSVOL}ms  CSE=${T_CSE}ms"
    echo "$i,$T_total,$T_LDAP,$T_SYSVOL,$T_CSE" >> "$RESULTS_FILE"

    sleep 2
done

echo ""
echo "=== Готово. Результаты сохранены в $RESULTS_FILE ==="
echo "Первый замер (строка run=1) рекомендуется исключить как 'холодный старт'."
