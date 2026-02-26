# 🏗️ On-Prem GitOps Microservices Platform

> Google Online Boutique 기반 MSA K8s 운영 자동화 및 관측성(Observability) 통합 플랫폼

## 🎯 Project Overview & Impact
본 프로젝트는 퍼블릭 클라우드의 매니지드 K8s 서비스에 의존하지 않고, **순수 온프레미스(kubeadm) 환경에서 Control Plane부터 Network, Storage, CI/CD 파이프라인까지 전 과정을 직접 설계하고 구축한 GitOps 기반 플랫폼**입니다.

* **Impact:** 선언적 상태 관리(SSoT)를 통해 인프라 구성의 멱등성을 보장하고, 어플리케이션 배포부터 모니터링 경고(Alert)까지의 라이프사이클을 100% 자동화하여 운영 개입을 최소화했습니다.

## 🛠️ Tech Stack
| Layer | Stack | Key Responsibility |
| :--- | :--- | :--- |
| **Orchestration** | <img src="https://img.shields.io/badge/kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white"> | `kubeadm` 기반 클러스터 수명 주기 관리 및 자원 추상화 |
| **CI/CD / GitOps** | <img src="https://img.shields.io/badge/gitlab-FC6D26?style=flat-square&logo=gitlab&logoColor=white"> <img src="https://img.shields.io/badge/argo%20cd-EF7B4D?style=flat-square&logo=argo&logoColor=white"> | CI 파이프라인 자동화 및 GitOps 기반 선언적 배포(SSoT) |
| **Networking** | <img src="https://img.shields.io/badge/NGINX-009639?style=flat-square&logo=nginx&logoColor=white"> <img src="https://img.shields.io/badge/Calico-24292E?style=flat-square&logo=databricks&logoColor=white"> | L4(MetalLB) / L7(Ingress) 트래픽 라우팅 및 Pod 간 통신 보안 |
| **Observability** | <img src="https://img.shields.io/badge/prometheus-E6522C?style=flat-square&logo=prometheus&logoColor=white"> <img src="https://img.shields.io/badge/grafana-F46800?style=flat-square&logo=grafana&logoColor=white"> | 메트릭/로그 통합 대시보드 및 임계치 기반 운영 알림 |
| **Storage** | <img src="https://img.shields.io/badge/NFS-blue?style=flat-square"> | `NFS Dynamic Provisioner`를 이용한 상태 저장형(Stateful) 데이터 관리 |

<div align="left">
  <img src="https://img.shields.io/badge/kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white">
  <img src="https://img.shields.io/badge/gitlab-FC6D26?style=for-the-badge&logo=gitlab&logoColor=white">
  <img src="https://img.shields.io/badge/argo%20cd-EF7B4D?style=for-the-badge&logo=argo&logoColor=white">
  <img src="https://img.shields.io/badge/prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white">
</div>

## 💻 Live Action
![Demo](./docs/images/online-boutique-home.png)

---

## 🗺️ Master Architecture Blueprint

> 플랫폼 제어 서버(CI/CD Hub)와 런타임 클러스터(1 Master, 2 Worker Nodes)를 분리하여 설계한 통합 데이터 흐름 및 네트워크 아키텍처입니다.

[![Master Architecture](./docs/images/mainarchitecture.png)](./docs/images/mainarchitecture.png)

## 📌 Key Engineering Decisions

인프라 구축 시 직면한 한계를 해결하기 위한 문제 해결 중심의 기술적 선택입니다.

| Topic | Challenge | Engineering Action |
| :--- | :--- | :--- |
| **K8s Implementation** | 클라우드 종속성 탈피 및 내부 구조 이해 필요 | **"The Hard Way"**: `kubeadm` 으로 Control Plane 및 CNI 직접 구성 |
| **Traffic Routing** | 온프레미스 환경의 로드밸런서(LB) 부재 | **MetalLB(L2)**와 **Ingress-NGINX** 연동으로 외부 통신 경로 확보 |
| **Operational Efficiency** | 수동 배포로 인한 구성 드리프트(Drift) 발생 | **GitOps**: Argo CD 도입으로 인프라 상태 동기화 및 가시성 확보 |
| **Visibility** | 분산된 마이크로서비스의 장애 전파 파악 어려움 | **Unified Logging**: Loki-Promtail-Grafana 통합 관측성 체계 구축 |
---

## 📚 Documentation & Deep Dive

아키텍처 설계 배경, 컴포넌트별 세부 구성 및 **인프라 구축 중 발생한 트러블슈팅(Troubleshooting) 기록** 등 상세한 엔지니어링 문서는 Wiki에서 제공합니다.

* [🏠 Wiki Home](https://github.com/msp-architect-2026/kim-jaehoon/wiki)
* [🖥️ Infrastructure Architecture](https://github.com/msp-architect-2026/kim-jaehoon/wiki/Infrastructure-Architecture)
* [📦 Application Architecture](https://github.com/msp-architect-2026/kim-jaehoon/wiki/Application-Architecture)
* [🔥 Troubleshooting Log (추가 권장)](#)
