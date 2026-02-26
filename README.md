# 🏗️ On-Prem GitOps Microservices Platform

> **Google Online Boutique** 기반의 온프레미스 Kubernetes 마이크로서비스 운영 자동화 플랫폼  
> **kubeadm 기반 클러스터 구축 + GitOps 배포 + 통합 Observability(Metrics/Logs/Alerting)**

---

## 🎯 Project Overview

퍼블릭 클라우드의 Managed Kubernetes(EKS/GKE/AKS)에 의존하지 않고, **순수 온프레미스(kubeadm) 환경에서 Kubernetes Control Plane부터 Network, CI/CD, GitOps, Observability까지 운영 필수 요소를 직접 설계·구축**한 프로젝트입니다.

- **Single Source of Truth(SSoT)** 기반으로 인프라/애플리케이션 선언적 상태를 Git에 고정
- 배포/동기화/롤백을 표준화하여 **구성 드리프트(Drift)와 수동 운영 개입을 최소화**
- 분산 마이크로서비스의 장애 탐지/원인 파악을 위해 **메트릭+로그+알림** 관측성 스택 통합

### ✅ Impact (정량 지표는 실제 수치로 교체 권장)
- 배포 리드타임: **[예: 30분 → 5분]**
- 변경 적용 방식: **[수동 SSH/수동 적용 → PR 기반 GitOps Sync]**
- 평균 장애 탐지 시간(MTTD): **[예: 15분 → 2분]**
- 롤백 시간: **[예: 10분 → 1분]**

> 위 수치는 템플릿입니다. 실제 측정값으로 교체하면 README 설득력이 크게 상승합니다.

---

## 🧰 Tech Stack

| Layer | Stack | Key Responsibility |
| :--- | :--- | :--- |
| **Orchestration** | ![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white) | `kubeadm` 기반 클러스터 수명주기 및 리소스 추상화 |
| **CI/CD + GitOps** | ![GitLab](https://img.shields.io/badge/GitLab-FC6D26?style=flat-square&logo=gitlab&logoColor=white) ![ArgoCD](https://img.shields.io/badge/Argo%20CD-EF7B4D?style=flat-square&logo=argo&logoColor=white) | CI 파이프라인 자동화 + GitOps 기반 선언적 배포(SSoT) |
| **Networking** | ![Calico](https://img.shields.io/badge/Calico-3DDC84?style=flat-square&logo=projectcalico&logoColor=white) ![MetalLB](https://img.shields.io/badge/MetalLB-0A66C2?style=flat-square&logoColor=white) ![NGINX](https://img.shields.io/badge/Ingress--NGINX-009639?style=flat-square&logo=nginx&logoColor=white) | L4 LB(MetalLB) + L7 Ingress + NetworkPolicy 기반 Pod 통신 제어 |
| **Observability** | ![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=flat-square&logo=prometheus&logoColor=white) ![Grafana](https://img.shields.io/badge/Grafana-F46800?style=flat-square&logo=grafana&logoColor=white) ![Loki](https://img.shields.io/badge/Loki-F2A900?style=flat-square&logo=grafana&logoColor=black) | 메트릭/로그 통합 대시보드 + Alerting 운영 체계 |

---

## 💻 Live Demo

![Online Boutique Home](./docs/images/online-boutique-home.png)

---

## 🗺️ Master Architecture Blueprint

> **플랫폼 제어 서버(CI/CD Hub)** 와 **런타임 Kubernetes 클러스터(1 Control Plane + N Worker)** 를 분리하여 설계한 통합 아키텍처입니다.

[![Master Architecture](./docs/images/mainarchitecture.png)](./docs/images/mainarchitecture.png)

### Data & Control Flow (요약)
1. 개발자가 GitLab에 PR/MR을 올리면 CI가 빌드/테스트 파이프라인을 수행  
2. 배포 매니페스트(Helm/Kustomize 등) 변경이 Git에 반영되면 Argo CD가 클러스터 상태를 동기화  
3. Ingress-NGINX가 L7 라우팅을 담당하고, MetalLB가 온프레미스 L4 LB를 제공  
4. Prometheus가 메트릭을 수집하고, Loki(+Promtail)가 로그를 중앙화  
5. Grafana에서 대시보드/알림(임계치 기반)을 통해 운영 이벤트를 추적

---

## 📌 Key Engineering Decisions

| Topic | Challenge | Engineering Action |
| :--- | :--- | :--- |
| **K8s Implementation** | 클라우드 종속성 탈피 및 내부 구조 이해 필요 | `kubeadm` 기반으로 Control Plane 및 CNI를 직접 구성하여 클러스터 운영 기반 확보 |
| **Traffic Routing (On-Prem)** | 온프레미스 환경의 LB 부재 및 외부 트래픽 유입 경로 필요 | **MetalLB(L2)** + **Ingress-NGINX** 조합으로 L4/L7 트래픽 경로 표준화 |
| **Operational Efficiency** | 수동 배포로 인한 Drift 발생 및 롤백 비용 증가 | **Argo CD GitOps** 도입으로 선언적 상태 동기화 및 롤백/감사 추적 강화 |
| **Observability** | 분산 MSA의 장애 전파/원인 파악 어려움 | **Prometheus + Loki + Grafana**로 메트릭/로그/알림 통합, 운영 가시성 확보 |

---

## 🔍 What I Built (면접 포인트)

- `kubeadm`로 Kubernetes 클러스터(Control Plane + Worker) 초기 구축 및 구성
- Calico 기반 CNI 및 NetworkPolicy로 서비스 간 통신 통제
- MetalLB로 온프레미스 LoadBalancer 타입 서비스 제공
- Ingress-NGINX로 L7 라우팅/도메인 기반 트래픽 관리
- GitLab CI 파이프라인 구축 및 배포 산출물(매니페스트) 업데이트 흐름 정리
- Argo CD로 GitOps 배포(SSoT), drift 감지/자동 동기화/롤백 운영
- Prometheus 메트릭 수집 + Loki/Promtail 로그 중앙화 + Grafana 대시보드 및 알림 구성

---

## 📚 Documentation & Deep Dive

아키텍처 설계 배경, 컴포넌트별 세부 구성 및 구축 과정에서의 트러블슈팅 기록은 Wiki에서 제공합니다.

- 🏠 Wiki Home: https://github.com/msp-architect-2026/kim-jaehoon/wiki
- 🖥️ Infrastructure Architecture: https://github.com/msp-architect-2026/kim-jaehoon/wiki/Infrastructure-Architecture
- 📦 Application Architecture: https://github.com/msp-architect-2026/kim-jaehoon/wiki/Application-Architecture
- 🔥 Troubleshooting Log: (링크 추가 권장)

---

## ✅ Quickstart (선택: 재현성 강화용)

> 아래는 예시 섹션입니다. 실제 레포 구조/스크립트에 맞게 커맨드를 연결하면 신뢰도가 크게 상승합니다.

```bash
# 1) (예) 클러스터 접근 확인
kubectl get nodes

# 2) (예) Argo CD 설치/접속 확인
kubectl get pods -n argocd

# 3) (예) GitOps 앱 동기화
argocd app sync online-boutique
