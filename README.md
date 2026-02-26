# 🏗️ On-Prem GitOps Microservices Platform
> **Google Online Boutique** 기반 온프레미스 Kubernetes 운영 자동화 플랫폼  
> **kubeadm 클러스터 구축 · GitOps 배포 · Observability(Metrics/Logs/Alerting) 통합**

![Status](https://img.shields.io/badge/Status-In%20Progress-orange?style=flat-square)
![Kubernetes](https://img.shields.io/badge/Kubernetes-kubeadm-blue?style=flat-square&logo=kubernetes&logoColor=white)
![GitOps](https://img.shields.io/badge/GitOps-Argo%20CD-ef7b4d?style=flat-square&logo=argo&logoColor=white)
![GitLab](https://img.shields.io/badge/CI%2FCD-GitLab-fc6d26?style=flat-square&logo=gitlab&logoColor=white)
![Observability](https://img.shields.io/badge/Observability-Prometheus%20%2B%20Loki%20%2B%20Grafana-5c6ac4?style=flat-square)

---

## ✅ Highlights
- **SSoT(단일 진실 소스)**: Git에 선언적 상태 고정 → **Argo CD Sync/Self-heal**로 Drift 최소화
- **온프렘 트래픽 표준 경로**: **MetalLB(L4) + Ingress-NGINX(L7)**로 외부 유입/라우팅 정리
- **운영 가시성 통합**: **Prometheus(메트릭) + Loki(로그) + Grafana(대시보드/알림)** → Slack(Webhook) 알림

---

## 🔎 Proof (작동 증빙)
| Evidence | Screenshot |
| --- | --- |
| Online Boutique UI | ![Online Boutique](./docs/images/online-boutique-home.png) |
| Architecture Blueprint | [![Architecture](./docs/images/mainarchitecture.png)](./docs/images/mainarchitecture.png) |
| Argo CD App Sync | ![ArgoCD Sync](./docs/images/argocd-sync.png) |
| Grafana Dashboard | ![Grafana](./docs/images/grafana-dashboard.png) |
| Slack Alert | ![Slack Alert](./docs/images/slack-alert.png) |

<!-- TODO: 위 이미지 3개(ArgoCD/Grafana/Slack)는 캡처 추가 -->

---

## 📌 Table of Contents
- [Project Overview](#-project-overview)
- [Environment](#-environment)
- [Architecture](#-architecture)
- [End-to-End Flow](#-end-to-end-flow)
- [Tech Stack](#-tech-stack)
- [Key Engineering Decisions](#-key-engineering-decisions)
- [Measured Results](#-measured-results)
- [What I Built](#-what-i-built)
- [Repository Structure](#-repository-structure)
- [Quickstart](#-quickstart)
- [Documentation](#-documentation--deep-dive)
- [Roadmap](#-roadmap)

---

## 🎯 Project Overview
퍼블릭 클라우드의 Managed Kubernetes(EKS/GKE/AKS)에 의존하지 않고 **온프레미스(kubeadm)** 환경에서  
**클러스터 구축 → 네트워킹 → CI/CD → GitOps 배포 → Observability 운영**까지 엔드투엔드로 설계·구축했습니다.

- Git 기반 운영(SSoT)으로 **배포/동기화/롤백**을 표준화
- Drift 감지/자체 복구(Self-heal)로 **수동 운영 개입 최소화**
- 분산 MSA의 장애 탐지/원인 파악을 위해 **메트릭+로그+알림**을 단일 운영 관점으로 통합

---

## 🧱 Environment
| Category | Value |
| --- | --- |
| Platform Server (CI/CD Hub) | Mini PC: GitLab + Container Registry + Runner + Grafana |
| Kubernetes Cluster | VM 3대: 1 Control Plane + 2 Worker |
| OS | Ubuntu 22.04 LTS |
| Kubernetes | v1.xx (kubeadm) |
| Container Runtime | containerd |
| Network | L2/L3 On-Prem LAN, MetalLB(L2) |
| External | Slack (Webhook) |

<!-- TODO: 실제 버전/스펙/대역/도메인 값으로 교체 -->

---

## 🗺️ Architecture
> **플랫폼 제어 서버(CI/CD Hub)** 와 **런타임 Kubernetes 클러스터**를 분리하여 운영 경계를 명확히 했습니다.

[![Master Architecture](./docs/images/mainarchitecture.png)](./docs/images/mainarchitecture.png)

---

## 🔁 End-to-End Flow
1. 개발자가 GitLab에 PR/MR → CI가 빌드/테스트 수행, 이미지를 Registry에 Push  
2. GitOps Repo의 이미지 태그/매니페스트 변경이 Git에 반영  
3. Argo CD가 GitOps Repo를 감시하고 클러스터 상태를 Sync (Self-heal/롤백 가능)  
4. MetalLB가 외부 IP를 할당하고 Ingress-NGINX가 L7 라우팅 처리  
5. Prometheus가 메트릭을 스크레이프, Loki가 로그를 중앙화  
6. Grafana가 대시보드 + Alerting 수행 → Slack(Webhook)로 알림 전송  

---

## 🧰 Tech Stack
| Layer | Stack | Responsibility |
| :--- | :--- | :--- |
| **Orchestration** | ![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white) | `kubeadm` 기반 클러스터 운영 |
| **CI/CD + GitOps** | ![GitLab](https://img.shields.io/badge/GitLab-FC6D26?style=flat-square&logo=gitlab&logoColor=white) ![ArgoCD](https://img.shields.io/badge/Argo%20CD-EF7B4D?style=flat-square&logo=argo&logoColor=white) | 빌드/배포 자동화 + 선언적 배포(SSoT) |
| **Networking** | ![Calico](https://img.shields.io/badge/Calico-3DDC84?style=flat-square&logo=projectcalico&logoColor=white) ![MetalLB](https://img.shields.io/badge/MetalLB-0A66C2?style=flat-square) ![NGINX](https://img.shields.io/badge/Ingress--NGINX-009639?style=flat-square&logo=nginx&logoColor=white) | L4/L7 트래픽 경로 + NetworkPolicy |
| **Observability** | ![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=flat-square&logo=prometheus&logoColor=white) ![Loki](https://img.shields.io/badge/Loki-F2A900?style=flat-square&logo=grafana&logoColor=black) ![Grafana](https://img.shields.io/badge/Grafana-F46800?style=flat-square&logo=grafana&logoColor=white) | 메트릭/로그/대시보드 + Grafana Alerting |

---

## 📌 Key Engineering Decisions
| Topic | Challenge | Decision |
| :--- | :--- | :--- |
| **kubeadm On-Prem** | Managed K8s 의존성 제거 + 내부 구조 이해 | Control Plane부터 직접 구성하여 운영 기반 확보 |
| **Traffic Routing** | 온프렘 LB 부재 + 표준 유입 경로 필요 | **MetalLB(L2)** + **Ingress-NGINX(L7)** |
| **GitOps** | 수동 배포 Drift + 롤백 비용 | **Argo CD** 기반 Sync/Self-heal/History |
| **Observability** | MSA 장애 전파/원인 파악 어려움 | **Prometheus + Loki + Grafana** 통합 운영 |
| **Alerting** | 운영 이벤트 알림 표준화 | **Grafana Alerting → Slack(Webhook)** |

---

## 📈 Measured Results
| Metric | Before | After | Evidence |
| --- | --- | --- | --- |
| Deploy Lead Time | - | - | <!-- TODO: CI 로그/Argo Sync 타임스탬프 --> |
| MTTD | - | - | <!-- TODO: Grafana Alert 발생/Slack 수신 캡처 --> |
| Rollback Time | - | - | <!-- TODO: Argo Rollback 히스토리 캡처 --> |
| Drift Recovery | - | - | <!-- TODO: Self-heal 이벤트 캡처 --> |

---

## 🔍 What I Built
- kubeadm 기반 **Kubernetes 클러스터(Control Plane + Worker)** 구축/운영
- **Calico** CNI 및 **NetworkPolicy**로 서비스 간 통신 정책화
- **MetalLB**로 온프렘 LoadBalancer 제공, **Ingress-NGINX**로 L7 라우팅 구성
- **GitLab CI** 파이프라인 구축 및 이미지 빌드/푸시 자동화
- **Argo CD**로 GitOps 배포(SSoT), 자동 Sync/Self-heal/롤백 운영
- **Prometheus/Loki** 수집 파이프라인 구성, **Grafana** 대시보드/알림(Slack) 구성

---

## 🗂️ Repository Structure
```text
.
├─ app-repo/                    # Online Boutique(또는 커스텀 앱) 소스/CI
│  └─ .gitlab-ci.yml
├─ gitops-repo/                 # 선언적 배포(SSoT): Kustomize/Helm
│  └─ apps/
│     └─ boutique/
│        ├─ base/
│        └─ overlays/
│           └─ dev/
├─ docs/
│  └─ images/
└─ scripts/                     # 부트스트랩/운영 자동화
