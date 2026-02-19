# 🏗️ 온프레미스 마이크로서비스 인프라 및 GitOps 자동화 프로젝트  
### (Google Online Boutique 기반)

## 1. 프로젝트 개요

이 프로젝트는 **Google Online Boutique**(마이크로서비스 데모 애플리케이션)를 기반으로,  
온프레미스 환경에서 **Kubernetes + GitLab + Argo CD 기반 GitOps 배포 체계**를 구축하는 것을 목표로 합니다.

단순 배포에 그치지 않고, 아래와 같은 **실무형 운영 요소**까지 포함합니다.

- **사설 GitLab + Container Registry 운영**
- **kubeadm 기반 Kubernetes 클러스터 구성**
- **MetalLB + Ingress 기반 온프레미스 네트워크 게이트웨이**
- **Argo CD 기반 GitOps 자동 배포**
- **Prometheus / Loki / Grafana 기반 관측(Observability)**
- **Alertmanager + Slack 알림 연동**
- **K6/Locust 기반 부하 테스트 및 HPA 검증**

---

## 2. 프로젝트 목표

이 프로젝트의 핵심 목표는 다음과 같습니다.

### ✅ 1) 온프레미스 인프라 직접 구축
- Mini PC를 플랫폼 서버로 사용 (GitLab / Registry / Runner)
- VM 3대를 Kubernetes 클러스터로 구성 (Control Plane 1, Worker 2)

### ✅ 2) GitOps 기반 배포 자동화 구현
- `app-repo`와 `gitops-repo` 분리
- GitLab CI로 이미지 빌드 및 Registry Push
- CI에서 `gitops-repo`의 이미지 태그를 **Commit SHA** 기준으로 자동 갱신
- Argo CD가 Git 변경사항을 감지하여 자동 Sync + Self-healing 수행

### ✅ 3) 운영 관점의 관찰 가능성 확보
- Prometheus / Loki / Grafana를 통한 메트릭/로그/대시보드 구성
- Alertmanager + Slack으로 장애 알림 체계 구축
- 부하 테스트를 통한 HPA 동작 검증

---

## 3. 전체 아키텍처

> 아래 다이어그램은 프로젝트 최종 목표 아키텍처입니다.

```text
[Developer PC]
   └─ push → [GitLab (Mini PC)]
              ├─ Container Registry
              └─ GitLab Runner (CI)

[GitLab CI]
   ├─ app-repo 빌드/테스트
   ├─ 이미지 빌드 & Push (Registry)
   └─ gitops-repo 이미지 태그(Commit SHA) 업데이트

[Argo CD on K8s]
   └─ gitops-repo 감시 → Sync → 배포 반영 (Self-heal)

[Kubernetes Cluster (kubeadm)]
   ├─ Control Plane (Master)
   ├─ Worker1
   └─ Worker2
      └─ Google Online Boutique (MSA)

[Ingress-NGINX + MetalLB]
   └─ 외부 접속 라우팅

[Observability]
   ├─ Prometheus (Metrics)
   ├─ Loki + Promtail (Logs)
   ├─ Grafana (Dashboard)
   └─ Alertmanager → Slack (Alerts)
```

---

## 4. 인프라 구성

### 4.1 노드 구성 예시

| 역할 | 호스트명 | IP (예시) | 설명 |
|------|----------|-----------|------|
| Platform | mini-pc | 192.168.x.10 | GitLab / Registry / Runner |
| Control Plane | k8s-master | 192.168.x.11 | Kubernetes Master |
| Worker | k8s-worker1 | 192.168.x.12 | 워커 노드 |
| Worker | k8s-worker2 | 192.168.x.13 | 워커 노드 |

> 실제 IP 대역은 환경에 맞게 변경

### 4.2 네트워크 및 기본 설정
- 고정 IP 할당
- `/etc/hosts` 기반 사설 DNS (`gitlab.local`, `registry.local`)
- `chrony` / `ntp` 시간 동기화
- Worker 노드 리소스 확보 (권장 4~8GB RAM 이상)

