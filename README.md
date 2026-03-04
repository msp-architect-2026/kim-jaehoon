<div align="center">

# 🏗️ On-Prem GitOps Microservices Platform

**코드 푸시부터 빌드·배포·모니터링·알림까지 — 온프레미스 환경의 GitOps 기반 운영 파이프라인**

[![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![GitLab CI](https://img.shields.io/badge/GitLab_CI-FC6D26?style=for-the-badge&logo=gitlab&logoColor=white)](https://gitlab.com/)
[![Argo CD](https://img.shields.io/badge/Argo_CD-EF7B4D?style=for-the-badge&logo=argo&logoColor=white)](https://argoproj.github.io/cd/)
[![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)](https://prometheus.io/)
[![Grafana](https://img.shields.io/badge/Grafana-F46800?style=for-the-badge&logo=grafana&logoColor=white)](https://grafana.com/)
[![Loki](https://img.shields.io/badge/Loki-F5A623?style=for-the-badge&logo=grafana&logoColor=white)](https://grafana.com/oss/loki/)
[![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
[![Helm](https://img.shields.io/badge/Helm-0F1689?style=for-the-badge&logo=helm&logoColor=white)](https://helm.sh/)

</div>

---

## 💡 왜 이 프로젝트를 만들었나

> 클라우드 없이, 온프레미스 환경에서 CI/CD · GitOps · Observability 스택을 1인으로 직접 설계하고 구축한 프로젝트입니다.

`2026.02.26 ~ 2026.03.12 · 2주 · 1인 프로젝트`

온프레미스 환경에서 마이크로서비스를 운영할 때, 배포·장애 감지·인프라 변경 추적 모두 사람이 직접 개입해야 했습니다. 이 프로젝트는 그 수동 개입을 제거하기 위해 설계했습니다. GitOps 원칙으로 인프라를 선언적으로 관리하고, CI/CD 파이프라인으로 배포 흐름을 자동화하며, Observability 스택으로 시스템 상태를 항상 가시화합니다.

---

## 📊 Key Achievements

| 항목 | Before | After |
|------|--------|-------|
| 🚀 배포 방식 | 수동 `kubectl apply` | 코드 푸시 → 빌드·배포 전 과정 자동화 |
| 🧩 운영 마이크로서비스 | — | 11개 서비스 단일 클러스터에서 동시 운영 |
| 🔍 장애 감지 | 직접 로그 확인 | Prometheus Alert → Slack 자동 알림 |
| 🔄 인프라 자가복구 | 수동 재배포 | Argo CD Self-Heal 자동 복구 |

---

## 🗺️ Architecture Overview

[![Architecture](./docs/images/mainarchitecture.png)](./docs/images/mainarchitecture.png)

CI/CD를 담당하는 플랫폼 서버와 실제 워크로드가 실행되는 Kubernetes 클러스터를 의도적으로 분리했습니다. 플랫폼 장애가 런타임에 영향을 주지 않도록 하기 위한 설계입니다.

<details>
<summary><b>📖 전체 흐름 요약</b></summary>

```
Developer/Ops
  └─ git push
       └─ GitLab CI 트리거
            ├─ Docker 이미지 빌드
            ├─ GitLab Container Registry에 Push
            └─ gitops-repo 이미지 태그 업데이트
                 └─ Argo CD (SSA 방식으로 K8s에 자동 Sync)
                      └─ Worker Node에 Pod 배포

User
  └─ HTTPS(443) 요청
       └─ MetalLB LoadBalancer
            └─ Ingress-NGINX
                 └─ Frontend Service
                      └─ gRPC → Cart / ProductCatalog / Currency / 기타 서비스

Observability
  └─ Promtail → Loki (로그 수집)
  └─ Prometheus (메트릭 스크레이핑)
  └─ Grafana (대시보드 시각화)
  └─ AlertManager → Slack (알림 Push)
```

</details>

---

## ✨ Core Features

### ① GitOps 기반 선언적 배포 자동화

GitLab CI가 이미지를 빌드해 레지스트리에 올리면, Argo CD가 gitops-repo 변경을 감지해 클러스터에 Sync합니다. Server-Side Apply(SSA) 방식을 적용해 선언된 상태와 실제 상태가 다를 경우 자동으로 Self-Heal합니다.

### ② MetalLB + Ingress-NGINX 트래픽 라우팅

클라우드 없이 온프레미스에서 `LoadBalancer` 타입 서비스를 사용하기 위해 MetalLB를 도입했습니다. Ingress-NGINX가 외부 트래픽을 받아 내부 마이크로서비스로 전달합니다.

### ③ 중앙 집중식 Observability 스택

Promtail이 모든 Pod의 로그를 수집해 Loki로 전송하고, Prometheus가 메트릭을 스크레이핑합니다. 모든 데이터는 Grafana 대시보드에서 통합 시각화되며, 임계값 초과 시 AlertManager가 Slack으로 자동 알림을 전송합니다.

### ④ 11개 마이크로서비스 동시 운영

Google Online Boutique 기반의 11개 서비스를 kubeadm으로 구성한 온프레미스 클러스터에서 운영합니다. 서비스 간 통신은 gRPC 기반으로 처리됩니다.

---

## 🤖 Automation Scripts

플랫폼 전체 구축 과정을 8개의 자동화 스크립트로 구현했습니다. 노드 초기설정부터 GitLab HTTPS 구축, Argo CD 설치, MetalLB IP 충돌 검사까지 순서대로 실행 가능하도록 설계했습니다.

| 스크립트 | 설명 |
|----------|------|
| `node-setup.sh` | K8s 노드 공통 초기설정 (Ubuntu, containerd, kubeadm) |
| `k8s-master-init.sh` | 마스터 노드 초기화 (kubeadm init, Calico CNI, Join 명령어 저장) |
| `gitlab-https-bootstrap.sh` | GitLab HTTPS 구축 (로컬 CA 생성, Registry, Runner) |
| `cleanup-gitlab.sh` | GitLab 전체 삭제 및 시스템 복구 |
| `k8s-bootstrap-phase3.sh` | Ingress-NGINX + Argo CD + MetalLB 설치 |
| `repo-auto.sh` | GitLab 프로젝트·토큰·CI 변수 자동 생성 |
| `metallb-ippool.sh` | MetalLB IP Pool 할당 및 네트워크 충돌 검사 |
| `install-ca-containerd.sh` | OS + Containerd CA 인증서 신뢰 등록 |

> 상세 사용법 및 설계 의도는 [Wiki - Build & Deploy](https://github.com/msp-architect-2026/kim-jaehoon/wiki/Build-&-Deploy)에서 확인할 수 있습니다.

---

## 🛠️ Tech Stack

| Category | Technologies |
|----------|-------------|
| Container Orchestration | ![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white) ![Helm](https://img.shields.io/badge/Helm-0F1689?style=flat-square&logo=helm&logoColor=white) |
| CI/CD | ![GitLab CI](https://img.shields.io/badge/GitLab_CI-FC6D26?style=flat-square&logo=gitlab&logoColor=white) ![Argo CD](https://img.shields.io/badge/Argo_CD-EF7B4D?style=flat-square&logo=argo&logoColor=white) |
| Container | ![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white) ![GitLab Registry](https://img.shields.io/badge/GitLab_Registry-FC6D26?style=flat-square&logo=gitlab&logoColor=white) |
| Networking | ![MetalLB](https://img.shields.io/badge/MetalLB-326CE5?style=flat-square&logo=kubernetes&logoColor=white) ![Ingress NGINX](https://img.shields.io/badge/Ingress_NGINX-009639?style=flat-square&logo=nginx&logoColor=white) |
| Observability | ![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=flat-square&logo=prometheus&logoColor=white) ![Grafana](https://img.shields.io/badge/Grafana-F46800?style=flat-square&logo=grafana&logoColor=white) ![Loki](https://img.shields.io/badge/Loki-F5A623?style=flat-square&logo=grafana&logoColor=white) ![Promtail](https://img.shields.io/badge/Promtail-F5A623?style=flat-square&logo=grafana&logoColor=white) ![AlertManager](https://img.shields.io/badge/AlertManager-E6522C?style=flat-square&logo=prometheus&logoColor=white) |

---

## 🖥️ Application Screenshot

> 11개 마이크로서비스로 구동되는 Online Boutique 쇼핑몰 프론트엔드

![Online Boutique](./docs/images/online-boutique-home.png)

---

## 📚 상세 문서 (Wiki)

아키텍처 설계 배경, 컴포넌트별 세부 구성, 트러블슈팅 기록은 Wiki에서 확인할 수 있습니다.

| 문서 | 내용 |
|------|------|
| [🏠 Wiki Home](https://github.com/msp-architect-2026/kim-jaehoon/wiki) | 전체 문서 목차 |
| [🖥️ Infrastructure Architecture](https://github.com/msp-architect-2026/kim-jaehoon/wiki/Infrastructure-Architecture) | 클러스터 구성, 네트워크 설계, 노드 역할 분리 |
| [📦 Application Architecture](https://github.com/msp-architect-2026/kim-jaehoon/wiki/Application-Architecture) | 마이크로서비스 구조, gRPC 통신 흐름 |
| [🔧 Troubleshooting](https://github.com/msp-architect-2026/kim-jaehoon/wiki/Troubleshooting) | 구축 과정에서 겪은 문제와 해결 기록 |
