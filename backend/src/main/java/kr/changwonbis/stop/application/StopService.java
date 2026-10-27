package kr.changwonbis.stop.application;

import kr.changwonbis.stop.api.StopSearchResponse;
import kr.changwonbis.stop.api.StopSummaryResponse;
import kr.changwonbis.stop.domain.StopRepository;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(readOnly = true)
public class StopService {

    private final StopRepository stopRepository;

    public StopService(StopRepository stopRepository) {
        this.stopRepository = stopRepository;
    }

    public StopSearchResponse search(String keyword, Integer cityCode, Pageable pageable) {
        var page = stopRepository.search(keyword, cityCode, pageable).map(StopSummaryResponse::from);
        return StopSearchResponse.from(page);
    }
}
