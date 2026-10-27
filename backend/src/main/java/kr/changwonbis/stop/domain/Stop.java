package kr.changwonbis.stop.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.OffsetDateTime;
import org.locationtech.jts.geom.Point;

/** DB의 stop 테이블과 1:1 매핑. 정류소는 TAGO 기준 방향별 폴(pole) 단위로 저장된다. */
@Entity
@Table(name = "stop")
public class Stop {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "external_stop_id", nullable = false, unique = true)
    private String externalStopId;

    @Column(name = "city_code", nullable = false)
    private Integer cityCode;

    @Column(name = "stop_no")
    private String stopNo;

    @Column(name = "stop_name", nullable = false)
    private String stopName;

    @Column(name = "geom", nullable = false)
    private Point geom;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;

    protected Stop() {
        // JPA
    }

    public Long getId() {
        return id;
    }

    public String getExternalStopId() {
        return externalStopId;
    }

    public Integer getCityCode() {
        return cityCode;
    }

    public String getStopNo() {
        return stopNo;
    }

    public String getStopName() {
        return stopName;
    }

    public Point getGeom() {
        return geom;
    }
}
