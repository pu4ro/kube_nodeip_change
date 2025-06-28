#!/bin/bash
set -e

# 환경 변수 파일 불러오기
source ./kubeip.env

if [ -f "$KUBEVIP_MANIFEST" ]; then
    echo "[INFO] kube-vip.yaml 파일을 $DEST_MANIFEST 로 이동합니다."
    mv "$KUBEVIP_MANIFEST" "$DEST_MANIFEST"
else
    echo "[INFO] $KUBEVIP_MANIFEST 파일이 없어 패스합니다."
fi

# 단계 1: kube-vip.yaml IP 변경
step1_kube_vip_manifest_change() {
    KUBEVIP_MANIFEST="/etc/kubernetes/manifests/kube-vip.yaml"
    if [ -f "$KUBEVIP_MANIFEST" ]; then
        echo "[INFO] kube-vip.yaml IP 변경 중..."
        sed -i "s/$OLD_KUBEVIP/$NEW_KUBEVIP/g" "$KUBEVIP_MANIFEST"
    else
        echo "[INFO] $KUBEVIP_MANIFEST 파일이 없어 패스합니다."
    fi
}

# 단계 2: kube manifests IP 변경
step2_kube_manifests_ip_change() {
    echo "[INFO] kube manifests IP 변경 중..."
    find /etc/kubernetes -type f -exec sed -i "s/$OLD_IP/$NEW_IP/g" {} +
}

# 단계 3: 인증서 SAN 준비
step3_certs_extra_sans() {
    EXTRA_SANS="10.96.0.1,master1,kubevip"
    if [[ -n "$ADDITIONAL_IPS" ]]; then
        EXTRA_SANS+=",$ADDITIONAL_IPS"
    fi
    export EXTRA_SANS
}

# 단계 4: 인증서 변경
step4_certs_change() {
    echo "[INFO] 인증서 갱신 중..."
    rm -rf /etc/kubernetes/pki/apiserver.* /etc/kubernetes/pki/etcd/peer.* /etc/kubernetes/pki/etcd/server.*
    kubeadm init phase certs apiserver --apiserver-cert-extra-sans=$EXTRA_SANS
    kubeadm init phase certs etcd-peer
    kubeadm init phase certs etcd-server
    sleep 5
}

# 단계 5: /etc/hosts 변경
step5_etc_hosts_change() {
    echo "[INFO] /etc/hosts 변경 중..."
    sed -i "s/$OLD_IP master1/$NEW_IP master1/g" /etc/hosts

    echo "[INFO] kubevip 관련 hosts 변경 중..."
    sed -i "s/$OLD_KUBEVIP kubevip/$NEW_KUBEVIP kubevip/g" /etc/hosts
    sed -i "s/$OLD_KUBEVIP/$NEW_KUBEVIP/g" /etc/hosts

    if [[ -n "$OLD_KUBEVIP_SVC_IP" && -n "$NEW_KUBEVIP_SVC_IP" ]]; then
        echo "[INFO] kubevip_svc_address 변경 중..."
        sed -i "s/$OLD_KUBEVIP_SVC_IP/$NEW_KUBEVIP_SVC_IP/g" /etc/hosts
    else
        echo "[INFO] kubevip_svc_address 치환 환경변수(OLD_KUBEVIP_SVC_IP, NEW_KUBEVIP_SVC_IP)가 없어서 패스합니다."
    fi
}

# 단계 6: kubeadm certs renew all
step6_kubeadm_certs_renew() {
    echo "[INFO] kubeadm 인증서 갱신 중..."
    kubeadm certs renew all
    sleep 5
}

# 단계 7: 서비스 재시작
step7_restart_services() {
    echo "[INFO] kubelet 및 containerd 서비스 재시작 중..."
    systemctl restart kubelet containerd
}

# 단계 8: kubevip 관련 설정 변경
step8_manifests_vip_change() {
    echo "[INFO] kubevip 관련 설정 변경 중..."
    find /etc/kubernetes/manifests -type f -exec sed -i "s/$OLD_KUBEVIP/$NEW_KUBEVIP/g" {} +
}

# 단계 9: kubelet.conf 변경
step9_kubelet_conf_change() {
    echo "[INFO] /etc/kubernetes/kubelet.conf IP 변경 중..."
    sed -i "s/$OLD_IP/$NEW_IP/g" /etc/kubernetes/kubelet.conf
}

# 단계 10: 추가 작업 알림
step10_warn_message() {
    echo "[WARNING] coredns ConfigMap IP 수정이 필요합니다."
    echo "[WARNING] istio Service LoadBalancer IP 수정이 필요합니다."
}

step11_find_all_ips() {
    echo "[INFO] /etc/kubernetes 내 모든 파일에서 IP 추출 중..."
    find /etc/kubernetes -type f -exec grep -EHn '([0-9]{1,3}\.){3}[0-9]{1,3}' {} +
}

# 단계 실행 배열
declare -a STEP_FUNCS=(
    step1_kube_vip_manifest_change
    step2_kube_manifests_ip_change
    step3_certs_extra_sans
    step4_certs_change
    step5_etc_hosts_change
    step6_kubeadm_certs_renew
    step7_restart_services
    step8_manifests_vip_change
    step9_kubelet_conf_change
    step10_warn_message
    step11_find_all_ips
)

# 실행 시작 단계(1부터 시작)
START_STEP=${1:-1}

for ((i=START_STEP-1; i<${#STEP_FUNCS[@]}; i++)); do
    ${STEP_FUNCS[$i]}
done

