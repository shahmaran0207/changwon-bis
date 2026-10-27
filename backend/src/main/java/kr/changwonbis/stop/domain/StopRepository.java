package kr.changwonbis.stop.domain;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface StopRepository extends JpaRepository<Stop, Long> {

    // 초성검색은 TODO (docs/api-spec.md 설계 메모 참고) - 지금은 부분일치 검색만 구현.
    @Query(
            "SELECT s FROM Stop s "
                    + "WHERE s.deletedAt IS NULL "
                    + "AND (:cityCode IS NULL OR s.cityCode = :cityCode) "
                    + "AND s.stopName LIKE CONCAT('%', :keyword, '%')")
    Page<Stop> search(@Param("keyword") String keyword, @Param("cityCode") Integer cityCode, Pageable pageable);
}
