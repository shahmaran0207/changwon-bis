-- changwon-bis DB 스키마
-- PostgreSQL + PostGIS 전제. 좌표는 전부 EPSG:4326(WGS84 lon/lat)로 통일한다.
-- 표준노드링크 원본은 ITRF2000 Central Belt(TM, m) 좌표계이므로 적재 시 ST_Transform(..., 4326) 필수.

CREATE EXTENSION IF NOT EXISTS postgis;

-- =========================================================
-- 1. 노선·정류소 도메인 (TAGO 기반, 정적 데이터)
-- =========================================================

CREATE TABLE stop (
    id                BIGSERIAL PRIMARY KEY,
    external_stop_id  VARCHAR(30)  UNIQUE NOT NULL,      -- TAGO nodeid (방향별 폴 단위로 별개)
    city_code         INTEGER      NOT NULL,              -- 38010=창원, 38030=진주 (TAGO citycode, SMALLINT 범위 초과함)
    stop_no           VARCHAR(20),                        -- TAGO nodeno
    stop_name         VARCHAR(100) NOT NULL,
    geom              geometry(Point, 4326) NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_stop_geom ON stop USING GIST (geom);
CREATE INDEX idx_stop_city ON stop (city_code);
CREATE INDEX idx_stop_name ON stop (stop_name);

CREATE TABLE route (
    id                 BIGSERIAL PRIMARY KEY,
    external_route_id  VARCHAR(30)  UNIQUE NOT NULL,     -- TAGO routeId
    city_code          INTEGER      NOT NULL,
    route_no           VARCHAR(10)  NOT NULL,             -- "21", "30-1" 등 문자 섞일 수 있어 VARCHAR
    route_type         VARCHAR(20),                        -- TAGO routetp (지선버스/일반버스/시외버스 등)
    start_node_nm      VARCHAR(100),
    end_node_nm        VARCHAR(100),
    first_vehicle_time TIME,
    last_vehicle_time  TIME,
    interval_weekday_min SMALLINT,                         -- TAGO intervaltime
    interval_sat_min     SMALLINT,                         -- TAGO intervalsattime
    interval_sun_min     SMALLINT,                         -- TAGO intervalsuntime
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_route_city ON route (city_code);
CREATE INDEX idx_route_no ON route (route_no);

-- 노선별 정류소 순서. TAGO 데이터 구조 그대로: 왕복 전체를 node_ord로 이어서 담고,
-- updown_cd(0=정방향/1=역방향)로 구간을 나눈다.
CREATE TABLE route_stop (
    route_id   BIGINT   NOT NULL REFERENCES route(id) ON DELETE CASCADE,
    node_ord   SMALLINT NOT NULL,
    stop_id    BIGINT   NOT NULL REFERENCES stop(id),
    updown_cd  SMALLINT NOT NULL CHECK (updown_cd IN (0, 1)),
    PRIMARY KEY (route_id, node_ord)
);
CREATE INDEX idx_route_stop_stop ON route_stop (stop_id);

-- 노선 형상(지도 표출용)은 별도 저장하지 않고 뷰로 계산한다 (중복 저장 방지).
CREATE VIEW route_line_view AS
SELECT
    rs.route_id,
    rs.updown_cd,
    ST_MakeLine(s.geom ORDER BY rs.node_ord) AS geom
FROM route_stop rs
JOIN stop s ON s.id = rs.stop_id
GROUP BY rs.route_id, rs.updown_cd;

-- =========================================================
-- 2. 실시간 운행 도메인
-- =========================================================

-- 버스 위치 원본 로그. 데이터량이 많으므로 날짜별 파티셔닝을 전제로 한다.
CREATE TABLE bus_location_log (
    id            BIGSERIAL,
    route_id      BIGINT       NOT NULL REFERENCES route(id),
    vehicle_no    VARCHAR(20)  NOT NULL,
    stop_id       BIGINT       REFERENCES stop(id),      -- 근접 정류소(TAGO nodeid 매칭), 못 찾으면 NULL
    node_ord      SMALLINT,
    geom          geometry(Point, 4326) NOT NULL,
    collected_at  TIMESTAMPTZ  NOT NULL,
    PRIMARY KEY (id, collected_at)
) PARTITION BY RANGE (collected_at);
CREATE INDEX idx_bus_loc_route_time ON bus_location_log (route_id, collected_at);
CREATE INDEX idx_bus_loc_geom ON bus_location_log USING GIST (geom);

-- 파티션 테이블은 실제 파티션이 있어야 insert가 가능하다.
-- 운영 단계에서는 pg_partman 등으로 자동 생성하되, 초기 구동용으로 당월/익월만 수동 생성.
CREATE TABLE bus_location_log_202610 PARTITION OF bus_location_log
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE bus_location_log_202611 PARTITION OF bus_location_log
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');

-- 도착예정 상태. 창원 BIS의 "조회 결과 없음"(사유 불명) 문제를 해결하기 위해
-- status를 명시적으로 분기한다.
CREATE TYPE arrival_status_type AS ENUM (
    'NORMAL',            -- 정상: predicted_sec 유효
    'SERVICE_ENDED',     -- 금일 운행 종료(막차 지남)
    'BEFORE_FIRST_BUS',  -- 첫차 전
    'WAITING_DISPATCH',  -- 운행 중이나 배차 대기
    'NO_SIGNAL'          -- 위치 데이터 수신 실패
);

CREATE TABLE arrival_status (
    stop_id        BIGINT NOT NULL REFERENCES stop(id),
    route_id       BIGINT NOT NULL REFERENCES route(id),
    status         arrival_status_type NOT NULL,
    predicted_sec  INT,                                   -- status='NORMAL'일 때만 값 존재
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (stop_id, route_id),
    CHECK ( (status = 'NORMAL' AND predicted_sec IS NOT NULL)
         OR (status <> 'NORMAL' AND predicted_sec IS NULL) )
);

-- =========================================================
-- 3. 관제 도메인
-- =========================================================

CREATE TABLE collection_status (
    id               BIGSERIAL PRIMARY KEY,
    source           VARCHAR(20) NOT NULL,                -- 'TAGO_BUS' | 'ITS_TRAFFIC'
    target_id        VARCHAR(30),                          -- route_id 등, 소스 전체 집계면 NULL
    last_collected_at TIMESTAMPTZ,
    success_count    BIGINT NOT NULL DEFAULT 0,
    fail_count       BIGINT NOT NULL DEFAULT 0,
    last_error_msg   TEXT
);
CREATE UNIQUE INDEX uq_collection_status_source_target ON collection_status (source, COALESCE(target_id, ''));

CREATE TYPE dispatch_anomaly_type AS ENUM ('BUNCHING', 'GAP_TOO_LONG');

CREATE TABLE dispatch_anomaly (
    id           BIGSERIAL PRIMARY KEY,
    route_id     BIGINT NOT NULL REFERENCES route(id),
    updown_cd    SMALLINT NOT NULL CHECK (updown_cd IN (0, 1)),
    detected_at  TIMESTAMPTZ NOT NULL,
    type         dispatch_anomaly_type NOT NULL,
    detail       TEXT
);
CREATE INDEX idx_dispatch_anomaly_route ON dispatch_anomaly (route_id, detected_at);

CREATE TABLE route_deviation (
    id              BIGSERIAL PRIMARY KEY,
    vehicle_no      VARCHAR(20) NOT NULL,
    route_id        BIGINT NOT NULL REFERENCES route(id),
    detected_at     TIMESTAMPTZ NOT NULL,
    deviation_m     NUMERIC(8, 2) NOT NULL,
    geom            geometry(Point, 4326) NOT NULL
);
CREATE INDEX idx_route_deviation_route ON route_deviation (route_id, detected_at);

-- =========================================================
-- 4. 도로망 · 디지털 트윈 도메인 (표준노드링크 + ITS)
-- =========================================================

CREATE TABLE road_node (
    id                BIGSERIAL PRIMARY KEY,
    external_node_id  VARCHAR(10) UNIQUE NOT NULL,        -- MOCT_NODE.NODE_ID
    node_name         VARCHAR(50),
    geom              geometry(Point, 4326) NOT NULL
);
CREATE INDEX idx_road_node_geom ON road_node USING GIST (geom);

CREATE TABLE road_link (
    id                BIGSERIAL PRIMARY KEY,
    external_link_id  VARCHAR(10) UNIQUE NOT NULL,        -- MOCT_LINK.LINK_ID
    f_node_id         BIGINT REFERENCES road_node(id),
    t_node_id         BIGINT REFERENCES road_node(id),
    road_name         VARCHAR(50),
    road_rank         VARCHAR(5),
    lanes             SMALLINT,
    max_speed_kmh     SMALLINT,                            -- 법정 제한속도(실측 아님)
    length_m          NUMERIC(10, 2),
    geom              geometry(LineString, 4326) NOT NULL
);
CREATE INDEX idx_road_link_geom ON road_link USING GIST (geom);

-- day_type: ITS 과거 데이터에서 평일 4일 / 토요일(공휴일 겹침) / 일요일 / 평일중 공휴일을
-- 분리 수집했고, 실제로 공휴일 패턴이 평일과 다르게 나타나 4분류를 유지하기로 결정함.
CREATE TYPE road_day_type AS ENUM ('WEEKDAY', 'SATURDAY', 'SUNDAY', 'HOLIDAY');
CREATE TYPE time_bucket_type AS ENUM ('COMMUTE_AM', 'DAYTIME', 'COMMUTE_PM', 'NIGHT');

-- scripts/aggregate_traffic_speed.py 결과물을 적재하는 테이블.
CREATE TABLE road_link_speed_stat (
    link_id        BIGINT NOT NULL REFERENCES road_link(id),
    city_code      INTEGER  NOT NULL,
    day_type       road_day_type NOT NULL,
    time_bucket    time_bucket_type NOT NULL,
    avg_speed_kmh  NUMERIC(5, 2) NOT NULL,
    sample_count   INT NOT NULL,
    PRIMARY KEY (link_id, day_type, time_bucket)
);

-- 노선(방향 단위)을 도로 링크 시퀀스에 맵매칭한 결과. 디지털 트윈 재생의 기준 데이터.
CREATE TABLE route_link_map (
    route_id   BIGINT   NOT NULL REFERENCES route(id),
    updown_cd  SMALLINT NOT NULL CHECK (updown_cd IN (0, 1)),
    seq        SMALLINT NOT NULL,
    link_id    BIGINT   NOT NULL REFERENCES road_link(id),
    PRIMARY KEY (route_id, updown_cd, seq)
);

-- =========================================================
-- 5. 안심귀가서비스
-- =========================================================

CREATE TABLE safety_guardian (
    id                  BIGSERIAL PRIMARY KEY,
    arrival_stop_id     BIGINT NOT NULL REFERENCES stop(id),
    guardian_phone      VARCHAR(20) NOT NULL,
    password_hash       VARCHAR(255) NOT NULL,
    child_tag_id        VARCHAR(50) NOT NULL,
    privacy_consent_at  TIMESTAMPTZ NOT NULL,              -- 진주 BIS에 없던 동의 절차. NOT NULL로 강제
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE safety_event (
    id             BIGSERIAL PRIMARY KEY,
    guardian_id    BIGINT NOT NULL REFERENCES safety_guardian(id),
    tag_time       TIMESTAMPTZ NOT NULL,
    route_id       BIGINT REFERENCES route(id),
    vehicle_no     VARCHAR(20),
    board_stop_id  BIGINT REFERENCES stop(id),
    sms_sent_at    TIMESTAMPTZ
);
CREATE INDEX idx_safety_event_guardian ON safety_event (guardian_id, tag_time);

-- =========================================================
-- 6. 관제 인증
-- =========================================================

-- 카카오/SMS는 사업자등록·건당과금 없이는 사실상 불가능해서
-- 완전 무료이면서 실무 표준인 TOTP(구글 OTP 앱 호환) 2단계 인증으로 결정.
CREATE TABLE admin_user (
    id               BIGSERIAL PRIMARY KEY,
    username         VARCHAR(50) UNIQUE NOT NULL,
    password_hash    VARCHAR(255) NOT NULL,
    totp_secret      VARCHAR(64) NOT NULL,                 -- Base32 인코딩된 TOTP 시크릿
    totp_enabled_at  TIMESTAMPTZ,                           -- NULL이면 아직 OTP 앱 등록 전(최초 로그인 시 설정 유도)
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
