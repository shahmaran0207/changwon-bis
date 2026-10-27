package kr.changwonbis.common;

import java.time.OffsetDateTime;

/** docs/api-spec.md "공통 > 에러 응답" 포맷. */
public record ErrorResponse(String code, String message, OffsetDateTime timestamp) {

    public static ErrorResponse of(String code, String message) {
        return new ErrorResponse(code, message, OffsetDateTime.now());
    }
}
