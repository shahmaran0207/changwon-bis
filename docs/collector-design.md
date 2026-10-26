# 수집기·맵매칭 설계

## 1. TAGO 버스 위치 수집기

### 트래픽 한도 문제

개발계정 일일 쿼터 10,000건. 창원 173개 + 진주 330개 = 총 503개 노선, 버스위치정보는 노선 단위 호출이라 전 노선 한 바퀴(1사이클)에 503건 소모.

- 24시간 전체 수집: 10,000 ÷ 503 ≈ **19.9사이클/일 → 약 72분 주기**
- 운행시간대(05:00~24:00, 19시간)만 수집: 1140분 ÷ 57분(사이클) ≈ 20사이클 → **약 57분 주기**

지금은 테스트 모드로 이 한도 그대로 사용. 정식 버전 전환 시 data.go.kr "활용사례 등록"으로 트래픽 증설 신청 예정 — 그때는 설정값만 바꾸면 되도록 설계.

### 구현 방식

- 503개 노선을 큐에 넣고 라운드로빈으로 하나씩 호출 (`@Scheduled(fixedDelay=...)`)
- 설정값(application.yml)으로 분리:
  ```yaml
  collector:
    tago:
      daily-quota: 10000
      operating-hours: "05:00-24:00"
  ```
- 결과: `bus_location_log`에 insert, `collection_status(source='TAGO_BUS')` 갱신
- 실패 시 재시도하지 않음 (실시간 데이터라 과거값 재조회는 의미 없음, 다음 사이클을 기다림). 특정 노선이 **연속 3회 실패**하면 그 노선의 `arrival_status.status`를 `NO_SIGNAL`로 반영

## 2. ITS 도로속도 수집기

- bbox 쿼리 방식(노선 단위 아님) — 창원 bbox 1회 + 진주 bbox 1회 = 사이클당 2건
- 5분 간격으로 돌려도 하루 2×288=576건 수준이라 TAGO처럼 쿼터 걱정 없음
- 결과: `road_link_speed_log`에 raw 로그로 적재

### 집계 배치 (매일 1회, 새벽)

전날 쌓인 `road_link_speed_log`를 day_type/time_bucket별로 묶어 기존 `road_link_speed_stat`과 **가중평균**으로 합산 갱신:

```
new_avg   = (old_avg * old_count + today_avg * today_count) / (old_count + today_count)
new_count = old_count + today_count
```

이렇게 하면 초기엔 `scripts/aggregate_traffic_speed.py`로 넣은 과거 7일 집계값으로 시작하고, 운영하면서 쌓이는 자체 데이터가 점점 비중을 키워가는 구조가 된다 (별도 전환 작업 없이 자연스럽게 고도화).

## 3. 노선 → 도로 링크 맵매칭 (pgRouting)

### 알고리즘

1. `road_link`에 이미 있는 `f_node_id`/`t_node_id`/`length_m`/`max_speed_kmh`로 `road_link_pgr` 뷰(= pgr_dijkstra가 요구하는 id/source/target/cost 형식) 구성. **cost는 거리가 아니라 통행 소요시간**(`length_m / max_speed_kmh`)으로 둬서, 버스가 실제로 다니는 큰길 위주 경로가 나오게 함 (최단거리 기준이면 좁은 골목으로 빠질 수 있음)
2. 노선의 각 정류소 좌표에서 KNN(`geom <->`)으로 가장 가까운 `road_node` 탐색 (실측 검증: 오차 없이 정확히 스냅됨)
3. 연속된 정류소 쌍(node_ord i → i+1)마다 `pgr_dijkstra(road_link_pgr, from_node, to_node)` 호출해 경로 링크 시퀀스 획득
4. 결과를 `route_link_map`에 seq 누적하며 저장

### 검증 완료 (Docker pgRouting 컨테이너)

노드 3개·링크 2개짜리 테스트 도로망에 정류소 2개를 양끝 근처에 배치 → 정확히 두 링크를 순서대로 지나는 경로가 계산됨 (cost 누적값도 거리/속도 계산과 일치).

### 왜 pgRouting인가 (Valhalla 대비)

- 이미 쓰는 PostgreSQL에 extension만 추가 — 별도 서비스/메모리 불필요
- 정류소 좌표가 TAGO 실측 GPS라 이미 정확해서, 복잡한 확률적 맵매칭(HMM 등) 없이 "정류소 간 최단(시간)경로 연결"만으로 충분
- 무료 호스팅 리소스 제약 원칙과 부합 (Valhalla 같은 별도 라우팅 엔진은 다른 프로젝트에서 이미 메모리를 쓰고 있어 부담)

### 트리거 시점

노선/정류소 데이터는 TAGO 쪽에서 자주 바뀌지 않으므로, 상시 스케줄이 아니라 **노선 동기화 배치 직후 또는 관리자 수동 트리거**로 실행.

## 남은 작업
- [ ] 노선/정류소 TAGO 동기화 배치(신규/변경/폐지 노선 반영) 상세 설계
- [ ] 배차 이상·노선 이탈 감지 로직(임계값, 판정 주기) 상세 설계
