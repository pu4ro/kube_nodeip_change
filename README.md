# kube-ip-change

> Kubernetes 마이그레이션/진단 시 사용 가능한 IP 자동 치환 및 진단 Shell Script

## 소개

이 스크립트는 Kubernetes 마스터/컨트롤플레인의 내부 IP, kube-vip, hosts, 인증서, manifest 등 다양한 위치의 IP를 일괄 변경하고,
실제 시스템 파일에 남아있는 모든 IP도 자동으로 검색/진단할 수 있도록 설계되었습니다.

* 주요 파일 및 설정의 IP 치환
* 인증서 SAN(SUBJECT ALT NAME) 자동 추가/재생성
* kubeadm 인증서 재갱신, 서비스 재시작
* `/etc/kubernetes` 하위 모든 파일에서 IP 목록 추출
* 단계별 실행 및 **중간 단계부터 재실행 지원**

## 주요 기능

* `/etc/kubernetes/` 및 관련 hosts, manifest 파일의 IP 치환
* kubeadm 인증서 SAN 변경 및 재발급
* kube-vip.yaml 자동 관리
* kubelet, containerd 자동 재시작
* 파일 내 모든 IP 자동 추출
* 함수 기반 **단계별 실행**
  (예: 6번부터 실행: `./ip_change.sh 6`)

## 사용법

### 1. 환경 변수 파일 작성

`kubeip.env` 파일을 아래와 같이 작성합니다.

```bash
OLD_IP=192.168.135.81
NEW_IP=192.168.135.83
ADDITIONAL_IPS=1.2.3.4,5.6.7.8
OLD_KUBEVIP=192.168.135.100
NEW_KUBEVIP=192.168.135.200
OLD_KUBEVIP_SVC_IP=10.96.0.100
NEW_KUBEVIP_SVC_IP=10.96.0.200
```

### 2. 스크립트 사용법

```bash
chmod +x ip_change.sh
./ip_change.sh         # 전체 단계 실행
./ip_change.sh 6       # 6번(인증서 재갱신)부터 실행
./ip_change.sh 11      # 11번(전체 파일 내 IP 추출)만 실행
```

> **TIP:** 반드시 `kubeip.env` 파일과 함께 사용하세요.

### 3. 단계별 실행 기능

| 단계 | 함수명                                | 설명                              |
| -- | ---------------------------------- | ------------------------------- |
| 1  | step1\_kube\_vip\_manifest\_change | kube-vip.yaml IP 변경             |
| 2  | step2\_kube\_manifests\_ip\_change | /etc/kubernetes 전체 IP 치환        |
| 3  | step3\_certs\_extra\_sans          | 인증서 SAN 자동 생성                   |
| 4  | step4\_certs\_change               | apiserver/etcd 인증서 삭제/재생성       |
| 5  | step5\_etc\_hosts\_change          | /etc/hosts 및 kubevip host 변경    |
| 6  | step6\_kubeadm\_certs\_renew       | kubeadm certs renew all         |
| 7  | step7\_restart\_services           | kubelet, containerd 재시작         |
| 8  | step8\_manifests\_vip\_change      | manifests 내 kubevip IP 변경       |
| 9  | step9\_kubelet\_conf\_change       | kubelet.conf 내 IP 치환            |
| 10 | step10\_warn\_message              | coredns/istio IP 수동 수정 안내       |
| 11 | step11\_find\_all\_ips             | /etc/kubernetes 내 모든 파일에서 IP 추출 |

### 4. 전체 IP 진단만 빠르게 하고 싶다면

```bash
./ip_change.sh 11
```

### 5. 코드 예시 (핵심 부분)

```bash
declare -a STEP_FUNCS=(
    step1_kube_vip_manifest_change
    step2_kube_manifests_ip_change
    ...
    step11_find_all_ips
)

START_STEP=${1:-1}

for ((i=START_STEP-1; i<${#STEP_FUNCS[@]}; i++)); do
    ${STEP_FUNCS[$i]}
done
```

## 주의 사항

* 실서버 반영 전 **반드시 백업** 및 테스트 환경에서 먼저 실행하세요.
* 추가로 coredns, istio 등 클러스터 서비스 리소스는 수동 변경 필요할 수 있습니다.
* 각 함수별 동작은 서버/설정에 따라 다를 수 있습니다.

