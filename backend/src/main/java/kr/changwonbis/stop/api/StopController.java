package kr.changwonbis.stop.api;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import kr.changwonbis.stop.application.StopService;
import org.springframework.data.domain.PageRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "정류소")
@RestController
public class StopController {

    private final StopService stopService;

    public StopController(StopService stopService) {
        this.stopService = stopService;
    }

    @Operation(summary = "정류소 검색", description = "docs/api-spec.md 2절")
    @GetMapping("/api/v1/stops")
    public StopSearchResponse search(
            @RequestParam String keyword,
            @RequestParam(required = false) Integer cityCode,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        int safeSize = Math.min(size, 100);
        return stopService.search(keyword, cityCode, PageRequest.of(page, safeSize));
    }
}
