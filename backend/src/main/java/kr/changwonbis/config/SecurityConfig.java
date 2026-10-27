package kr.changwonbis.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;

/**
 * 대시민 조회 API는 전부 공개, 관제(/api/v1/admin/**)는 인증 필요.
 * JWT+TOTP 인증 필터는 아직 미구현(docs/api-spec.md 7절) — 지금은 관제 경로가 기본 보안으로 막혀있는 상태.
 */
@Configuration
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http.csrf(csrf -> csrf.disable())
                .authorizeHttpRequests(auth -> auth.requestMatchers(
                                "/api/v1/stops/**",
                                "/api/v1/routes/**",
                                "/api/v1/digital-twin/**",
                                "/swagger-ui/**",
                                "/v3/api-docs/**")
                        .permitAll()
                        .anyRequest()
                        .authenticated())
                .httpBasic(basic -> basic.disable())
                .formLogin(form -> form.disable());
        return http.build();
    }
}
