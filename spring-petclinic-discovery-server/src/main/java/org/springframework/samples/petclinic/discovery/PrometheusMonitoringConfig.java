package org.springframework.samples.petclinic.discovery;

import io.micrometer.core.instrument.Clock;
import io.micrometer.prometheus.PrometheusConfig;
import io.micrometer.prometheus.PrometheusMeterRegistry;
import io.prometheus.client.CollectorRegistry;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Configuration pour l'intégration avec Prometheus
 * Cette classe permet d'exposer les métriques du Discovery Server via l'endpoint /actuator/prometheus
 */
@Configuration
public class PrometheusMonitoringConfig {

    @Bean
    public PrometheusMeterRegistry prometheusMeterRegistry(PrometheusConfig config, CollectorRegistry collectorRegistry, Clock clock) {
        return new PrometheusMeterRegistry(config, collectorRegistry, clock);
    }
    
    @Bean
    public CollectorRegistry collectorRegistry() {
        return new CollectorRegistry(true);
    }
    
    @Bean
    public Clock micrometerClock() {
        return Clock.SYSTEM;
    }
}
