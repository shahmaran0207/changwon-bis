# DB 설계 개념 정리

이 프로젝트 DB 설계 과정에서 나온 개념을 정리해둔다. 결정한 설계가 "왜" 그렇게 됐는지 나중에 다시 찾아볼 수 있도록 용어 + 이 프로젝트에 적용한 방식을 같이 적는다.

## 서러게이트 키 (Surrogate Key)

업무적 의미가 전혀 없는, DB가 그냥 발급하는 대체 식별자. `BIGSERIAL`, `UUID` 같은 걸 PK로 쓰는 방식.

반대 개념은 **자연키(Natural Key)** — 실제 업무 데이터에서 가져온 값(TAGO의 `routeId`, `nodeid` 같은 것)을 그대로 PK로 쓰는 방식.

### 비교

| | 자연키 | 서러게이트 키 |
|---|---|---|
| 장점 | 조인 없이 바로 이해 가능, 구현 단순 | 외부 시스템이 ID 체계를 바꾸거나, 다른 데이터 소스가 추가돼도 내부 구조가 안 흔들림 |
| 단점 | 외부 시스템(TAGO) 쪽 ID 포맷이 바뀌면 FK 걸린 테이블 전부 영향받음 | PK 하나가 더 생겨서 조인 시 컬럼이 하나 더 탐(성능 차이는 미미) |
| 확장성 | 외부 시스템에 종속적 | 데이터 소스가 늘어나도 내부는 안전 |

### 이 프로젝트에 적용한 방식

TAGO API 의존도가 높고, 나중에 다른 도시/다른 데이터 소스로 확장할 가능성이 있어서 **서러게이트 키**를 선택했다.

- TAGO의 `routeId`, `nodeid`는 문자열이라 조인 성능도 INT 서러게이트 키보다 불리함 (대용량 로그 테이블인 `bus_location_log`에서 특히 체감)
- TAGO ID는 버리지 않고 `external_route_id`, `external_stop_id`처럼 **UNIQUE 제약이 걸린 일반 컬럼**으로 남겨서, 자연키의 가독성도 유지

```sql
-- 예시
CREATE TABLE route (
    id                 BIGSERIAL PRIMARY KEY,         -- 서러게이트 키
    external_route_id  VARCHAR(30) UNIQUE NOT NULL,   -- TAGO routeId (자연키 보존)
    city_code          SMALLINT NOT NULL,
    route_no           VARCHAR(10) NOT NULL
);

CREATE TABLE stop (
    id                 BIGSERIAL PRIMARY KEY,
    external_stop_id   VARCHAR(30) UNIQUE NOT NULL,   -- TAGO nodeid
    city_code          SMALLINT NOT NULL,
    stop_name          VARCHAR(100) NOT NULL
);

-- 다른 테이블은 TAGO ID가 아니라 내부 id(서러게이트 키)를 FK로 참조
CREATE TABLE route_stop (
    route_id   BIGINT NOT NULL REFERENCES route(id),
    node_ord   SMALLINT NOT NULL,
    stop_id    BIGINT NOT NULL REFERENCES stop(id),
    updown_cd  SMALLINT NOT NULL,
    PRIMARY KEY (route_id, node_ord)
);
```
