# incident-analyzer/ - AI 기반 장애 분석기

## 역할
Prometheus 메트릭 + Loki 로그를 **LLM으로 분석**해서 Slack에 전달

## 구성요소 (예정)
- Prometheus 쿼리 (에러율, latency)
- Loki 쿼리 (에러 로그)
- OpenAI/Claude API 호출
- Slack Webhook 전송

## 파일 (예정)
- `docker-compose.yml` - 분석기 컨테이너
- `analyzer.py` - 메인 로직
- `config.example.env` - API key 템플릿
- `promql_queries.md` - 사용하는 쿼리 목록
- `slack_format.md` - Slack 메시지 포맷

## 작성 시점
Phase 6 끝나고 알람이 동작하면 추가

## 동작 흐름
1. Alertmanager에서 Webhook 받음
2. 해당 시간대 메트릭/로그 수집
3. LLM에 "무슨 문제인지 분석해줘" 요청
4. 결과를 Slack에 전송