---

## 5. 기술 스택

### Platform / CI-CD
- **GitLab**
- **GitLab Container Registry**
- **GitLab Runner (Docker Executor)**

### Kubernetes / GitOps
- **Kubernetes (kubeadm)**
- **containerd**
- **Argo CD**
- **Kustomize** (base/overlays)
- *(선택)* **Helm** (Ingress-NGINX, Observability stack 설치용)

### Network / Access
- **MetalLB**
- **Ingress-NGINX**
- *(선택)* Self-signed SSL (사설 Registry 통신)

### Observability / SRE
- **Prometheus Operator (kube-prometheus-stack)**
- **Loki + Promtail**
- **Grafana**
- **Alertmanager + Slack**

### Advanced
- **Terraform**
- **Sealed Secrets / External Secrets Operator**
- **K6 / Locust**
- **HPA (Horizontal Pod Autoscaler)**

---

## 6. 저장소 구조 (예시)

### 6.1 app-repo (애플리케이션/CI)
```text
app-repo/
├─ .gitlab-ci.yml
├─ src/ ...
└─ Dockerfile
```

### 6.2 gitops-repo (배포 매니페스트)
```text
gitops-repo/
└─ apps/
   └─ online-boutique/
      ├─ base/
      │  ├─ kustomization.yaml
      │  ├─ deployment-*.yaml
      │  ├─ service-*.yaml
      │  └─ configmap/secret templates
      └─ overlays/
         ├─ dev/
         │  └─ kustomization.yaml
         └─ prod/
            └─ kustomization.yaml
```

---

## 7. GitOps 배포 흐름

이 프로젝트의 핵심 배포 흐름은 아래와 같습니다.

1. 개발자가 `app-repo`에 코드 Push
2. GitLab CI 파이프라인 실행
3. 애플리케이션 이미지 빌드 및 사설 Registry Push
4. CI가 `gitops-repo`의 Kustomize 이미지 태그를 **Commit SHA**로 업데이트
5. Argo CD가 `gitops-repo` 변경사항 감지
6. Kubernetes에 자동 Sync 및 배포 반영
7. 장애/드리프트 발생 시 Self-healing 수행

---

## 8. 구현 범위 (Roadmap)

### Phase 0. Foundation
- [ ] 네트워크 대역 및 고정 IP 확정
- [ ] `/etc/hosts` 설정 (`gitlab.local`, `registry.local`)
- [ ] 시간 동기화 설정 (chrony/ntp)
- [ ] 리소스 할당 검토 (온라인 부티크용)

### Phase 1. Platform (Mini PC)
- [ ] GitLab + Registry 구축
- [ ] Self-signed SSL 인증서 생성 및 보관
- [ ] GitLab Runner (docker executor) 최적화
- [ ] `app-repo` / `gitops-repo` 분리

### Phase 2. Kubernetes Cluster
- [ ] containerd 설치 및 사설 Registry 신뢰 설정
- [ ] kubeadm init + CNI 설치 (Calico/Cilium)
- [ ] StorageClass 구성 (Local Path or NFS)
- [ ] 노드 라벨링 구성

### Phase 3. Gateway & Argo CD
- [ ] MetalLB 설치 (L2 모드)
- [ ] Ingress-NGINX 설치 및 VIP 확인
- [ ] Argo CD 설치 + Ingress 설정
- [ ] Argo CD Git 인증 구성 (Deploy Key/PAT)

### Phase 4. GitOps 설계
- [ ] Kustomize base/overlays 구조 설계
- [ ] ConfigMap / Secret 분리 관리
- [ ] Argo Application + Auto Sync + Self-heal 구성

### Phase 5. CI/CD
- [ ] Multi-stage Docker build 구성
- [ ] CI에서 Commit SHA 기반 태그 생성
- [ ] `kustomize edit set image`로 gitops-repo 자동 업데이트
- [ ] `imagePullSecrets` 구성

