package kr.changwonbis.stop.api;

import kr.changwonbis.stop.domain.Stop;

/** docs/api-spec.md 2절(정류소 검색) 응답 스펙과 1:1 대응. */
public record StopSummaryResponse(
        Long stopId, String externalStopId, Integer cityCode, String stopNo, String stopName, double lat, double lng) {

    public static StopSummaryResponse from(Stop stop) {
        return new StopSummaryResponse(
                stop.getId(),
                stop.getExternalStopId(),
                stop.getCityCode(),
                stop.getStopNo(),
                stop.getStopName(),
                stop.getGeom().getY(), // ST_MakePoint(lng, lat) 이므로 Y=위도
                stop.getGeom().getX() // X=경도
                );
    }
}
