# team-08
Team 08 - MSP Architect Training 2026
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

## 3. 왜 Google Online Boutique를 선택했는가?

Google Online Boutique는 여러 개의 마이크로서비스로 구성된 대표적인 데모 애플리케이션으로,  
다음 이유로 GitOps/운영 프로젝트 실습에 적합합니다.

- **MSA 구조 학습에 적합** (서비스 간 통신 구조 명확)
- **배포/롤백/장애 대응 시나리오 재현 가능**
- **모니터링/로깅/알림 실습에 유리**
- **부하 테스트 및 HPA 검증에 적합**

---

## 4. 전체 아키텍처

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
