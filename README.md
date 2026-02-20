# 🏗️ 온프레미스 마이크로서비스 인프라 및 GitOps 자동화 프로젝트
### (Google Online Boutique 기반)

![Status](https://img.shields.io/badge/Status-In%20Progress-orange)
![Kubernetes](https://img.shields.io/badge/Kubernetes-kubeadm-blue?logo=kubernetes)
![GitOps](https://img.shields.io/badge/GitOps-Argo%20CD-ef7b4d?logo=argo)
![CI/CD](https://img.shields.io/badge/CI%2FCD-GitLab-fc6d26?logo=gitlab)

> **목표:** 온프레미스 환경에서 `Kubernetes + GitLab + Argo CD` 기반의 실무형 GitOps 배포 체계를 직접 구축하고, 운영 관점의 관측(Observability)·알림·검증 체계까지 연결하는 프로젝트입니다.

---

## 📸 Demo Screenshots

- Online Boutique 메인 화면
- Cart / Checkout 화면
- (추가 예정) GitLab CI / Argo CD / Grafana / Slack 알림 화면

---

## 1) 프로젝트 개요

이 프로젝트는 **Google Online Boutique**(마이크로서비스 데모 애플리케이션)를 기반으로, 온프레미스(On-Premise) 환경에서 **Kubernetes + GitLab + Argo CD 기반 GitOps 배포 체계**를 구축하는 것을 목표로 합니다.

단순한 배포 자동화를 넘어서, 아래 요소까지 포함한 **운영 친화적 DevOps 환경**을 지향합니다.

- **사설 GitLab + Container Registry 운영**
- **kubeadm 기반 Kubernetes 클러스터 구성**
- **Ingress/MetalLB 기반 온프레미스 트래픽 진입 구조**
- **Argo CD 기반 GitOps 자동 배포 (Sync / Self-heal)**
- **Prometheus / Loki / Grafana 기반 관측(Observability)**
- **Alertmanager + Slack 알림 연동**
- **부하 테스트(K6/Locust) + HPA 검증 (확장 단계)**

---

## 2) 핵심 목표

### ✅ 1. 온프레미스 인프라 직접 구축
- Mini PC를 플랫폼 노드로 구성 (GitLab / Registry / Runner)
- VM 3대를 Kubernetes 클러스터로 구성 (Control Plane 1, Worker 2)

### ✅ 2. GitOps 기반 배포 자동화 구현
- `app-repo`와 `gitops-repo` 역할 분리
- GitLab CI에서 이미지 빌드 및 Registry Push
- CI가 `gitops-repo` 이미지 태그를 **Commit SHA** 기준으로 자동 갱신
- Argo CD가 Git 변경사항 감지 후 자동 Sync + Self-healing 수행

### ✅ 3. 운영 관점의 관찰 가능성 확보
- Prometheus / Loki / Grafana를 통한 메트릭/로그/대시보드 구성
- Alertmanager + Slack 장애 알림 체계 구축
- 부하 테스트 기반 HPA 동작 검증

---

## 3) 전체 아키텍처

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
   ├─ Control Plane
   ├─ Worker1
   └─ Worker2
      └─ Online Boutique (MSA)

[Ingress-NGINX + MetalLB]
   └─ 외부 접속 라우팅

[Observability]
   ├─ Prometheus (Metrics)
   ├─ Loki + Promtail (Logs)
   ├─ Grafana (Dashboard)
   └─ Alertmanager → Slack (Alerts)
```

---

## 4) 기술 스택

### Platform / CI
- GitLab
- GitLab Container Registry
- GitLab Runner (Docker Executor)

### Kubernetes / GitOps
- Kubernetes (kubeadm)
- containerd
- Argo CD
- Kustomize (base/overlays)
- (선택) Helm (Ingress-NGINX / Observability Stack 설치용)

### Network / Access
- Ingress-NGINX
- MetalLB (L2)
- (환경에 따라) Self-signed TLS / Insecure Registry 설정

### Observability / SRE
- Prometheus
- Loki + Promtail
- Grafana
- Alertmanager + Slack

### Advanced (확장 계획)
- Terraform
- Sealed Secrets / External Secrets
- K6 / Locust
- HPA

---

## 5) 저장소 분리 전략 (Repository Strategy)
안전하고 추적 가능한 GitOps 운영을 위해 저장소를 분리합니다.

* **`app-repo` (애플리케이션 + CI)**
  - 애플리케이션 소스 코드
  - Dockerfile
  - `.gitlab-ci.yml`
* **`gitops-repo` (배포 선언 상태)**
  - Kubernetes 매니페스트
  - Kustomize base/overlays
  - Argo CD가 감시하는 단일 진실원천(Source of Truth)

---

## 6) GitOps 배포 흐름 (핵심)
1. 개발자가 `app-repo`에 코드 Push
2. GitLab CI 파이프라인 실행
3. 이미지 빌드 및 사설 Registry Push
4. CI가 `gitops-repo`의 이미지 태그를 Commit SHA로 업데이트
5. Argo CD가 `gitops-repo` 변경사항 감지
6. Kubernetes에 자동 Sync 및 배포 반영
7. 드리프트/장애 발생 시 Self-healing 수행

---

## 7) 문서화 (Wiki)
README는 개요/핵심 흐름 중심으로 유지하고, 상세 설계/운영/트러블슈팅은 Wiki에서 관리합니다.

📚 **[Wiki Home 바로가기](https://github.com/msp-architect-2026/kim-jaehoon/wiki)**
- Infrastructure Architecture
- Application Architecture
- API Specification
- Data Architecture
- User Interface (UI)
- Operations Runbook
- Troubleshooting Log

---

## 8) 현재 진행 상태 (Summary)

| 영역 | 상태 | 비고 |
| --- | :---: | --- |
| Wiki 구조화 / 문서 템플릿 정리 | ✅ 완료 | |
| Phase 0 Foundation (네트워크/기본 설정) | 🟡 진행 중 | |
| Phase 1 Platform (GitLab/Registry/Runner) | 🟡 진행 중 | |
| Phase 2 Kubernetes Cluster (kubeadm/CNI) | 🟡 진행 중 | |
| Phase 3 Gateway & Argo CD | 🟡 진행 중 | |
| Phase 4 GitOps 구조 (Kustomize/Argo App) | ✅ 설계 완료 | 적용 진행 |
| Phase 5 CI/CD 자동 연동 | 🟡 진행 중 | |
| Phase 6 Observability & Alerts | ⏳ 예정 | |
| Phase 7 Advanced (Terraform/HPA/Load Test) | ⏳ 예정 | |

> 상세 체크리스트 및 작업 로그는 Wiki에서 관리합니다.

---

## 9) 주요 구현 포인트 (실무 관점)

### 9.1 CI와 CD 역할 분리
- **CI (GitLab CI):** 빌드/테스트/이미지 생성/Registry Push
- **CD (Argo CD):** Git 상태를 기준으로 클러스터 동기화

### 9.2 Commit SHA 기반 이미지 태그 전략
- `latest` 대신 불변(immutable) 태그 사용
- 롤백/추적성(Traceability) 확보
- GitOps 변경 이력과 이미지 버전 연결 가능

### 9.3 GitOps 저장소 분리
- **app-repo:** 애플리케이션 소스 + CI
- **gitops-repo:** 배포 선언 상태 (desired state)
- 운영 안정성과 권한 분리 측면에서 유리

### 9.4 온프레미스 네트워크 고려사항
- 클라우드 LB 대신 MetalLB / NodePort 기반 접근
- 사설 Registry 인증서 신뢰 설정 필요
- 노드 간 시간 동기화 중요 (TLS / 로그 분석)

---

## 10) 검증 및 증빙 (Evidence)

### 기능/배포 검증
- [ ] Online Boutique 전체 서비스 정상 배포
- [ ] Ingress를 통한 외부 접속 확인
- [ ] Argo CD Sync 상태 / History 확인
- [ ] 이미지 태그 변경 시 롤링 업데이트 확인
- [ ] Self-healing 동작 확인 (리소스 드리프트 복구)

### 관측/알림 검증
- [ ] Grafana 대시보드 구성 확인
- [ ] Pod Crash 알림 → Slack 수신 확인
- [ ] 노드 자원 압박 알림 → Slack 수신 확인

### 성능/오토스케일 검증 (확장)
- [ ] K6/Locust 부하 발생
- [ ] HPA Scale Out / In 확인
- [ ] 병목 지표 분석 (CPU/Memory/Latency)

---

## 11) 트러블슈팅 기록 정책
구축/운영 중 발생한 이슈는 Wiki의 `Troubleshooting Log`에 기록합니다.

* **기록 형식:** 증상 → 원인 → 해결 → 검증 → 재발 방지
* **예시:**
  - GitLab Registry 인증 실패 (`denied: access forbidden`)
  - Registry TLS / insecure 설정 문제
  - `kubeconfig` / `kubectl` 권한 문제
  - Argo CD repo 인증 문제
  - Ingress 외부 접속 문제

👉 **[Troubleshooting Log 바로가기](https://github.com/msp-architect-2026/kim-jaehoon/wiki/Troubleshooting-Log)**

---

## 12) 결과 화면 (추가 예정)
- [ ] GitLab CI 파이프라인 성공 화면
- [ ] Argo CD Sync / History / Rollback 화면
- [ ] Online Boutique 접속 화면
- [ ] Grafana 대시보드 화면
- [ ] Slack 알림 수신 화면
> 스크린샷은 진행 단계별로 업데이트 예정입니다.

---

## 13) 향후 확장 계획
- Terraform 기반 인프라 코드화
- Sealed Secrets / External Secrets 도입
- HPA + 부하 테스트 기반 자동 확장 검증
- NetworkPolicy / 보안 강화
- (선택) TLS/사설 CA 체계 정리

---

## 14) 참고 자료
- Google Online Boutique (Open Source Demo)
- Kubernetes Documentation
- Argo CD Documentation
- GitLab CI/CD Documentation
- Prometheus / Grafana / Loki Documentation

---

### 📌 Notes
- 본 README는 프로젝트 개요 및 핵심 흐름 중심으로 유지합니다.
- 상세 설계/운영/트러블슈팅/검증 절차는 Wiki 문서에서 계속 업데이트합니다.
- 민감정보(PAT/토큰/비밀번호/시크릿)는 문서 및 저장소에 직접 기록하지 않습니다.