### Phase 6. Observability
- [ ] Prometheus Operator 설치
- [ ] Loki + Promtail 설치
- [ ] Grafana 대시보드 구성 (Online Boutique 기준)
- [ ] Alertmanager + Slack 알림 연동

### Phase 7. Advanced
- [ ] Terraform으로 인프라 코드화
- [ ] Sealed Secrets / External Secrets 도입
- [ ] K6/Locust 부하 테스트
- [ ] HPA 동작 검증

---

## 9. 주요 구현 포인트 (실무 관점)

### 9.1 CI와 CD 역할 분리
- **CI (GitLab CI)**: 빌드/테스트/이미지 생성/레지스트리 Push
- **CD (Argo CD)**: Git 상태를 기준으로 클러스터 동기화

### 9.2 Commit SHA 기반 이미지 태그 전략
- `latest` 대신 **불변(immutable) 태그** 사용
- 롤백/추적성(Traceability) 확보
- GitOps 변경 이력과 이미지 버전 연결 가능

### 9.3 GitOps 저장소 분리
- `app-repo`: 애플리케이션 소스 + CI
- `gitops-repo`: 배포 선언 상태 (desired state)
- 운영 안정성과 권한 분리 측면에서 유리

### 9.4 온프레미스 네트워크 고려사항
- 클라우드 LB 대신 **MetalLB**
- 사설 Registry 인증서 신뢰 설정 필요
- 노드 간 시간 동기화 중요 (TLS / 로그 분석)

---

## 10. 실행/검증 계획 (예정)

### 기능 검증
- [ ] Online Boutique 전체 서비스 정상 배포
- [ ] Ingress를 통한 외부 접속 확인
- [ ] Argo CD에서 Sync 상태 및 히스토리 확인

### 운영 검증
- [ ] Pod 강제 삭제 시 Self-healing 확인
- [ ] 잘못된 리소스 변경 후 Argo CD 드리프트 복구 확인
- [ ] 이미지 태그 변경 시 롤링 업데이트 확인

### 관측/알림 검증
- [ ] Grafana 대시보드 구성 확인
- [ ] Pod Crash 알림 → Slack 수신 확인
- [ ] 노드 자원 부족 알림 → Slack 수신 확인

### 성능/오토스케일 검증
- [ ] K6/Locust로 트래픽 부하 발생
- [ ] HPA 스케일 아웃/인 확인
- [ ] 지표 기반 병목 분석 (CPU/Memory/Latency)

---

## 11. 트러블슈팅 (작성 예정)

프로젝트 진행 중 겪은 문제와 해결 과정을 정리할 예정입니다.

예시:
- GitLab Registry 인증 실패 (`denied: access forbidden`)
- Docker / containerd insecure registry 또는 인증서 신뢰 문제
- kubeadm 초기화 후 `kubectl` context 문제
- Argo CD repo 인증 문제 (PAT / Deploy Key)
- Ingress / MetalLB 외부 접속 문제
- 시간 동기화 불일치로 인한 인증서/로그 문제

> 실제 이슈 발생 시 `문제 원인 → 해결 방법 → 재발 방지` 형식으로 기록

---

## 12. 결과 화면 (추가 예정)

- [ ] GitLab CI 파이프라인 성공 화면
- [ ] Argo CD Sync / History / Rollback 화면
- [ ] Online Boutique 접속 화면
- [ ] Grafana 대시보드 화면
- [ ] Slack 알림 수신 화면

---

## 13. 회고 (추가 예정)

이 프로젝트를 통해 아래 역량을 강화하는 것을 목표로 합니다.

- 온프레미스 Kubernetes 운영 능력
- GitLab CI + Argo CD 기반 GitOps 자동화 설계 능력
- 관측(Observability) 및 장애 대응 역량
- 운영 친화적인 배포/롤백/알림 체계 설계 능력

---

## 14. 참고 자료

- Google Online Boutique (Open Source Demo)
- Kubernetes Documentation
- Argo CD Documentation
- GitLab CI/CD Documentation
- Prometheus / Grafana / Loki Documentation

