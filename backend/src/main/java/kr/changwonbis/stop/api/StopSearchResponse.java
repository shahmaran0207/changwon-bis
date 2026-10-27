package kr.changwonbis.stop.api;

import java.util.List;
import org.springframework.data.domain.Page;

public record StopSearchResponse(List<StopSummaryResponse> content, int page, int size, long totalElements) {

    public static StopSearchResponse from(Page<StopSummaryResponse> page) {
        return new StopSearchResponse(
                page.getContent(), page.getNumber(), page.getSize(), page.getTotalElements());
    }
}
